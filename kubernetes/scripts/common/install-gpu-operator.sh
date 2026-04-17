#!/bin/bash
set -euo pipefail

# Multi-Cloud GPU Operator Installation Script
# Supports EKS (AWS) and AKS (Azure) with automatic cloud provider detection
# This can be run independently to test GPU operator installation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo "=========================================="
echo "   Multi-Cloud GPU Operator Installer    "
echo "=========================================="
echo ""

# Detect cloud provider from kubectl context or node labels
detect_cloud_provider() {
    local context=$(kubectl config current-context 2>/dev/null || echo "")

    # Check for EKS context pattern
    if [[ "$context" == *"eks"* ]]; then
        echo "eks"
        return
    fi

    # Check for AKS context pattern
    if [[ "$context" == *"aks"* ]]; then
        echo "aks"
        return
    fi

    # Fallback: check node providerID
    local provider_id=$(kubectl get nodes -o json 2>/dev/null | jq -r '.items[0].spec.providerID // ""' || echo "")
    if [[ "$provider_id" == aws* ]]; then
        echo "eks"
        return
    elif [[ "$provider_id" == azure* ]]; then
        echo "aks"
        return
    fi

    # Last resort: check node labels
    if kubectl get nodes -l kubernetes.azure.com/role &>/dev/null 2>&1; then
        echo "aks"
    elif kubectl get nodes -l eks.amazonaws.com/nodegroup &>/dev/null 2>&1; then
        echo "eks"
    else
        echo "unknown"
    fi
}

# Check prerequisites
echo "🔍 Checking prerequisites..."

# Check kubectl connectivity
if ! kubectl get nodes >/dev/null 2>&1; then
    echo -e "${RED}❌ Cannot connect to Kubernetes cluster${NC}"
    echo "Please ensure kubectl is configured and cluster is accessible"
    exit 1
fi

# Detect cloud provider
CLOUD_PROVIDER=$(detect_cloud_provider)
echo -e "${CYAN}☁️  Detected cloud provider: ${CLOUD_PROVIDER^^}${NC}"

if [[ "$CLOUD_PROVIDER" == "unknown" ]]; then
    echo -e "${RED}❌ Could not detect cloud provider (EKS or AKS)${NC}"
    echo "Please ensure you're connected to an EKS or AKS cluster"
    echo "Supported providers: AWS EKS, Azure AKS"
    exit 1
fi

# Set cloud-specific parameters
if [[ "$CLOUD_PROVIDER" == "eks" ]]; then
    GPU_NODE_SELECTOR="node.kubernetes.io/instance-type=g5.4xlarge"
    GPU_INSTANCE_TYPE="g5.4xlarge (NVIDIA A10G)"
    GPU_LABEL_KEY="nvidia.com/gpu"
    GPU_LABEL_VALUE="true"
    NODE_OS_CHECK="Ubuntu"
elif [[ "$CLOUD_PROVIDER" == "aks" ]]; then
    # AKS uses agentpool label - detect the GPU node pool name
    GPU_NODEPOOL=$(kubectl get nodes -o json | jq -r '.items[] | select(.metadata.labels."kubernetes.azure.com/accelerator" == "nvidia") | .metadata.labels."kubernetes.azure.com/agentpool"' | head -1)

    if [[ -z "$GPU_NODEPOOL" ]]; then
        # Fallback: try to find any node pool with GPU VM size in name
        GPU_NODEPOOL=$(kubectl get nodes -o json | jq -r '.items[] | select(.metadata.labels."kubernetes.azure.com/agentpool" | test("gpu|renny|nc[0-9]")) | .metadata.labels."kubernetes.azure.com/agentpool"' | head -1)
    fi

    if [[ -z "$GPU_NODEPOOL" ]]; then
        echo -e "${YELLOW}⚠️  Could not auto-detect GPU node pool name${NC}"
        echo "Will check all nodes for GPU capability"
        GPU_NODE_SELECTOR="kubernetes.azure.com/accelerator=nvidia"
    else
        GPU_NODE_SELECTOR="kubernetes.azure.com/agentpool=${GPU_NODEPOOL}"
    fi

    GPU_INSTANCE_TYPE="Standard_NC*_T4_* (NVIDIA T4)"
    GPU_LABEL_KEY="nvidia.com/gpu"
    GPU_LABEL_VALUE="true"
    NODE_OS_CHECK="Ubuntu|CBL-Mariner"  # AKS supports both
