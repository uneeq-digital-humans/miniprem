#!/bin/bash

################################################################################
# MiniPrem CNS Status Script
#
# Shows status of CNS deployment including cluster, GPU, and MiniPrem components.
#
# Usage:
#   ./status.sh                              # Local status
#   CNS_REMOTE_HOST=x.x.x.x ./status.sh     # Remote status
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

run_cmd() {
    if [[ -n "$CNS_REMOTE_HOST" ]]; then
        ssh $SSH_OPTS -i "$CNS_SSH_KEY" "$CNS_REMOTE_USER@$CNS_REMOTE_HOST" "$*"
    else
        eval "$*"
    fi
}

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
# Status Checks
################################################################################

check_kubernetes() {
    echo "=== Kubernetes Cluster ==="

    if [[ "$CNS_K8S_TYPE" == "microk8s" ]]; then
        run_cmd "microk8s status" 2>/dev/null || warning "MicroK8s not running"
    else
        run_kubectl cluster-info 2>/dev/null || warning "Cluster not accessible"
    fi

    echo ""
    run_kubectl get nodes -o wide 2>/dev/null || true
    echo ""
}

check_gpu() {
    echo "=== GPU Status ==="

    # NVIDIA SMI
    echo "NVIDIA Driver:"
    run_cmd "nvidia-smi --query-gpu=name,driver_version,memory.total,memory.used --format=csv" 2>/dev/null || warning "nvidia-smi not available"
    echo ""

    # Kubernetes GPU resources
    echo "Kubernetes GPU Resources:"
    run_kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}Allocatable: {.status.allocatable.nvidia\.com/gpu}{"\t"}Capacity: {.status.capacity.nvidia\.com/gpu}{"\n"}{end}' 2>/dev/null || true
    echo ""
}

check_gpu_operator() {
    echo "=== GPU Operator ==="

    run_kubectl get pods -n gpu-operator 2>/dev/null || warning "GPU Operator namespace not found"
    echo ""
}

check_miniprem_components() {
    echo "=== MiniPrem Components ==="

    echo "Namespaces:"
    run_kubectl get namespaces | grep -E "uneeq|nim|riva|miniprem" 2>/dev/null || echo "  No MiniPrem namespaces found"
    echo ""

    # Check each namespace
    for ns in uneeq nim-operator nim-models nim-rag riva; do
        if run_kubectl get namespace "$ns" &>/dev/null; then
            echo "[$ns]"
            run_kubectl get pods -n "$ns" 2>/dev/null || echo "  No pods"
            echo ""
        fi
    done
}

check_services() {
    echo "=== Services & Endpoints ==="

    echo "Services in uneeq namespace:"
    run_kubectl get svc -n uneeq 2>/dev/null || echo "  None"
    echo ""

    echo "Services in nim-rag namespace:"
    run_kubectl get svc -n nim-rag 2>/dev/null || echo "  None"
    echo ""
}

check_storage() {
    echo "=== Storage ==="

    echo "Persistent Volume Claims:"
    run_kubectl get pvc -A 2>/dev/null || echo "  None"
    echo ""
}

################################################################################
# Summary
################################################################################

show_summary() {
    echo "=== Quick Summary ==="

    # Cluster status
    if run_kubectl get nodes &>/dev/null; then
        local node_count=$(run_kubectl get nodes --no-headers 2>/dev/null | wc -l)
        local ready_nodes=$(run_kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready" || echo "0")
        echo "  Cluster: $ready_nodes/$node_count nodes ready"
    else
        echo "  Cluster: Not accessible"
    fi

    # GPU status
    local gpu_count=$(run_kubectl get nodes -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}' 2>/dev/null || echo "0")
    echo "  GPU slots: $gpu_count available"

    # Renny status
    local renny_ready=$(run_kubectl get deployment renny -n uneeq -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local renny_desired=$(run_kubectl get deployment renny -n uneeq -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    if [[ "$renny_desired" != "0" ]]; then
        echo "  Renny: $renny_ready/$renny_desired replicas ready"
    else
        echo "  Renny: Not deployed"
    fi

    # NIM Operator
    if run_kubectl get deployment -n nim-operator &>/dev/null; then
        echo "  NIM Operator: Installed"
    else
        echo "  NIM Operator: Not installed"
    fi

    echo ""
}

################################################################################
# Main
################################################################################

main() {
    echo "
╔═══════════════════════════════════════════════════════════════╗
║                   CNS Deployment Status                       ║
╚═══════════════════════════════════════════════════════════════╝
"

    if [[ -n "$CNS_REMOTE_HOST" ]]; then
        info "Target: $CNS_REMOTE_USER@$CNS_REMOTE_HOST"
    else
        info "Target: Local cluster"
    fi
    echo ""

    check_kubernetes
    check_gpu
    check_gpu_operator
    check_miniprem_components
    check_services
    check_storage
    show_summary
}

main "$@"
