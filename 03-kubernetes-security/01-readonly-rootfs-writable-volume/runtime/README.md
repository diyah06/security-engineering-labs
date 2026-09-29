# Lab-only containerd compatibility patch

This is experimental lab infrastructure, **not an upstream containerd release or a production recommendation**. The stock kind node could not schedule the hardened Pod; see the [original evidence](../evidence/2026-09-29-github-actions.md).

The patch targets containerd v2.4.0, commit `a7fe631d96c08fb14cf8eff0afdc280e99c30a94`. Its vendored Kubernetes 1.37 CRI definitions include `Mount.mount_options` and `RuntimeFeatures.mount_options`, but the inspected runtime implementation does not forward/advertise them. The patch:

1. Passes the three allowed CRI security flags to OCI bind mounts, preserving unrelated options and removing conflicts and duplicates.
2. Rejects unknown or weakening options.
3. Advertises support on Linux.
4. Adds tests for unchanged baseline options, security flags, conflicts, duplicates, invalid input, and input preservation.

The [workflow](../../../.github/workflows/lab01.yml) builds this source on a temporary Linux runner, runs targeted tests, labels the binary `v2.4.0-lab01`, and records binary and patch checksums. It copies the binary into a local image derived from the pinned kind node. No custom image or binary is published or installed on the learner's Mac. Both comparison Pods use this same runtime and the original manifests.

Successful unit tests alone do not validate mount enforcement. The [completed run](../evidence/2026-09-29-completed-comparison.md) additionally observed writable scratch storage, the requested mount flags, denied direct execution, and successful interpreter execution in real Pods. Results apply to this custom build only; they must not be presented as stock-runtime support.

Design reference: [Kubernetes KEP-5855 runtime changes](https://www.kubernetes.dev/resources/keps/5855/). Upstream source: [containerd v2.4.0](https://github.com/containerd/containerd/tree/a7fe631d96c08fb14cf8eff0afdc280e99c30a94). Compatibility code is limited to this synthetic experiment; no claim is made about untested volume types or production readiness.
