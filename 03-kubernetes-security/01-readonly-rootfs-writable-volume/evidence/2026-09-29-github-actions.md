# Lab 01 remote experiment — 2026-09-29 UTC

Historical run. A later [completed comparison](2026-09-29-completed-comparison.md) used an explicitly documented custom runtime. The observations below remain unchanged and apply to the initial stock-runtime attempt.

Status: baseline reproduced; hardened execution tests blocked by scheduling. The overall workflow concluded **failure**, not success.

## Provenance and environment

- [Run 36506196345](https://github.com/diyah06/security-engineering-labs/actions/runs/36506196345), approximately 01:05–01:09 UTC (September 28 in Los Angeles).
- Source commit: `8d9efc5aa67787b654e90d9f246b62f064686247`.
- GitHub-hosted Ubuntu 24.04.5, runner image `20260920.314.1`, Linux x86_64.
- kind `v0.33.0`; kubectl and Kubernetes server `v1.37.0`.
- Docker server `28.0.4`; Kubernetes node runtime `containerd://2.3.4`.
- Node OS: Debian GNU/Linux 13 (trixie), amd64.
- Node image: `kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5`.
- Baseline BusyBox imageID on both clusters: `docker.io/library/busybox@sha256:bdf57e528e45e4433820e045b29b4597825a1c9e38353532d90a01445013f82e`.

The workflow created `security-labs` from `kind.yaml`, ran `bash verify.sh baseline`, removed that cluster, then created `security-labs-mounts` from `kind-mount-controls.yaml` and ran `bash verify.sh comparison`. Both creations used the pinned node image. See [workflow](../../../.github/workflows/lab01.yml) and [probe commands](../verify.sh) at the source commit for exact invocation details. Both lab clusters were deleted by the end of the run.

## Checkpoint A: observed baseline

Strict server dry-run, Pod creation, and readiness succeeded. The same baseline also passed in the feature-enabled cluster before the hardened Pod was attempted.

Each probe below ran using `kubectl --context <lab-context> --namespace rootfs-lab --request-timeout=30s exec rootfs-insecure -- <command>`. Results were identical in `kind-security-labs` and `kind-security-labs-mounts`.

| Container command | Observed output/result | Exit |
| --- | --- | --- |
| `id` | `uid=1000 gid=1000 groups=1000` | 0 |
| `touch /tmp/lab-write-probe` | `touch: /tmp/lab-write-probe: Read-only file system` | 1 |
| `sh -c 'touch /scratch/lab-write-probe && rm /scratch/lab-write-probe'` | No output; write and removal succeeded | 0 |
| `sh -c 'cp /bin/busybox /scratch/busybox && chmod 755 /scratch/busybox'` | No output; copy and chmod succeeded | 0 |
| `sh -c '/scratch/busybox echo executed-from-scratch'` | `executed-from-scratch` | 0 |
| `sh -c '/scratch/demo.sh'` | `interpreted-from-scratch` | 0 |
| `/bin/sh /scratch/demo.sh` | `interpreted-from-scratch` | 0 |

The script was created with `printf "#!/bin/sh\necho interpreted-from-scratch\n" > /scratch/demo.sh && chmod 755 /scratch/demo.sh`, run through `sh -c`; this setup returned 0. The outer shell for direct execution invokes the scratch file as a program; it does not substitute the explicit `/bin/sh /scratch/demo.sh` interpreter test.

Selected `/proc/self/mountinfo` fields, extracted with `awk '$5 == "/" || $5 == "/scratch" || $5 == "/dev/shm" {print $5, $6}'`:

```text
/ ro,relatime
/scratch rw,relatime
/dev/shm rw,relatime
```

The probe script reported:

```text
PASS: rootfs-insecure on kind-security-labs
PASS: rootfs-insecure on kind-security-labs-mounts
```

These observations support the baseline claim: the read-only root mount did not prevent writing and executing a harmless copied binary on a separate writable mount. They do not demonstrate an initial compromise, privilege escalation, or host escape. The manual `/`, `/etc`, and `/dev/shm` write probes were not run.

## Checkpoint B: observed compatibility failure

With `VolumeBindMountOptions` enabled, `kubectl explain pod.spec.containers.volumeMounts.bindMountOptions` returned the field documentation. Strict server dry-run and apply of `manifests/hardened.yaml` succeeded:

```text
pod/rootfs-hardened created (server dry run)
pod/rootfs-hardened created
```

`kubectl --context kind-security-labs-mounts --namespace rootfs-lab --request-timeout=30s wait --for=condition=Ready pod/rootfs-hardened --timeout=180s` failed:

```text
error: timed out waiting for the condition on pods/rootfs-hardened
```

The subsequent status query reported phase `Pending`, condition `PodScheduled=False`, reason `Unschedulable`, and this message:

```text
0/1 nodes are available: 1 node(s) didn't match Pod's required features. preemption: 0/1 nodes are available: 1 Preemption is not helpful for scheduling.
```

The verification script exited 1. No hardened container started; its mount flags, write probes, direct execution denial, and interpreter behavior were **not measured**. Node feature/runtime incompatibility is indicated by the scheduler; the exact missing advertised capability was not inspected in this run.

## Interpretation and next experiment

The baseline reproduced twice. Kubernetes API acceptance alone did not establish that the node could run the hardened workload. The next experiment must inspect node-declared features and runtime support, then rerun on a compatible configuration without weakening the manifest. The expected `noexec` behavior remains a hypothesis for this lab until then.

Before this run, the first workflow dispatch was rejected because `runner.temp` was referenced in job-level `env`. Commit `8d9efc5` moved kubeconfig path setup into a runner step. No Kubernetes experiment ran during that rejected dispatch.

This record contains reviewed synthetic observations, not a full raw log. No credentials, kubeconfig contents, or host backing paths are included.