else
    echo -e "${RED}❌ Unsupported cloud provider: $CLOUD_PROVIDER${NC}"
    exit 1
fi

echo -e "${CYAN}🔍 GPU Node Selector: ${GPU_NODE_SELECTOR}${NC}"
echo -e "${CYAN}🎮 GPU Instance Type: ${GPU_INSTANCE_TYPE}${NC}"

# Check for GPU nodes
GPU_NODE_COUNT=$(kubectl get nodes -l "$GPU_NODE_SELECTOR" --no-headers 2>/dev/null | wc -l | tr -d ' \n' || echo "0")
if [ "$GPU_NODE_COUNT" -eq "0" ]; then
    echo -e "${YELLOW}⚠️  No GPU nodes found with label ${GPU_NODE_SELECTOR}${NC}"
    echo "GPU operator will still install but may not deploy drivers"
    echo "Please ensure your GPU node pool is deployed and labeled correctly"

    # Show available nodes for debugging
    echo -e "\n${CYAN}Available nodes:${NC}"
    kubectl get nodes --show-labels | grep -E "NAME|gpu|GPU|nvidia|NVIDIA" || kubectl get nodes
fi

echo -e "${GREEN}✅ Found $GPU_NODE_COUNT GPU nodes${NC}"

# Check if already installed
if helm list -n gpu-operator 2>/dev/null | grep -q "gpu-operator.*deployed"; then
    echo -e "${YELLOW}⚠️  GPU operator already installed${NC}"
    echo "Use --force to reinstall or --status to check status"

    if [[ "${1:-}" == "--force" ]]; then
        echo "🗑️  Uninstalling existing GPU operator..."
        helm uninstall gpu-operator -n gpu-operator --timeout=300s || true
        kubectl delete namespace gpu-operator --wait=false || true
        echo "⏳ Waiting for cleanup..."
        sleep 30
    elif [[ "${1:-}" == "--status" ]]; then
        echo ""
        echo "📊 Current GPU Operator Status:"
        helm list -n gpu-operator
        echo ""
        echo "GPU Operator Pods:"
        kubectl get pods -n gpu-operator -o wide
        echo ""
        echo "GPU Node Capacity:"
        kubectl get nodes -l "$GPU_NODE_SELECTOR" -o json | jq -r ".items[] | \"\(.metadata.name): \(.status.capacity.\"nvidia.com/gpu\" // \"0\") GPUs\""
        exit 0
    else
        exit 1
    fi
fi

echo ""
echo -e "${BLUE}🎮 Installing NVIDIA GPU Operator...${NC}"
echo "This will:"
echo "  - Install NVIDIA driver 580+ on all GPU nodes"
echo "  - Configure containerd with NVIDIA runtime"
echo "  - Enable GPU device plugin and monitoring"
echo "  - Cloud provider: ${CLOUD_PROVIDER^^}"
echo ""

# Add NVIDIA Helm repository
echo "📦 Adding NVIDIA Helm repository..."
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia || true
helm repo update

# Create namespace
echo "📁 Creating gpu-operator namespace..."
kubectl create namespace gpu-operator --dry-run=client -o yaml | kubectl apply -f -

# Install GPU Operator with cloud-agnostic configuration
echo "⚙️  Installing GPU operator v23.9.2..."
helm upgrade --install gpu-operator nvidia/gpu-operator \
    --namespace gpu-operator \
    --version v23.9.2 \
    --set operator.defaultRuntime=containerd \
    --set driver.enabled=true \
    --set toolkit.enabled=true \
    --set devicePlugin.enabled=true \
    --set dcgmExporter.enabled=true \
    --set nodeStatusExporter.enabled=false \
    --set driver.env[0].name=ENABLE_AUTO_DRAIN \
    --set-string driver.env[0].value="false" \
    --set driver.env[1].name=DISABLE_DEV_CHAR_SYMLINK_CREATION \
    --set-string driver.env[1].value="true" \
    --timeout=15m \
    --wait

