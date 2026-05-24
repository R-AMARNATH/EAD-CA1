#!/usr/bin/env bash
set -euo pipefail

echo "== Plain HTTP root =="
curl -i http://localhost/ || true
echo

echo "== HTTPS root (self-signed) =="
curl -k -i https://localhost/ || true
echo

echo "== HTTPS architecture route without token =="
curl -k -i https://localhost/api/arch || true
echo

if [ -n "${ACCESS_TOKEN:-}" ]; then
  echo "== HTTPS architecture route with token =="
  curl -k -i https://localhost/api/arch \
    -H "Authorization: Bearer $ACCESS_TOKEN" || true
  echo

  echo "== HTTPS checkout route with token =="
  curl -k -i https://localhost/api/checkout \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H 'Content-Type: application/json' \
    -d '{"sku":1,"subtotal":100}' || true
  echo
fi
