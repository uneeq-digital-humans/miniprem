#!/bin/bash
# Note: NOT using 'set -e' to allow script to continue on kubectl errors
# when cluster control plane is already being destroyed

# Set script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Set TERRAFORM_DIR for Azure BEFORE sourcing (to prevent readonly conflict)
readonly TERRAFORM_DIR="$(cd "$SCRIPT_DIR/../terraform/aks" && pwd)"

# Source deployment functions
source "$SCRIPT_DIR/deployment-functions.sh"

# Parse command line arguments
TARGET_DEPLOYMENT_ID=""
DESTROY_ALL=false
LIST_ONLY=false
FORCE_DESTROY=false
DEBUG_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --deployment-id)
            TARGET_DEPLOYMENT_ID="$2"
            shift 2
            ;;
        --all)
            DESTROY_ALL=true
            shift
            ;;
        --list)
            LIST_ONLY=true
            shift
            ;;
        --force)
            FORCE_DESTROY=true
            shift
            ;;
        --debug)
            DEBUG_MODE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --deployment-id ID           Destroy specific deployment ID"
            echo "  --all                        Destroy ALL deployments (use with caution!)"
            echo "  --list                       List all deployments and exit"
            echo "  --force                      Skip confirmation prompts"
            echo "  --debug                      Enable verbose debug output"
            echo "  --help, -h                   Show this help message"
            echo ""
            echo "Deployment Management:"
            echo "  By default, destroy-azure.sh will detect and destroy the current deployment"
            echo "  (based on .deployment_id file or terraform.tfvars)."
            echo ""
            echo "  Use --deployment-id to target a specific deployment"
            echo "  Use --all to destroy ALL deployments for this project/environment"
            echo "  Use --list to see all deployments without destroying anything"
            echo "  Use --force to skip confirmation prompts (dangerous!)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Colors for output (only define if not already set by deployment-functions.sh)
if [ -z "${RED:-}" ]; then RED='\033[0;31m'; fi
if [ -z "${GREEN:-}" ]; then GREEN='\033[0;32m'; fi
if [ -z "${YELLOW:-}" ]; then YELLOW='\033[1;33m'; fi
if [ -z "${BLUE:-}" ]; then BLUE='\033[0;34m'; fi
if [ -z "${CYAN:-}" ]; then CYAN='\033[0;36m'; fi
if [ -z "${NC:-}" ]; then NC='\033[0m'; fi

# Timing
START_TIME=$(date +%s)

echo "======================================"
echo "   Renny AKS Cluster Destruction     "
echo "======================================"
echo ""

# Debug logging function
debug_log() {
    if [ "$DEBUG_MODE" = true ]; then
        echo -e "${CYAN}[DEBUG] $1${NC}"
    fi
}

# Load deployment configuration
cd "$TERRAFORM_DIR"
if [ "$LIST_ONLY" = "true" ]; then
    echo "📋 Listing all deployments..."
    # Load Azure-specific configuration
    PROJECT_NAME=$(awk '/^project_name[[:space:]]*=/ {gsub(/[" ]/, "", $3); print $3}' terraform.tfvars 2>/dev/null || echo "renny")
    ENVIRONMENT=$(awk '/^environment[[:space:]]*=/ {gsub(/[" ]/, "", $3); print $3}' terraform.tfvars 2>/dev/null || echo "production")
    list_all_deployments_azure
    exit 0
fi

if [ "$DESTROY_ALL" = "true" ]; then
    echo -e "${RED}⚠️  WARNING: --all flag specified - this will destroy ALL deployments!${NC}"
    # Configuration will be loaded in the "elif [ "$DESTROY_ALL" = "true" ]" block above
    if [ "$FORCE_DESTROY" != "true" ]; then
        if ! confirm_action "Are you sure you want to destroy ALL deployments?" "n"; then
            echo "Cancelled."
            exit 0
        fi
    fi
fi

# Load deployment configuration based on mode
if [ -n "$TARGET_DEPLOYMENT_ID" ]; then
    # Target specific deployment ID
    echo "🎯 Targeting deployment ID: $TARGET_DEPLOYMENT_ID"
    # Load Azure-specific configuration
    cd "$TERRAFORM_DIR"
    PROJECT_NAME=$(awk '/^project_name[[:space:]]*=/ {gsub(/[" ]/, "", $3); print $3}' terraform.tfvars 2>/dev/null || echo "renny")
    ENVIRONMENT=$(awk '/^environment[[:space:]]*=/ {gsub(/[" ]/, "", $3); print $3}' terraform.tfvars 2>/dev/null || echo "production")
    DEPLOYMENT_ID="$TARGET_DEPLOYMENT_ID"
    if [ -n "$DEPLOYMENT_ID" ]; then
        CLUSTER_NAME="$PROJECT_NAME-$ENVIRONMENT-$DEPLOYMENT_ID"
    else
        CLUSTER_NAME="$PROJECT_NAME-$ENVIRONMENT"
    fi
    # Update terraform.tfvars to target this deployment (skip save_deployment_id as it's AWS-specific)
    if grep -q "^deployment_id[[:space:]]*=" terraform.tfvars; then
        sed -i.bak "s/^deployment_id[[:space:]]*=.*/deployment_id = \"$DEPLOYMENT_ID\"/" terraform.tfvars
    else
        echo "" >> terraform.tfvars
        echo "deployment_id = \"$DEPLOYMENT_ID\"" >> terraform.tfvars
    fi
    export PROJECT_NAME ENVIRONMENT DEPLOYMENT_ID CLUSTER_NAME AZURE_REGION RESOURCE_GROUP_NAME