echo ""
echo "⏳ Waiting for initial pods to be ready..."
kubectl wait --for=condition=ready pod -l app=nvidia-operator -n gpu-operator --timeout=300s || {
    echo -e "${YELLOW}⚠️  Operator pods not ready yet, but installation completed${NC}"
}

# Apply EKS-specific DNS fix for Ubuntu systemd-resolved (only if EKS + Ubuntu)
if [[ "$CLOUD_PROVIDER" == "eks" ]]; then
    echo ""
    echo "🔧 Checking if DNS fix is needed for EKS Ubuntu nodes..."

    # Get node OS image to verify Ubuntu
    NODE_OS_IMAGE=$(kubectl get nodes -l "$GPU_NODE_SELECTOR" -o jsonpath='{.items[0].status.nodeInfo.osImage}' 2>/dev/null || echo "")

    if [[ "$NODE_OS_IMAGE" =~ Ubuntu ]]; then
        echo -e "${CYAN}Ubuntu nodes detected: $NODE_OS_IMAGE${NC}"
        echo "Applying DNS systemd-resolved fix..."

        kubectl patch daemonset nvidia-driver-daemonset -n gpu-operator --type='merge' -p='
{
  "spec": {
    "template": {
      "spec": {
        "containers": [
          {
            "name": "nvidia-driver-ctr",
            "env": [
              {
                "name": "NVIDIA_DISABLE_REQUIRE",
                "value": "true"
              }
            ],
            "volumeMounts": [
              {
                "name": "resolv-conf",
                "mountPath": "/etc/resolv.conf",
                "subPath": "resolv.conf",
                "readOnly": true
              }
            ]
          }
        ],
        "volumes": [
          {
            "name": "resolv-conf",
            "configMap": {
              "name": "dns-fix-config"
            }
          }
        ]
      }
    }
  }
}
' 2>/dev/null || {
            echo -e "${YELLOW}⚠️  DNS patch may have already been applied${NC}"
        }

        # Create DNS config
        kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: dns-fix-config
  namespace: gpu-operator
data:
  resolv.conf: |
    nameserver 8.8.8.8
    nameserver 8.8.4.4
    search default.svc.cluster.local svc.cluster.local cluster.local
    options ndots:5
EOF

        echo -e "${GREEN}✅ DNS fix applied${NC}"
    else
        echo -e "${CYAN}Non-Ubuntu OS detected: $NODE_OS_IMAGE${NC}"
        echo "Skipping DNS fix (not needed)"
    fi
else
    echo ""
    echo -e "${CYAN}ℹ️  AKS deployment detected - skipping EKS-specific DNS fix${NC}"
fi

echo ""
echo -e "${GREEN}✅ GPU Operator installation completed!${NC}"
echo ""
echo "📊 Monitoring driver installation (this may take 10-25 minutes)..."
echo "Use 'kubectl get pods -n gpu-operator -w' to watch progress"
echo ""

# Show current status
echo "Current pod status:"
kubectl get pods -n gpu-operator -o wide

echo ""
echo -e "${CYAN}💡 Useful commands:${NC}"
echo ""
echo "Check if drivers are ready:"
echo "  kubectl get pods -n gpu-operator -l app=nvidia-driver-daemonset"
echo ""
echo "Check GPU capacity:"
if [[ "$CLOUD_PROVIDER" == "eks" ]]; then
    echo "  kubectl get nodes -l ${GPU_NODE_SELECTOR} -o json | jq -r '.items[] | \"\(.metadata.name): \(.status.capacity.\"nvidia.com/gpu\" // \"0\") GPUs\"'"
else
    echo "  kubectl get nodes -l ${GPU_NODE_SELECTOR} -o json | jq -r '.items[] | \"\(.metadata.name): \(.status.capacity.\"nvidia.com/gpu\" // \"0\") GPUs\"'"
fi
echo ""
echo "Test nvidia-smi:"
echo "  POD=\$(kubectl get pods -n gpu-operator -l app=nvidia-driver-daemonset -o name | head -1)"
echo "  kubectl exec -n gpu-operator \$POD -- nvidia-smi"
echo ""
echo "Monitor logs:"
echo "  kubectl logs -n gpu-operator -l app=nvidia-driver-daemonset -f"
echo ""
