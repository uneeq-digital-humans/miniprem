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
RENNY_REPLICAS="${RENNY_REPLICAS:-4}"  # Number of Renny instances (adjust for GPU count)
GPU_TIMESLICE_REPLICAS="${GPU_TIMESLICE_REPLICAS:-8}"  # GPU time-slices per physical GPU

# Version pinning
MICROK8S_CHANNEL="1.31/stable"
GPU_OPERATOR_VERSION="v24.9.0"
NIM_OPERATOR_VERSION="1.0.0"

################################################################################
# Prerequisite Checks
################################################################################

# Detect package manager (needed by multiple functions)
detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
    else
        PKG_MANAGER=""
    fi
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
}

install_prerequisites() {
    info "Installing system prerequisites..."

    # Detect package manager
    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
    else
        warning "Unknown package manager. Some prerequisites may need manual installation."
        return
    fi

    # Install snapd (required for MicroK8s)
    if ! command -v snap &> /dev/null; then
        info "Installing snapd..."
        case "$PKG_MANAGER" in
            apt)
                apt-get update
                apt-get install -y snapd
                # Ensure snapd socket is running
                systemctl enable --now snapd.socket
                # Create symlink for classic snap support
                ln -sf /var/lib/snapd/snap /snap 2>/dev/null || true
                # Wait for snapd to be ready
                sleep 5
                ;;
            dnf|yum)
                $PKG_MANAGER install -y snapd
                systemctl enable --now snapd.socket
                ln -sf /var/lib/snapd/snap /snap 2>/dev/null || true
                sleep 5
                ;;
        esac
        success "snapd installed"
    else
        success "snapd already installed"
    fi

    # Install Google Chrome (required for MiniPrem kiosk interface)
    if ! command -v google-chrome &> /dev/null && ! command -v google-chrome-stable &> /dev/null; then
        info "Installing Google Chrome..."
        case "$PKG_MANAGER" in
            apt)
                # Download and install Chrome
                wget -q -O /tmp/google-chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
                apt-get install -y /tmp/google-chrome.deb || {
                    # If dependencies fail, fix them
                    apt-get install -f -y
                    apt-get install -y /tmp/google-chrome.deb
                }
                rm -f /tmp/google-chrome.deb
                ;;
            dnf|yum)
                # Add Chrome repo and install
                cat > /etc/yum.repos.d/google-chrome.repo << 'REPO'
[google-chrome]
name=google-chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
REPO
                $PKG_MANAGER install -y google-chrome-stable
                ;;
        esac
        success "Google Chrome installed"
    else
        success "Google Chrome already installed"
    fi

    # Install other common prerequisites
    info "Installing additional tools..."
    case "$PKG_MANAGER" in
        apt)
            apt-get install -y curl wget jq git
            ;;
        dnf|yum)
            $PKG_MANAGER install -y curl wget jq git
            ;;
    esac
    success "Prerequisites installed"
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
        local driver_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
        local gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)

        success "NVIDIA driver installed: $driver_version"
        nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader

        # Validate driver version for Renny compatibility
        validate_driver_for_renny "$driver_version" "$gpu_name"
    else
        warning "NVIDIA driver not installed. Will be installed via GPU Operator."
    fi
}