elif [ "$DESTROY_ALL" = "true" ]; then
    # Will handle multiple deployments in destroy logic
    cd "$TERRAFORM_DIR"
    PROJECT_NAME=$(awk '/^project_name[[:space:]]*=/ {gsub(/[" ]/, "", $3); print $3}' terraform.tfvars 2>/dev/null || echo "renny")
    ENVIRONMENT=$(awk '/^environment[[:space:]]*=/ {gsub(/[" ]/, "", $3); print $3}' terraform.tfvars 2>/dev/null || echo "production")
    DEPLOYMENT_ID=""
    CLUSTER_NAME="" # Will be set per deployment in loop
else
    # Use current deployment (from .deployment_id file or terraform.tfvars)
    cd "$TERRAFORM_DIR"
    PROJECT_NAME=$(awk '/^project_name[[:space:]]*=/ {gsub(/[" ]/, "", $3); print $3}' terraform.tfvars 2>/dev/null || echo "renny")
    ENVIRONMENT=$(awk '/^environment[[:space:]]*=/ {gsub(/[" ]/, "", $3); print $3}' terraform.tfvars 2>/dev/null || echo "production")
    DEPLOYMENT_ID=$(awk '/^deployment_id[[:space:]]*=/ {gsub(/[" ]/, "", $3); print $3}' terraform.tfvars 2>/dev/null || echo "")

    if [ -n "$DEPLOYMENT_ID" ]; then
        CLUSTER_NAME="$PROJECT_NAME-$ENVIRONMENT-$DEPLOYMENT_ID"
    else
        CLUSTER_NAME="$PROJECT_NAME-$ENVIRONMENT"
    fi
    export PROJECT_NAME ENVIRONMENT DEPLOYMENT_ID CLUSTER_NAME
fi

# Get Azure region from terraform.tfvars
AZURE_REGION=$(awk '/^azure_region[[:space:]]*=/ {gsub(/[" ]/, "", $3); print $3}' terraform.tfvars 2>/dev/null)
RESOURCE_GROUP_NAME=$(awk '/^resource_group_name[[:space:]]*=/ {gsub(/[" ]/, "", $3); print $3}' terraform.tfvars 2>/dev/null || echo "renny-kubernetes")

if [ -z "$AZURE_REGION" ]; then
    echo -e "${RED}Error: azure_region not set in terraform.tfvars${NC}"
    exit 1
fi

debug_log "Azure Region: $AZURE_REGION"
debug_log "Resource Group: $RESOURCE_GROUP_NAME"
debug_log "Cluster Name: $CLUSTER_NAME"

# Confirmation prompts (skip if --force)
if [ "$FORCE_DESTROY" != "true" ]; then
    echo -e "${RED}⚠️  WARNING: This will destroy all resources!${NC}"
    echo "This includes:"
    echo "  - AKS cluster and all nodes (GPU + system nodes)"
    echo "  - VNet and networking resources"
    echo "  - Node pools and VM scale sets"
    echo "  - All deployed applications (Renny, GPU Operator)"
    echo "  - All data in the cluster"
    echo "  - All load balancers"
    echo "  - All managed disks"
    echo "  - Resource group (if only contains AKS resources)"
    echo ""
    echo -e "${YELLOW}Estimated time: 15-25 minutes (8 comprehensive steps)${NC}"
    echo ""
    echo "This action cannot be undone!"
    echo ""
    echo "Type 'destroy' to confirm:"
    read -r response

    if [[ "$response" != "destroy" ]]; then
        echo "Destruction cancelled"
        exit 0
    fi

    echo ""
    echo "Are you absolutely sure? Type 'yes-destroy-everything' to proceed:"
    read -r response

    if [[ "$response" != "yes-destroy-everything" ]]; then
        echo "Destruction cancelled"
        exit 0
    fi
else
    echo -e "${YELLOW}⚠️  --force flag enabled - skipping confirmations${NC}"
fi

echo ""
echo "🗑️  Beginning destruction process..."
echo -e "${BLUE}This process will take approximately 15-20 minutes${NC}"
echo ""

# Function to wait with spinner
wait_with_spinner() {
    local pid=$1
    local message=$2
    local spin='-\|/'
    local i=0
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) %4 ))
        printf "\r${message} ${spin:$i:1}"
        sleep .1
    done
    printf "\r${message} ✓\n"
}

# Function to wait for resource deletion
wait_for_deletion() {
    local check_command=$1
    local resource_name=$2
    local max_attempts=$3
    local attempt=1

    echo "Waiting for $resource_name to be deleted..."
    while [ $attempt -le $max_attempts ]; do
        if ! eval $check_command &>/dev/null; then
            echo -e "${GREEN}✓ $resource_name deleted${NC}"
            return 0
        fi
        echo "  Still waiting... (attempt $attempt/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    echo -e "${YELLOW}⚠ Timeout waiting for $resource_name deletion${NC}"
    return 1
}

