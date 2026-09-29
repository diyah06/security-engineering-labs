#!/usr/bin/env bash
# Run only against the dedicated lab clusters. No cluster creation or deletion here.
set -euo pipefail

case "${1:-}" in
  baseline) context=kind-security-labs; pods=(rootfs-insecure) ;;
  comparison) context=kind-security-labs-mounts; pods=(rootfs-insecure rootfs-hardened) ;;
  *) echo 'Usage: bash verify.sh baseline|comparison' >&2; exit 2 ;;
esac
cd "$(dirname "$0")"
k=(kubectl --context "$context" --namespace rootfs-lab --request-timeout=30s)

run() {
  printf '\n$'
  printf ' %q' "$@"
  printf '\n'
  "$@"
}

# Check the actual exit code and error text; an unrelated exec failure is not a pass.
expect() {
  local expected=$1 pattern=$2 output rc=0
  shift 2
  printf '\n$'
  printf ' %q' "$@"
  printf '\n'
  output=$("$@" 2>&1) || rc=$?
  printf '%s\nexit=%s; expected=%s\n' "$output" "$rc" "$expected"
  if [[ "$rc" != "$expected" ]] || ! grep -Fq -- "$pattern" <<< "$output"; then
    echo 'FAIL: unexpected result' >&2
    exit 1
  fi
}

run "${k[@]}" version
run "${k[@]}" get nodes -o 'custom-columns=NAME:.metadata.name,KUBERNETES:.status.nodeInfo.kubeletVersion,RUNTIME:.status.nodeInfo.containerRuntimeVersion,OS:.status.nodeInfo.osImage,ARCH:.status.nodeInfo.architecture'
namespace=$("${k[@]}" get namespace rootfs-lab --ignore-not-found -o name)
if [[ -z "$namespace" ]]; then run "${k[@]}" create namespace rootfs-lab; fi
if [[ "$1" == comparison ]]; then
  run "${k[@]}" explain pod.spec.containers.volumeMounts.bindMountOptions
fi

for pod in "${pods[@]}"; do
  manifest=manifests/insecure.yaml
  if [[ "$pod" == rootfs-hardened ]]; then manifest=manifests/hardened.yaml; fi
  run "${k[@]}" apply --dry-run=server --validate=strict -f "$manifest"
  run "${k[@]}" apply -f "$manifest"
  if ! run "${k[@]}" wait --for=condition=Ready "pod/$pod" --timeout=180s; then
    run "${k[@]}" get "pod/$pod" -o 'jsonpath={.status.phase}{"\n"}{.status.conditions}{"\n"}{.status.containerStatuses}{"\n"}'
    exit 1
  fi
  run "${k[@]}" get "pod/$pod" -o 'jsonpath={.status.containerStatuses[0].imageID}{"\n"}'
  expect 0 'uid=1000' "${k[@]}" exec "$pod" -- id

  # Only mount point and flags are printed; host backing paths are omitted.
  mounts=$("${k[@]}" exec "$pod" -- awk '$5 == "/" || $5 == "/scratch" || $5 == "/dev/shm" {print $5, $6}' /proc/self/mountinfo)
  printf '\nMount points and flags for %s:\n%s\n' "$pod" "$mounts"
  root_options=$(awk '$1 == "/" {print $2}' <<< "$mounts")
  scratch_options=$(awk '$1 == "/scratch" {print $2}' <<< "$mounts")
  [[ ",$root_options," == *,ro,* ]]
  [[ ",$scratch_options," == *,rw,* ]]
  if [[ "$pod" == rootfs-hardened ]]; then
    for flag in noexec nosuid nodev; do [[ ",$scratch_options," == *,$flag,* ]]; done
  else
    [[ ",$scratch_options," != *,noexec,* ]]
  fi

  expect 1 'Read-only file system' "${k[@]}" exec "$pod" -- touch /tmp/lab-write-probe
  # Survey additional mounts without assuming every failure is caused by ro.
  run "${k[@]}" exec "$pod" -- sh -c '
    for directory in / /etc /tmp /scratch /dev/shm; do
      probe="${directory%/}/lab-directory-probe"
      rc=0
      touch "$probe" 2>&1 || rc=$?
      printf "directory=%s write_exit=%s\n" "$directory" "$rc"
      if [ "$rc" -eq 0 ]; then rm "$probe" || exit 1; fi
    done'
  expect 0 '' "${k[@]}" exec "$pod" -- sh -c 'touch /scratch/lab-write-probe && rm /scratch/lab-write-probe'
  expect 0 '' "${k[@]}" exec "$pod" -- sh -c 'cp /bin/busybox /scratch/busybox && chmod 755 /scratch/busybox'
  expect 0 '' "${k[@]}" exec "$pod" -- sh -c 'printf "#!/bin/sh\necho interpreted-from-scratch\n" > /scratch/demo.sh && chmod 755 /scratch/demo.sh'
  if [[ "$pod" == rootfs-hardened ]]; then
    expect 126 'Permission denied' "${k[@]}" exec "$pod" -- sh -c '/scratch/busybox echo executed-from-scratch'
    expect 126 'Permission denied' "${k[@]}" exec "$pod" -- sh -c '/scratch/demo.sh'
  else
    expect 0 'executed-from-scratch' "${k[@]}" exec "$pod" -- sh -c '/scratch/busybox echo executed-from-scratch'
    expect 0 'interpreted-from-scratch' "${k[@]}" exec "$pod" -- sh -c '/scratch/demo.sh'
  fi
  expect 0 'interpreted-from-scratch' "${k[@]}" exec "$pod" -- /bin/sh /scratch/demo.sh
  printf '\nPASS: %s on %s\n' "$pod" "$context"
done
