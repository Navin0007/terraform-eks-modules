#!/usr/bin/env bash
# Wrapper — canonical script lives in modules/eks-validation/scripts/.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec bash "${ROOT}/modules/eks-validation/scripts/validate-eks-cluster.sh" "$@"
