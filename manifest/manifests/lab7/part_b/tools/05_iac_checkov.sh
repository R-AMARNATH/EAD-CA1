#!/usr/bin/env bash
set -euo pipefail
REPO=${1:-.}
mkdir -p "$REPO/.reports"
echo "[iac] checkov scanning directory: $REPO"
docker run --rm -v "$REPO:/repo" -w /repo bridgecrew/checkov:latest \
  -d . -o json > .reports/checkov.json || true
echo "[iac] wrote: $REPO/.reports/checkov.json"
