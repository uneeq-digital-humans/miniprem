#!/bin/bash

################################################################################
# MiniPrem CNS Remote Deployment Script
#
# Deploys NVIDIA Cloud Native Stack to a remote server via SSH.
# Optionally uses Ansible for more robust configuration management.
#
# Prerequisites:
#   - SSH access to target server
#   - Target server: Ubuntu 22.04+ or RHEL 8.7+ with NVIDIA GPU
#   - Ansible (optional, for enhanced deployment)
#
# Usage:
#   ./deploy-remote.sh
#   CNS_REMOTE_HOST=192.168.1.100 ./deploy-remote.sh
################################################################################

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBERNETES_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
ANSIBLE_DIR="$KUBERNETES_DIR/ansible"

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

CNS_REMOTE_HOST="${CNS_REMOTE_HOST:-}"
CNS_REMOTE_USER="${CNS_REMOTE_USER:-ubuntu}"
CNS_SSH_KEY="${CNS_SSH_KEY:-~/.ssh/id_rsa}"
CNS_K8S_TYPE="${CNS_K8S_TYPE:-kubeadm}"
NGC_API_KEY="${NGC_API_KEY:-}"
USE_ANSIBLE="${USE_ANSIBLE:-auto}"

# Expand tilde in SSH key path
CNS_SSH_KEY=$(eval echo "$CNS_SSH_KEY")

################################################################################
# Validation
################################################################################

validate_config() {
    if [[ -z "$CNS_REMOTE_HOST" ]]; then
        error "CNS_REMOTE_HOST not set"
        exit 1
    fi

    if [[ ! -f "$CNS_SSH_KEY" ]]; then
        error "SSH key not found: $CNS_SSH_KEY"
        exit 1
    fi
}

################################################################################
# SSH Helpers
################################################################################

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

ssh_cmd() {
    ssh $SSH_OPTS -i "$CNS_SSH_KEY" "$CNS_REMOTE_USER@$CNS_REMOTE_HOST" "$@"
}

# SSH with TTY allocation for interactive commands
ssh_interactive() {
    ssh -t $SSH_OPTS -i "$CNS_SSH_KEY" "$CNS_REMOTE_USER@$CNS_REMOTE_HOST" "$@"
}

scp_to_remote() {
    local src="$1"
    local dst="$2"
    scp $SSH_OPTS -i "$CNS_SSH_KEY" -r "$src" "$CNS_REMOTE_USER@$CNS_REMOTE_HOST:$dst"
}

################################################################################
# Remote System Checks
################################################################################

check_remote_system() {
    info "Checking remote system..."

    # Check connectivity
    if ! ssh_cmd "echo 'SSH connection successful'" &>/dev/null; then
        error "Cannot connect to $CNS_REMOTE_HOST"
        exit 1
    fi
    success "SSH connection established"

    # Check OS
    local os_info=$(ssh_cmd "cat /etc/os-release | grep -E '^(ID|VERSION_ID)=' || true")
    info "Remote OS: $os_info"

    # Check for NVIDIA GPU
    info "Checking for NVIDIA GPU on remote..."
    if ssh_cmd "lspci | grep -qi nvidia"; then
        success "NVIDIA GPU detected on remote"
        ssh_cmd "lspci | grep -i nvidia | head -2"
    else
        error "No NVIDIA GPU detected on remote server"
        exit 1
    fi

    # Check for existing NVIDIA driver
    if ssh_cmd "command -v nvidia-smi" &>/dev/null; then
        info "NVIDIA driver already installed:"
        ssh_cmd "nvidia-smi --query-gpu=name,driver_version --format=csv,noheader" || true
    fi
}

################################################################################
# Ansible Deployment
################################################################################

deploy_with_ansible() {
    info "Deploying via Ansible..."

    if [[ ! -d "$ANSIBLE_DIR" ]]; then
        warning "Ansible directory not found: $ANSIBLE_DIR"
        warning "Falling back to SSH deployment"
        deploy_with_ssh
        return
    fi

    # Create temporary inventory file
    local inventory_file=$(mktemp)
    cat > "$inventory_file" <<EOF
[cns]
$CNS_REMOTE_HOST ansible_user=$CNS_REMOTE_USER ansible_ssh_private_key_file=$CNS_SSH_KEY

[cns:vars]
cns_k8s_type=$CNS_K8S_TYPE
ngc_api_key=$NGC_API_KEY
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF

    # Run Ansible playbook
    cd "$ANSIBLE_DIR"
    ansible-playbook \
        -i "$inventory_file" \
        playbooks/cns-install.yml \
        -e "cns_k8s_type=$CNS_K8S_TYPE" \
        -e "ngc_api_key=$NGC_API_KEY"

    rm -f "$inventory_file"

    success "Ansible deployment complete"
}

