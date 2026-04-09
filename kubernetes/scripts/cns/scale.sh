#!/bin/bash

################################################################################
# MiniPrem CNS Scaling Script
#
# Scales Renny replicas on CNS deployment.
#
# Usage:
#   ./scale.sh <replica_count>
#   ./scale.sh 4                     # Scale to 4 Renny instances
################################################################################

set -euo pipefail

# Color codes
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

################################################################################
# Configuration
################################################################################

CNS_K8S_TYPE="${CNS_K8S_TYPE:-microk8s}"
CNS_REMOTE_HOST="${CNS_REMOTE_HOST:-}"
CNS_REMOTE_USER="${CNS_REMOTE_USER:-ubuntu}"
CNS_SSH_KEY="${CNS_SSH_KEY:-~/.ssh/id_rsa}"
NAMESPACE="${NAMESPACE:-uneeq}"
DEPLOYMENT="${DEPLOYMENT:-renny}"

CNS_SSH_KEY=$(eval echo "$CNS_SSH_KEY")

################################################################################
# SSH Helper
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
# Scaling Functions
################################################################################

get_current_replicas() {
    run_kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0"
}

get_available_gpus() {
    run_kubectl get nodes -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}' 2>/dev/null || echo "0"
}

scale_deployment() {
    local target_replicas=$1

    info "Scaling $DEPLOYMENT to $target_replicas replicas..."

    run_kubectl scale deployment "$DEPLOYMENT" -n "$NAMESPACE" --replicas="$target_replicas"

    # Wait for rollout
    info "Waiting for rollout to complete..."
    run_kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout=300s || true

    success "Scaling complete"
}

################################################################################
# Main
################################################################################

main() {
    local target_replicas="${1:-}"

    print_color "$BOLD" "
╔═══════════════════════════════════════════════════════════════╗
║              CNS Renny Scaling ($CNS_K8S_TYPE)                 ║
╚═══════════════════════════════════════════════════════════════╝
"

    if [[ -n "$CNS_REMOTE_HOST" ]]; then
        info "Target: $CNS_REMOTE_USER@$CNS_REMOTE_HOST"
    else
        info "Target: Local cluster"
    fi
    echo ""

    # Get current state
    local current_replicas=$(get_current_replicas)
    local available_gpus=$(get_available_gpus)

    info "Current Renny replicas: $current_replicas"
    info "Available GPU slots: $available_gpus"
    echo ""

    # If no target specified, prompt
    if [[ -z "$target_replicas" ]]; then
        echo "Current configuration:"
        run_kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o wide 2>/dev/null || warning "Deployment not found"
        echo ""

        read -p "Enter desired replica count [$current_replicas]: " target_replicas
        target_replicas="${target_replicas:-$current_replicas}"
    fi

    # Validate
    if ! [[ "$target_replicas" =~ ^[0-9]+$ ]]; then
        error "Invalid replica count: $target_replicas"
        exit 1
    fi

    if [[ "$target_replicas" -gt "$available_gpus" ]]; then
        warning "Requested $target_replicas replicas but only $available_gpus GPU slots available"
        warning "Some pods may remain pending until GPU time-slicing is configured"
    fi

    # Scale
    if [[ "$target_replicas" -eq "$current_replicas" ]]; then
        info "Already at $target_replicas replicas. No change needed."
    else
        scale_deployment "$target_replicas"
    fi

    # Show final state
    echo ""
    print_color "$BOLD" "=== Current Deployment Status ==="
    run_kubectl get pods -n "$NAMESPACE" -l app=renny 2>/dev/null || run_kubectl get pods -n "$NAMESPACE"
}

main "$@"
