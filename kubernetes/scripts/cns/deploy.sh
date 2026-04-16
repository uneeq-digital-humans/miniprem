#!/bin/bash

################################################################################
# MiniPrem CNS (Cloud Native Stack) Deployment Router
#
# This script routes CNS deployment to either local or remote installation
# based on the CNS_DEPLOY_TYPE environment variable set by the main deploy.sh
#
# Environment Variables (set by parent script):
#   CNS_DEPLOY_TYPE  - "local" or "remote"
#   CNS_K8S_TYPE     - "microk8s" or "kubeadm"
#   CNS_REMOTE_HOST  - Target hostname/IP (for remote deployments)
#   CNS_REMOTE_USER  - SSH username (for remote deployments)
#   CNS_SSH_KEY      - SSH key path (for remote deployments)
#
# Usage:
#   ./deploy.sh                    # Uses environment variables
#   CNS_DEPLOY_TYPE=local ./deploy.sh
################################################################################

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes (define BEFORE sourcing common functions to avoid readonly conflicts)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

print_color() { echo -e "${1}${2}${NC}"; }
info() { print_color "$BLUE" "ℹ️  $*"; }
success() { print_color "$GREEN" "✅ $*"; }
warning() { print_color "$YELLOW" "⚠️  $*"; }
error() { print_color "$RED" "❌ $*"; }

# Source common functions (optional - colors already defined above)
source "$SCRIPT_DIR/../common/deployment-functions.sh" 2>/dev/null || true

################################################################################
# Configuration
################################################################################

CNS_DEPLOY_TYPE="${CNS_DEPLOY_TYPE:-local}"
CNS_K8S_TYPE="${CNS_K8S_TYPE:-microk8s}"
CNS_REMOTE_HOST="${CNS_REMOTE_HOST:-}"
CNS_REMOTE_USER="${CNS_REMOTE_USER:-ubuntu}"
CNS_SSH_KEY="${CNS_SSH_KEY:-~/.ssh/id_rsa}"

################################################################################
# Main
################################################################################

main() {
    print_color "$BOLD" "
╔═══════════════════════════════════════════════════════════════╗
║        NVIDIA Cloud Native Stack (CNS) Deployment             ║
╚═══════════════════════════════════════════════════════════════╝
"

    info "Deployment Type: $CNS_DEPLOY_TYPE"
    info "Kubernetes Type: $CNS_K8S_TYPE"

    if [[ "$CNS_DEPLOY_TYPE" == "remote" ]]; then
        info "Target: $CNS_REMOTE_USER@$CNS_REMOTE_HOST"
    fi
    echo ""

    case "$CNS_DEPLOY_TYPE" in
        local)
            if [[ -f "$SCRIPT_DIR/deploy-local.sh" ]]; then
                exec "$SCRIPT_DIR/deploy-local.sh" "$@"
            else
                error "Local deployment script not found: $SCRIPT_DIR/deploy-local.sh"
                exit 1
            fi
            ;;
        remote)
            if [[ -f "$SCRIPT_DIR/deploy-remote.sh" ]]; then
                exec "$SCRIPT_DIR/deploy-remote.sh" "$@"
            else
                error "Remote deployment script not found: $SCRIPT_DIR/deploy-remote.sh"
                exit 1
            fi
            ;;
        *)
            error "Unknown deployment type: $CNS_DEPLOY_TYPE"
            echo "Valid options: local, remote"
            exit 1
            ;;
    esac
}

main "$@"
