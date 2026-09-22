# Lab 01: a read-only root filesystem is not an execution policy

**Status: prepared, not run.** Work through checkpoint A before checkpoint B. No deployment, compromise, or hardening result has been observed yet.

## Fundamentals

A container has a filesystem assembled from multiple mounts. `readOnlyRootFilesystem: true` makes the root mount read-only; it does not make an `emptyDir` mounted at `/scratch` read-only. File permissions, writable mounts, and executable mounts are separate controls. A non-root user can execute a file it owns on an executable writable mount.

`noexec` denies direct execution from a mount. It does not stop `/bin/sh /scratch/demo.sh`: the executable is `/bin/sh`, which reads the script as data. This lab demonstrates a filesystem boundary, not a complete defense against arbitrary code execution.

Before running: predict whether writing `/tmp/probe` and `/scratch/probe` will work. Then predict whether a copied binary will execute.

## Architecture

```text
macOS → Docker Linux VM → kind node → rootfs-lab namespace
                                  └─ demo Pod (UID 1000)
                                     ├─ /         read-only image
                                     └─ /scratch  writable emptyDir
```

One sleeping BusyBox container; no Service, ingress, hostPath, privileged container, credentials, or application exploit. Each comparison Pod gets its own ephemeral volume. Deleting its Pod removes that volume. We copy a harmless existing binary rather than downloading a payload.

### Important manifest lines, before execution

| Field | Meaning |
| --- | --- |
| `apiVersion: v1`, `kind: Pod` | Create a core Kubernetes Pod, the smallest scheduling unit. |
| `metadata.name`, `namespace` | Identify the experiment and keep its resources together. A namespace is not a complete security boundary. |
| `os.name: linux` | Declare Linux semantics for this Pod. |
| `automountServiceAccountToken: false` | Avoid injecting an unnecessary API credential. |
| `restartPolicy: Never` | Do not restart the container when its command exits. |
| `runAsNonRoot`, `runAsUser`, `runAsGroup` | Run with numeric UID/GID 1000 instead of root. |
| `fsGroup: 1000` | Allow the process's group to use the volume. |
| `seccompProfile: RuntimeDefault` | Use the runtime's default syscall filter. |
| `image: busybox:1.37.0` | Small toolbox for the experiment. A tag is mutable; record the resolved imageID. |
| `command: ["sleep", "86400"]` | Keep the container alive for manual inspection for up to a day. |
| `readOnlyRootFilesystem: true` | Make the root filesystem read-only; this is the control under test. |
| `allowPrivilegeEscalation: false` | Prevent gaining privileges through exec mechanisms such as setuid. |
| `capabilities.drop: ["ALL"]` | Remove Linux capabilities, including mount administration. |
| `resources` | Request modest CPU/memory and cap their use; CPU is in millicores, memory in MiB. |
| `volumeMounts`, `mountPath: /scratch` | Attach the named volume as a separate writable mount. |
| `emptyDir`, `sizeLimit: 32Mi` | Pod-lifetime scratch storage with a size limit; enforcement is not a synchronous write quota. |

The filename “insecure” refers specifically to executable scratch storage. Other basic controls are intentionally present in both examples to isolate the comparison.

## Threat model

Assume an attacker already controls a process running as UID 1000, for example after an application compromise. We simulate that starting condition with `kubectl exec`; this does not demonstrate how initial compromise happens. Assets: image integrity and control over direct execution from scratch storage. The attacker can write their own files and run available tools, but cannot change Pod specs or administer mounts. Host compromise, credential theft, network isolation, and kernel exploits are outside this first experiment.

## Experiment

### Checkpoint A — baseline only

Read each block before running it. These are commands for you to run, not recorded output.

Install local prerequisites on macOS if missing:

```bash
brew install kind kubernetes-cli
brew install --cask docker-desktop
open -a Docker
```

Complete Docker Desktop's startup, then verify `docker info` succeeds. Docker supplies the Linux environment; kind creates a Kubernetes node inside it; kubectl talks to its API.

```bash
cd ~/security-engineering-labs/03-kubernetes-security/01-readonly-rootfs-writable-volume
docker info
kind create cluster --name security-labs --config kind.yaml --wait 120s
kubectl --context kind-security-labs get nodes -o wide
kubectl --context kind-security-labs create namespace rootfs-lab
kubectl --context kind-security-labs apply --dry-run=server --validate=strict -f manifests/insecure.yaml
kubectl --context kind-security-labs apply -f manifests/insecure.yaml
kubectl --context kind-security-labs -n rootfs-lab wait --for=condition=Ready pod/rootfs-insecure --timeout=120s
```