validate_driver_for_renny() {
    local driver_version="$1"
    local gpu_name="$2"

    info "Validating driver version for Renny compatibility..."

    # Extract major.minor version (e.g., 580.82 from 580.82.09)
    local major_minor=$(echo "$driver_version" | cut -d. -f1,2)

    # Known problematic versions
    if [[ "$major_minor" == "580.126" ]]; then
        error "Driver $driver_version is INCOMPATIBLE with Renny!"
        echo ""
        print_color "$RED" "  Driver 580.126.x breaks NVENC hardware encoding on ALL GPU types."
        echo "  Renny requires driver 580.82.x for proper video encoding."
        echo ""
        echo "  To fix, install the correct driver:"
        echo "    - For Blackwell/RTX PRO 6000: Download 580.82.09 from NVIDIA"
        echo "    - For L4/A10G/T4: apt install nvidia-driver-580=580.82.07-0ubuntu1"
        echo ""
        read -p "Do you want to continue anyway? (y/N): " response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            exit 1
        fi
        warning "Continuing with incompatible driver. Renny video encoding may fail."
        return
    fi

    # Check for recommended 580.82.x version
    if [[ "$major_minor" == "580.82" ]]; then
        success "Driver $driver_version is compatible with Renny"
        return
    fi

    # Check if driver is too old (< 550)
    local major=$(echo "$driver_version" | cut -d. -f1)
    if [[ "$major" -lt 550 ]]; then
        warning "Driver $driver_version may be too old for optimal Renny performance"
        echo "  Recommended: 580.82.x for production Renny deployments"
    fi

    # Check for Blackwell GPUs that need specific driver
    if [[ "$gpu_name" =~ "Blackwell" ]] || [[ "$gpu_name" =~ "RTX PRO 6000" ]] || [[ "$gpu_name" =~ "RTX 6000" ]]; then
        if [[ "$major_minor" != "580.82" ]]; then
            warning "Blackwell/RTX PRO 6000 GPU detected with driver $driver_version"
            echo ""
            echo "  For best Renny compatibility, install driver 580.82.09:"
            echo "    wget https://us.download.nvidia.com/XFree86/Linux-x86_64/580.82.09/NVIDIA-Linux-x86_64-580.82.09.run"
            echo "    chmod +x NVIDIA-Linux-x86_64-580.82.09.run"
            echo "    sudo ./NVIDIA-Linux-x86_64-580.82.09.run --silent --dkms"
            echo ""
        fi
    fi
}

################################################################################
# Vulkan Setup for Renny (UE5 requires Vulkan rendering)
################################################################################

setup_vulkan_for_renny() {
    info "Setting up Vulkan for Renny..."

    # Install vulkan-tools for verification
    if ! command -v vulkaninfo &> /dev/null; then
        info "Installing vulkan-tools..."
        case "$PKG_MANAGER" in
            apt)
                apt-get update
                apt-get install -y vulkan-tools libvulkan1
                ;;
            dnf|yum)
                $PKG_MANAGER install -y vulkan-tools vulkan-loader
                ;;
        esac
    fi

    # Create NVIDIA Vulkan ICD file if missing
    local NVIDIA_ICD="/usr/share/vulkan/icd.d/nvidia_icd.json"
    if [[ ! -f "$NVIDIA_ICD" ]]; then
        info "Creating NVIDIA Vulkan ICD file..."
        mkdir -p /usr/share/vulkan/icd.d
        cat > "$NVIDIA_ICD" << 'EOF'
{
    "file_format_version" : "1.0.0",
    "ICD" : {
        "library_path" : "libGLX_nvidia.so.0",
        "api_version" : "1.3.275"
    }
}
EOF
        success "Created $NVIDIA_ICD"
    else
        success "NVIDIA Vulkan ICD already exists"
    fi

    # Verify Vulkan works (requires X display)
    if [[ -n "${DISPLAY:-}" ]] || [[ -S /tmp/.X11-unix/X1 ]]; then
        local test_display="${DISPLAY:-:1}"
        info "Testing Vulkan with DISPLAY=$test_display..."
        if DISPLAY="$test_display" vulkaninfo --summary 2>&1 | grep -q "NVIDIA"; then
            success "Vulkan NVIDIA driver detected and working"
        else
            warning "Vulkan test could not confirm NVIDIA driver"
        fi
    else
        warning "No X display available - skipping Vulkan verification"
    fi
}

################################################################################
# Xvfb Setup for Headless Rendering
################################################################################

setup_xvfb_for_renny() {
    info "Setting up Xvfb for headless Renny rendering..."

    # Install Xvfb if not present
    if ! command -v Xvfb &> /dev/null; then
        info "Installing Xvfb..."
        case "$PKG_MANAGER" in
            apt)
                apt-get update
                apt-get install -y xvfb x11-xserver-utils
                ;;
            dnf|yum)
                $PKG_MANAGER install -y xorg-x11-server-Xvfb
                ;;
        esac
    fi

    # Create systemd service for Xvfb persistence
    local XVFB_SERVICE="/etc/systemd/system/xvfb.service"
    if [[ ! -f "$XVFB_SERVICE" ]]; then
        info "Creating Xvfb systemd service..."
        cat > "$XVFB_SERVICE" << 'EOF'
