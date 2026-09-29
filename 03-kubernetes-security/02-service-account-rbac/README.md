# Lab 02: service-account RBAC and least privilege

Status: prepared, not yet run.

## Fundamentals

Authentication identifies a caller; authorization decides which requests that caller may make. A ServiceAccount provides a workload identity. A Role grants verbs on resources within one namespace; a RoleBinding grants those rules to an identity. RBAC grants are additive, so adding a restrictive Role does not cancel an existing broad grant.

The application requirement here is one named GET: read `app-config` in `rbac-lab`. The baseline unnecessarily grants get/list/watch/patch on all ConfigMaps and Secrets in that namespace. Hardening replaces the same Role's rules with `get` on ConfigMap `app-config`, retaining the same binding and workload identity. See [hardening.diff](hardening.diff).

## Architecture

GitHub Ubuntu runner → Docker → stock kind Kubernetes node → `rbac-lab` namespace → `rbac-client` Pod using ServiceAccount `config-reader` → HTTPS Kubernetes API.

The Pod runs non-root with a read-only root filesystem and intentionally mounts its service-account token because its job is to call the API. Python's standard library validates the API server certificate using the mounted cluster CA. The token is read only inside the Pod and never printed or copied into evidence. A second namespace holds a synthetic ConfigMap for boundary checks. The Secret fixture is empty and contains no credential.

## Threat model

Assume a process can already use the workload's service-account identity. The risk is excess API permissions: reading unrelated configuration or Secret objects, enumerating resources, or modifying application configuration. We demonstrate those actions only against synthetic fixtures in a disposable cluster. Initial compromise, token theft, network isolation, host access, and cluster-admin compromise are outside scope.

## Experiment

The [manual workflow](../../.github/workflows/lab02.yml) creates a dedicated stock kind cluster, invokes [verify.sh](verify.sh), and deletes the cluster even on failure. No custom runtime or alpha features are required.

From the repository root, this command starts the remote experiment:

```bash
gh workflow run lab02.yml --repo diyah06/security-engineering-labs --ref main
```

Read the script before running it manually. It applies synthetic fixtures, creates a ConfigMap containing [probe.py](probe.py), applies the baseline Role and Pod, waits for readiness, and runs actual API requests inside the Pod. A SelfSubjectReview verifies the authenticated username before the probes. It then updates the same Role with the hardened rules and repeats the requests in the same Pod. A final administrator read verifies that the denied patch did not change the baseline marker.

Server-side dry-run checks validate the RBAC and Pod manifests before applying them. The script fails on unexpected HTTP status codes, and checks that a denial is specifically `Forbidden`, not a TLS, authentication, missing-resource, or network error. Response bodies and tokens are omitted from logs. The recorded imageID identifies the resolved Python image; its source tag is mutable.

## Expected behavior

| Request | Baseline | Hardened |
| --- | --- | --- |
| Get `app-config` | 200 | 200 |
| List ConfigMaps | 200 | 403 |
| Get `other-config` | 200 | 403 |
| Get empty synthetic Secret | 200 | 403 |
| Patch `app-config` | 200 | 403 |
| Get ConfigMap in other namespace | 403 | 403 |
| List cluster nodes | 403 | 403 |

These are predictions until a successful run is recorded. The baseline grants `watch`, but this lab does not independently exercise watch streams. Named GET remains usable; clients that need list/watch require a different justified policy.

## Observed behavior

Not run. See [evidence](evidence/README.md) for status. Do not substitute expected HTTP codes for measurements.

## Security implications

Least privilege should preserve the application's required request while removing unrelated resources and write verbs. Namespace-scoped RBAC limits this baseline even before hardening; it does not provide network isolation. Other bindings could still grant access, which is why this experiment uses a fresh cluster and updates the existing Role rather than layering an additional restrictive Role.

## Lessons learned

Pending execution: compare actual HTTP results, verify the identity stays constant, and distinguish resource-name restrictions, verb restrictions, and namespace boundaries. A real-token API test exercises authentication and authorization together; an administrator's impersonation check alone would not test the workload's token path.

## News connection and sources

This is a fundamentals experiment, not a news or CVE reproduction.

- [Kubernetes RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/): Roles, bindings, additive permissions, and resourceNames.
- [Kubernetes authentication](https://kubernetes.io/docs/reference/access-authn-authz/authentication/): service-account identities and SelfSubjectReview.
- [Service accounts](https://kubernetes.io/docs/concepts/security/service-accounts/): workload identity and mounted credentials.
