# Kubernetes Security

| Lab | Security question | Status |
| --- | --- | --- |
| [01 — Read-only root filesystem and writable volumes](01-readonly-rootfs-writable-volume/README.md) | Can a non-root process execute from writable scratch storage despite a read-only root filesystem? | Complete remotely: baseline and hardening validated; comparison requires custom lab runtime |

Lab 01's [completed comparison](01-readonly-rootfs-writable-volume/evidence/2026-09-29-completed-comparison.md) includes actual execution results, the interpreter limitation, and custom runtime provenance. The [initial compatibility failure](01-readonly-rootfs-writable-volume/evidence/2026-09-29-github-actions.md) remains preserved. Further labs have not been implemented. Use [the lab template](../templates/lab-README.md) for future experiments.
