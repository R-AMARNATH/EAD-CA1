#!/usr/bin/env bash
set -euo pipefail
URL=${1:-http://localhost/}
OUT=reports
mkdir -p "$OUT"
echo "[dast] nuclei against: $URL"
docker run --rm -v "$PWD/$OUT:/out" projectdiscovery/nuclei:latest \
  -u "$URL" -jsonl -o /out/nuclei.jsonl || true
echo "[dast] wrote: $OUT/nuclei.jsonl"
