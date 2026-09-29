"""Real in-Pod API requests. Never print tokens or API response bodies."""
import json
import ssl
import sys
import urllib.error
import urllib.request
from pathlib import Path

phase = sys.argv[1]
if phase not in {"baseline", "hardened"}:
    raise SystemExit("Expected baseline or hardened")
credentials = Path("/var/run/secrets/kubernetes.io/serviceaccount")
tls = ssl.create_default_context(cafile=str(credentials / "ca.crt"))
token = (credentials / "token").read_text().strip()
base = "https://kubernetes.default.svc"


def request(method, path, body=None):
    headers = {"Authorization": "Bearer " + token}
    if body is not None:
        headers["Content-Type"] = (
            "application/merge-patch+json" if method == "PATCH" else "application/json"
        )
    req = urllib.request.Request(
        base + path,
        data=None if body is None else json.dumps(body).encode(),
        headers=headers,
        method=method,
    )
    try:
        with urllib.request.urlopen(req, context=tls, timeout=15) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        return error.code, json.load(error)


# Authenticate as the real Pod identity, not administrator impersonation.
status, identity = request(
    "POST", "/apis/authentication.k8s.io/v1/selfsubjectreviews",
    {"apiVersion": "authentication.k8s.io/v1", "kind": "SelfSubjectReview"},
)
expected_identity = "system:serviceaccount:rbac-lab:config-reader"
if status != 201 or identity.get("status", {}).get("userInfo", {}).get("username") != expected_identity:
    raise SystemExit("FAIL: unexpected authenticated identity (response omitted)")
print(f"IDENTITY {expected_identity}", flush=True)

scope = "/api/v1/namespaces/rbac-lab"
restricted = 200 if phase == "baseline" else 403
cases = [
    ("get required config", "GET", scope + "/configmaps/app-config", None, 200),
    ("list configs", "GET", scope + "/configmaps", None, restricted),
    ("get unrelated config", "GET", scope + "/configmaps/other-config", None, restricted),
    ("get empty synthetic secret", "GET", scope + "/secrets/synthetic-empty", None, restricted),
    ("patch required config", "PATCH", scope + "/configmaps/app-config", {"data": {"probe": phase}}, restricted),
    ("get foreign config", "GET", "/api/v1/namespaces/rbac-lab-other/configmaps/foreign-config", None, 403),
    ("list cluster nodes", "GET", "/api/v1/nodes", None, 403),
]
for label, method, path, body, expected in cases:
    status, response = request(method, path, body)
    print(f"{phase}: {label}: HTTP {status}; expected {expected}", flush=True)
    if status != expected or (expected == 403 and response.get("reason") != "Forbidden"):
        raise SystemExit("FAIL: unexpected authorization result (response omitted)")
print(f"PASS: {phase} — 7 API permission checks", flush=True)
