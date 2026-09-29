# Completed Lab 01 comparison — 2026-09-29 UTC

**Result: passed in the documented remote environment.** [GitHub Actions run 36508385718](https://github.com/diyah06/security-engineering-labs/actions/runs/36508385718) ran the stock baseline, built and tested a custom compatibility runtime, and validated both unchanged Pod manifests on that runtime. All steps, including cleanup, succeeded. This does not establish stock containerd support.

## Provenance

- Source commit: `85c8c63` (`test(k8s): add explicit lab runtime for mount-option validation`).
- Run window: approximately 01:32–01:35 UTC, September 29 (September 28 in Los Angeles).
- GitHub-hosted Ubuntu 24.04 runner, Linux x86_64; Docker server 28.0.4.
- kind 0.33.0; kubectl and Kubernetes 1.37.0.
- Base node: `kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5`.
- Node OS: Debian GNU/Linux 13 (trixie), amd64.
- Stock baseline runtime: containerd 2.3.4.
- Comparison runtime: `containerd://2.4.0-lab01`, built with Go 1.26.6 from upstream commit `a7fe631d96c08fb14cf8eff0afdc280e99c30a94` plus the checked-in [compatibility patch](../runtime/containerd-mount-options.patch).
- Runtime binary SHA-256: `7990709e25ce019634fc9793e3e09cbfebce183a3a9ad39cd5189cef5f1cda53`.
- Patch SHA-256: `de67e00158cb2c3a113147777d893a062e963c3322abd1e7d262a4be8d963cbb`.
- Built local node image ID: `sha256:31443fdf803cb8dbe7229be0df565b67aacd72c8ab46a08f0649bb62df4a3702` (not published).
- Both comparison Pods used `docker.io/library/busybox@sha256:bdf57e528e45e4433820e045b29b4597825a1c9e38353532d90a01445013f82e`.

Checksums identify this run's build, not a promise that future builds are byte-identical. The [workflow](../../../.github/workflows/lab01.yml) pins source and base image, records build identity, and performs the experiment. The [runtime README](../runtime/README.md) describes the compatibility code and its limits.

## Build and compatibility observations

The runtime's five option-handling subtests passed: unchanged baseline, security flags, conflicts/duplicates, rejection of weakening flags, and rejection of unknown flags. The upstream `TestWithMountsCgroupNamespaceOptions` test and its four subtests also passed. These were targeted tests, not the full containerd test suite.

The node reported `containerd://2.4.0-lab01` and included `VolumeBindMountOptions` in `.status.declaredFeatures`. An ancillary `crictl info` diagnostic selected `.runtimeFeatures` and printed `null`; that query did not establish CRI support. The subsequent workflow correction removes that misleading query and asserts the node-declared feature instead. Scheduling, mount flags, and execution results below provide the runtime evidence.

## Controlled Pod experiment

Both Pods passed strict server-side dry-run, creation, and readiness. Both returned `uid=1000 gid=1000 groups=1000` from `id`, exit 0.

The workflow ran `bash verify.sh comparison`. Each container command in the table was invoked using:

```bash
kubectl --context kind-security-labs-mounts --namespace rootfs-lab --request-timeout=30s exec POD -- COMMAND
```

Replace `POD` with `rootfs-insecure` or `rootfs-hardened`. Exact setup and probe commands are in [verify.sh](../verify.sh) at source commit `85c8c63`; each was printed in the run log before execution.

| Container command | Baseline result | Hardened result |
| --- | --- | --- |
| `touch /tmp/lab-write-probe` | Read-only filesystem, exit 1 | Read-only filesystem, exit 1 |
| `sh -c 'touch /scratch/lab-write-probe && rm /scratch/lab-write-probe'` | Exit 0 | Exit 0 |
| `sh -c 'cp /bin/busybox /scratch/busybox && chmod 755 /scratch/busybox'` | Exit 0 | Exit 0 |
| `sh -c '/scratch/busybox echo executed-from-scratch'` | `executed-from-scratch`, exit 0 | `sh: /scratch/busybox: Permission denied`, exit 126 |
| `sh -c '/scratch/demo.sh'` | `interpreted-from-scratch`, exit 0 | `sh: /scratch/demo.sh: Permission denied`, exit 126 |
| `/bin/sh /scratch/demo.sh` | `interpreted-from-scratch`, exit 0 | `interpreted-from-scratch`, exit 0 |

Script setup used `printf "#!/bin/sh\necho interpreted-from-scratch\n" > /scratch/demo.sh && chmod 755 /scratch/demo.sh` through `sh -c`, returning 0 on both Pods. The direct-execution probes use an outer shell to report the conventional exit 126 for a denied executable. This differs from explicitly asking `/bin/sh` to read the script as data.

The directory survey attempted `touch` and removed successful probe files. Both comparison Pods, and the separate stock baseline, returned:

```text
directory=/ write_exit=1
directory=/etc write_exit=1
directory=/tmp write_exit=1
directory=/scratch write_exit=0
directory=/dev/shm write_exit=0
```

The three failed writes each reported `Read-only file system`. The survey is a sample of directories, not an exhaustive filesystem inventory.

Selected mount-point and option fields from `/proc/self/mountinfo` for the baseline:

```text
/ ro,relatime
/scratch rw,relatime
/dev/shm rw,relatime
```

The same fields for the hardened Pod:

```text
/ ro,relatime
/scratch rw,nosuid,nodev,noexec,relatime
/dev/shm rw,relatime
```

The script checked root `ro`, scratch `rw`, all three hardened flags, and absence of `noexec` on baseline scratch. All checks passed. The final probe summaries were:

```text
PASS: rootfs-insecure on kind-security-labs
PASS: rootfs-insecure on kind-security-labs-mounts
PASS: rootfs-hardened on kind-security-labs-mounts
```

## Interpretation and limits

The read-only root filesystem did not prevent execution from a separate writable mount. With the runtime compatibility implementation, the unchanged hardened manifest made scratch storage writable but denied direct execution. An existing interpreter still read and executed its script, demonstrating the control's limit.

Both Pods in the controlled comparison ran on the same custom runtime and image. The stock baseline was an additional check; comparing only a stock baseline against a patched hardened Pod would confound runtime and manifest changes.

`nosuid` and `nodev` were confirmed as mount flags, but their independent behavioral effects were not exercised. `/dev/shm` remained writable; execution from that mount was not tested. No initial compromise, privilege escalation, host escape, production readiness, or local macOS reproduction is claimed.

The [earlier failed run](2026-09-29-github-actions.md) remains evidence that API acceptance and version numbers do not establish runtime support. This completion result is specifically for the pinned custom-runtime environment, not an upstream support announcement.

## Cleanup and publication

The stock baseline cluster was deleted before the custom build. The comparison cluster was deleted after the probes, and the workflow completed successfully. No cluster remains available for an interactive shell. No binary, kubeconfig, credentials, or raw host mount paths were committed; this is a reviewed summary linked to the actual run.
