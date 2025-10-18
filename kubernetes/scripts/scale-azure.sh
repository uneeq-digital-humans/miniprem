#!/bin/bash
set -e

# =============================================================================
# Azure AKS Node Pool Scaling Script for Renny Digital Humans
# =============================================================================
# This script provides comprehensive node pool scaling capabilities for AKS
# clusters with full feature parity to AWS EKS scaling operations.
#
# Features:
#   - Azure CLI-based node pool scaling
#   - Pre-flight validation (az CLI, kubectl, authentication)
#   - Current state display and comparison
#   - Scaling bounds validation (min/max)
#   - Progress tracking and monitoring
#   - Post-scale verification
#   - Cost impact estimation
#   - Renny pod scaling with GPU time-slicing awareness
#
# Requirements:
#   - Azure CLI (az) 2.50.0+
#   - kubectl 1.28.0+
#   - Active Azure authentication
#   - AKS cluster already deployed
#
# Usage:
#   ./scale-azure.sh [OPTIONS] <desired_count>
#
# Options:
#   --component, -c COMPONENT  Component to scale (renny) [default: renny]
#   --help, -h                 Show this help message
#   --debug                    Enable verbose debug output
#
# Examples:
#   ./scale-azure.sh 15              # Scale Renny to 15 nodes
#   ./scale-azure.sh --debug 12      # Scale with debug output
#
# =============================================================================

# Source deployment functions (includes color definitions)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Set TERRAFORM_DIR for Azure before sourcing (to prevent readonly conflict)
PROJECT_DIR_TEMP="$( cd "$SCRIPT_DIR/../.." && pwd )"
TERRAFORM_DIR="$PROJECT_DIR_TEMP/kubernetes/terraform/aks"
export TERRAFORM_DIR

source "$SCRIPT_DIR/deployment-functions.sh"

# Parse command line arguments
COMPONENT="renny"
SHOW_HELP=false
DEBUG_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --component|-c)
            COMPONENT="$2"
            shift 2
            ;;
        --help|-h)
            SHOW_HELP=true
            shift
            ;;
        --debug)
            DEBUG_MODE=true
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

# Debug logging
debug_log() {
    if [ "$DEBUG_MODE" = true ]; then
        echo -e "${CYAN}[DEBUG] $1${NC}"
    fi
}

# Show help
if [ "$SHOW_HELP" = true ] || [ -z "${DESIRED_COUNT:-}" ]; then
    echo "Usage: ./scale-azure.sh [OPTIONS] <desired_count>"
    echo ""
    echo "Scale Azure AKS node pools for Renny digital human deployment"
    echo ""
    echo "Options:"
    echo "  --component, -c COMPONENT  Component to scale (renny) [default: renny]"
    echo "  --debug                    Enable verbose debug output"
    echo "  --help, -h                 Show this help message"
    echo ""
    echo "Examples:"
    echo "  ./scale-azure.sh 15              # Scale Renny to 15 nodes"
    echo "  ./scale-azure.sh --debug 12      # Scale with debug output"
    echo ""
    echo "Cost Impact (westus3 pricing):"
    echo "  Standard_NC16as_T4_v3: ~\$1.50/hour per node"
    echo "  10 nodes: ~\$360/day, ~\$10,800/month"
    echo "  20 nodes: ~\$720/day, ~\$21,600/month"
    echo ""
    exit 0
fi

# =============================================================================
# Pre-flight Checks
# =============================================================================

echo -e "${BLUE}🚀 Azure AKS Node Pool Scaling${NC}"
echo ""

# Check Azure CLI
debug_log "Checking Azure CLI installation..."
if ! command -v az &> /dev/null; then
    echo -e "${RED}❌ Azure CLI (az) not found${NC}"
    echo ""
    echo "Please install Azure CLI:"
    echo "  macOS:   brew install azure-cli"
    echo "  Ubuntu:  curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
    echo "  Windows: Download from https://aka.ms/installazurecliwindows"
    echo ""
    exit 1
