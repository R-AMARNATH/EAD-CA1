#!/usr/bin/env bash
set -euo pipefail
URL=${1:-http://localhost/}
OUT=reports
mkdir -p "$OUT"
echo "[dast] ZAP baseline against: $URL"
docker run --rm -t -v "$PWD/$OUT:/zap/wrk" ghcr.io/zaproxy/zaproxy:stable \
  zap-baseline.py -t "$URL" -r zap-report.html || true
echo "[dast] wrote: $OUT/zap-report.html"
