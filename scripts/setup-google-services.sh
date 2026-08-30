#!/usr/bin/env bash
set -euo pipefail

target="android/app/google-services.json"
secret="${GOOGLE_SERVICES_JSON:-}"

if [[ -z "${secret//[[:space:]]/}" ]]; then
  rm -f "$target"
  echo "GOOGLE_SERVICES_JSON is empty; skipping google-services.json."
  exit 0
fi

python3 - "$target" <<'PY'
import base64
import json
import os
import pathlib
import sys

target = pathlib.Path(sys.argv[1])
secret = os.environ.get("GOOGLE_SERVICES_JSON", "")


def write_json(text: str, source: str) -> None:
    json.loads(text)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text.rstrip("\n") + "\n", encoding="utf-8")
    print(f"Prepared {target} from {source}.")


try:
    write_json(secret, "raw GOOGLE_SERVICES_JSON")
except Exception:
    pass
else:
    sys.exit(0)

candidate = "".join(secret.split())
try:
    decoded = base64.b64decode(candidate, validate=True).decode("utf-8")
    write_json(decoded, "base64-encoded GOOGLE_SERVICES_JSON")
except Exception as exc:
    print(
        "ERROR: GOOGLE_SERVICES_JSON must be either raw JSON or base64-encoded JSON.",
        file=sys.stderr,
    )
    print(f"DETAIL: {exc}", file=sys.stderr)
    sys.exit(1)
PY