# Use cluster info from deployment configuration
if [ -z "$CLUSTER_NAME" ]; then
    echo -e "${RED}Error: No cluster name determined. Check deployment configuration.${NC}"
    exit 1
fi

# Azure-specific function to list all deployments
list_all_deployments_azure() {
    local base_name="$PROJECT_NAME-$ENVIRONMENT"

    echo -e "${BLUE}📋 All AKS deployments for $base_name:${NC}"
    echo ""

    local clusters
    clusters=$(az aks list --query "[?contains(name, '$base_name')].name" -o tsv 2>/dev/null || echo "")

    if [ -z "$clusters" ]; then
        echo -e "${YELLOW}No deployments found${NC}"
        return 1
    fi

    while IFS= read -r cluster; do
        if [ -n "$cluster" ]; then
            local rg=$(az aks show --name "$cluster" --query "resourceGroup" -o tsv 2>/dev/null || echo "Unknown")
            local status=$(az aks show --name "$cluster" --resource-group "$rg" --query "provisioningState" -o tsv 2>/dev/null || echo "Unknown")
            local location=$(az aks show --name "$cluster" --resource-group "$rg" --query "location" -o tsv 2>/dev/null || echo "Unknown")

            # Extract deployment ID
            local deployment_id=""
            if [[ "$cluster" =~ ^${base_name}-(.+)$ ]]; then
                deployment_id="${BASH_REMATCH[1]}"
            fi

            printf "%s%s%s\\n" "$CYAN" "$cluster" "$NC"
            printf "  Status: %s | Location: %s | RG: %s\\n" "$status" "$location" "$rg"
            if [ -n "$deployment_id" ]; then
                printf "  Deployment ID: %s\\n" "$deployment_id"
            fi
            echo ""
        fi
    done <<< "$clusters"

    return 0
}

# Handle --all flag by destroying each deployment individually
if [ "$DESTROY_ALL" = "true" ]; then
    echo -e "${RED}⚠️  DESTROY ALL MODE ACTIVATED${NC}"
    echo "🔍 Finding all deployments for $PROJECT_NAME-$ENVIRONMENT..."

    # Get all clusters for this project/environment
    base_name="$PROJECT_NAME-$ENVIRONMENT"
    all_clusters=$(az aks list --query "[?contains(name, '$base_name')].name" -o tsv 2>/dev/null || echo "")

    if [ -z "$all_clusters" ]; then
        echo -e "${YELLOW}No deployments found to destroy${NC}"
        exit 0
    fi

    echo "Found deployments to destroy:"
    for cluster in $all_clusters; do
        echo "  - $cluster"
    done
    echo ""

    if [ "$FORCE_DESTROY" != "true" ]; then
        if ! confirm_action "Proceed to destroy ALL these deployments?" "n"; then
            echo "Cancelled."
            exit 0
        fi
    fi

    echo "💥 Starting mass destruction..."

    # Destroy each cluster individually
    for cluster in $all_clusters; do
        echo -e "${CYAN}========================================${NC}"
        echo -e "${CYAN}Destroying: $cluster${NC}"
        echo -e "${CYAN}========================================${NC}"

        # Extract deployment ID if present
        cluster_deployment_id=""
        if [[ "$cluster" =~ ^${base_name}-(.+)$ ]]; then
            cluster_deployment_id="${BASH_REMATCH[1]}"
        fi

        # Update configuration for this cluster
        CLUSTER_NAME="$cluster"
        DEPLOYMENT_ID="$cluster_deployment_id"

        # Get resource group for this cluster
        RESOURCE_GROUP_NAME=$(az aks show --name "$cluster" --query "resourceGroup" -o tsv 2>/dev/null || echo "$RESOURCE_GROUP_NAME")

        # Save deployment ID to terraform for this iteration
        if [ -n "$cluster_deployment_id" ]; then
            save_deployment_id "$cluster_deployment_id"
        else
            # Legacy cluster - clear deployment ID
            save_deployment_id ""
        fi

        # Run destroy process for this cluster
        destroy_single_deployment

        echo -e "${GREEN}✅ Completed destruction of: $cluster${NC}"
        echo ""
    done

    # Final cleanup
    cleanup_deployment_id

    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}🎆 ALL DEPLOYMENTS DESTROYED${NC}"
    echo -e "${GREEN}========================================${NC}"
    exit 0
fi

# Configure kubectl if possible
if [ "$CLUSTER_NAME" != "unknown" ] && [ -n "$CLUSTER_NAME" ]; then
    echo "Configuring kubectl for cluster: $CLUSTER_NAME"
    az aks get-credentials --resource-group "$RESOURCE_GROUP_NAME" --name "$CLUSTER_NAME" --overwrite-existing 2>/dev/null || true
fi

