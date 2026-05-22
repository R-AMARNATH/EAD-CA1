#!/usr/bin/env bash
set -euo pipefail
IMG=${1:-}
REPO=${2:-.}
if [ -z "$IMG" ]; then
  echo "Usage: $0 <image:tag> [repo_path]"
  exit 1
fi
mkdir -p "$REPO/.reports"
OUT="$REPO/.reports/trivy-$(echo "$IMG" | tr '/:' '__').txt"
echo "[image] trivy scanning: $IMG"
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:latest image \
  --no-progress "$IMG" > "$OUT" || true
echo "[image] wrote: $OUT"
