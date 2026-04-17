#!/bin/bash
set -e

# Source deployment functions (includes color definitions)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/deployment-functions.sh"

# Parse command line arguments
AWS_PROFILE_ARG=""
COMPONENT="renny"
SHOW_HELP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --profile)
            AWS_PROFILE_ARG="$2"
            shift 2
            ;;
        --component|-c)
            COMPONENT="$2"
            shift 2
            ;;
        --help|-h)
            SHOW_HELP=true
            shift
            ;;
        [0-9]*)
            DESIRED_COUNT="$1"
            shift
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
fi

# Note: SCRIPT_DIR and PROJECT_DIR already defined by sourcing deployment-functions.sh

# Show help
if [ "$SHOW_HELP" = true ] || [ -z "${DESIRED_COUNT:-}" ]; then
    echo "Usage: ./scale.sh [OPTIONS] <desired_count>"
    echo ""
    echo "Options:"
    echo "  --component, -c COMPONENT  Component to scale (renny) [default: renny]"
    echo "  --profile PROFILE_NAME     Use specific AWS profile"
    echo "  --help, -h                 Show this help message"
    echo ""
    echo "Examples:"
    echo "  ./scale.sh 15              # Scale Renny to 15 nodes"
    echo "  ./scale.sh --profile prod 12  # Scale with specific AWS profile"
    echo ""
    exit 0
fi

# Get configuration limits from terraform.tfvars
cd "$PROJECT_DIR/kubernetes/terraform/eks"
if [ "$COMPONENT" = "renny" ]; then
    MAX_COUNT=$(awk '/^renny_max_size[[:space:]]*=/ {gsub(/[^0-9]/, "", $3); print $3}' terraform.tfvars || echo "20")
    MIN_COUNT=$(awk '/^renny_min_size[[:space:]]*=/ {gsub(/[^0-9]/, "", $3); print $3}' terraform.tfvars || echo "10")
    COMPONENT_NAME="Renny"
    NODE_LABEL="renny"
else
    echo -e "${RED}❌ Invalid component: $COMPONENT${NC}"
    echo "Valid components: renny"
    exit 1
fi