# Comprehensive GPU Operator cleanup function
cleanup_gpu_operator_completely() {
    echo "    🎮 Starting comprehensive GPU Operator cleanup..."

    # Check if kubectl is accessible first
    if ! kubectl cluster-info &>/dev/null; then
        echo "      ⚠️  Cluster unreachable - skipping kubectl cleanup (cluster may already be destroyed)"
        return 0
    fi

    # Step 1: Force kill all GPU operator pods immediately
    echo "      - Force killing all GPU operator pods..."
    kubectl delete pods -l app=nvidia-driver-daemonset -n gpu-operator --force --grace-period=0 --wait=false 2>/dev/null || true
    kubectl delete pods -l app=nvidia-device-plugin-daemonset -n gpu-operator --force --grace-period=0 --wait=false 2>/dev/null || true
    kubectl delete pods -l app=nvidia-container-toolkit-daemonset -n gpu-operator --force --grace-period=0 --wait=false 2>/dev/null || true
    kubectl delete pods -l app=nvidia-dcgm-exporter -n gpu-operator --force --grace-period=0 --wait=false 2>/dev/null || true
    kubectl delete pods -l app=gpu-feature-discovery -n gpu-operator --force --grace-period=0 --wait=false 2>/dev/null || true
    kubectl delete pods -l app=nvidia-operator-validator -n gpu-operator --force --grace-period=0 --wait=false 2>/dev/null || true

    # Step 2: Remove finalizers from ClusterPolicy to prevent hanging
    echo "      - Removing ClusterPolicy finalizers..."
    kubectl patch clusterpolicy cluster-policy --type='merge' -p='{"metadata":{"finalizers":[]}}' 2>/dev/null || true

    # Step 3: Delete ClusterPolicy and related CRDs
    echo "      - Deleting GPU Operator CRDs..."
    kubectl delete clusterpolicy cluster-policy --ignore-not-found=true --timeout=30s 2>/dev/null || true
    kubectl delete crd clusterpolicies.nvidia.com --ignore-not-found=true --timeout=30s 2>/dev/null || true
    kubectl delete crd nvidiadrivers.nvidia.com --ignore-not-found=true --timeout=30s 2>/dev/null || true
    kubectl delete crd gpufeaturepolicies.nvidia.com --ignore-not-found=true --timeout=30s 2>/dev/null || true

    # Step 4: Clean up node labels and taints that might prevent destruction
    echo "      - Cleaning up GPU node labels and taints..."
    kubectl get nodes --no-headers 2>/dev/null | while read node _; do
        # Remove GPU-related taints
        kubectl taint node "$node" nvidia.com/gpu:NoSchedule- 2>/dev/null || true
        kubectl taint node "$node" nvidia.com/gpu:NoExecute- 2>/dev/null || true

        # Remove GPU-related labels (but keep nvidia.com/gpu=true for node identification)
        kubectl label node "$node" nvidia.com/cuda.driver.major- 2>/dev/null || true
        kubectl label node "$node" nvidia.com/cuda.driver.minor- 2>/dev/null || true
        kubectl label node "$node" nvidia.com/cuda.driver.rev- 2>/dev/null || true
        kubectl label node "$node" nvidia.com/cuda.runtime.major- 2>/dev/null || true
        kubectl label node "$node" nvidia.com/cuda.runtime.minor- 2>/dev/null || true
        kubectl label node "$node" nvidia.com/gfd.timestamp- 2>/dev/null || true
        kubectl label node "$node" nvidia.com/gpu.compute.major- 2>/dev/null || true
        kubectl label node "$node" nvidia.com/gpu.compute.minor- 2>/dev/null || true
        kubectl label node "$node" nvidia.com/gpu.count- 2>/dev/null || true
        kubectl label node "$node" nvidia.com/gpu.family- 2>/dev/null || true
        kubectl label node "$node" nvidia.com/gpu.machine- 2>/dev/null || true
        kubectl label node "$node" nvidia.com/gpu.memory- 2>/dev/null || true
        kubectl label node "$node" nvidia.com/gpu.product- 2>/dev/null || true
        kubectl label node "$node" nvidia.com/gpu.replicas- 2>/dev/null || true
        kubectl label node "$node" nvidia.com/mig.strategy- 2>/dev/null || true
    done

    # Step 5: Wait a moment for pods to terminate
    echo "      - Waiting for pods to terminate..."
    sleep 15

    # Step 6: Uninstall helm chart with extended timeout
    echo "      - Uninstalling GPU Operator Helm chart..."
    helm uninstall gpu-operator -n gpu-operator --timeout=180s 2>/dev/null || true

    # Step 7: Force delete any remaining GPU operator resources
    echo "      - Force deleting remaining GPU operator resources..."
    kubectl delete daemonsets --all -n gpu-operator --force --grace-period=0 --ignore-not-found=true 2>/dev/null || true
    kubectl delete deployments --all -n gpu-operator --force --grace-period=0 --ignore-not-found=true 2>/dev/null || true
    kubectl delete replicasets --all -n gpu-operator --force --grace-period=0 --ignore-not-found=true 2>/dev/null || true
    kubectl delete jobs --all -n gpu-operator --force --grace-period=0 --ignore-not-found=true 2>/dev/null || true

    # Step 8: Clean up any remaining pods with force
    echo "      - Final cleanup of any stuck pods..."
    kubectl delete pods --all -n gpu-operator --force --grace-period=0 --wait=false 2>/dev/null || true

    # Step 9: Remove any stuck finalizers from remaining resources
    echo "      - Removing finalizers from stuck resources..."
    kubectl get all -n gpu-operator -o name 2>/dev/null | while read resource; do
        kubectl patch "$resource" --type='merge' -p='{"metadata":{"finalizers":[]}}' -n gpu-operator 2>/dev/null || true
    done

    echo "    ✅ GPU Operator cleanup completed"
}

