#!/bin/bash

################################################################################
# CNS Update Script
#
# Applies configuration changes from renny-values-cns.yaml to the running
# CNS deployment without a full reinstall.
#
# Usage:
#   ./cns-update.sh              # Apply values file changes
#   ./cns-update.sh --replicas 5 # Change replica count
#   ./cns-update.sh --restart    # Just restart pods (no helm upgrade)
#
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBERNETES_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
VALUES_FILE="$KUBERNETES_DIR/values/renny-values-cns.yaml"
CHART_DIR="$KUBERNETES_DIR/renny"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}ℹ️  $*${NC}"; }
success() { echo -e "${GREEN}✅ $*${NC}"; }
warning() { echo -e "${YELLOW}⚠️  $*${NC}"; }
error() { echo -e "${RED}❌ $*${NC}"; }

# Detect kubectl command
if command -v microk8s &> /dev/null; then
    KUBECTL="microk8s kubectl"
    HELM="microk8s helm3"
else
    KUBECTL="kubectl"
    HELM="helm"
fi

# Parse arguments
REPLICAS=""
RESTART_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --replicas|-r)
            REPLICAS="$2"
            shift 2
            ;;
        --restart)
            RESTART_ONLY=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --replicas, -r <count>  Set number of Renny replicas"
            echo "  --restart               Only restart pods (skip helm upgrade)"
            echo "  --help, -h              Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                      # Apply values file changes"
            echo "  $0 --replicas 5         # Scale to 5 replicas"
            echo "  $0 --restart            # Restart pods without config change"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check prerequisites
if [[ ! -f "$VALUES_FILE" ]]; then
    error "Values file not found: $VALUES_FILE"
    exit 1
fi

if [[ ! -d "$CHART_DIR" ]]; then
    error "Helm chart not found: $CHART_DIR"
    exit 1
fi

# Get current state
info "Current deployment status:"
$KUBECTL get deployment renderer -n uneeq -o wide 2>/dev/null || {
    error "No Renny deployment found in uneeq namespace"
    exit 1
}

CURRENT_REPLICAS=$($KUBECTL get deployment renderer -n uneeq -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
info "Current replicas: $CURRENT_REPLICAS"

if [[ "$RESTART_ONLY" == "true" ]]; then
    info "Restarting Renny pods..."
    $KUBECTL rollout restart deployment/renderer -n uneeq
    $KUBECTL rollout status deployment/renderer -n uneeq --timeout=300s
    success "Pods restarted successfully"
    exit 0
fi

# Build helm upgrade command
HELM_ARGS=(
    upgrade renny "$CHART_DIR"
    --namespace uneeq
    --values "$VALUES_FILE"
)

if [[ -n "$REPLICAS" ]]; then
    HELM_ARGS+=(--set "deployment.totalReplicas=$REPLICAS")
    info "Setting replicas to: $REPLICAS"
else
    info "Using replica count from values file"
fi

# Delete existing secret to ensure clean update
info "Cleaning up existing secrets..."
$KUBECTL delete secret renderer -n uneeq --ignore-not-found 2>/dev/null || true

# Run helm upgrade
info "Applying configuration changes..."
$HELM "${HELM_ARGS[@]}" --wait --timeout 10m

# Restart pods to pick up changes
info "Restarting Renny pods..."
$KUBECTL rollout restart deployment/renderer -n uneeq
$KUBECTL rollout status deployment/renderer -n uneeq --timeout=300s

# Show final status
echo ""
success "Configuration applied successfully!"
echo ""
info "Current pod status:"
$KUBECTL get pods -n uneeq -o wide

echo ""
info "To watch pod logs:"
echo "  $KUBECTL logs -f deployment/renderer -n uneeq"
