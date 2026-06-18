#!/usr/bin/env python3
"""Reconstruct the local plaintext backend-secrets file for an environment by
pulling the live `echo-backend-secrets` Secret from its cluster.

Read-only against the cluster. Writes the base64 `data` values straight to
secrets/backend-secrets-<env>.yaml in the format secret-manager.sh expects.
Secret VALUES are never printed — only key names + count, so the transcript
stays clean. Run before adding a new key so a reseal won't purge anything.

Usage: python3 scripts/reconstruct-secrets.py <dev|testing|prod> [--comments]

--comments decodes each value and writes it as `# <plaintext>` comment lines
above the key (matching secret-manager.sh's human-readable format). Multi-line
values get one comment line per line so the YAML stays valid. Decoded values
are still only written to the file, never printed.
"""
import sys
import json
import base64
import subprocess

ENVS = {
    "dev": ("do-ams3-dbr-echo-dev-k8s-cluster", "echo-dev"),
    "testing": ("do-ams3-dbr-echo-testing-k8s-cluster", "echo-testing"),
    "prod": ("do-ams3-dbr-echo-prod-k8s-cluster", "echo-prod"),
}

def main() -> int:
    argv = sys.argv[1:]
    comments = "--comments" in argv
    argv = [a for a in argv if a != "--comments"]
    if len(argv) != 1 or argv[0] not in ENVS:
        print("usage: reconstruct-secrets.py <dev|testing|prod> [--comments]")
        return 2
    env = argv[0]
    ctx, ns = ENVS[env]

    out = subprocess.run(
        ["kubectl", "--context", ctx, "get", "secret",
         "echo-backend-secrets", "-n", ns, "-o", "json"],
        capture_output=True, text=True,
    )
    if out.returncode != 0:
        sys.stderr.write(out.stderr)
        return 1

    data = json.loads(out.stdout).get("data", {})
    keys = sorted(data)

    lines = [
        "apiVersion: v1",
        "kind: Secret",
        "metadata:",
        "  name: echo-backend-secrets",
        f"  namespace: {ns}",
        "type: Opaque",
        "data:",
    ]
    # values are already base64 in .data; write verbatim, never print them
    for k in keys:
        if comments:
            try:
                plain = base64.b64decode(data[k]).decode("utf-8")
                # one comment line per line so multi-line values stay valid YAML
                for cl in plain.split("\n"):
                    lines.append(f"  # {cl}")
            except (ValueError, UnicodeDecodeError):
                lines.append("  # <binary value, not shown>")
        lines.append(f"  {k}: {data[k]}")

    path = f"secrets/backend-secrets-{env}.yaml"
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")

    print(f"{env}: wrote {len(keys)} keys -> {path}")
    for k in keys:
        print(f"  {k}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