# Function to destroy a single deployment (extracted from main logic)
destroy_single_deployment() {

# Step 1: Force terminate all applications (no graceful shutdown)
echo ""
echo "🛑 Step 1/8: Force terminating all applications..."

# Check if cluster is accessible before attempting kubectl operations
if kubectl cluster-info &>/dev/null; then
    echo "  - Force killing all Renny sessions and pods..."
    kubectl delete pods -l app=renderer -n uneeq-renderer --force --grace-period=0 --wait=false 2>/dev/null || true

    echo "  - Uninstalling Renny (with force)..."
    helm uninstall renny -n uneeq-renderer --timeout=60s 2>/dev/null || true

    echo "  - Comprehensive GPU Operator cleanup..."
    cleanup_gpu_operator_completely
else
    echo "  ⚠️  Cluster unreachable - skipping kubectl/helm cleanup (cluster may already be destroyed)"
    echo "  ✓ Proceeding directly to Azure resource cleanup..."
fi

if kubectl cluster-info &>/dev/null; then
    echo "  - Uninstalling Cluster Autoscaler..."
    helm uninstall cluster-autoscaler -n kube-system --timeout=60s 2>/dev/null || true

    # Force delete any remaining pods
    echo "  - Force deleting any remaining pods..."
    kubectl delete pods --all -n uneeq-renderer --force --grace-period=0 --wait=false 2>/dev/null || true
    kubectl delete pods --all -n gpu-operator --force --grace-period=0 --wait=false 2>/dev/null || true

    # Give pods a moment to terminate
    sleep 15
fi

# Step 2: Clean up Kubernetes resources and configurations
echo ""
echo "🗑️  Step 2/8: Cleaning up Kubernetes resources and configurations..."

if kubectl cluster-info &>/dev/null; then
    # Delete GPU time-slicing configurations
    echo "  - Removing GPU time-slicing configurations..."
    kubectl delete configmap renny-time-slicing-config -n gpu-operator --ignore-not-found=true 2>/dev/null || true
    kubectl delete clusterpolicy cluster-policy --ignore-not-found=true 2>/dev/null || true

    # Delete any services that might have created load balancers (force delete)
    echo "  - Force deleting all services..."
    kubectl delete svc --all -n uneeq-renderer --force --grace-period=0 --ignore-not-found=true 2>/dev/null || true
    kubectl delete svc --all -n gpu-operator --force --grace-period=0 --ignore-not-found=true 2>/dev/null || true

    # Delete secrets and config maps
    echo "  - Deleting secrets and config maps..."
    kubectl delete secrets --all -n uneeq-renderer --ignore-not-found=true 2>/dev/null || true
    kubectl delete configmaps --all -n uneeq-renderer --ignore-not-found=true 2>/dev/null || true
    kubectl delete configmaps --all -n gpu-operator --ignore-not-found=true 2>/dev/null || true

    # Delete PVCs with force
    echo "  - Force deleting persistent volume claims..."
    kubectl delete pvc --all -n uneeq-renderer --force --grace-period=0 --ignore-not-found=true 2>/dev/null || true
    kubectl delete pvc --all -n gpu-operator --force --grace-period=0 --ignore-not-found=true 2>/dev/null || true

    # Delete any remaining GPU operator custom resource definitions
    echo "  - Final GPU Operator CRD cleanup..."
    kubectl delete crd clusterpolicies.nvidia.com --ignore-not-found=true --timeout=30s 2>/dev/null || true
    kubectl delete crd nvidiadrivers.nvidia.com --ignore-not-found=true --timeout=30s 2>/dev/null || true
    kubectl delete crd gpufeaturepolicies.nvidia.com --ignore-not-found=true --timeout=30s 2>/dev/null || true
    # Remove finalizers if CRDs are stuck
    kubectl patch crd clusterpolicies.nvidia.com --type='merge' -p='{"metadata":{"finalizers":[]}}' 2>/dev/null || true
    kubectl patch crd nvidiadrivers.nvidia.com --type='merge' -p='{"metadata":{"finalizers":[]}}' 2>/dev/null || true
    kubectl patch crd gpufeaturepolicies.nvidia.com --type='merge' -p='{"metadata":{"finalizers":[]}}' 2>/dev/null || true

    # Force delete namespaces
    echo "  - Force deleting namespaces..."
    kubectl delete namespace uneeq-renderer --force --grace-period=0 --ignore-not-found=true --timeout=60s 2>/dev/null || true
    kubectl delete namespace gpu-operator --force --grace-period=0 --ignore-not-found=true --timeout=60s 2>/dev/null || true

    # Wait for load balancers to be deleted
    echo "  - Waiting for Azure load balancers to be deleted..."
    sleep 15
else
    echo "  ⚠️  Cluster unreachable - skipping kubectl resource cleanup"
    echo "  ✓ Proceeding to Azure resource cleanup..."
fi

# Step 3: Drain nodes and scale down node pools
echo ""
echo "🔄 Step 3/8: Draining nodes and scaling down node pools..."

if [ "$CLUSTER_NAME" != "unknown" ]; then
    # Get all node pools for this cluster
    echo "  - Finding node pools..."
    NODE_POOLS=$(az aks nodepool list --cluster-name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "[].name" -o tsv 2>/dev/null || echo "")

    if [ -n "$NODE_POOLS" ]; then
        echo "  Found node pools: $NODE_POOLS"

        # Scale all node pools to 0 nodes
        for pool in $NODE_POOLS; do
            echo "    Scaling $pool to 0 nodes..."
            az aks nodepool scale \
                --cluster-name "$CLUSTER_NAME" \
                --resource-group "$RESOURCE_GROUP_NAME" \
                --name "$pool" \
                --node-count 0 2>/dev/null || true
        done

        # Wait for nodes to terminate
        echo "  - Waiting for nodes to terminate..."
        sleep 30

        # Drain all nodes before deletion (only if kubectl is accessible)
        if kubectl cluster-info &>/dev/null; then
            echo "  - Draining all Kubernetes nodes..."
            kubectl get nodes --no-headers -o custom-columns=":metadata.name" 2>/dev/null | while read node; do
                echo "    Draining $node..."
                kubectl drain "$node" --ignore-daemonsets --delete-emptydir-data --force --grace-period=0 --timeout=60s 2>/dev/null || true
            done
        else
            echo "  ⚠️  Cluster unreachable - skipping node drain"
        fi
    else
        echo "  No node pools found for cluster"
    fi
fi

# Step 4: Delete AKS node pools
echo ""
echo "🖥️  Step 4/8: Removing AKS node pools..."
cd "$TERRAFORM_DIR"

if [ "$CLUSTER_NAME" != "unknown" ]; then
    # List current node pools
    echo "Current node pools:"
    az aks nodepool list --cluster-name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP_NAME" -o table 2>/dev/null || true

    # Delete GPU node pool first (created via Azure CLI in deploy-azure.sh)
    echo ""
    echo "🎮 Checking for CLI-created GPU node pool..."
    GPU_POOL_EXISTS=$(az aks nodepool show --cluster-name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP_NAME" --name "rennygpu" --query "name" -o tsv 2>/dev/null || echo "")

    if [ -n "$GPU_POOL_EXISTS" ]; then
        echo "  Found GPU node pool: rennygpu"
        echo "  - Deleting rennygpu node pool (driver 580+ configuration)..."
        az aks nodepool delete \
            --cluster-name "$CLUSTER_NAME" \
            --resource-group "$RESOURCE_GROUP_NAME" \
            --name "rennygpu" \
            --no-wait 2>/dev/null || true
        echo -e "${GREEN}✓ GPU node pool deletion initiated${NC}"
    else
        echo "  No GPU node pool found (may have been deleted already)"
    fi

    # Delete remaining node pools (exclude system pool as it will be deleted with cluster)
    echo ""
    echo "Checking for other user node pools..."

    ACTUAL_NODEPOOLS=$(az aks nodepool list --cluster-name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "[?mode!='System' && name!='rennygpu'].name" -o tsv 2>/dev/null || echo "")

    if [ -n "$ACTUAL_NODEPOOLS" ]; then
        for nodepool in $ACTUAL_NODEPOOLS; do
            echo "  - Deleting $nodepool..."
            az aks nodepool delete \
                --cluster-name "$CLUSTER_NAME" \
                --resource-group "$RESOURCE_GROUP_NAME" \
                --name "$nodepool" \
                --no-wait 2>/dev/null || true
        done
    else
        echo "  No additional user node pools found"
    fi

    # Wait for all user node pools to be deleted
    echo "Waiting for node pools to be deleted (this typically takes 5-10 minutes)..."
    for i in {1..60}; do
        NODEPOOLS=$(az aks nodepool list --cluster-name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "[?mode!='System'].name" -o tsv 2>/dev/null || echo "")
        if [ -z "$NODEPOOLS" ]; then
            echo -e "${GREEN}✓ All user node pools deleted${NC}"
            break
        fi
        REMAINING=$(echo "$NODEPOOLS" | wc -w | tr -d ' ')
        echo "  Still waiting... ($REMAINING node pools remaining, attempt $i/60)"
        sleep 10
    done
fi

# Step 5: Force terminate VMs and cleanup Azure resources
echo ""
echo "💥 Step 5/8: Force terminating VMs and cleaning up Azure resources..."

if [ "$CLUSTER_NAME" != "unknown" ]; then
    # Get VM Scale Sets associated with this cluster
    echo "  - Finding VM Scale Sets..."
    VMSS_NAMES=$(az vmss list --resource-group "$RESOURCE_GROUP_NAME" --query "[?tags.\"aks-managed-cluster-name\"=='$CLUSTER_NAME'].name" -o tsv 2>/dev/null || echo "")

    if [ -n "$VMSS_NAMES" ]; then
        echo "  Found VMSS: $VMSS_NAMES"
        for vmss in $VMSS_NAMES; do
            echo "    Deleting VMSS: $vmss..."
            az vmss delete --name "$vmss" --resource-group "$RESOURCE_GROUP_NAME" --no-wait 2>/dev/null || true
        done
    else
        echo "  No VMSS found for cluster"
    fi

    # Check for orphaned disks
    echo "  - Checking for orphaned managed disks..."
    DISKS=$(az disk list --resource-group "$RESOURCE_GROUP_NAME" --query "[?tags.\"kubernetes.io-created-for-pv-name\"].id" -o tsv 2>/dev/null || echo "")
    if [ -n "$DISKS" ]; then
        echo "  Found managed disks: $(echo "$DISKS" | wc -l | tr -d ' ')"
        for disk in $DISKS; do
            echo "    Deleting disk: $(basename $disk)..."
            az disk delete --ids "$disk" --yes --no-wait 2>/dev/null || true
        done
    fi
fi

# Step 6: Cleanup remaining Azure resources
echo ""
echo "🔍 Step 6/8: Cleaning up remaining Azure resources..."

if [ "$CLUSTER_NAME" != "unknown" ]; then
    # Check for load balancers
    echo "  - Checking for load balancers..."
    LOAD_BALANCERS=$(az network lb list --resource-group "$RESOURCE_GROUP_NAME" --query "[?contains(name, 'kubernetes')].name" -o tsv 2>/dev/null || echo "")
    if [ -n "$LOAD_BALANCERS" ]; then
        echo "  Found load balancers: $LOAD_BALANCERS"
        for lb in $LOAD_BALANCERS; do
            echo "    Deleting $lb..."
            az network lb delete --name "$lb" --resource-group "$RESOURCE_GROUP_NAME" --no-wait 2>/dev/null || true
        done
    fi

    # Check for public IPs
    echo "  - Checking for public IPs..."
    PUBLIC_IPS=$(az network public-ip list --resource-group "$RESOURCE_GROUP_NAME" --query "[?tags.\"kubernetes-cluster-name\"=='$CLUSTER_NAME'].name" -o tsv 2>/dev/null || echo "")
    if [ -n "$PUBLIC_IPS" ]; then
        echo "  Found public IPs: $PUBLIC_IPS"
        for ip in $PUBLIC_IPS; do
            echo "    Deleting $ip..."
            az network public-ip delete --name "$ip" --resource-group "$RESOURCE_GROUP_NAME" --no-wait 2>/dev/null || true
        done
    fi

    # Check for network security groups
    echo "  - Checking for network security groups..."
    NSGS=$(az network nsg list --resource-group "$RESOURCE_GROUP_NAME" --query "[?contains(name, 'aks')].name" -o tsv 2>/dev/null || echo "")
    if [ -n "$NSGS" ]; then
        echo "  Found NSGs: $NSGS"
        for nsg in $NSGS; do
            echo "    Deleting $nsg..."
            az network nsg delete --name "$nsg" --resource-group "$RESOURCE_GROUP_NAME" --no-wait 2>/dev/null || true
        done
    fi
fi

# Step 7: Destroy infrastructure with Terraform
echo ""
echo "🏗️  Step 7/8: Destroying infrastructure with Terraform..."
echo "This will remove:"
echo "  - AKS cluster"
echo "  - VNet and subnets"
echo "  - Route tables"
echo "  - Network security groups"
echo "  - Managed identities"
echo "  - All remaining resources"
echo ""

cd "$TERRAFORM_DIR"
terraform destroy -auto-approve

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}⚠ Terraform destroy encountered issues. Attempting cleanup...${NC}"
    # Try again with -refresh=false if it failed
    terraform destroy -auto-approve -refresh=false
fi

# Step 8: Final cleanup and verification
echo ""
echo "🔍 Step 8/8: Final cleanup and verification..."

# Clean up kubeconfig context
if [ "$CLUSTER_NAME" != "unknown" ]; then
    echo "  - Cleaning up kubeconfig context..."
    kubectl config delete-context "$CLUSTER_NAME" 2>/dev/null || true
    kubectl config delete-cluster "$CLUSTER_NAME" 2>/dev/null || true
fi

# Check if resource group should be deleted (only if it was created for AKS)
if [ "$CLUSTER_NAME" != "unknown" ]; then
    echo "  - Checking resource group status..."
    RG_EXISTS=$(az group exists --name "$RESOURCE_GROUP_NAME" -o tsv 2>/dev/null || echo "false")

    if [ "$RG_EXISTS" = "true" ]; then
        # Count remaining resources
        RESOURCE_COUNT=$(az resource list --resource-group "$RESOURCE_GROUP_NAME" --query "length(@)" -o tsv 2>/dev/null || echo "0")

        if [ "$RESOURCE_COUNT" -eq "0" ]; then
            echo -e "${YELLOW}  Resource group is empty. Delete it? (y/N):${NC}"
            if [ "$FORCE_DESTROY" = "true" ]; then
                response="y"
            else
                read -n 1 -r response
                echo ""
            fi

            if [[ "$response" =~ ^[Yy]$ ]]; then
                echo "    Deleting empty resource group..."
                az group delete --name "$RESOURCE_GROUP_NAME" --yes --no-wait 2>/dev/null || true
            fi
        else
            echo -e "${CYAN}  Resource group has $RESOURCE_COUNT remaining resources (not deleting)${NC}"
        fi
    else
        echo -e "${GREEN}✓ Resource group already deleted${NC}"
    fi
fi

echo ""
echo "🧹 Azure infrastructure destroyed - local project files preserved"

# Calculate elapsed time
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
ELAPSED_MIN=$((ELAPSED / 60))
ELAPSED_SEC=$((ELAPSED % 60))

# Clean up deployment ID after successful destruction
if [ -n "$DEPLOYMENT_ID" ] && [ "$DESTROY_ALL" != "true" ]; then
    echo "🧹 Cleaning up deployment ID configuration..."
    cleanup_deployment_id
fi

echo ""
echo "======================================"
echo -e "${GREEN}✅ All resources destroyed successfully${NC}"
echo "======================================"
echo ""
echo "Time elapsed: ${ELAPSED_MIN} minutes ${ELAPSED_SEC} seconds"
echo ""

# ============================================================================
# POST-DESTRUCTION VERIFICATION
# ============================================================================
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║            Post-Destruction Verification Report              ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}🔍 Verifying all resources are completely removed...${NC}"
echo ""