[Unit]
Description=X Virtual Framebuffer for Renny
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/Xvfb :1 -screen 0 1920x1080x24 +extension GLX
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        success "Created Xvfb systemd service"
    fi

    # Enable and start Xvfb
    systemctl enable xvfb
    systemctl start xvfb || {
        warning "Failed to start Xvfb via systemd, starting manually..."
        pkill -9 Xvfb 2>/dev/null || true
        nohup Xvfb :1 -screen 0 1920x1080x24 +extension GLX &>/dev/null &
        sleep 2
    }

    # Verify X11 socket exists
    if [[ -S /tmp/.X11-unix/X1 ]]; then
        success "Xvfb running on :1"
    else
        error "Failed to start Xvfb - /tmp/.X11-unix/X1 not found"
        exit 1
    fi

    # Export DISPLAY for subsequent commands
    export DISPLAY=:1
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

    # Verify snapd is available (should be installed in prerequisites)
    if ! command -v snap &> /dev/null; then
        error "snapd is not installed. Run install_prerequisites first."
        exit 1
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
    local GPU_OPERATOR_NS="gpu-operator"

    if [[ "$CNS_K8S_TYPE" == "microk8s" ]]; then
        KUBECTL="microk8s kubectl"
        GPU_OPERATOR_NS="gpu-operator-resources"  # MicroK8s uses different namespace
    fi

    # Wait for GPU operator to be ready
    info "Waiting for GPU operator pods to be ready..."
    $KUBECTL wait --for=condition=ready pod -l app=gpu-operator -n "$GPU_OPERATOR_NS" --timeout=300s || true

    # Fix known symlink creation bug (affects systemd cgroup setups)
    info "Applying GPU operator fixes..."
    $KUBECTL patch clusterpolicy/cluster-policy --type=merge \
        -p '{"spec":{"validator":{"driver":{"env":[{"name":"DISABLE_DEV_CHAR_SYMLINK_CREATION","value":"true"}]}}}}' || true

    # Wait for pods to restart after patch
    sleep 10

    # Create time-slicing ConfigMap
    info "Creating time-slicing configuration..."
    cat <<EOF | $KUBECTL apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: time-slicing-config
  namespace: $GPU_OPERATOR_NS
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
            replicas: ${GPU_TIMESLICE_REPLICAS:-8}
EOF

    # Patch cluster policy for time-slicing
    $KUBECTL patch clusterpolicies.nvidia.com/cluster-policy \
        --type merge \
        -p '{"spec": {"devicePlugin": {"config": {"name": "time-slicing-config", "default": "any"}}}}' || true

    # Wait for device plugin to restart
    info "Waiting for GPU resources to update..."
    sleep 30

    # Verify time-slicing is working
    local gpu_count=$($KUBECTL get nodes -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}' 2>/dev/null || echo "0")
    if [[ "$gpu_count" -gt 1 ]]; then
        success "GPU time-slicing configured ($gpu_count GPU replicas available)"
    else
        warning "Time-slicing may not be active yet. GPU count: $gpu_count"
    fi
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
        # Use CNS-specific values file
        local VALUES_FILE="$KUBERNETES_DIR/values/renny-values-cns.yaml"
        if [[ ! -f "$VALUES_FILE" ]]; then
            VALUES_FILE="$KUBERNETES_DIR/values/renny-values.yaml"
            warning "CNS values file not found, using default values"
        fi

        $HELM upgrade --install renny "$KUBERNETES_DIR/renny" \
            --namespace uneeq \
            --values "$VALUES_FILE" \
            --set deployment.totalReplicas="${RENNY_REPLICAS:-4}" \
            --set telemetry.platform="cns" \
            --set nim.endpoint="http://localhost:8000/v1" \
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
    detect_package_manager  # Needed by setup functions
    check_os
    check_nvidia_gpu
    check_nvidia_driver

    echo ""
    info "Installing system prerequisites..."
    echo ""

    # Install prerequisites (snap, Chrome, etc.)
    install_prerequisites

    echo ""
    info "Setting up Renny display requirements..."
    echo ""

    # Setup Xvfb for headless rendering (needed before Vulkan check)
    setup_xvfb_for_renny

    # Setup Vulkan (requires NVIDIA driver and X display)
    setup_vulkan_for_renny

    echo ""

    # NGC API key (after prerequisites so we have wget/curl)
    check_ngc_api_key

    echo ""
    info "Starting Kubernetes installation..."
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
