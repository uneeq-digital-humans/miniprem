#!/bin/bash
set -e

# Standalone GPU Operator Installation Script
# This can be run independently to test GPU operator installation

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo "========================================"
echo "   Standalone GPU Operator Installer   "
echo "========================================"
echo ""

# Check prerequisites
echo "🔍 Checking prerequisites..."

# Check kubectl connectivity
if ! kubectl get nodes >/dev/null 2>&1; then
    echo -e "${RED}❌ Cannot connect to Kubernetes cluster${NC}"
    echo "Please ensure kubectl is configured and cluster is accessible"
    exit 1
fi

# Check for GPU nodes
GPU_NODES=$(kubectl get nodes -l nvidia.com/gpu=true --no-headers 2>/dev/null | wc -l | tr -d ' \n' || echo "0")
if [ "$GPU_NODES" -eq "0" ]; then
    echo -e "${YELLOW}⚠️  No GPU nodes found (nvidia.com/gpu=true label)${NC}"
    echo "GPU operator will still install but won't deploy drivers"
fi

echo "✅ Found $GPU_NODES GPU nodes"

# Check if already installed
if helm list -n gpu-operator | grep -q "gpu-operator.*deployed"; then
    echo -e "${YELLOW}⚠️  GPU operator already installed${NC}"
    echo "Use --force to reinstall or --status to check status"
    
    if [[ "$1" == "--force" ]]; then
        echo "🗑️  Uninstalling existing GPU operator..."
        helm uninstall gpu-operator -n gpu-operator --timeout=300s || true
        kubectl delete namespace gpu-operator --wait=false || true
        echo "⏳ Waiting for cleanup..."
        sleep 30
    elif [[ "$1" == "--status" ]]; then
        echo ""
        echo "📊 Current GPU Operator Status:"
        helm list -n gpu-operator
        echo ""
        echo "GPU Operator Pods:"
        kubectl get pods -n gpu-operator -o wide
        echo ""
        echo "GPU Node Capacity:"
        kubectl get nodes -o json | jq -r '.items[] | select(.metadata.labels."nvidia.com/gpu" == "true") | "\(.metadata.name): \(.status.capacity."nvidia.com/gpu" // "0") GPUs"'
        exit 0
    else
        exit 1
    fi
fi

echo ""
echo "🎮 Installing NVIDIA GPU Operator..."
echo "This will:"
echo "  - Install NVIDIA driver 580+ on all GPU nodes"
echo "  - Configure containerd with NVIDIA runtime"
echo "  - Enable GPU device plugin and monitoring"
echo ""

# Add NVIDIA Helm repository
echo "📦 Adding NVIDIA Helm repository..."
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

# Create namespace
echo "📁 Creating gpu-operator namespace..."
kubectl create namespace gpu-operator --dry-run=client -o yaml | kubectl apply -f -

# Install GPU Operator (fixed boolean parsing)
echo "⚙️  Installing GPU operator with corrected values..."
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

# Apply DNS fix for Ubuntu systemd-resolved
echo ""
echo "🔧 Applying DNS fix for Ubuntu systemd-resolved..."
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
'

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

echo ""
echo "✅ GPU Operator installation completed!"
echo ""
echo "📊 Monitoring driver installation (this may take 10-25 minutes)..."
echo "Use 'kubectl get pods -n gpu-operator -w' to watch progress"
echo ""

# Show current status
echo "Current pod status:"
kubectl get pods -n gpu-operator -o wide

echo ""
echo "💡 To check if drivers are ready:"
echo "   kubectl get pods -n gpu-operator -l app=nvidia-driver-daemonset"
echo ""
echo "💡 To check GPU capacity:"
echo "   kubectl get nodes -o json | jq -r '.items[] | select(.metadata.labels.\"nvidia.com/gpu\" == \"true\") | \"\(.metadata.name): \(.status.capacity.\"nvidia.com/gpu\" // \"0\") GPUs\"'"
echo ""
echo "💡 To monitor logs:"
echo "   kubectl logs -n gpu-operator -l app=nvidia-driver-daemonset -f"