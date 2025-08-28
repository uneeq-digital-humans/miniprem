#!/bin/bash
# Quick cleanup script for testing - removes all resources without confirmations
# USE WITH CAUTION - This will destroy everything immediately

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"

echo -e "${RED}⚠️  EMERGENCY CLEANUP - NO CONFIRMATIONS${NC}"
echo "Starting immediate teardown..."

# Get cluster info
cd "$PROJECT_DIR/terraform"
CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "")
REGION=$(terraform output -raw region 2>/dev/null || echo "us-east-1")
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