fi

# Check Azure CLI version
AZ_VERSION=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "0.0.0")
debug_log "Azure CLI version: $AZ_VERSION"

# Check kubectl
debug_log "Checking kubectl installation..."
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl not found${NC}"
    echo "Please install kubectl: https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi

# Check Azure authentication
debug_log "Verifying Azure authentication..."
if ! az account show &> /dev/null; then
    echo -e "${RED}❌ Not logged in to Azure${NC}"
    echo ""
    echo "Please login with one of:"
    echo "  az login                    # Interactive browser login"
    echo "  az login --use-device-code  # Device code flow"
    echo ""
    exit 1
fi

ACCOUNT_NAME=$(az account show --query "name" -o tsv 2>/dev/null || echo "Unknown")
ACCOUNT_ID=$(az account show --query "id" -o tsv 2>/dev/null || echo "Unknown")
debug_log "Azure Subscription: $ACCOUNT_NAME ($ACCOUNT_ID)"

echo -e "${GREEN}✅ Pre-flight checks passed${NC}"
echo ""

# =============================================================================
# Load Configuration
# =============================================================================

cd "$TERRAFORM_DIR"

# Validate component
if [ "$COMPONENT" = "renny" ]; then
    # Get configuration limits from terraform.tfvars
    MAX_COUNT=$(awk '/^renny_max_size[[:space:]]*=/ {gsub(/[^0-9]/, "", $3); print $3}' terraform.tfvars || echo "20")
    MIN_COUNT=$(awk '/^renny_min_size[[:space:]]*=/ {gsub(/[^0-9]/, "", $3); print $3}' terraform.tfvars || echo "2")
    COMPONENT_NAME="Renny"
    NODE_POOL_NAME="rennygpu"
    NODE_LABEL="renny"
else
    echo -e "${RED}❌ Invalid component: $COMPONENT${NC}"
    echo "Valid components: renny"
    exit 1
fi

debug_log "Configuration loaded: min=$MIN_COUNT, max=$MAX_COUNT, pool=$NODE_POOL_NAME"

# Validate input is a number
if ! [[ "$DESIRED_COUNT" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}❌ Error: Desired count must be a number${NC}"
    exit 1
fi

# Validate range
if [ $DESIRED_COUNT -lt $MIN_COUNT ] || [ $DESIRED_COUNT -gt $MAX_COUNT ]; then
    echo -e "${RED}❌ Desired count must be between $MIN_COUNT and $MAX_COUNT${NC}"
    echo "Current limits from terraform.tfvars: min=$MIN_COUNT, max=$MAX_COUNT"
    echo ""
    echo "To change limits, edit terraform.tfvars and run:"
    echo "  cd $TERRAFORM_DIR"
    echo "  terraform apply"
    exit 1
fi

# Get cluster name from terraform outputs or terraform.tfvars
if ! CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null); then
    # Fallback to reading from terraform.tfvars
    PROJECT_NAME=$(awk '/^project_name[[:space:]]*=/ {gsub(/[" ]/, "", $3); print $3}' terraform.tfvars 2>/dev/null || echo "renny")
    ENVIRONMENT=$(awk '/^environment[[:space:]]*=/ {gsub(/[" ]/, "", $3); print $3}' terraform.tfvars 2>/dev/null || echo "production")
    DEPLOYMENT_ID=$(awk '/^deployment_id[[:space:]]*=/ {gsub(/[" ]/, "", $3); print $3}' terraform.tfvars 2>/dev/null || echo "")

    if [ -n "$DEPLOYMENT_ID" ]; then
        CLUSTER_NAME="$PROJECT_NAME-$ENVIRONMENT-$DEPLOYMENT_ID"
    else
        CLUSTER_NAME="$PROJECT_NAME-$ENVIRONMENT"
    fi
