# Lab 01: a read-only root filesystem is not an execution policy

**Status: complete in the documented remote lab environment.** Baseline, hardened comparison, directory survey, and interpreter limitation were reproduced on GitHub Actions on 2026-09-29 UTC. The comparison required a [custom lab-only containerd build](runtime/README.md); this is not a claim of stock-runtime or production support. See [reviewed evidence](evidence/2026-09-29-completed-comparison.md).

## Fundamentals

A container has a filesystem assembled from multiple mounts. `readOnlyRootFilesystem: true` makes the root mount read-only; it does not make an `emptyDir` mounted at `/scratch` read-only. File permissions, writable mounts, and executable mounts are separate controls. A non-root user can execute a file it owns on an executable writable mount.

`noexec` denies direct execution from a mount. It does not stop `/bin/sh /scratch/demo.sh`: the executable is `/bin/sh`, which reads the script as data. This lab demonstrates a filesystem boundary, not a complete defense against arbitrary code execution.

Before running: predict whether writing `/tmp/probe` and `/scratch/probe` will work. Then predict whether a copied binary will execute.

## Architecture

```text
GitHub Ubuntu runner → Docker → kind node → rootfs-lab namespace
                                  └─ demo Pod (UID 1000)
                                     ├─ /         read-only image
                                     └─ /scratch  writable emptyDir
```

The completed run used Linux/amd64 remotely. The stock baseline used containerd 2.3.4; the controlled comparison ran both Pods on containerd 2.4.0-lab01 with the mount-options feature gate enabled. Local macOS execution is an alternative, not a validated environment.

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

### Remote execution with GitHub Actions

The [manual workflow](../../.github/workflows/lab01.yml) runs on a temporary Ubuntu Linux VM with Docker, rather than on the learner's Mac. From the repository root, the following command starts it:

```bash
gh workflow run lab01.yml --repo diyah06/security-engineering-labs --ref main
```

The workflow verifies downloaded tool checksums, pins kind 0.33.0 and the Kubernetes 1.37.0 node image by digest, then creates the stock baseline cluster and builds a separate feature-enabled node with the tested [runtime patch](runtime/README.md). Both comparison Pods run on that same custom node. It invokes [verify.sh](verify.sh) to apply the existing manifests and assert observed exit codes and mount flags. It deletes both temporary clusters afterward, including on failure. Logs contain the commands and results; kubeconfigs and binaries are not published.

Use the run URL printed by GitHub CLI to inspect each step. A successful baseline step does not mean the full comparison passed. The initial stock-runtime run failed at hardened Pod readiness. The completed workflow builds the compatibility runtime and passes the comparison; the earlier failure remains in the evidence history.

The remote script tests `/tmp` and `/scratch`, surveys writes to `/`, `/etc`, `/tmp`, `/scratch`, and `/dev/shm`, and tests direct binary/script execution and explicit interpreter execution. It prints selected mount flags without host backing paths.

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
# From the repository root:
cd 03-kubernetes-security/01-readonly-rootfs-writable-volume
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

The optional kind config enables the gate but does not upgrade the node image or its runtime. The remote workflow builds `lab01-node:containerd-mount-options` from the pinned upstream node plus the documented custom runtime. To run the commands below manually, first build that image using the recipe in the workflow, or supply another independently verified compatible image. An ordinary stock node is not a verified substitute. Use a separate cluster:

```bash
kind create cluster --name security-labs-mounts --config kind-mount-controls.yaml --image lab01-node:containerd-mount-options --wait 120s
kubectl --context kind-security-labs-mounts create namespace rootfs-lab
kubectl --context kind-security-labs-mounts explain pod.spec.containers.volumeMounts.bindMountOptions
kubectl --context kind-security-labs-mounts apply --dry-run=server --validate=strict -f manifests/hardened.yaml
kubectl --context kind-security-labs-mounts apply -f manifests/insecure.yaml
kubectl --context kind-security-labs-mounts apply -f manifests/hardened.yaml
kubectl --context kind-security-labs-mounts -n rootfs-lab wait --for=condition=Ready pod --all --timeout=120s
```

If cluster creation, schema validation, scheduling, or container startup fails, stop B and record it as unsupported in this environment. The original stock 1.37.0 image accepted the field but could not schedule the hardened Pod. The later custom-runtime node successfully scheduled and enforced the unchanged manifest; see the runtime recipe and evidence. Do not remove the feature gate or bypass validation to claim success.

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

