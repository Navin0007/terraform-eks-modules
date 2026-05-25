#!/usr/bin/env bash
# Backward-compatible entrypoint — delegates to ensure-node-cluster-auth.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ensure-node-cluster-auth.sh
source "${SCRIPT_DIR}/ensure-node-cluster-auth.sh"
ensure_node_cluster_auth