fi

# Get resource group
if ! RESOURCE_GROUP=$(terraform output -raw resource_group_name 2>/dev/null); then
    RESOURCE_GROUP=$(awk '/^resource_group_name[[:space:]]*=/ {gsub(/[" ]/, "", $3); print $3}' terraform.tfvars 2>/dev/null || echo "renny-kubernetes")
fi

# Get region
if ! AZURE_REGION=$(terraform output -raw azure_region 2>/dev/null); then
    AZURE_REGION=$(awk '/^azure_region[[:space:]]*=/ {gsub(/[" ]/, "", $3); print $3}' terraform.tfvars 2>/dev/null || echo "eastus")
fi

debug_log "Cluster: $CLUSTER_NAME"
debug_log "Resource Group: $RESOURCE_GROUP"
debug_log "Region: $AZURE_REGION"

# Verify cluster exists
if ! az aks show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    echo -e "${RED}❌ AKS cluster '$CLUSTER_NAME' not found in resource group '$RESOURCE_GROUP'${NC}"
    echo ""
    echo "Please ensure the infrastructure has been deployed with:"
    echo "  cd kubernetes/"
    echo "  ./scripts/deploy-azure.sh"
    exit 1
fi

# Verify node pool exists
if ! az aks nodepool show --cluster-name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" --name "$NODE_POOL_NAME" &>/dev/null; then
    echo -e "${RED}❌ Node pool '$NODE_POOL_NAME' not found in cluster '$CLUSTER_NAME'${NC}"
    exit 1
fi

echo -e "${CYAN}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║              Cluster Configuration                    ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Cluster: $CLUSTER_NAME"
echo "Resource Group: $RESOURCE_GROUP"
echo "Region: $AZURE_REGION"
echo "Node Pool: $NODE_POOL_NAME"
echo ""

# =============================================================================
# Get Current State
# =============================================================================

echo "📊 Current $COMPONENT_NAME status:"

