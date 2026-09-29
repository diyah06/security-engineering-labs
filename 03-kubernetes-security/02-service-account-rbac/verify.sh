#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
k=(kubectl --context kind-rbac-lab --request-timeout=30s)
run() {
  printf '\n$'
  printf ' %q' "$@"
  printf '\n'
  "$@"
}
run "${k[@]}" version
run "${k[@]}" get nodes -o 'custom-columns=NAME:.metadata.name,VERSION:.status.nodeInfo.kubeletVersion,RUNTIME:.status.nodeInfo.containerRuntimeVersion'
run "${k[@]}" apply -f manifests/fixtures.yaml
"${k[@]}" -n rbac-lab create configmap rbac-probes --from-file=probe.py --dry-run=client -o yaml | "${k[@]}" apply -f -
run "${k[@]}" apply --dry-run=server --validate=strict -f manifests/insecure.yaml
run "${k[@]}" apply -f manifests/insecure.yaml
run "${k[@]}" apply --dry-run=server --validate=strict -f manifests/pod.yaml
run "${k[@]}" apply -f manifests/pod.yaml
run "${k[@]}" -n rbac-lab wait --for=condition=Ready pod/rbac-client --timeout=180s
run "${k[@]}" -n rbac-lab get pod/rbac-client -o 'jsonpath={.status.containerStatuses[0].imageID}{"\n"}'
pod_uid=$("${k[@]}" -n rbac-lab get pod/rbac-client -o jsonpath='{.metadata.uid}')
run "${k[@]}" -n rbac-lab exec rbac-client -- python /probes/probe.py baseline
run "${k[@]}" apply --dry-run=server --validate=strict -f manifests/hardened.yaml
# Same Role and RoleBinding: replace broad rules, do not add a second grant.
run "${k[@]}" apply -f manifests/hardened.yaml
run "${k[@]}" -n rbac-lab exec rbac-client -- python /probes/probe.py hardened
[[ "$pod_uid" == "$("${k[@]}" -n rbac-lab get pod/rbac-client -o jsonpath='{.metadata.uid}')" ]]
echo 'PASS: same Pod identity before and after hardening'
value=$("${k[@]}" -n rbac-lab get configmap app-config -o jsonpath='{.data.probe}')
[[ "$value" == baseline ]]
echo 'PASS: denied hardened patch left the baseline marker unchanged'