################################################################################
# SSH-Only Deployment
################################################################################

deploy_with_ssh() {
    info "Deploying via SSH (without Ansible)..."

    # Copy the local deployment script to remote
    info "Copying deployment scripts to remote..."
    ssh_cmd "mkdir -p ~/miniprem-cns"
    scp_to_remote "$SCRIPT_DIR/deploy-local.sh" "~/miniprem-cns/"

    # Copy common files if they exist
    if [[ -d "$SCRIPT_DIR/../common" ]]; then
        scp_to_remote "$SCRIPT_DIR/../common" "~/miniprem-cns/"
    fi

    # Copy Helm charts if they exist
    if [[ -d "$KUBERNETES_DIR/renny" ]]; then
        info "Copying Renny Helm chart..."
        scp_to_remote "$KUBERNETES_DIR/renny" "~/miniprem-cns/"
    fi

    if [[ -d "$KUBERNETES_DIR/values" ]]; then
        scp_to_remote "$KUBERNETES_DIR/values" "~/miniprem-cns/"
    fi

    # Execute deployment on remote
    info "Executing deployment on remote server..."
    echo ""
    echo "The deployment script will now prompt you for:"
    echo "  • DHOP API Key and Tenant ID (UneeQ credentials)"
    echo "  • Quality Mode (web for stock digital humans, miniprem for MiniPrem character maps)"
    echo "  • Number of Renny instances to deploy"
    echo ""
    read -p "Press Enter to continue with remote deployment..."
    echo ""

    # Use ssh_interactive for TTY allocation (required for prompts)
    ssh_interactive "cd ~/miniprem-cns && \
        sudo CNS_K8S_TYPE='$CNS_K8S_TYPE' \
        NGC_API_KEY='${NGC_API_KEY:-}' \
        KUBERNETES_DIR=~/miniprem-cns \
        bash deploy-local.sh"

    success "Remote deployment complete"
}

################################################################################
# Verification
################################################################################

verify_remote_deployment() {
    info "Verifying remote deployment..."

    echo ""
    echo "=== Remote Cluster Status ==="

    local kubectl_cmd="kubectl"
    if [[ "$CNS_K8S_TYPE" == "microk8s" ]]; then
        kubectl_cmd="microk8s kubectl"
    fi

    ssh_cmd "$kubectl_cmd get nodes" || true
    echo ""

    ssh_cmd "$kubectl_cmd get pods -n gpu-operator" || true
    echo ""

    ssh_cmd "$kubectl_cmd get pods -n uneeq" || true

    success "Remote verification complete"
}

################################################################################
# Main
################################################################################

main() {
    echo "
╔═══════════════════════════════════════════════════════════════╗
║               MiniPrem CNS Remote Deployment                  ║
╚═══════════════════════════════════════════════════════════════╝
"

    validate_config

    info "Target: $CNS_REMOTE_USER@$CNS_REMOTE_HOST"
    info "SSH Key: $CNS_SSH_KEY"
    info "Kubernetes: $CNS_K8S_TYPE"
    echo ""

    # Check remote system
    check_remote_system

    # Determine deployment method
    if [[ "$USE_ANSIBLE" == "auto" ]]; then
        if command -v ansible &>/dev/null && [[ -d "$ANSIBLE_DIR/playbooks" ]]; then
            USE_ANSIBLE="yes"
        else
            USE_ANSIBLE="no"
        fi
    fi

    echo ""
    if [[ "$USE_ANSIBLE" == "yes" ]]; then
        info "Using Ansible for deployment"
        deploy_with_ansible
    else
        info "Using SSH for deployment"
        deploy_with_ssh
    fi

    # Verify
    echo ""
    verify_remote_deployment

    echo ""
    echo "
╔═══════════════════════════════════════════════════════════════╗
║              Remote CNS Deployment Complete!                  ║
╚═══════════════════════════════════════════════════════════════╝
"

    echo "The CNS cluster is now running on $CNS_REMOTE_HOST"
    echo ""
    echo "To access the cluster remotely:"
    echo "  ssh -i $CNS_SSH_KEY $CNS_REMOTE_USER@$CNS_REMOTE_HOST"
    if [[ "$CNS_K8S_TYPE" == "microk8s" ]]; then
        echo "  microk8s kubectl get pods -A"
    else
        echo "  kubectl get pods -A"
    fi
    echo ""
    echo "To check status:"
    echo "  ./status.sh  (select CNS)"
    echo ""
}

main "$@"