# Validate input is a number
if ! [[ "$DESIRED_COUNT" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}❌ Error: Desired count must be a number${NC}"
    exit 1
fi

# Validate range
if [ $DESIRED_COUNT -lt $MIN_COUNT ] || [ $DESIRED_COUNT -gt $MAX_COUNT ]; then
    echo -e "${RED}❌ Desired count must be between $MIN_COUNT and $MAX_COUNT${NC}"
    echo "Current limits from terraform.tfvars: min=$MIN_COUNT, max=$MAX_COUNT"
    exit 1
fi

# Load deployment configuration
cd "$PROJECT_DIR/kubernetes/terraform/eks"
if ! init_deployment_config "false" ""; then
    echo -e "${RED}❌ Could not load deployment configuration${NC}"
    echo "Please ensure the infrastructure has been deployed and .deployment_id exists"
    exit 1
fi

if [ -z "$CLUSTER_NAME" ]; then
    echo -e "${RED}❌ Could not determine cluster name${NC}"
    echo "Please ensure the infrastructure has been deployed"
    exit 1
fi

# Get region from terraform.tfvars (single source of truth)
if ! REGION=$(terraform output -raw region 2>/dev/null); then
    # Fallback to reading from terraform.tfvars
    REGION=$(awk '/^aws_region[[:space:]]*=/ {gsub(/[" ]/, "", $3); print $3}' terraform.tfvars 2>/dev/null)
    if [ -z "$REGION" ]; then
        echo -e "${RED}Error: Cannot determine AWS region${NC}" >&2
        echo "Either deploy infrastructure first (for terraform output) or set aws_region in terraform.tfvars" >&2
        exit 1
    fi
fi

# Get current node count
echo "📊 Current $COMPONENT_NAME status:"
CURRENT_NODES=$(kubectl get nodes -l uneeq.io/node-type=$NODE_LABEL --no-headers 2>/dev/null | wc -l || echo "0")
echo "Current $COMPONENT_NAME nodes: $CURRENT_NODES"

# Show confirmation prompt
echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                   Scaling Confirmation                ║${NC}" 
echo -e "${CYAN}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Component: $COMPONENT_NAME"
echo "Current nodes: $CURRENT_NODES"
echo "Target nodes: $DESIRED_COUNT"
echo "Range: $MIN_COUNT - $MAX_COUNT"
echo ""
if [ "$DESIRED_COUNT" -gt "$CURRENT_NODES" ]; then
    local additional=$((DESIRED_COUNT - CURRENT_NODES))
    echo -e "${BLUE}This will ADD $additional nodes (scale up)${NC}"
    echo "Cost impact: ~$additional additional GPU instances"
elif [ "$DESIRED_COUNT" -lt "$CURRENT_NODES" ]; then
    local removing=$((CURRENT_NODES - DESIRED_COUNT))
    echo -e "${BLUE}This will REMOVE $removing nodes (scale down)${NC}"
    echo "Cost savings: ~$removing fewer GPU instances"
else
    echo -e "${YELLOW}No change needed - already at $DESIRED_COUNT nodes${NC}"
    exit 0
fi
echo ""
# Flexible user input validation helper (copied from deploy.sh for consistency)
read_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local response
    
    if [[ "$default" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}${prompt} (Y/n) response: ${NC}"
    else
        echo -e "${YELLOW}${prompt} (y/N) response: ${NC}"
    fi
    
    read -r response
    
    if [ -z "$response" ]; then
        response="$default"
    fi
    
    if [[ "$response" =~ ^[Yy]([Ee][Ss])?$ ]]; then
        return 0
    else
        return 1
    fi
}

if ! read_yes_no "Proceed with scaling?" "n"; then
    echo "Scaling cancelled"
    exit 0
fi

echo ""
echo "🔄 Scaling $COMPONENT_NAME to $DESIRED_COUNT instances..."

# Update the node group (with correct naming)
echo "Updating node group configuration..."
NODEGROUP_NAME="${CLUSTER_NAME}-${NODE_LABEL}-gpu-v4"

aws eks update-nodegroup-config \
    --cluster-name "$CLUSTER_NAME" \
    --nodegroup-name "$NODEGROUP_NAME" \
    --scaling-config minSize=$MIN_COUNT,maxSize=$MAX_COUNT,desiredSize=$DESIRED_COUNT \
    --region "$REGION" \
    --output json > /dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Node group scaling initiated${NC}"
else
    echo -e "${RED}❌ Failed to update node group${NC}"
    echo "Node group name tried: $NODEGROUP_NAME"
    exit 1
fi

# Scale the deployment replicas to match
echo "Scaling $COMPONENT_NAME deployment to $DESIRED_COUNT replicas..."
kubectl scale deployment $COMPONENT -n uneeq-renderer --replicas=$DESIRED_COUNT

echo ""
echo "⏳ Scaling in progress..."
echo "This process may take 5-15 minutes to complete."
echo ""
echo "Monitor progress with:"
echo "  kubectl get nodes -l uneeq.io/node-type=$NODE_LABEL -w"
echo ""
echo "Check $COMPONENT_NAME pods with:"
echo "  kubectl get pods -n uneeq-renderer -l app=$COMPONENT"
echo ""

# Wait a bit and show initial status
sleep 5

echo "📊 Node scaling status:"
kubectl get nodes -l uneeq.io/node-type=$NODE_LABEL

echo ""
echo "🚀 $COMPONENT_NAME pod status:"
kubectl get pods -n uneeq-renderer -l app=$COMPONENT

echo ""
echo -e "${GREEN}✅ Scaling command submitted successfully${NC}"
echo "Target configuration:"
echo "  - $COMPONENT_NAME nodes: $DESIRED_COUNT"
echo "  - $COMPONENT_NAME pods: $DESIRED_COUNT"