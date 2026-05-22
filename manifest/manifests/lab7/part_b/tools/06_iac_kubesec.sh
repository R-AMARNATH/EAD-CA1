#!/usr/bin/env bash
set -euo pipefail
REPO=${1:-.}
mkdir -p "$REPO/.reports"
echo "[iac] kubesec scanning YAML files under: $REPO"
YAMLS=$(find "$REPO" -maxdepth 6 -type f \( -name '*.yaml' -o -name '*.yml' \) | tr '\n' ' ' || true)
if [ -z "$YAMLS" ]; then
  echo "No YAML files found."
  exit 0
fi
for f in $YAMLS; do
  base=$(basename "$f")
  out="$REPO/.reports/kubesec-${base}.json"
  docker run --rm -i kubesec/kubesec:latest scan /dev/stdin < "$f" > "$out" || true
done
echo "[iac] wrote kubesec reports under: $REPO/.reports/"