Observed in [successful run 36508385718](https://github.com/diyah06/security-engineering-labs/actions/runs/36508385718), using Kubernetes 1.37.0. Both comparison Pods used containerd **2.4.0-lab01**, the same BusyBox image digest, UID/GID 1000, and the unchanged manifests.

| Probe | Baseline observed | Hardened observed |
| --- | --- | --- |
| Pod readiness | Ready | Ready |
| Root mount | `ro,relatime` | `ro,relatime` |
| Scratch mount | `rw,relatime` | `rw,nosuid,nodev,noexec,relatime` |
| Write `/`, `/etc`, `/tmp` | Read-only filesystem errors, exit 1 | Same |
| Write `/scratch`, `/dev/shm` | Succeeded, exit 0 | Same |
| Copy BusyBox to scratch and chmod | Succeeded, exit 0 | Same |
| Execute copied BusyBox | Succeeded, exit 0 | Permission denied, exit 126 |
| Execute scratch script directly | Succeeded, exit 0 | Permission denied, exit 126 |
| Execute script via `/bin/sh` | Succeeded, exit 0 | Succeeded, exit 0 |

The stock-runtime baseline also passed separately. Runtime option-handling tests, server-side manifest validation, readiness checks, mount assertions, execution probes, and cluster cleanup all passed. See [complete provenance and reviewed output](evidence/2026-09-29-completed-comparison.md).

The [initial stock-runtime failure](evidence/2026-09-29-github-actions.md) remains part of the learning record: API acceptance succeeded, but the node could not schedule the hardened Pod. The custom runtime solved that compatibility problem; no Pod protections were removed.

## Security implications

A read-only root mount protects image contents against filesystem writes. It is not an allowlist of executable code. Per-mount controls reduce specific uses of scratch storage; interpreters, existing executables, other mounts, and already-running compromised processes remain relevant. Dropping capabilities and disabling privilege escalation help prevent the workload from undoing controls. This lab does not establish production readiness or network containment.

## Lessons learned

- The root mount and scratch mount enforced different write policies. A read-only root did not prevent executing a copied program from scratch storage as UID 1000.
- The write and execution probes were separate observations; a successful write alone would not establish that execution was possible.
- API schema acceptance did not establish runtime compatibility. The hardened manifest passed validation but could not schedule.
- On the compatible lab runtime, `noexec` denied direct binary and script execution while preserving writes. Explicit interpreter execution still succeeded, so this control is not a general execution allowlist.
- `/dev/shm` was writable in both Pods; hardening `/scratch` did not harden every writable mount. Execution from `/dev/shm` was not tested.
- The node advertised `VolumeBindMountOptions` after the compatibility patch. Actual mount flags and exit codes, not just the API field or feature declaration, established enforcement.
- `nosuid` and `nodev` were observed as mount flags, but their individual behavioral effects were not tested. Production use requires supported upstream runtimes and broader validation, not this lab patch.

## News connection and sources

Candidate portfolio angle: “I tested whether a read-only Kubernetes root filesystem also prevents execution from scratch storage.” Publish a success claim only after collecting results.

- [Kubernetes storage-hardening announcement, September 16, 2026](https://kubernetes.io/blog/2026/09/16/kubernetes-v1-37-hardening-container-storage/): motivates the optional new mount-control comparison; this lab is not a CVE reproduction.
- [Kubernetes volume semantics](https://kubernetes.io/docs/concepts/storage/volumes/).
- [Kubernetes security context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/).
- [Linux mount flags](https://man7.org/linux/man-pages/man2/mount.2.html) and [execve errors](https://man7.org/linux/man-pages/man2/execve.2.html).
- [kind quick start](https://kind.sigs.k8s.io/docs/user/quick-start/).
- Homebrew prerequisites: [kind](https://formulae.brew.sh/formula/kind), [kubectl](https://formulae.brew.sh/formula/kubernetes-cli), [Docker Desktop](https://formulae.brew.sh/cask/docker-desktop).

Completion scope: the filesystem question, baseline, hardened comparison, interpreter limitation, directory survey, evidence, and lessons are complete in the documented remote environment. Local macOS reproduction, stock-runtime hardening support, other volume types, and independent behavioral tests of `nosuid`/`nodev` are outside this result.