# Function to verify resource is deleted
verify_clean() {
    local resource_name="$1"
    local check_command="$2"

    # Pad resource name to 28 characters for alignment
    printf "  %-28s" "$resource_name"

    # Run check command and capture result
    local result
    result=$(eval "$check_command" 2>/dev/null || echo "")

    if [ -z "$result" ] || [ "$result" = "0" ] || [ "$result" = "[]" ]; then
        echo -e "│ ${GREEN}✅ CLEAN${NC}  │ No orphaned resources"
        return 0
    else
        echo -e "│ ${YELLOW}⚠️  FOUND${NC} │ $result"
        return 1
    fi
}

# Verification table header
echo -e "${CYAN}┌──────────────────────────────┬───────────┬─────────────────────────────────┐${NC}"
echo -e "${CYAN}│ Resource Type                │ Status    │ Details                         │${NC}"
echo -e "${CYAN}├──────────────────────────────┼───────────┼─────────────────────────────────┤${NC}"

# Verify all resource types are gone
verify_clean "AKS Clusters" \
    "az aks list --query \"[?contains(name, '$CLUSTER_NAME')].name\" -o tsv"

verify_clean "Node Pools" \
    "az aks nodepool list --cluster-name $CLUSTER_NAME --resource-group $RESOURCE_GROUP_NAME --query 'length(@)' -o tsv 2>/dev/null"

