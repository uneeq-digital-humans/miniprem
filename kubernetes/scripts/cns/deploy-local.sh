#!/bin/bash

################################################################################
# MiniPrem CNS Local Deployment Script
#
# Installs NVIDIA Cloud Native Stack on the local machine with:
#   - MicroK8s or kubeadm Kubernetes distribution
#   - NVIDIA GPU Operator
#   - GPU time-slicing for multiple Renny instances
#   - Full MiniPrem stack (Renny, NIM, Riva, etc.)
#
# Prerequisites:
#   - Ubuntu 22.04+ or RHEL 8.7+
#   - NVIDIA GPU(s)
#   - Sudo access
#   - Internet connectivity
#
# Usage:
#   sudo ./deploy-local.sh
#   sudo CNS_K8S_TYPE=kubeadm ./deploy-local.sh
################################################################################

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBERNETES_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

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
NGC_API_KEY="${NGC_API_KEY:-}"
NVIDIA_DIR="${NVIDIA_DIR:-$KUBERNETES_DIR/../nvidia}"

# Version pinning
MICROK8S_CHANNEL="1.31/stable"
GPU_OPERATOR_VERSION="v24.9.0"
NIM_OPERATOR_VERSION="1.0.0"

################################################################################
# Prerequisite Checks
################################################################################

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_os() {
    info "Checking operating system..."

    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        case "$ID" in
            ubuntu)
                if [[ "${VERSION_ID}" < "22.04" ]]; then
                    error "Ubuntu 22.04 or later required (found $VERSION_ID)"
                    exit 1
                fi
                success "Ubuntu $VERSION_ID detected"
                ;;
            rhel|centos|rocky|almalinux)
                if [[ "${VERSION_ID%%.*}" -lt 8 ]]; then
                    error "RHEL 8.7+ required (found $VERSION_ID)"
                    exit 1
                fi
                success "$NAME $VERSION_ID detected"
                ;;
            *)
                warning "Unsupported OS: $ID. Proceeding anyway..."
                ;;
        esac
    else
        warning "Could not detect OS version"
    fi
}

check_nvidia_gpu() {
    info "Checking for NVIDIA GPU..."

    if lspci | grep -qi nvidia; then
        success "NVIDIA GPU detected"
        lspci | grep -i nvidia | head -3
    else
        error "No NVIDIA GPU detected. CNS requires NVIDIA GPU hardware."
        exit 1
    fi
}

check_nvidia_driver() {
    info "Checking NVIDIA driver..."

    if command -v nvidia-smi &> /dev/null; then
        success "NVIDIA driver installed"
        nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader
    else
        warning "NVIDIA driver not installed. Will be installed via GPU Operator."
    fi
}

check_ngc_api_key() {
    if [[ -z "$NGC_API_KEY" ]]; then
        warning "NGC_API_KEY not set. Required for NVIDIA model downloads."
        echo ""
        echo "To get an NGC API key:"
        echo "  1. Visit https://ngc.nvidia.com/"
        echo "  2. Sign in or create an account"
        echo "  3. Go to Setup > API Key"
        echo "  4. Generate and copy your API key"
        echo ""
        read -p "Enter NGC API Key (or press Enter to skip): " NGC_API_KEY
        export NGC_API_KEY
    fi

    if [[ -n "$NGC_API_KEY" ]]; then
        success "NGC API Key configured"
    else
        warning "Continuing without NGC API Key. Some features may not work."
    fi
}

################################################################################
# MicroK8s Installation
################################################################################

install_microk8s() {
    info "Installing MicroK8s..."

    # Install snapd if not present
    if ! command -v snap &> /dev/null; then
        apt-get update && apt-get install -y snapd
    fi

    # Install MicroK8s
    if ! command -v microk8s &> /dev/null; then
        snap install microk8s --classic --channel="$MICROK8S_CHANNEL"
        success "MicroK8s installed"
    else
        info "MicroK8s already installed"
        microk8s version
    fi

    # Wait for MicroK8s to be ready
    info "Waiting for MicroK8s to be ready..."
    microk8s status --wait-ready

    # Enable required addons
    info "Enabling MicroK8s addons..."
    microk8s enable dns
    microk8s enable hostpath-storage
    microk8s enable helm3

    # Enable NVIDIA addon
    info "Enabling NVIDIA GPU support..."
    microk8s enable nvidia

    success "MicroK8s configured with GPU support"

    # Create kubectl alias
    if [[ ! -f /usr/local/bin/kubectl ]]; then
        ln -sf /snap/bin/microk8s.kubectl /usr/local/bin/kubectl
    fi

    # Create helm alias
    if [[ ! -f /usr/local/bin/helm ]]; then
        ln -sf /snap/bin/microk8s.helm3 /usr/local/bin/helm
    fi
}

