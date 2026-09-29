# Security engineering labs

Hands-on personal learning using synthetic systems and data. Each experiment starts with a question, records a prediction, and compares it with observed evidence. No employer infrastructure or material belongs here.

## Learning areas

- [01-linux-security](01-linux-security/)
- [02-container-security](02-container-security/)
- [03-kubernetes-security](03-kubernetes-security/)
- [04-cicd-security](04-cicd-security/)
- [05-identity-workload-auth](05-identity-workload-auth/)
- [06-pki-certificates](06-pki-certificates/)
- [07-detection-engineering](07-detection-engineering/)
- [08-ai-agent-security](08-ai-agent-security/)

## First experiment

[Read-only root filesystem and writable volumes](03-kubernetes-security/01-readonly-rootfs-writable-volume/README.md) — **complete in the documented remote lab environment**. Baseline and hardened comparison reproduced on GitHub Actions; the comparison uses an explicitly documented custom containerd build. Includes reviewed evidence and a reproducible manual workflow.

## From security news to a portfolio entry

1. Select one primary source and record its publication date and precise claim.
2. Turn that claim into a small, falsifiable hypothesis using the [lab template](templates/lab-README.md).
3. Predict outcomes before executing commands locally.
4. Record versions, image IDs, commands, exit codes, and sanitized observations.
5. Compare one control at a time; describe limitations and alternative explanations.
6. Publish a short write-up: question → architecture → evidence → implications → lessons. Link to the reproducible lab and label unfinished work honestly.

Weekly reading is an input to experiments, not evidence that an experiment succeeded. Keep personal conclusions in your own words. The first lab links a recent Kubernetes storage-hardening announcement to a testable mount-boundary claim.

## Safety and evidence

Only synthetic/sample resources. No real credentials or secrets. Git ignore patterns are convenience filters, not a secret detector. Review staged files before committing or publishing. Raw local evidence is ignored; explicitly curate sanitized evidence for the portfolio.
