#!/bin/bash

################################################################################
# MiniPrem CNS Restart Script
#
# Restarts the CNS deployment by scaling Renny replicas back up.
# If no previous replica count is saved, uses the count from config file.
#
# Usage:
#   ./restart.sh                              # Local restart
#   ./restart.sh 4                            # Restart with 4 replicas
#   CNS_REMOTE_HOST=x.x.x.x ./restart.sh     # Remote restart
################################################################################

set -euo pipefail

# Color codes
BOLD='\033[1m'
NC='\033[0m'

info() { echo "ℹ️  $*"; }
success() { echo "✅ $*"; }
warning() { echo "⚠️  $*"; }
error() { echo "❌ $*"; }

################################################################################
# Configuration
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CNS_K8S_TYPE="${CNS_K8S_TYPE:-kubeadm}"
CNS_REMOTE_HOST="${CNS_REMOTE_HOST:-}"
CNS_REMOTE_USER="${CNS_REMOTE_USER:-ubuntu}"
CNS_SSH_KEY="${CNS_SSH_KEY:-~/.ssh/id_rsa}"
CNS_CONFIG_FILE="$SCRIPT_DIR/.cns_config"

CNS_SSH_KEY=$(eval echo "$CNS_SSH_KEY")

# Get replica count from argument, saved file, or config
REPLICAS="${1:-}"
if [[ -z "$REPLICAS" ]]; then
    # Try to load from last stop
    if [[ -f "$SCRIPT_DIR/.cns_last_replicas" ]]; then
        REPLICAS=$(cat "$SCRIPT_DIR/.cns_last_replicas")
        info "Using saved replica count from last stop: $REPLICAS"
    # Try to load from config
    elif [[ -f "$CNS_CONFIG_FILE" ]]; then
        source "$CNS_CONFIG_FILE"
        # Default to 4 if not set
        REPLICAS="${RENNY_REPLICAS:-4}"
        info "Using replica count from config: $REPLICAS"
    else
        REPLICAS=4
        info "Using default replica count: $REPLICAS"
    fi
fi

################################################################################
# Command Execution Helper
################################################################################

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

run_kubectl() {
    local kubectl_cmd="kubectl"
    if [[ "$CNS_K8S_TYPE" == "microk8s" ]]; then
        kubectl_cmd="microk8s kubectl"
    fi

    if [[ -n "$CNS_REMOTE_HOST" ]]; then
        ssh $SSH_OPTS -i "$CNS_SSH_KEY" "$CNS_REMOTE_USER@$CNS_REMOTE_HOST" "$kubectl_cmd $*"
    else
        $kubectl_cmd "$@"
    fi
}

################################################################################
# Main
################################################################################

main() {
    echo "
╔═══════════════════════════════════════════════════════════════╗
║                   Restarting CNS Deployment                   ║
╚═══════════════════════════════════════════════════════════════╝
"

    if [[ -n "$CNS_REMOTE_HOST" ]]; then
        info "Target: $CNS_REMOTE_USER@$CNS_REMOTE_HOST"
    else
        info "Target: Local cluster"
    fi
    echo ""

    # Check if Renny deployment exists
    if ! run_kubectl get deployment renny -n uneeq &>/dev/null; then
        error "Renny deployment not found in uneeq namespace"
        echo "  Use deploy-local.sh to deploy first."
        exit 1
    fi

    # Get current replica count
    local current_replicas
    current_replicas=$(run_kubectl get deployment renny -n uneeq -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    info "Current replica count: $current_replicas"

    # Scale up
    info "Scaling Renny deployment to $REPLICAS replicas..."
    run_kubectl scale deployment renny -n uneeq --replicas="$REPLICAS"

    # Wait for pods to be ready
    info "Waiting for pods to be ready..."
    local timeout=300  # 5 minutes - Renny can take a while to start
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        local ready_pods
        ready_pods=$(run_kubectl get deployment renny -n uneeq -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        ready_pods="${ready_pods:-0}"

        if [[ "$ready_pods" -ge "$REPLICAS" ]]; then
            break
        fi

        echo "  Waiting... ($ready_pods/$REPLICAS pods ready)"
        sleep 10
        ((elapsed+=10))
    done

    # Verify restart
    local final_ready
    final_ready=$(run_kubectl get deployment renny -n uneeq -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    final_ready="${final_ready:-0}"

    echo ""
    if [[ "$final_ready" -ge "$REPLICAS" ]]; then
        success "CNS deployment restarted successfully"
        echo ""
        echo "Status:"
        run_kubectl get pods -n uneeq
    else
        warning "Not all pods are ready yet ($final_ready/$REPLICAS)"
        echo ""
        echo "Pods may still be starting. Check status with:"
        echo "  ./miniprem.sh status"
        echo ""
        run_kubectl get pods -n uneeq
    fi
}

main "$@"
