#!/usr/bin/env bash
set -euo pipefail
REPO=${1:-.}
mkdir -p "$REPO/.reports"
echo "[secrets] gitleaks scanning working tree: $REPO"
docker run --rm -v "$REPO:/repo" -w /repo zricethezav/gitleaks:latest detect \
  --no-git --redact --report-format json --report-path .reports/gitleaks.json || true
echo "[secrets] wrote: $REPO/.reports/gitleaks.json"
