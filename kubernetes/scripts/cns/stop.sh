#!/bin/bash

################################################################################
# MiniPrem CNS Stop Script
#
# Stops the CNS deployment by scaling Renny replicas to 0.
# Use restart.sh to bring services back up.
#
# Usage:
#   ./stop.sh                              # Local stop
#   CNS_REMOTE_HOST=x.x.x.x ./stop.sh     # Remote stop
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

CNS_K8S_TYPE="${CNS_K8S_TYPE:-microk8s}"
CNS_REMOTE_HOST="${CNS_REMOTE_HOST:-}"
CNS_REMOTE_USER="${CNS_REMOTE_USER:-ubuntu}"
CNS_SSH_KEY="${CNS_SSH_KEY:-~/.ssh/id_rsa}"

CNS_SSH_KEY=$(eval echo "$CNS_SSH_KEY")

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
║                   Stopping CNS Deployment                     ║
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
        warning "Renny deployment not found in uneeq namespace"
        echo "  Use deploy-local.sh to deploy first."
        exit 1
    fi

    # Get current replica count for later restart
    local current_replicas
    current_replicas=$(run_kubectl get deployment renny -n uneeq -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")

    # Save current replica count for restart
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo "$current_replicas" > "$SCRIPT_DIR/.cns_last_replicas"
    info "Saved current replica count: $current_replicas"

    # Scale down to 0
    info "Scaling Renny deployment to 0 replicas..."
    run_kubectl scale deployment renny -n uneeq --replicas=0

    # Wait for pods to terminate
    info "Waiting for pods to terminate..."
    local timeout=60
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        local running_pods
        running_pods=$(run_kubectl get pods -n uneeq --no-headers 2>/dev/null | wc -l || echo "0")
        if [[ "$running_pods" -eq 0 ]]; then
            break
        fi
        echo "  Waiting... ($running_pods pods still running)"
        sleep 5
        ((elapsed+=5))
    done

    # Verify stop
    local final_pods
    final_pods=$(run_kubectl get pods -n uneeq --no-headers 2>/dev/null | wc -l || echo "0")

    if [[ "$final_pods" -eq 0 ]]; then
        success "CNS deployment stopped successfully"
        echo ""
        echo "To restart, run: ./miniprem.sh start"
        echo "To check status, run: ./miniprem.sh status"
    else
        warning "Some pods may still be terminating"
        run_kubectl get pods -n uneeq
    fi
}

main "$@"
