# Evidence

Status: complete in the documented remote environment, including the custom-runtime hardened comparison.

- [Completed baseline and hardened comparison](2026-09-29-completed-comparison.md): observed mount flags, execution denial, interpreter behavior, versions, and checksums.
- [Initial stock-runtime compatibility failure](2026-09-29-github-actions.md): preserved historical result, not the current completion status.

Save local transcripts under `raw/` (ignored by Git).
Before publishing, copy only reviewed synthetic output into a curated Markdown file.
Record date, OS/CPU, kind/Kubernetes/runtime versions, imageID, commands, stderr, exit codes, mount flags, and unexpected outcomes.
