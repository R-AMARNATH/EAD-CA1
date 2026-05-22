#!/usr/bin/env bash
set -euo pipefail
LOG=/var/lib/rancher/k3s/server/logs/kube-audit.log
if [ ! -f "$LOG" ]; then
  echo "Audit log not found at: $LOG"
  echo "Check that audit logging is enabled and k3s restarted."
  exit 0
fi
echo "[audit] showing last 120 lines:"
sudo tail -n 120 "$LOG" | sed -n '1,120p'
echo "----"
echo "[audit] high-signal grep (best-effort):"
echo "pods/exec:"
sudo grep -i "pods/exec" -n "$LOG" | tail -n 20 || true
echo "secrets:"
sudo grep -i "\"secrets\"" -n "$LOG" | tail -n 20 || true
echo "rbac writes:"
sudo egrep -i "clusterrolebinding|clusterrole|rolebinding|role\"" "$LOG" | tail -n 20 || true