Expected: a Ready node, namespace created, Pod accepted, and Ready condition met. All cluster commands explicitly select the local context. If the namespace already exists, inspect it and skip its creation. If the Pod is not Ready, inspect `kubectl --context kind-security-labs -n rootfs-lab describe pod rootfs-insecure`; do not assume the experiment ran.

Record environment and image identity:

```bash
kind version
kubectl --context kind-security-labs version
kubectl --context kind-security-labs get nodes -o wide
kubectl --context kind-security-labs -n rootfs-lab get pod rootfs-insecure -o jsonpath='{.status.containerStatuses[0].imageID}{"\n"}'
```

Inspect identity, mounts, and selected directories:

```bash
kubectl --context kind-security-labs -n rootfs-lab exec rootfs-insecure -- id
kubectl --context kind-security-labs -n rootfs-lab exec rootfs-insecure -- cat /proc/self/mountinfo
kubectl --context kind-security-labs -n rootfs-lab exec rootfs-insecure -- sh -c '
for d in / /etc /tmp /scratch /dev/shm; do
  f="$d/lab-write-probe"
  if touch "$f"; then
    echo "WRITABLE: $d"
    rm "$f"
  else
    echo "WRITE DENIED: $d"
  fi
done'
```

Read errors as well as labels: permission denial differs from a read-only filesystem. The probe samples directories as UID 1000; it is not an exhaustive filesystem inventory. Runtime mounts such as `/dev/shm` may be writable too. In mountinfo, identify `/` and `/scratch` in the mount-point column and inspect `ro`/`rw` and execution flags.

Copy an existing harmless binary, then run its echo applet:

```bash
kubectl --context kind-security-labs -n rootfs-lab exec rootfs-insecure -- sh -c 'cp /bin/busybox /scratch/busybox && chmod 755 /scratch/busybox'
kubectl --context kind-security-labs -n rootfs-lab exec rootfs-insecure -- /scratch/busybox echo 'executed from scratch'
echo "exit=$?"
```

Stop here and fill in observed behavior. If execution is denied already, inspect actual mount flags and record that your environment did not reproduce the proposed baseline. Do not disable controls just to force success.

### Checkpoint B — compare mount hardening after recording A

Review [the full diff](hardening.diff):

```bash
diff -u manifests/insecure.yaml manifests/hardened.yaml
```

`diff` returns 1 when files differ; that is expected. The Pod name changes solely to keep both examples available. The only security changes are on `/scratch`:

```diff
           mountPath: /scratch
+          bindMountOptions:
+            - noexec
+            - nosuid
+            - nodev
```

- `noexec`: deny direct binary/script execution from this writable mount.
- `nosuid`: suppress setuid/setgid privilege transitions from files on it; overlaps with the existing no-new-privileges setting.
- `nodev`: do not interpret device special files on it; defense in depth even though this process cannot create devices with its current capabilities.

Writing remains possible. Changing the mount to read-only would remove required scratch functionality instead of testing this boundary.

**Compatibility gate:** the cited Kubernetes 1.37 documentation describes `VolumeBindMountOptions` as alpha. It must be enabled on the API server and kubelet, and the runtime must support CRI mount options. Ordinary older `emptyDir` YAML cannot express these controls. Do not add a made-up `emptyDir.mountOptions` field. `kubectl` schema acceptance alone does not prove enforcement.

The optional kind config enables the gate but does not upgrade the node image or its runtime. Once you have a compatible kind node image/runtime, use a separate local cluster:

```bash
kind create cluster --name security-labs-mounts --config kind-mount-controls.yaml --wait 120s
kubectl --context kind-security-labs-mounts create namespace rootfs-lab
kubectl --context kind-security-labs-mounts explain pod.spec.containers.volumeMounts.bindMountOptions
kubectl --context kind-security-labs-mounts apply --dry-run=server --validate=strict -f manifests/hardened.yaml
kubectl --context kind-security-labs-mounts apply -f manifests/insecure.yaml
kubectl --context kind-security-labs-mounts apply -f manifests/hardened.yaml
kubectl --context kind-security-labs-mounts -n rootfs-lab wait --for=condition=Ready pod --all --timeout=120s
```

