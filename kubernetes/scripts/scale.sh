#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"

# Check if desired count is provided
if [ $# -eq 0 ]; then
    echo "Usage: ./scale.sh <desired_count>"
    echo "Example: ./scale.sh 15"
    echo ""
    echo "This will scale the Renny node group to the desired number of instances."
    echo "Valid range: 10-20 instances"
    exit 1
fi

DESIRED_COUNT=$1
MAX_COUNT=20
MIN_COUNT=10

# Validate input is a number
if ! [[ "$DESIRED_COUNT" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}❌ Error: Desired count must be a number${NC}"
    exit 1
fi

# Validate range
if [ $DESIRED_COUNT -lt $MIN_COUNT ] || [ $DESIRED_COUNT -gt $MAX_COUNT ]; then
    echo -e "${RED}❌ Desired count must be between $MIN_COUNT and $MAX_COUNT${NC}"
    exit 1
fi

echo "🔄 Scaling Renny nodes to $DESIRED_COUNT instances..."

# Get cluster name from Terraform
cd "$PROJECT_DIR/terraform"
if ! CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null); then
    echo -e "${RED}❌ Could not get cluster name from Terraform${NC}"
    echo "Please ensure the infrastructure has been deployed"
    exit 1
fi

if ! REGION=$(terraform output -raw region 2>/dev/null); then
    REGION="us-east-1"
fi
cd "$PROJECT_DIR"

# Get current node count
echo "📊 Current node status:"
CURRENT_NODES=$(kubectl get nodes -l uneeq.io/node-type=renny --no-headers 2>/dev/null | wc -l)
echo "Current Renny nodes: $CURRENT_NODES"

# Update the node group
echo "Updating node group configuration..."
aws eks update-nodegroup-config \
    --cluster-name "$CLUSTER_NAME" \
    --nodegroup-name "${CLUSTER_NAME}-renny-gpu" \
    --scaling-config minSize=$MIN_COUNT,maxSize=$MAX_COUNT,desiredSize=$DESIRED_COUNT \
    --region "$REGION" \
    --output json > /dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Node group scaling initiated${NC}"
else
    echo -e "${RED}❌ Failed to update node group${NC}"
    exit 1
fi

# Scale the Renny deployment replicas to match
echo "Scaling Renny deployment to $DESIRED_COUNT replicas..."
kubectl scale deployment renny -n uneeq-renderer --replicas=$DESIRED_COUNT

echo ""
echo "⏳ Scaling in progress..."
echo "This process may take 5-10 minutes to complete."
echo ""
echo "Monitor progress with:"
echo "  kubectl get nodes -l uneeq.io/node-type=renny -w"
echo ""
echo "Check Renny pods with:"
echo "  kubectl get pods -n uneeq-renderer -l app=renny"
echo ""

# Wait a bit and show initial status
sleep 5

echo "📊 Node scaling status:"
kubectl get nodes -l uneeq.io/node-type=renny

echo ""
echo "🚀 Renny pod status:"
kubectl get pods -n uneeq-renderer -l app=renny

echo ""
echo -e "${GREEN}✅ Scaling command submitted successfully${NC}"
echo "Target configuration:"
echo "  - Renny nodes: $DESIRED_COUNT"
echo "  - Renny pods: $DESIRED_COUNT"