################################################################################
# kubeadm Installation
################################################################################

install_kubeadm() {
    info "Installing Kubernetes via kubeadm..."

    # This is a simplified kubeadm setup
    # For production, more configuration is needed

    # Install containerd
    apt-get update
    apt-get install -y containerd

    # Configure containerd for NVIDIA
    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml

    # Install kubeadm, kubelet, kubectl
    apt-get install -y apt-transport-https ca-certificates curl

    # Add Kubernetes apt repository
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' > /etc/apt/sources.list.d/kubernetes.list

    apt-get update
    apt-get install -y kubelet kubeadm kubectl
    apt-mark hold kubelet kubeadm kubectl

    # Initialize cluster
    kubeadm init --pod-network-cidr=10.244.0.0/16

    # Setup kubectl for root user
    mkdir -p /root/.kube
    cp -i /etc/kubernetes/admin.conf /root/.kube/config

    # Install Calico CNI
    kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.0/manifests/calico.yaml

    # Remove taint to allow scheduling on control plane (single node)
    kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true

    success "Kubernetes cluster initialized via kubeadm"
}

################################################################################
# GPU Operator Installation
################################################################################

install_gpu_operator() {
    info "Installing NVIDIA GPU Operator..."

    local KUBECTL="kubectl"
    local HELM="helm"

    if [[ "$CNS_K8S_TYPE" == "microk8s" ]]; then
        KUBECTL="microk8s kubectl"
        HELM="microk8s helm3"
    fi

    # Add NVIDIA Helm repo
    $HELM repo add nvidia https://helm.ngc.nvidia.com/nvidia || true
    $HELM repo update

    # Create namespace
    $KUBECTL create namespace gpu-operator --dry-run=client -o yaml | $KUBECTL apply -f -

    # Install GPU Operator
    $HELM upgrade --install gpu-operator nvidia/gpu-operator \
        --namespace gpu-operator \
        --version "$GPU_OPERATOR_VERSION" \
        --set driver.enabled=true \
        --set toolkit.enabled=true \
        --set devicePlugin.enabled=true \
        --set dcgmExporter.enabled=true \
        --wait --timeout 10m

    success "GPU Operator installed"

    # Wait for GPU to be available
    info "Waiting for GPU resources to be available..."
    local retries=30
    while [[ $retries -gt 0 ]]; do
        local gpu_count=$($KUBECTL get nodes -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}' 2>/dev/null || echo "0")
        if [[ "$gpu_count" != "0" && -n "$gpu_count" ]]; then
            success "GPU resources available: $gpu_count GPU(s)"
            break
        fi
        echo "  Waiting for GPU... ($retries attempts remaining)"
        sleep 10
        ((retries--))
    done

    if [[ $retries -eq 0 ]]; then
        warning "GPU resources not yet visible. Deployment will continue."
    fi
}

################################################################################
# GPU Time-Slicing Configuration
################################################################################

configure_gpu_timeslicing() {
    info "Configuring GPU time-slicing..."

    local KUBECTL="kubectl"
    if [[ "$CNS_K8S_TYPE" == "microk8s" ]]; then
        KUBECTL="microk8s kubectl"
    fi

    # Create time-slicing ConfigMap
    cat <<EOF | $KUBECTL apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: time-slicing-config
  namespace: gpu-operator
data:
  any: |-
    version: v1
    flags:
      migStrategy: none
    sharing:
      timeSlicing:
        renameByDefault: false
        failRequestsGreaterThanOne: false
        resources:
          - name: nvidia.com/gpu
            replicas: 4
EOF

    # Patch cluster policy
    $KUBECTL patch clusterpolicies.nvidia.com/cluster-policy \
        -n gpu-operator \
        --type merge \
        -p '{"spec": {"devicePlugin": {"config": {"name": "time-slicing-config", "default": "any"}}}}' || true

    success "GPU time-slicing configured (4 replicas per GPU)"
}

################################################################################
# MiniPrem Stack Deployment
################################################################################

