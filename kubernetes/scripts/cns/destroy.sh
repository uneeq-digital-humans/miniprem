#!/bin/bash

################################################################################
# MiniPrem CNS Destruction Script
#
# Removes CNS deployment from local or remote server.
#
# Usage:
#   ./destroy.sh                    # Local destruction
#   CNS_REMOTE_HOST=x.x.x.x ./destroy.sh  # Remote destruction
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
PURGE_ALL="${PURGE_ALL:-false}"

CNS_SSH_KEY=$(eval echo "$CNS_SSH_KEY")

################################################################################
# SSH Helper
################################################################################

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

ssh_cmd() {
    ssh $SSH_OPTS -i "$CNS_SSH_KEY" "$CNS_REMOTE_USER@$CNS_REMOTE_HOST" "$@"
}

################################################################################
# Local Destruction
################################################################################

destroy_local() {
    print_color "$BOLD" "
╔═══════════════════════════════════════════════════════════════╗
║                    CNS Local Destruction                      ║
╚═══════════════════════════════════════════════════════════════╝
"

    warning "This will remove the CNS deployment from this machine."
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        info "Destruction cancelled"
        exit 0
    fi

    local kubectl_cmd="kubectl"
    local helm_cmd="helm"

    if [[ "$CNS_K8S_TYPE" == "microk8s" ]]; then
        kubectl_cmd="microk8s kubectl"
        helm_cmd="microk8s helm3"
    fi

    # Remove Helm releases
    info "Removing Helm releases..."
    $helm_cmd uninstall renny -n uneeq 2>/dev/null || true
    $helm_cmd uninstall nim-operator -n nim-operator 2>/dev/null || true
    $helm_cmd uninstall gpu-operator -n gpu-operator 2>/dev/null || true

    # Remove namespaces
    info "Removing namespaces..."
    for ns in uneeq nim-rag nim-models nim-operator riva miniprem; do
        $kubectl_cmd delete namespace "$ns" --ignore-not-found 2>/dev/null || true
    done

    if [[ "$PURGE_ALL" == "true" ]]; then
        warning "Purging entire Kubernetes installation..."

        case "$CNS_K8S_TYPE" in
            microk8s)
                info "Resetting MicroK8s..."
                sudo microk8s reset --destroy-storage || true
                info "Removing MicroK8s..."
                sudo snap remove microk8s || true
                ;;
            kubeadm)
                info "Resetting kubeadm..."
                sudo kubeadm reset -f || true
                sudo rm -rf /etc/kubernetes /var/lib/kubelet /var/lib/etcd
                ;;
        esac

        success "Complete purge finished"
    else
        success "MiniPrem components removed. Kubernetes cluster preserved."
        echo ""
        echo "To completely remove Kubernetes, run with PURGE_ALL=true:"
        echo "  PURGE_ALL=true ./destroy.sh"
    fi
}

################################################################################
# Remote Destruction
################################################################################

destroy_remote() {
    print_color "$BOLD" "
╔═══════════════════════════════════════════════════════════════╗
║                   CNS Remote Destruction                      ║
╚═══════════════════════════════════════════════════════════════╝
"

    info "Target: $CNS_REMOTE_USER@$CNS_REMOTE_HOST"
    echo ""

    warning "This will remove the CNS deployment from the remote server."
    read -p "Are you sure you want to continue? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        info "Destruction cancelled"
        exit 0
    fi

    # Copy and execute destroy script on remote
    info "Executing destruction on remote server..."

    ssh_cmd "CNS_K8S_TYPE='$CNS_K8S_TYPE' PURGE_ALL='$PURGE_ALL' bash -s" <<'REMOTE_SCRIPT'
set -e
kubectl_cmd="kubectl"
helm_cmd="helm"

if [[ "$CNS_K8S_TYPE" == "microk8s" ]]; then
    kubectl_cmd="microk8s kubectl"
    helm_cmd="microk8s helm3"
fi

echo "Removing Helm releases..."
$helm_cmd uninstall renny -n uneeq 2>/dev/null || true
$helm_cmd uninstall nim-operator -n nim-operator 2>/dev/null || true
$helm_cmd uninstall gpu-operator -n gpu-operator 2>/dev/null || true

echo "Removing namespaces..."
for ns in uneeq nim-rag nim-models nim-operator riva miniprem; do
    $kubectl_cmd delete namespace "$ns" --ignore-not-found 2>/dev/null || true
done

if [[ "$PURGE_ALL" == "true" ]]; then
    echo "Purging Kubernetes..."
    if [[ "$CNS_K8S_TYPE" == "microk8s" ]]; then
        sudo microk8s reset --destroy-storage || true
        sudo snap remove microk8s || true
    else
        sudo kubeadm reset -f || true
    fi
fi

echo "Done"
REMOTE_SCRIPT

    success "Remote destruction complete"
}

################################################################################
# Main
################################################################################

main() {
    if [[ -n "$CNS_REMOTE_HOST" ]]; then
        destroy_remote
    else
        destroy_local
    fi
}

main "$@"