If cluster creation, schema validation, scheduling, or container startup fails, stop B and record it as unsupported in this environment. A compatible node image has not been verified here. Do not remove the feature gate or bypass validation to claim success.

Repeat checkpoint A's mount/write/binary probes on this cluster for **both** Pod names, replacing the context with `kind-security-labs-mounts`. Expected hardened outcome: copying and chmod succeed, execution fails with permission denied and a nonzero status. Confirm `/scratch` actually has `noexec,nosuid,nodev`. This test demonstrates `noexec`; it does not independently test the other two flags.

Show the interpreter limitation on the hardened Pod:

```bash
kubectl --context kind-security-labs-mounts -n rootfs-lab exec rootfs-hardened -- sh -c 'printf "#!/bin/sh\necho interpreted-from-scratch\n" > /scratch/demo.sh && chmod 755 /scratch/demo.sh'
kubectl --context kind-security-labs-mounts -n rootfs-lab exec rootfs-hardened -- /scratch/demo.sh
echo "direct exit=$?"
kubectl --context kind-security-labs-mounts -n rootfs-lab exec rootfs-hardened -- /bin/sh /scratch/demo.sh
echo "interpreter exit=$?"
```

### Cleanup after recording evidence

These commands delete only the named lab namespaces and their temporary volumes:

```bash
kubectl --context kind-security-labs delete namespace rootfs-lab
# Only if you created checkpoint B's cluster:
kubectl --context kind-security-labs-mounts delete namespace rootfs-lab
```

Optionally remove the dedicated clusters with `kind delete cluster --name security-labs` and, if created, `kind delete cluster --name security-labs-mounts`.

## Expected behavior

| Probe | Baseline | Hardened, supported runtime |
| --- | --- | --- |
| Write `/tmp` on root filesystem | Denied | Denied |
| Write `/scratch` | Allowed | Allowed |
| Execute copied BusyBox on `/scratch` | Allowed if mount is executable | Denied |
| Execute `/scratch/demo.sh` directly | Allowed with executable bit | Denied |
| `/bin/sh /scratch/demo.sh` | Allowed | Allowed |

These are hypotheses, not measurements. Other writable mounts are outside this mount's protection.

## Observed behavior

**Not run.** Fill in environment versions, imageID, command, output/exit code, mount flags, deviations from prediction, and a link to curated [evidence](evidence/README.md). Record checkpoint A and B separately. Never replace this section with the expected table.

## Security implications

A read-only root mount protects image contents against filesystem writes. It is not an allowlist of executable code. Per-mount controls reduce specific uses of scratch storage; interpreters, existing executables, other mounts, and already-running compromised processes remain relevant. Dropping capabilities and disabling privilege escalation help prevent the workload from undoing controls. This lab does not establish production readiness or network containment.

## Lessons learned

Learner TODO after running:

- Which mount boundary explained the result?
- What evidence separated write permission from execution permission?
- What did `noexec` prevent, and what did the interpreter experiment show?
- Which hypotheses were unsupported or wrong in your environment?
- What would you test next before making a production recommendation?

## News connection and sources

Candidate portfolio angle: “I tested whether a read-only Kubernetes root filesystem also prevents execution from scratch storage.” Publish a success claim only after collecting results.

- [Kubernetes storage-hardening announcement, September 16, 2026](https://kubernetes.io/blog/2026/09/16/kubernetes-v1-37-hardening-container-storage/): motivates the optional new mount-control comparison; this lab is not a CVE reproduction.
- [Kubernetes volume semantics](https://kubernetes.io/docs/concepts/storage/volumes/).
- [Kubernetes security context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/).
- [Linux mount flags](https://man7.org/linux/man-pages/man2/mount.2.html) and [execve errors](https://man7.org/linux/man-pages/man2/execve.2.html).
- [kind quick start](https://kind.sigs.k8s.io/docs/user/quick-start/).
- Homebrew prerequisites: [kind](https://formulae.brew.sh/formula/kind), [kubectl](https://formulae.brew.sh/formula/kubernetes-cli), [Docker Desktop](https://formulae.brew.sh/cask/docker-desktop).

Next build steps: install tools, run A, interpret its output together, verify a compatible runtime for B, then write the evidence-backed portfolio entry. Automation, detection rules, and further labs are intentionally future exercises.
