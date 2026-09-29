# Kubernetes Security

| Lab | Security question | Status |
| --- | --- | --- |
| [01 — Read-only root filesystem and writable volumes](01-readonly-rootfs-writable-volume/README.md) | Can a non-root process execute from writable scratch storage despite a read-only root filesystem? | Baseline reproduced remotely; hardened comparison blocked by node feature compatibility |

Lab 01's [reviewed evidence](01-readonly-rootfs-writable-volume/evidence/2026-09-29-github-actions.md) distinguishes observed baseline behavior from untested hardening expectations. Further labs have not been implemented. Use [the lab template](../templates/lab-README.md) for future experiments.
