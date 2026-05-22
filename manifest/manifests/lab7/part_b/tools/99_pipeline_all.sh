#!/usr/bin/env bash
set -euo pipefail
REPO=${1:-.}
echo "[pipeline] running all stages for: $REPO"
bash "$(dirname "$0")/01_secrets_gitleaks.sh" "$REPO"
bash "$(dirname "$0")/02_sast_semgrep.sh" "$REPO"
bash "$(dirname "$0")/03_sca_dependency_check.sh" "$REPO"
bash "$(dirname "$0")/05_iac_checkov.sh" "$REPO"
bash "$(dirname "$0")/06_iac_kubesec.sh" "$REPO"
echo "[pipeline] done. Reports are in: $REPO/.reports/"