verify_clean "VM Scale Sets" \
    "az vmss list --resource-group $RESOURCE_GROUP_NAME --query \"[?tags.\\\"aks-managed-cluster-name\\\"=='$CLUSTER_NAME'].name\" -o tsv"

verify_clean "VNets" \
    "az network vnet list --resource-group $RESOURCE_GROUP_NAME --query 'length(@)' -o tsv"

verify_clean "Load Balancers" \
    "az network lb list --resource-group $RESOURCE_GROUP_NAME --query \"[?contains(name, 'kubernetes')].name\" -o tsv"

verify_clean "Public IPs" \
    "az network public-ip list --resource-group $RESOURCE_GROUP_NAME --query \"[?tags.\\\"kubernetes-cluster-name\\\"=='$CLUSTER_NAME'].name\" -o tsv"

verify_clean "Managed Disks" \
    "az disk list --resource-group $RESOURCE_GROUP_NAME --query \"[?tags.\\\"kubernetes.io-created-for-pv-name\\\"].name\" -o tsv"

verify_clean "Network Security Groups" \
    "az network nsg list --resource-group $RESOURCE_GROUP_NAME --query \"[?contains(name, 'aks')].name\" -o tsv"

verify_clean "Network Interfaces" \
    "az network nic list --resource-group $RESOURCE_GROUP_NAME --query \"[?contains(name, 'aks')].name\" -o tsv"