# Get current node pool count
CURRENT_NODES=$(az aks nodepool show \
    --cluster-name "$CLUSTER_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --name "$NODE_POOL_NAME" \
    --query "count" -o tsv 2>/dev/null || echo "0")

debug_log "Current nodes from Azure API: $CURRENT_NODES"

# Get current node count from kubectl
KUBECTL_NODES=$(kubectl get nodes -l uneeq.io/node-type=$NODE_LABEL --no-headers 2>/dev/null | wc -l | tr -d ' ' || echo "0")
debug_log "Current nodes from kubectl: $KUBECTL_NODES"

echo "Current $COMPONENT_NAME nodes: $CURRENT_NODES"

# Check if autoscaler is enabled
AUTOSCALER_ENABLED=$(az aks nodepool show \
    --cluster-name "$CLUSTER_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --name "$NODE_POOL_NAME" \
    --query "enableAutoScaling" -o tsv 2>/dev/null || echo "false")

if [ "$AUTOSCALER_ENABLED" = "true" ]; then
    echo -e "${YELLOW}⚠️  Note: Autoscaler is enabled on this node pool${NC}"
    echo "   Manual scaling will set a new desired size, but autoscaler may adjust later"
    echo ""
fi

# =============================================================================
# Show Confirmation Prompt
# =============================================================================

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

# Calculate cost impact (Standard_NC16as_T4_v3 pricing)
HOURLY_COST_PER_NODE=1.50
CURRENT_HOURLY=$(echo "$CURRENT_NODES * $HOURLY_COST_PER_NODE" | bc)
CURRENT_MONTHLY=$(echo "$CURRENT_HOURLY * 730" | bc)
NEW_HOURLY=$(echo "$DESIRED_COUNT * $HOURLY_COST_PER_NODE" | bc)
NEW_MONTHLY=$(echo "$NEW_HOURLY * 730" | bc)

if [ "$DESIRED_COUNT" -gt "$CURRENT_NODES" ]; then
    ADDITIONAL=$((DESIRED_COUNT - CURRENT_NODES))
    COST_CHANGE=$(echo "$NEW_HOURLY - $CURRENT_HOURLY" | bc)
    MONTHLY_CHANGE=$(echo "$NEW_MONTHLY - $CURRENT_MONTHLY" | bc)

    echo -e "${BLUE}This will ADD $ADDITIONAL nodes (scale up)${NC}"
    echo ""
    echo "Cost Impact:"
    printf "  Current: \$%.2f/hour (~\$%.0f/month)\n" "$CURRENT_HOURLY" "$CURRENT_MONTHLY"
    printf "  New:     \$%.2f/hour (~\$%.0f/month)\n" "$NEW_HOURLY" "$NEW_MONTHLY"
    printf "  Change:  ${RED}+\$%.2f/hour (+\$%.0f/month)${NC}\n" "$COST_CHANGE" "$MONTHLY_CHANGE"
elif [ "$DESIRED_COUNT" -lt "$CURRENT_NODES" ]; then
    REMOVING=$((CURRENT_NODES - DESIRED_COUNT))
    COST_CHANGE=$(echo "$CURRENT_HOURLY - $NEW_HOURLY" | bc)
    MONTHLY_CHANGE=$(echo "$CURRENT_MONTHLY - $NEW_MONTHLY" | bc)

    echo -e "${BLUE}This will REMOVE $REMOVING nodes (scale down)${NC}"
    echo ""
    echo "Cost Savings:"
    printf "  Current: \$%.2f/hour (~\$%.0f/month)\n" "$CURRENT_HOURLY" "$CURRENT_MONTHLY"
    printf "  New:     \$%.2f/hour (~\$%.0f/month)\n" "$NEW_HOURLY" "$NEW_MONTHLY"
    printf "  Savings: ${GREEN}-\$%.2f/hour (-\$%.0f/month)${NC}\n" "$COST_CHANGE" "$MONTHLY_CHANGE"
else
    echo -e "${YELLOW}No change needed - already at $DESIRED_COUNT nodes${NC}"
    exit 0
fi

echo ""

# Flexible user input validation helper
read_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local response

    if [[ "$default" =~ ^[Yy]$ ]]; then
        echo -ne "${YELLOW}${prompt} (Y/n): ${NC}"
    else
        echo -ne "${YELLOW}${prompt} (y/N): ${NC}"
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

# =============================================================================
# Execute Scaling Operation
# =============================================================================

echo ""
echo "🔄 Scaling $COMPONENT_NAME to $DESIRED_COUNT nodes..."
echo ""

# Scale the node pool
echo "Updating node pool configuration..."
debug_log "Command: az aks nodepool scale --name $NODE_POOL_NAME --node-count $DESIRED_COUNT --resource-group $RESOURCE_GROUP --cluster-name $CLUSTER_NAME"

if az aks nodepool scale \
    --name "$NODE_POOL_NAME" \
    --node-count "$DESIRED_COUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --cluster-name "$CLUSTER_NAME" \
    --no-wait 2>&1; then
    echo -e "${GREEN}✅ Node pool scaling initiated${NC}"
else
    echo -e "${RED}❌ Failed to scale node pool${NC}"
    echo "Node pool name tried: $NODE_POOL_NAME"
    echo "Cluster: $CLUSTER_NAME"
    echo "Resource Group: $RESOURCE_GROUP"
    exit 1
fi

# =============================================================================
# Scale Renny Deployment (if time-slicing enabled)
# =============================================================================

# Read time-slicing config from renny-values.yaml
VALUES_FILE="$KUBERNETES_DIR/values/renny-values.yaml"
if [ -f "$VALUES_FILE" ]; then
    REPLICAS_PER_GPU=$(grep "replicasPerGpu:" "$VALUES_FILE" | awk '{print $2}' || echo "1")
    TOTAL_REPLICAS=$((DESIRED_COUNT * REPLICAS_PER_GPU))

    echo ""
    echo "📦 Scaling $COMPONENT_NAME deployment..."
    echo "   GPU time-slicing: $REPLICAS_PER_GPU pods per GPU"
    echo "   Total pods: $TOTAL_REPLICAS (${DESIRED_COUNT} nodes × ${REPLICAS_PER_GPU} pods/node)"

    if kubectl scale deployment $COMPONENT -n uneeq-renderer --replicas=$TOTAL_REPLICAS 2>/dev/null; then
        echo -e "${GREEN}✅ Deployment scaled to $TOTAL_REPLICAS pods${NC}"
    else
        echo -e "${YELLOW}⚠️  Could not scale deployment (may not exist yet)${NC}"
    fi
else
    echo ""
    echo "📦 Scaling $COMPONENT_NAME deployment to match node count..."
    if kubectl scale deployment $COMPONENT -n uneeq-renderer --replicas=$DESIRED_COUNT 2>/dev/null; then
        echo -e "${GREEN}✅ Deployment scaled to $DESIRED_COUNT pods${NC}"
    else
        echo -e "${YELLOW}⚠️  Could not scale deployment (may not exist yet)${NC}"
    fi
fi

# =============================================================================
# Monitor Progress
# =============================================================================

echo ""
echo "⏳ Scaling in progress..."
echo "This process may take 5-15 minutes to complete."
echo ""

# Wait for scaling operation to start
sleep 10

# Monitor scaling progress
echo "📊 Monitoring scaling progress..."
echo ""

MAX_WAIT=900  # 15 minutes
WAIT_INTERVAL=20
ELAPSED=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
    # Get current provisioning state
    PROVISIONING_STATE=$(az aks nodepool show \
        --cluster-name "$CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name "$NODE_POOL_NAME" \
        --query "provisioningState" -o tsv 2>/dev/null || echo "Unknown")

    # Get current count
    CURRENT_COUNT=$(az aks nodepool show \
        --cluster-name "$CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name "$NODE_POOL_NAME" \
        --query "count" -o tsv 2>/dev/null || echo "0")

    # Get ready nodes from kubectl
    READY_NODES=$(kubectl get nodes -l uneeq.io/node-type=$NODE_LABEL --no-headers 2>/dev/null | grep -c "Ready" || echo "0")

    ELAPSED_MIN=$((ELAPSED / 60))
    ELAPSED_SEC=$((ELAPSED % 60))

    if [ "$DEBUG_MODE" = true ]; then
        echo "[${ELAPSED_MIN}m${ELAPSED_SEC}s] State: $PROVISIONING_STATE | Azure count: $CURRENT_COUNT | Ready: $READY_NODES/$DESIRED_COUNT"
    else
        echo -ne "\r   Progress: $READY_NODES/$DESIRED_COUNT nodes ready | State: $PROVISIONING_STATE | Elapsed: ${ELAPSED_MIN}m${ELAPSED_SEC}s"
    fi

    # Check if scaling is complete
    if [ "$PROVISIONING_STATE" = "Succeeded" ] && [ "$CURRENT_COUNT" -eq "$DESIRED_COUNT" ] && [ "$READY_NODES" -eq "$DESIRED_COUNT" ]; then
        if [ "$DEBUG_MODE" != true ]; then
            echo ""
        fi
        echo ""
        echo -e "${GREEN}✅ Scaling completed successfully${NC}"
        break
    fi

    # Check for failures
    if [ "$PROVISIONING_STATE" = "Failed" ]; then
        if [ "$DEBUG_MODE" != true ]; then
            echo ""
        fi
        echo ""
        echo -e "${RED}❌ Node pool scaling failed${NC}"
        echo "Check Azure Portal for details"
        exit 1
    fi

    sleep $WAIT_INTERVAL
    ELAPSED=$((ELAPSED + WAIT_INTERVAL))
done

if [ "$DEBUG_MODE" != true ]; then
    echo ""
fi

# =============================================================================
# Post-Scale Verification
# =============================================================================

echo ""
echo "🔍 Post-scale verification..."
echo ""

# Final node count check
FINAL_NODES=$(kubectl get nodes -l uneeq.io/node-type=$NODE_LABEL --no-headers 2>/dev/null | wc -l | tr -d ' ' || echo "0")
FINAL_READY=$(kubectl get nodes -l uneeq.io/node-type=$NODE_LABEL --no-headers 2>/dev/null | grep -c "Ready" || echo "0")

echo "📊 Node scaling status:"
kubectl get nodes -l uneeq.io/node-type=$NODE_LABEL

echo ""
echo "🚀 $COMPONENT_NAME pod status:"
kubectl get pods -n uneeq-renderer -l app=$COMPONENT 2>/dev/null || echo "No pods found (deployment may not exist yet)"

# =============================================================================
# Summary
# =============================================================================

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  🎉 Scaling Complete!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${CYAN}Summary:${NC}"
echo "  Component: $COMPONENT_NAME"
echo "  Previous nodes: $CURRENT_NODES"
echo "  Target nodes: $DESIRED_COUNT"
echo "  Final nodes: $FINAL_READY ready / $FINAL_NODES total"
echo ""

printf "${CYAN}Cost Impact:${NC}\n"
printf "  Previous: \$%.2f/hour (~\$%.0f/month)\n" "$CURRENT_HOURLY" "$CURRENT_MONTHLY"
printf "  New:      \$%.2f/hour (~\$%.0f/month)\n" "$NEW_HOURLY" "$NEW_MONTHLY"

if [ "$DESIRED_COUNT" -gt "$CURRENT_NODES" ]; then
    printf "  Change:   ${RED}+\$%.2f/hour (+\$%.0f/month)${NC}\n" "$(echo "$NEW_HOURLY - $CURRENT_HOURLY" | bc)" "$(echo "$NEW_MONTHLY - $CURRENT_MONTHLY" | bc)"
elif [ "$DESIRED_COUNT" -lt "$CURRENT_NODES" ]; then
    printf "  Savings:  ${GREEN}-\$%.2f/hour (-\$%.0f/month)${NC}\n" "$(echo "$CURRENT_HOURLY - $NEW_HOURLY" | bc)" "$(echo "$CURRENT_MONTHLY - $NEW_MONTHLY" | bc)"
fi

echo ""
echo -e "${CYAN}Monitoring Commands:${NC}"
echo "  # Watch nodes"
echo "  kubectl get nodes -l uneeq.io/node-type=$NODE_LABEL -w"
echo ""
echo "  # Watch pods"
echo "  kubectl get pods -n uneeq-renderer -l app=$COMPONENT -w"
echo ""
echo "  # Check logs"
echo "  kubectl logs -n uneeq-renderer -l app=$COMPONENT --tail=50 -f"
echo ""
echo "  # Azure Portal"
echo "  https://portal.azure.com/#resource/subscriptions/$ACCOUNT_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ContainerService/managedClusters/$CLUSTER_NAME"
echo ""

if [ "$FINAL_READY" -ne "$DESIRED_COUNT" ]; then
    echo -e "${YELLOW}⚠️  Warning: Not all nodes are ready yet${NC}"
    echo "   This is normal - nodes may still be provisioning"
    echo "   Monitor with: kubectl get nodes -l uneeq.io/node-type=$NODE_LABEL -w"
    echo ""
fi

echo -e "${CYAN}Next Steps:${NC}"
echo "  - Monitor cluster health: kubectl get nodes"
echo "  - Check application pods: kubectl get pods -n uneeq-renderer"
echo "  - View Azure Monitor: Azure Portal > Monitor > Insights"
echo ""
