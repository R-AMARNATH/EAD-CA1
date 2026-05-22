#!/usr/bin/env bash
set -euo pipefail
REPO=${1:-.}
mkdir -p "$REPO/.reports"
if [ ! -f "$REPO/semgrep.rules.yaml" ]; then
  echo "Missing semgrep.rules.yaml in repo root."
  echo "Copy it first: cp ~/k8s-labs/labB-security/samples/semgrep.rules.yaml $REPO/"
  exit 1
fi
echo "[sast] semgrep scanning: $REPO"
docker run --rm -v "$REPO:/repo" -w /repo returntocorp/semgrep:latest semgrep \
  --config semgrep.rules.yaml --json -o .reports/semgrep.json || true
echo "[sast] wrote: $REPO/.reports/semgrep.json"
