#!/bin/bash
# Status check script - shows current state of the deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"

echo "======================================"
echo "   Renny EKS Deployment Status       "
echo "======================================"
echo ""

# Check if terraform state exists
if [ ! -f "$PROJECT_DIR/terraform/terraform.tfstate" ]; then
    echo -e "${RED}❌ No deployment found${NC}"
    echo "Run ./scripts/deploy.sh to create a deployment"
    exit 1
fi

# Get cluster info
cd "$PROJECT_DIR/terraform"
CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "")
REGION=$(terraform output -raw region 2>/dev/null || echo "us-east-1")
cd "$PROJECT_DIR"

if [ -z "$CLUSTER_NAME" ]; then
    echo -e "${RED}❌ Could not get cluster information${NC}"
    exit 1
fi

# Configure kubectl
echo "Connecting to cluster: $CLUSTER_NAME"
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME" 2>/dev/null || {
    echo -e "${RED}❌ Could not connect to cluster${NC}"
    exit 1
}

echo ""
echo -e "${BLUE}📊 Cluster Overview${NC}"
echo "===================="
echo "Cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo ""

# Node status
echo -e "${BLUE}🖥️  Node Status${NC}"
echo "===================="
TOTAL_NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "0")
READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready " || echo "0")
echo "Total Nodes: $TOTAL_NODES"
echo "Ready Nodes: $READY_NODES"
echo ""

# Node breakdown
echo "Node Groups:"
CONTROL_NODES=$(kubectl get nodes -l uneeq.io/node-type=control --no-headers 2>/dev/null | wc -l || echo "0")
RENNY_NODES=$(kubectl get nodes -l uneeq.io/node-type=renny --no-headers 2>/dev/null | wc -l || echo "0")
A2F_NODES=$(kubectl get nodes -l uneeq.io/node-type=a2f --no-headers 2>/dev/null | wc -l || echo "0")

echo "  Control Nodes: $CONTROL_NODES (t3.large)"
echo "  Renny GPU Nodes: $RENNY_NODES (g5.2xlarge)"
echo "  A2F GPU Nodes: $A2F_NODES (g5.2xlarge)"
echo ""

# Pod status
echo -e "${BLUE}🚀 Application Status${NC}"
echo "===================="

# Renny pods
RENNY_RUNNING=$(kubectl get pods -n uneeq-renderer -l app=renny --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l || echo "0")
RENNY_TOTAL=$(kubectl get pods -n uneeq-renderer -l app=renny --no-headers 2>/dev/null | wc -l || echo "0")

if [ "$RENNY_TOTAL" -gt 0 ]; then
    if [ "$RENNY_RUNNING" -eq "$RENNY_TOTAL" ]; then
        echo -e "Renny: ${GREEN}✅ $RENNY_RUNNING/$RENNY_TOTAL pods running${NC}"
    else
        echo -e "Renny: ${YELLOW}⚠️  $RENNY_RUNNING/$RENNY_TOTAL pods running${NC}"
    fi
else
    echo -e "Renny: ${RED}❌ Not deployed${NC}"
fi

# A2F pods
A2F_RUNNING=$(kubectl get pods -n uneeq-renderer -l app=a2f --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l || echo "0")
A2F_TOTAL=$(kubectl get pods -n uneeq-renderer -l app=a2f --no-headers 2>/dev/null | wc -l || echo "0")

if [ "$A2F_TOTAL" -gt 0 ]; then
    if [ "$A2F_RUNNING" -eq "$A2F_TOTAL" ]; then
        echo -e "Audio2Face: ${GREEN}✅ $A2F_RUNNING/$A2F_TOTAL pods running${NC}"
    else
        echo -e "Audio2Face: ${YELLOW}⚠️  $A2F_RUNNING/$A2F_TOTAL pods running${NC}"
    fi
else
    echo -e "Audio2Face: ${RED}❌ Not deployed${NC}"
fi

# GPU Operator
GPU_OP_RUNNING=$(kubectl get pods -n gpu-operator --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l || echo "0")
if [ "$GPU_OP_RUNNING" -gt 0 ]; then
    echo -e "GPU Operator: ${GREEN}✅ Running ($GPU_OP_RUNNING pods)${NC}"
else
    echo -e "GPU Operator: ${RED}❌ Not running${NC}"
fi

# Autoscaler
AUTOSCALER_RUNNING=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-cluster-autoscaler --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l || echo "0")
if [ "$AUTOSCALER_RUNNING" -gt 0 ]; then
    echo -e "Cluster Autoscaler: ${GREEN}✅ Running${NC}"
else
    echo -e "Cluster Autoscaler: ${YELLOW}⚠️  Not running${NC}"
fi

echo ""

# Resource usage
echo -e "${BLUE}📈 Resource Usage${NC}"
echo "===================="

# Try to get resource metrics
if kubectl top nodes &>/dev/null; then
    echo "Top 5 nodes by CPU usage:"
    kubectl top nodes | head -6
else
    echo "Metrics not available (metrics-server may not be installed)"
fi

echo ""

# Cost estimate
echo -e "${BLUE}💰 Cost Estimate${NC}"
echo "===================="
HOURLY_COST=$(echo "scale=2; (2 * 0.17) + ($RENNY_NODES * 1.22) + ($A2F_NODES * 1.22) + 0.10" | bc 2>/dev/null || echo "15")
DAILY_COST=$(echo "scale=2; $HOURLY_COST * 24" | bc 2>/dev/null || echo "360")
MONTHLY_COST=$(echo "scale=2; $DAILY_COST * 30" | bc 2>/dev/null || echo "10800")

echo "Estimated costs (USD):"
echo "  Hourly: ~\$$HOURLY_COST"
echo "  Daily: ~\$$DAILY_COST"
echo "  Monthly: ~\$$MONTHLY_COST"
echo ""

# Recent events
echo -e "${BLUE}📋 Recent Events${NC}"
echo "===================="
EVENTS=$(kubectl get events -n uneeq-renderer --sort-by='.lastTimestamp' 2>/dev/null | tail -5)
if [ -n "$EVENTS" ]; then
    echo "$EVENTS"
else
    echo "No recent events"
fi

echo ""
echo "======================================"
echo -e "${GREEN}Status check complete${NC}"
echo ""
echo "Commands:"
echo "  Scale: ./scripts/scale.sh <count>"
echo "  Destroy: ./scripts/destroy.sh"
echo "  Logs: kubectl logs -n uneeq-renderer -l app=renny --tail=50"