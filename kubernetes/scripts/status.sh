#!/bin/bash
# Status check script - shows current state of the deployment

set -e

# Source deployment functions
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/deployment-functions.sh"

# Parse command line arguments
AWS_PROFILE_ARG=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --profile)
            AWS_PROFILE_ARG="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --profile PROFILE_NAME    Use specific AWS profile"
            echo "  --help, -h                Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Set AWS profile if provided
if [ -n "$AWS_PROFILE_ARG" ]; then
    export AWS_PROFILE="$AWS_PROFILE_ARG"
    echo "Using AWS profile: $AWS_PROFILE"
fi

# Note: Colors, SCRIPT_DIR, and PROJECT_DIR already defined in deployment-functions.sh

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

# Load deployment configuration
cd "$PROJECT_DIR/terraform"
init_deployment_config "false" ""
REGION="$AWS_REGION"

# Read actual configuration from terraform.tfvars for accurate cost calculations
if [ -f "terraform.tfvars" ]; then
    RENNY_DESIRED=$(awk '/^renny_desired_size[[:space:]]*=/ {gsub(/[^0-9]/, "", $3); print $3}' terraform.tfvars || echo "10")
    RENNY_INSTANCE=$(awk '/^renny_instance_type[[:space:]]*=/ {gsub(/"/, "", $3); print $3}' terraform.tfvars || echo "g5.4xlarge")
    CONTROL_INSTANCE=$(awk '/^control_instance_type[[:space:]]*=/ {gsub(/"/, "", $3); print $3}' terraform.tfvars || echo "t3.large")
else
    echo -e "${YELLOW}⚠️  terraform.tfvars not found, using defaults${NC}"
    RENNY_DESIRED="10"
    RENNY_INSTANCE="g5.4xlarge"
    CONTROL_INSTANCE="t3.large"
fi

if [ -z "$CLUSTER_NAME" ]; then
    echo -e "${RED}❌ Could not get cluster information${NC}"
    exit 1
fi

# Configure kubectl with better error handling
echo "Connecting to cluster: $CLUSTER_NAME"
if ! aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME" 2>/dev/null; then
    echo -e "${RED}❌ Could not connect to cluster${NC}"
    echo "Please check:"
    echo "  - AWS credentials are configured correctly"
    echo "  - Region is correct: $REGION"
    echo "  - Cluster exists and you have access: $CLUSTER_NAME"
    if [ -n "$AWS_PROFILE" ]; then
        echo "  - AWS profile is valid: $AWS_PROFILE"
    fi
    exit 1
fi

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

echo "  Control Nodes: $CONTROL_NODES ($CONTROL_INSTANCE)"
echo "  Renny GPU Nodes: $RENNY_NODES ($RENNY_INSTANCE)"
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

# Try to get resource metrics with timeout
if timeout 10s kubectl top nodes &>/dev/null; then
    echo "Top 5 nodes by CPU usage:"
    kubectl top nodes | head -6
else
    echo "Metrics not available (metrics-server may not be installed or not ready)"
    echo "To install: kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
fi

echo ""

# Cost estimate based on actual configuration
echo -e "${BLUE}💰 Cost Estimate${NC}"
echo "===================="

# Instance pricing (USD/hour) - approximate pricing (varies by region)
get_instance_cost() {
    case $1 in
        "t3.large") echo "0.08" ;;
        "g5.2xlarge") echo "1.22" ;;
        "g5.4xlarge") echo "2.03" ;;
        "g5.8xlarge") echo "2.72" ;;
        "g5.12xlarge") echo "4.32" ;;
        *) echo "1.50" ;;  # default estimate
    esac
}

CONTROL_COST=$(get_instance_cost "$CONTROL_INSTANCE")
RENNY_COST=$(get_instance_cost "$RENNY_INSTANCE")

# Calculate actual costs based on running nodes and NAT gateway
HOURLY_COST=$(echo "scale=2; ($CONTROL_NODES * $CONTROL_COST) + ($RENNY_NODES * $RENNY_COST) + 0.045" | bc 2>/dev/null || echo "10")
DAILY_COST=$(echo "scale=2; $HOURLY_COST * 24" | bc 2>/dev/null || echo "360")
MONTHLY_COST=$(echo "scale=2; $DAILY_COST * 30" | bc 2>/dev/null || echo "10800")

echo "Instance breakdown:"
echo "  Control ($CONTROL_INSTANCE): $CONTROL_NODES × \$$CONTROL_COST/hr = \$$(echo "scale=2; $CONTROL_NODES * $CONTROL_COST" | bc)/hr"
echo "  Renny ($RENNY_INSTANCE): $RENNY_NODES × \$$RENNY_COST/hr = \$$(echo "scale=2; $RENNY_NODES * $RENNY_COST" | bc)/hr"
echo "  NAT Gateway: \$0.045/hr"
echo ""

echo "Estimated costs (USD):"
echo "  Hourly: ~\$$HOURLY_COST"
echo "  Daily: ~\$$DAILY_COST"
echo "  Monthly: ~\$$MONTHLY_COST"
echo ""

# Recent events with better formatting
echo -e "${BLUE}📋 Recent Events${NC}"
echo "===================="
if kubectl get events -n uneeq-renderer --sort-by='.lastTimestamp' 2>/dev/null | tail -5 > /tmp/events.tmp; then
    if [ -s /tmp/events.tmp ]; then
        cat /tmp/events.tmp
    else
        echo "No recent events in uneeq-renderer namespace"
    fi
    rm -f /tmp/events.tmp
else
    echo "Could not retrieve events (namespace may not exist yet)"
fi

echo ""
echo "======================================"
echo -e "${GREEN}Status check complete${NC}"
echo ""
echo "Commands:"
echo "  Scale Renny: ./scripts/scale.sh <count>"
echo "  Destroy: ./scripts/destroy.sh"
echo "  Logs (Renny): kubectl logs -n uneeq-renderer -l app=renny --tail=50"
