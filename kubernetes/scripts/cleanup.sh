#!/bin/bash
# Quick cleanup script for testing - removes all resources without confirmations
# USE WITH CAUTION - This will destroy everything immediately

set -e

# Source deployment functions
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/deployment-functions.sh"

# Colors for output (already defined in deployment-functions.sh)
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color
PROJECT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"

echo -e "${RED}⚠️  EMERGENCY CLEANUP - NO CONFIRMATIONS${NC}"
echo "Starting immediate teardown..."

# Load deployment configuration
cd "$PROJECT_DIR/terraform"
init_deployment_config "false" ""
REGION="$AWS_REGION"
cd "$PROJECT_DIR"

if [ -n "$CLUSTER_NAME" ]; then
    # Configure kubectl
    aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME" 2>/dev/null || true
    
    # Force delete all namespaces
    kubectl delete namespace uneeq-renderer --grace-period=0 --force 2>/dev/null || true
    kubectl delete namespace gpu-operator --grace-period=0 --force 2>/dev/null || true
    
    # Force delete node groups (updated naming)
    for nodegroup in "${CLUSTER_NAME}-renny-gpu-v4" "${CLUSTER_NAME}-a2f-gpu-v4" "${CLUSTER_NAME}-control"; do
        aws eks delete-nodegroup \
            --cluster-name "$CLUSTER_NAME" \
            --nodegroup-name "$nodegroup" \
            --region "$REGION" 2>/dev/null || true
    done
fi

# Force terraform destroy
cd "$PROJECT_DIR/terraform"
terraform destroy -auto-approve -refresh=false 2>/dev/null || true

echo -e "${GREEN}✅ Emergency cleanup completed${NC}"