deploy_miniprem_stack() {
    info "Deploying MiniPrem stack..."

    local KUBECTL="kubectl"
    local HELM="helm"

    if [[ "$CNS_K8S_TYPE" == "microk8s" ]]; then
        KUBECTL="microk8s kubectl"
        HELM="microk8s helm3"
    fi

    # Create namespaces
    for ns in nim-operator nim-models nim-rag riva uneeq miniprem; do
        $KUBECTL create namespace "$ns" --dry-run=client -o yaml | $KUBECTL apply -f -
    done

    # Create NGC API secret if key is provided
    if [[ -n "$NGC_API_KEY" ]]; then
        info "Creating NGC API secret..."
        $KUBECTL create secret generic ngc-api-key \
            --from-literal=NGC_API_KEY="$NGC_API_KEY" \
            --namespace nim-operator \
            --dry-run=client -o yaml | $KUBECTL apply -f -
    fi

    # Install NIM Operator
    info "Installing NIM Operator..."
    $HELM repo add nvidia https://helm.ngc.nvidia.com/nvidia || true
    $HELM repo update

    $HELM upgrade --install nim-operator nvidia/k8s-nim-operator \
        --namespace nim-operator \
        --version "$NIM_OPERATOR_VERSION" \
        --wait --timeout 5m || warning "NIM Operator installation skipped or failed"

    # Deploy Renny via Helm
    info "Deploying Renny..."
    if [[ -f "$KUBERNETES_DIR/renny/Chart.yaml" ]]; then
        $HELM upgrade --install renny "$KUBERNETES_DIR/renny" \
            --namespace uneeq \
            --values "$KUBERNETES_DIR/values/renny-values.yaml" \
            --set replicas=2 \
            --wait --timeout 10m || warning "Renny deployment skipped or failed"
    else
        warning "Renny Helm chart not found at $KUBERNETES_DIR/renny"
    fi

    success "MiniPrem stack deployment initiated"
}

################################################################################
# Verification
################################################################################

verify_deployment() {
    info "Verifying deployment..."

    local KUBECTL="kubectl"
    if [[ "$CNS_K8S_TYPE" == "microk8s" ]]; then
        KUBECTL="microk8s kubectl"
    fi

    echo ""
    print_color "$BOLD" "=== Cluster Status ==="
    $KUBECTL get nodes

    echo ""
    print_color "$BOLD" "=== GPU Resources ==="
    $KUBECTL get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}'

    echo ""
    print_color "$BOLD" "=== Namespaces ==="
    $KUBECTL get namespaces

    echo ""
    print_color "$BOLD" "=== GPU Operator Pods ==="
    $KUBECTL get pods -n gpu-operator

    echo ""
    print_color "$BOLD" "=== MiniPrem Pods ==="
    $KUBECTL get pods -n uneeq 2>/dev/null || echo "No pods in uneeq namespace yet"

    echo ""
    success "CNS deployment verification complete"
}

################################################################################
# Main
################################################################################

main() {
    print_color "$BOLD" "
╔═══════════════════════════════════════════════════════════════╗
║     MiniPrem CNS Local Installation ($CNS_K8S_TYPE)           ║
╚═══════════════════════════════════════════════════════════════╝
"

    # Prerequisite checks
    check_root
    check_os
    check_nvidia_gpu
    check_nvidia_driver
    check_ngc_api_key

    echo ""
    info "Starting installation..."
    echo ""

    # Install Kubernetes distribution
    case "$CNS_K8S_TYPE" in
        microk8s)
            install_microk8s
            ;;
        kubeadm)
            install_kubeadm
            install_gpu_operator
            ;;
        *)
            error "Unknown Kubernetes type: $CNS_K8S_TYPE"
            exit 1
            ;;
    esac

    # Configure GPU time-slicing (for multiple Rennys)
    configure_gpu_timeslicing

    # Deploy MiniPrem stack
    deploy_miniprem_stack

    # Verify deployment
    verify_deployment

    echo ""
    print_color "$BOLD" "
╔═══════════════════════════════════════════════════════════════╗
║              CNS Installation Complete!                        ║
╚═══════════════════════════════════════════════════════════════╝
"

    echo "Next steps:"
    echo "  1. Check deployment status:"
    if [[ "$CNS_K8S_TYPE" == "microk8s" ]]; then
        echo "     microk8s kubectl get pods -A"
    else
        echo "     kubectl get pods -A"
    fi
    echo ""
    echo "  2. Access MiniPrem Monitor:"
    echo "     Open http://localhost:3001 in your browser"
    echo ""
    echo "  3. Scale Renny instances:"
    echo "     ./scale.sh <count>"
    echo ""
}

main "$@"