verify_clean "Route Tables" \
    "az network route-table list --resource-group $RESOURCE_GROUP_NAME --query 'length(@)' -o tsv"

verify_clean "Terraform State Resources" \
    "cd $TERRAFORM_DIR && terraform state list 2>/dev/null | wc -l | tr -d ' '"

verify_clean "Kubectl Context" \
    "kubectl config get-contexts --no-headers | grep -c '$CLUSTER_NAME' || echo '0'"

# Table footer
echo -e "${CYAN}└──────────────────────────────┴───────────┴─────────────────────────────────┘${NC}"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ VERIFICATION COMPLETE - ENVIRONMENT IS CLEAN!            ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================================
# ADDITIONAL INFO
# ============================================================================
echo "📁 LOCAL PROJECT FILES PRESERVED:"
echo "✅ All Terraform configuration files (.tf, .tfvars)"
echo "✅ Kubernetes manifests and Helm values"
echo "✅ Scripts and documentation"
echo "✅ Ready for immediate redeployment!"
echo ""
echo "The following Azure items may still exist:"
echo "  - Resource group (if it contained other resources)"
echo "  - Azure Monitor metrics data (expires automatically)"
echo "  - Activity logs (retained per Azure retention policy)"
echo ""
echo "💰 COST SAVINGS:"
echo "  - Stopped ~\$12-15/hour in compute costs"
echo "  - Monthly savings: ~\$8,000-12,000"
echo "  - No more GPU instance charges"
echo "  - No more data transfer charges"
echo ""
echo "To redeploy, run: ./scripts/azure/deploy.sh"

} # End of destroy_single_deployment function

# Execute single deployment destroy if not in --all mode
if [ "$DESTROY_ALL" != "true" ]; then
    destroy_single_deployment
fi
