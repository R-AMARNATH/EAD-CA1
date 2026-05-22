#!/usr/bin/env bash
set -euo pipefail
REPO=${1:-.}
mkdir -p "$REPO/.reports"
echo "[sca] dependency-check scanning: $REPO"
echo "This may take time and may need outbound access to vulnerability data."
docker run --rm \
  -v "$REPO:/src" \
  -v "$REPO/.reports:/report" \
  owasp/dependency-check:latest \
  --scan /src \
  --format "HTML" \
  --out /report \
  --project "labB-sca" || true
echo "[sca] wrote under: $REPO/.reports/"
