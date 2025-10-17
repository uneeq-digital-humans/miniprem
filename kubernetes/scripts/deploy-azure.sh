#!/usr/bin/env bash

# =============================================================================
# Azure AKS Deployment Script for Renny Digital Humans
# =============================================================================
# This script deploys a production-ready Azure AKS cluster with GPU support
# for Renny digital human rendering using NVIDIA T4 GPUs.
#
# Features:
#   - Terraform-based infrastructure deployment
#   - NVIDIA GPU Operator installation (standard drivers for T4 GPUs)
#   - GPU time-slicing configuration (multiple pods per GPU)
#   - Application deployment (Renny digital human renderer)
#   - Azure Monitor integration
#   - Health checks and validation
#   - Proper error handling and rollback
#
# Requirements:
#   - bash 3.2+ (macOS 10.4+, most Linux distros)
#   - Azure CLI (az) 2.50.0+
#   - kubectl 1.28.0+
#   - Terraform 1.5.0+
#   - Helm 3.12.0+
#   - jq (JSON processor)
#
# Usage:
#   ./deploy-azure.sh [OPTIONS]
#
# Options:
#   --debug                  Enable verbose debug output
#   --deployment-id ID       Use specific deployment ID
#   --new                    Force create new deployment with fresh ID
#   --list-deployments       List all existing deployments and exit
#   --help, -h              Show help message
#
# =============================================================================

# Ensure we're running bash version 3.2+ for compatibility
if [ -z "$BASH_VERSION" ]; then
    echo "Error: This script requires bash. Please run with: bash $0 $*" >&2
    exit 1
fi

# Check for minimum bash version (3.2+)
bash_major="${BASH_VERSION%%.*}"
bash_minor="${BASH_VERSION#*.}"
bash_minor="${bash_minor%%.*}"
if [ "$bash_major" -lt 3 ] || ([ "$bash_major" -eq 3 ] && [ "$bash_minor" -lt 2 ]); then
    echo "Error: This script requires bash 3.2 or later. Current version: $BASH_VERSION" >&2
    exit 1
fi

set -e

# Get script directory in a portable way
if [ -n "${BASH_SOURCE[0]:-}" ]; then
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
else
    SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
fi

# Source shared deployment functions (includes color definitions and utility functions)
source "$SCRIPT_DIR/deployment-functions.sh"

# Override TERRAFORM_DIR for Azure
readonly TERRAFORM_DIR="$PROJECT_DIR/kubernetes/terraform/aks"

# Parse command line arguments
DEBUG_MODE=false
FORCE_NEW_DEPLOYMENT=false
PROVIDED_DEPLOYMENT_ID=""

while [ $# -gt 0 ]; do
    case $1 in
        --debug)
            DEBUG_MODE=true
            shift
            ;;
        --deployment-id)
            PROVIDED_DEPLOYMENT_ID="$2"
            shift 2
            ;;
        --new)
            FORCE_NEW_DEPLOYMENT=true
            shift
            ;;
        --list-deployments)
            echo "🚀 Loading configuration..."
            cd "$TERRAFORM_DIR"
            load_terraform_config
            list_all_deployments_azure
            exit 0
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Deploy Renny digital humans to Azure AKS with GPU support"
            echo ""
            echo "Options:"
            echo "  --debug                  Enable verbose debug output"
            echo "  --deployment-id ID       Use specific deployment ID"
            echo "  --new                    Force create new deployment with fresh ID"
            echo "  --list-deployments       List all existing deployments and exit"
            echo "  --help, -h              Show this help message"
            echo ""
            echo "Deployment ID Management:"
            echo "  By default, deploy.sh will detect existing deployments and prompt you"
            echo "  to either update an existing deployment or create a new one."
            echo ""
            echo "  Use --new to always create a fresh deployment with a new ID"
            echo "  Use --deployment-id to specify a custom deployment ID"
            echo "  Use --list-deployments to see all existing deployments"
            echo ""
            echo "Prerequisites:"
            echo "  - Azure CLI authenticated (az login)"
            echo "  - terraform.tfvars configured with Azure credentials"
            echo "  - GPU quota approved (160 vCPUs for NC16as_T4_v3)"
            echo ""
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo "🚀 Starting Renny AKS Deployment on Azure..."

# Debug logging functions
debug_log() {
    if [ "$DEBUG_MODE" = true ]; then
        echo -e "${CYAN}[DEBUG] $1${NC}"
    fi
}

info_log() {
    echo -e "$1"
}

# Show debug mode status
if [ "$DEBUG_MODE" = true ]; then
    echo -e "${CYAN}🐛 Debug mode enabled - verbose output active${NC}"
else
    echo -e "${BLUE}💡 Use --debug flag for verbose troubleshooting output${NC}"
fi

# Timing
START_TIME=$(date +%s)

# Function to show elapsed time
show_elapsed() {
    local current_time=$(date +%s)
    local elapsed=$((current_time - START_TIME))
    local elapsed_min=$((elapsed / 60))
    local elapsed_sec=$((elapsed % 60))
    echo "Elapsed time: ${elapsed_min}m ${elapsed_sec}s"
}

# =============================================================================
# Azure-Specific Functions
# =============================================================================

# Get Azure region from terraform.tfvars (single source of truth)
get_azure_region() {
    local terraform_dir="${1:-$TERRAFORM_DIR}"
    local original_dir="$(pwd)"

    cd "$terraform_dir" 2>/dev/null || {
        echo -e "${RED}Error: Cannot access terraform directory: $terraform_dir${NC}" >&2
        return 1
    }

    if [ ! -f "terraform.tfvars" ]; then
        echo -e "${RED}Error: terraform.tfvars not found${NC}" >&2
        echo "Please create terraform.tfvars with azure_region = \"your-region\"" >&2
        cd "$original_dir"
        return 1
    fi

    local azure_region
    azure_region=$(awk '/^azure_region[[:space:]]*=/ {gsub(/[" ]/, "", $3); print $3}' terraform.tfvars 2>/dev/null)

    cd "$original_dir"

    if [ -z "$azure_region" ] || [ "$azure_region" = "null" ]; then
        echo -e "${RED}Error: azure_region not set in terraform.tfvars${NC}" >&2
        echo "Please add: azure_region = \"eastus\"  (or your preferred region)" >&2
        return 1
    fi

    echo "$azure_region"
    return 0
}

# Load configuration from terraform.tfvars (Azure version)
load_terraform_config_azure() {
    cd "$TERRAFORM_DIR"

    if [ ! -f "terraform.tfvars" ]; then
        echo -e "${RED}Error: terraform.tfvars not found in $TERRAFORM_DIR${NC}" >&2
        return 1
    fi

    # Parse terraform.tfvars
    PROJECT_NAME=$(awk '/^project_name[[:space:]]*=/ {gsub(/[" ]/, "", $3); print $3}' terraform.tfvars 2>/dev/null || echo "renny")
    ENVIRONMENT=$(awk '/^environment[[:space:]]*=/ {gsub(/[" ]/, "", $3); print $3}' terraform.tfvars 2>/dev/null || echo "production")
    AZURE_REGION=$(awk '/^azure_region[[:space:]]*=/ {gsub(/[" ]/, "", $3); print $3}' terraform.tfvars 2>/dev/null)
    RESOURCE_GROUP_NAME=$(awk '/^resource_group_name[[:space:]]*=/ {gsub(/[" ]/, "", $3); print $3}' terraform.tfvars 2>/dev/null || echo "renny-kubernetes")

    if [ -z "$AZURE_REGION" ] || [ "$AZURE_REGION" = "null" ]; then
        echo -e "${RED}Error: azure_region not set in terraform.tfvars${NC}" >&2
        echo "Please add: azure_region = \"eastus\"  (or your preferred region)" >&2
        return 1
    fi

    # Check if deployment_id is already set in terraform.tfvars
    local tfvars_deployment_id
    tfvars_deployment_id=$(awk '/^deployment_id[[:space:]]*=/ {gsub(/[" ]/, "", $3); print $3}' terraform.tfvars 2>/dev/null || echo "")

    if [ -n "$tfvars_deployment_id" ]; then
        DEPLOYMENT_ID="$tfvars_deployment_id"
    fi

    # GPU node configuration
    RENNY_DESIRED_SIZE=$(awk '/^renny_desired_size[[:space:]]*=/ {gsub(/[^0-9]/, "", $3); print $3}' terraform.tfvars 2>/dev/null || echo "2")
    RENNY_VM_SIZE=$(awk '/^renny_vm_size[[:space:]]*=/ {gsub(/"/, "", $3); print $3}' terraform.tfvars 2>/dev/null || echo "Standard_NC16as_T4_v3")

    # Calculate total nodes
    GPU_NODES=$RENNY_DESIRED_SIZE

    # Export variables
    export PROJECT_NAME ENVIRONMENT AZURE_REGION RESOURCE_GROUP_NAME
    export RENNY_DESIRED_SIZE RENNY_VM_SIZE GPU_NODES
}

# Initialize deployment configuration (Azure version)
init_deployment_config_azure() {
    local force_new="${1:-false}"
    local provided_id="${2:-}"

    echo -e "${BLUE}🚀 Initializing Azure deployment configuration...${NC}"

    # Load terraform configuration
    load_terraform_config_azure

    # Handle provided deployment ID
    if [ -n "$provided_id" ]; then
        if validate_deployment_id "$provided_id"; then
            DEPLOYMENT_ID="$provided_id"
            save_deployment_id "$DEPLOYMENT_ID"
            echo -e "${GREEN}✅ Using provided deployment ID: $DEPLOYMENT_ID${NC}"
        else
            echo -e "${RED}Invalid deployment ID provided${NC}"
            exit 1
        fi
    elif [ "$force_new" = "true" ]; then
        DEPLOYMENT_ID=$(generate_deployment_id)
        save_deployment_id "$DEPLOYMENT_ID"
        echo -e "${GREEN}✅ Generated new deployment ID: $DEPLOYMENT_ID${NC}"
    else
        if load_deployment_id; then
            echo -e "${GREEN}✅ Loaded existing deployment ID: $DEPLOYMENT_ID${NC}"
        else
            select_deployment_action_azure

            if [ -z "$DEPLOYMENT_ID" ]; then
                DEPLOYMENT_ID=$(generate_deployment_id)
                save_deployment_id "$DEPLOYMENT_ID"
                echo -e "${GREEN}✅ Generated new deployment ID: $DEPLOYMENT_ID${NC}"
            fi
        fi
    fi

    # Set cluster name
    if [ -n "$DEPLOYMENT_ID" ]; then
        CLUSTER_NAME="$PROJECT_NAME-$ENVIRONMENT-$DEPLOYMENT_ID"
    else
        CLUSTER_NAME="$PROJECT_NAME-$ENVIRONMENT"
    fi

    export DEPLOYMENT_ID CLUSTER_NAME

    echo -e "${CYAN}Configuration:${NC}"
    echo "  Project: $PROJECT_NAME"
    echo "  Environment: $ENVIRONMENT"
    echo "  Deployment ID: ${DEPLOYMENT_ID:-'(legacy)'}"
    echo "  Cluster Name: $CLUSTER_NAME"
    echo "  Region: $AZURE_REGION"
    echo "  Resource Group: $RESOURCE_GROUP_NAME"
}

# List existing AKS deployments
list_existing_deployments_azure() {
    local base_name="$PROJECT_NAME-$ENVIRONMENT"

    echo -e "${BLUE}🔍 Scanning for existing AKS deployments...${NC}"

    # Get all AKS clusters with our base name pattern
    local clusters
    clusters=$(az aks list --query "[?contains(name, '$base_name')].name" -o tsv 2>/dev/null || echo "")

    if [ -z "$clusters" ]; then
        echo -e "${GREEN}No existing deployments found${NC}"
        return 1
    fi

    echo -e "${CYAN}Found existing deployments:${NC}"
    local count=0
    while IFS= read -r cluster; do
        if [ -n "$cluster" ]; then
            count=$((count + 1))

            # Get cluster details
            local rg=$(az aks show --name "$cluster" --query "resourceGroup" -o tsv 2>/dev/null || echo "Unknown")
            local status=$(az aks show --name "$cluster" --resource-group "$rg" --query "provisioningState" -o tsv 2>/dev/null || echo "Unknown")
            local location=$(az aks show --name "$cluster" --resource-group "$rg" --query "location" -o tsv 2>/dev/null || echo "Unknown")

            # Extract deployment ID if present
            local deployment_id=""
            if [[ "$cluster" =~ ^${base_name}-(.+)$ ]]; then
                deployment_id="${BASH_REMATCH[1]}"
            fi

            printf "  %d) %s\\n" "$count" "$cluster"
            printf "     Status: %s | Location: %s | RG: %s\\n" "$status" "$location" "$rg"
            if [ -n "$deployment_id" ]; then
                printf "     Deployment ID: %s\\n" "$deployment_id"
            else
                printf "     %sLegacy deployment (no deployment ID)%s\\n" "$YELLOW" "$NC"
            fi
            echo ""
        fi
    done <<< "$clusters"

    return 0
}

# List all deployments for management (Azure version)
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
            local node_count=$(az aks show --name "$cluster" --resource-group "$rg" --query "agentPoolProfiles[0].count" -o tsv 2>/dev/null || echo "0")

            # Extract deployment ID
            local deployment_id=""
            local cluster_type=""
            if [[ "$cluster" =~ ^${base_name}-(.+)$ ]]; then
                deployment_id="${BASH_REMATCH[1]}"
                cluster_type="Tagged"
            else
                cluster_type="Legacy"
            fi

            printf "%s%s%s\\n" "$CYAN" "$cluster" "$NC"
            printf "  Status: %s | Location: %s | Nodes: %s\\n" "$status" "$location" "$node_count"
            printf "  Resource Group: %s\\n" "$rg"
            if [ -n "$deployment_id" ]; then
                printf "  Type: %s | Deployment ID: %s\\n" "$cluster_type" "$deployment_id"
            else
                printf "  Type: %s%s%s (no deployment ID)\\n" "$YELLOW" "$cluster_type" "$NC"
            fi

            if [ "$status" = "Succeeded" ]; then
                printf "  %sACTIVE - Incurring costs%s\\n" "$GREEN" "$NC"
            else
                printf "  %sStatus: %s%s\\n" "$YELLOW" "$status" "$NC"
            fi
            echo ""
        fi
    done <<< "$clusters"

    return 0
}

# Interactive deployment selection (Azure version)
select_deployment_action_azure() {
    local base_name="$PROJECT_NAME-$ENVIRONMENT"

    if ! list_existing_deployments_azure; then
        echo -e "${GREEN}✨ This will be a fresh deployment${NC}"
        return 0
    fi

    echo -e "${YELLOW}What would you like to do?${NC}"
    echo "1) Create new deployment with fresh ID"
    echo "2) Update existing deployment (reuse existing resources)"
    echo "3) Cancel"
    echo ""

    while true; do
        read -p "Enter choice (1-3): " choice
        case "$choice" in
            1)
                echo -e "${GREEN}✨ Creating new deployment${NC}"
                return 0
                ;;
            2)
                # Find most recent deployment
                local latest_cluster
                latest_cluster=$(az aks list --query "[?contains(name, '$base_name')].name" -o tsv 2>/dev/null | head -1)
                if [ -n "$latest_cluster" ]; then
                    if [[ "$latest_cluster" =~ ^${base_name}-(.+)$ ]]; then
                        DEPLOYMENT_ID="${BASH_REMATCH[1]}"
                        echo -e "${GREEN}🔄 Updating existing deployment: $latest_cluster${NC}"
                        save_deployment_id "$DEPLOYMENT_ID"
                        return 0
                    else
                        DEPLOYMENT_ID=""
                        echo -e "${YELLOW}🔄 Updating legacy deployment: $latest_cluster${NC}"
                        return 0
                    fi
                else
                    echo -e "${RED}Error: No deployments found${NC}"
                fi
                ;;
            3)
                echo -e "${YELLOW}Cancelled${NC}"
                exit 0
                ;;
            *)
                echo "Invalid choice. Please enter 1-3."
                ;;
        esac
    done
}

# Check Azure CLI authentication
check_azure_auth() {
    echo "🔍 Checking Azure CLI authentication..."

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
    local az_version=$(az version --query '\"azure-cli\"' -o tsv 2>/dev/null || echo "0.0.0")
    debug_log "Azure CLI version: $az_version"

    # Try to get current account
    if ! az account show &> /dev/null; then
        echo -e "${RED}❌ Not logged in to Azure${NC}"
        echo ""
        echo "Please login with one of:"
        echo "  az login                    # Interactive browser login"
        echo "  az login --use-device-code  # Device code flow"
        echo ""
        exit 1
    fi

    # Get account information
    local account_name=$(az account show --query "name" -o tsv 2>/dev/null || echo "Unknown")
    local account_id=$(az account show --query "id" -o tsv 2>/dev/null || echo "Unknown")
    local tenant_id=$(az account show --query "tenantId" -o tsv 2>/dev/null || echo "Unknown")

    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║        Azure Account Information           ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
    echo -e "${BLUE}Subscription:${NC} $account_name"
    echo -e "${BLUE}Subscription ID:${NC} $account_id"
    echo -e "${BLUE}Tenant ID:${NC} $tenant_id"
    echo -e "${BLUE}Region:${NC} $AZURE_REGION"
    echo ""

    echo -e "${GREEN}✅ Azure authentication successful${NC}"
    return 0
}

# Check required tools
check_required_tools() {
    echo "🔍 Checking required tools..."

    local missing_tools=()

    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        missing_tools+=("azure-cli (az)")
    fi

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi

    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        missing_tools+=("terraform")
    fi

    # Check Helm
    if ! command -v helm &> /dev/null; then
        missing_tools+=("helm")
    fi

    # Check jq
    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi

    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo -e "${RED}❌ Missing required tools:${NC}"
        for tool in "${missing_tools[@]}"; do
            echo "  - $tool"
        done
        echo ""
        echo "Please install missing tools and try again."
        exit 1
    fi

    echo -e "${GREEN}✅ All required tools installed${NC}"
    return 0
}

# Check if AKS cluster exists and is healthy
check_existing_cluster_azure() {
    local cluster_name="$CLUSTER_NAME"
    local resource_group="$RESOURCE_GROUP_NAME"

    echo "🔍 Checking AKS cluster health for '$cluster_name'..."

    # Check if cluster exists
    if ! az aks show --name "$cluster_name" --resource-group "$resource_group" &>/dev/null; then
        echo -e "${YELLOW}⚡ Cluster '$cluster_name' not found - will create new infrastructure${NC}"
        echo ""
        return 1
    fi

    echo -e "${GREEN}✅ Found cluster: $cluster_name${NC}"

    # Check cluster status
    local cluster_status=$(az aks show --name "$cluster_name" --resource-group "$resource_group" --query "provisioningState" -o tsv 2>/dev/null)
    if [ "$cluster_status" != "Succeeded" ]; then
        echo -e "${RED}❌ Cluster status: $cluster_status (not Succeeded)${NC}"
        echo "Infrastructure appears incomplete - will run full deployment"
        echo ""
        return 1
    fi

    # Check node pools
    echo "Validating node pools..."
    local node_pools=$(az aks nodepool list --cluster-name "$cluster_name" --resource-group "$resource_group" --query "[].name" -o tsv 2>/dev/null || echo "")

    if [ -z "$node_pools" ]; then
        echo -e "${RED}❌ No node pools found${NC}"
        return 1
    fi

    local system_pool_found=false
    local gpu_pool_found=false

    while IFS= read -r pool; do
        if [ -n "$pool" ]; then
            local pool_status=$(az aks nodepool show --cluster-name "$cluster_name" --resource-group "$resource_group" --name "$pool" --query "provisioningState" -o tsv 2>/dev/null)
            echo "  Node pool '$pool': $pool_status"

            # Check for system and GPU pools
            if [[ "$pool" == *"system"* ]]; then
                system_pool_found=true
            fi
            if [[ "$pool" == *"gpu"* ]] || [[ "$pool" == *"renny"* ]]; then
                gpu_pool_found=true
            fi

            if [ "$pool_status" != "Succeeded" ]; then
                echo -e "${YELLOW}⚠️ Node pool $pool is not ready: $pool_status${NC}"
                return 1
            fi
        fi
    done <<< "$node_pools"

    if [ "$system_pool_found" = false ] || [ "$gpu_pool_found" = false ]; then
        echo -e "${RED}❌ Missing required node pools (system or GPU)${NC}"
        return 1
    fi

    echo -e "${GREEN}✓ Cluster status: Succeeded${NC}"
    echo -e "${GREEN}✓ All node pools: Ready${NC}"
    echo -e "${CYAN}📋 Infrastructure is healthy - skipping to application deployment${NC}"
    echo ""
    return 0
}

# Wait for GPU operator to be ready
wait_for_gpu_operator_ready_azure() {
    local max_timeout="${1:-2400}"
    local start_time=$(date +%s)
    local last_status=""

    echo "⏰ Maximum wait time: $((max_timeout/60)) minutes"

    # Wait for GPU nodes to be labeled
    local gpu_nodes=0
    local attempts=0
    while [ $gpu_nodes -eq 0 ] && [ $attempts -lt 60 ]; do
        gpu_nodes=$(kubectl get nodes -l nvidia.com/gpu.present=true --no-headers 2>/dev/null | wc -l || echo "0")
        if [ $gpu_nodes -eq 0 ]; then
            debug_log "Waiting for GPU nodes to be detected..."
            sleep 10
            ((attempts++))
        fi
    done

    if [ $gpu_nodes -eq 0 ]; then
        echo -e "${YELLOW}⚠️  No GPU nodes detected yet, using expected count${NC}"
        gpu_nodes=$GPU_NODES
        echo "Using calculated GPU nodes: $gpu_nodes"
    fi

    echo "Targeting $gpu_nodes GPU nodes for driver installation"

    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if [ $elapsed -ge $max_timeout ]; then
            echo -e "${RED}❌ Timeout waiting for GPU operator after $((max_timeout/60)) minutes${NC}"
            kubectl get pods -n gpu-operator -o wide
            return 1
        fi

        # Get GPU operator status
        local driver_pods=$(kubectl get pods -n gpu-operator -l app=nvidia-driver-daemonset -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.phase}{" "}{.status.containerStatuses[0].ready}{"\n"}{end}' 2>/dev/null | awk '$2=="Running" && $3=="true"' | wc -l | tr -d ' \n' || echo "0")
        local total_pods=$(kubectl get pods -n gpu-operator --no-headers 2>/dev/null | wc -l | tr -d ' \n' || echo "0")

        local elapsed_min=$((elapsed / 60))
        local elapsed_sec=$((elapsed % 60))
        local remaining_time=$((max_timeout - elapsed))
        local remaining_min=$((remaining_time / 60))

        # Progress bar
        if [ "$DEBUG_MODE" != true ]; then
            local progress=0
            if [ "$gpu_nodes" -gt "0" ]; then
                progress=$((driver_pods * 100 / gpu_nodes))
                if [ $progress -gt 100 ]; then progress=100; fi
            fi

            local progress_bar=""
            local filled=$((progress / 5))
            for ((i=1; i<=20; i++)); do
                if [ $i -le $filled ]; then
                    progress_bar+="█"
                else
                    progress_bar+="░"
                fi
            done
            echo -ne "\r🎮 Installing GPU drivers... [$progress_bar] $driver_pods/$gpu_nodes ready (${elapsed_min}m${elapsed_sec}s, ~${remaining_min}m left)"
        fi

        # Success condition
        if [ "$driver_pods" -ge "$gpu_nodes" ] && [ "$gpu_nodes" -gt "0" ]; then
            local gpu_capacity=$(kubectl get nodes -o json | jq -r '.items[] | select(.metadata.labels."nvidia.com/gpu" == "true") | .status.capacity."nvidia.com/gpu" // "0"' | awk '{sum += $1} END {print sum+0}')

            if [ "$gpu_capacity" -gt "0" ]; then
                if [ "$DEBUG_MODE" != true ]; then
                    echo ""
                fi
                echo -e "${GREEN}✓ GPU drivers installed on all $gpu_nodes GPU nodes ($gpu_capacity total GPUs available)${NC}"
                return 0
            fi
        fi

        sleep 20
    done
}

# Deploy infrastructure with Terraform
deploy_infrastructure() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Step 1: Infrastructure Deployment${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo ""

    cd "$TERRAFORM_DIR"

    # Initialize Terraform
    echo "📦 Initializing Terraform..."
    if ! terraform init -upgrade 2>&1 | grep -E "Terraform has been successfully initialized|has already been initialized"; then
        echo -e "${RED}❌ Terraform initialization failed${NC}"
        return 1
    fi
    echo -e "${GREEN}✅ Terraform initialized${NC}"

    # Plan
    echo ""
    echo "📋 Planning infrastructure changes..."
    if ! terraform plan -out=tfplan 2>&1; then
        echo -e "${RED}❌ Terraform plan failed${NC}"
        return 1
    fi

    # Apply
    echo ""
    echo "🏗️  Applying infrastructure changes (this will take 15-20 minutes)..."
    echo ""

    if ! terraform apply -auto-approve tfplan 2>&1; then
        echo -e "${RED}❌ Terraform apply failed${NC}"
        return 1
    fi

    echo -e "${GREEN}✅ Infrastructure deployed successfully${NC}"

    # Get kubeconfig
    echo ""
    echo "🔑 Configuring kubectl access..."

    local rg=$(terraform output -raw resource_group_name 2>/dev/null || echo "$RESOURCE_GROUP_NAME")
    local cluster=$(terraform output -raw cluster_name 2>/dev/null || echo "$CLUSTER_NAME")

    if ! az aks get-credentials --resource-group "$rg" --name "$cluster" --overwrite-existing 2>&1; then
        echo -e "${RED}❌ Failed to get AKS credentials${NC}"
        return 1
    fi

    echo -e "${GREEN}✅ Kubectl configured for cluster: $cluster${NC}"

    # Wait for cluster to be ready
    echo ""
    echo "⏳ Waiting for cluster to be ready..."
    local ready_nodes=0
    local attempts=0
    while [ $ready_nodes -eq 0 ] && [ $attempts -lt 30 ]; do
        ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" || echo "0")
        if [ $ready_nodes -eq 0 ]; then
            sleep 10
            ((attempts++))
        fi
    done

    if [ $ready_nodes -eq 0 ]; then
        echo -e "${YELLOW}⚠️  No nodes ready yet, but continuing...${NC}"
    else
        echo -e "${GREEN}✅ Cluster has $ready_nodes ready nodes${NC}"
    fi

    return 0
}

# Install GPU Operator
install_gpu_operator() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Step 2: GPU Operator Installation${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo ""

    # Add NVIDIA Helm repo
    echo "📦 Adding NVIDIA Helm repository..."
    if ! helm repo add nvidia https://helm.ngc.nvidia.com/nvidia 2>&1; then
        echo -e "${YELLOW}⚠️  Helm repo already exists, updating...${NC}"
    fi
    helm repo update

    # Check if GPU operator already installed
    if helm list -n gpu-operator | grep -q "gpu-operator"; then
        echo -e "${CYAN}ℹ️  GPU Operator already installed, upgrading...${NC}"
    else
        echo "Installing GPU Operator..."
    fi

    # Create namespace
    kubectl create namespace gpu-operator --dry-run=client -o yaml | kubectl apply -f -

    # Install/upgrade GPU Operator
    if ! helm upgrade --install gpu-operator nvidia/gpu-operator \
        --namespace gpu-operator \
        --set driver.enabled=true \
        --set driver.version="580.13.01" \
        --set toolkit.enabled=true \
        --set devicePlugin.enabled=true \
        --set mig.strategy=single \
        --set operator.defaultRuntime=containerd \
        --timeout 20m \
        --wait 2>&1; then
        echo -e "${RED}❌ GPU Operator installation failed${NC}"
        return 1
    fi

    echo -e "${GREEN}✅ GPU Operator installed${NC}"

    # Wait for GPU operator to be ready
    echo ""
    wait_for_gpu_operator_ready_azure 2400

    return 0
}

# Configure GPU time-slicing
configure_gpu_time_slicing() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Step 3: GPU Time-Slicing Configuration${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo ""

    # Read time-slicing config from renny-values.yaml
    local values_file="$KUBERNETES_DIR/values/renny-values.yaml"
    local replicas_per_gpu=$(grep "replicasPerGpu:" "$values_file" | awk '{print $2}' || echo "2")

    echo "Configuring GPU time-slicing: $replicas_per_gpu pods per GPU"

    # Create time-slicing ConfigMap
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: renny-time-slicing-config
  namespace: gpu-operator
data:
  renny: |-
    version: v1
    flags:
      migStrategy: none
    sharing:
      timeSlicing:
        resources:
        - name: nvidia.com/gpu
          replicas: $replicas_per_gpu
EOF

    # Update GPU operator to use time-slicing config
    helm upgrade gpu-operator nvidia/gpu-operator \
        --namespace gpu-operator \
        --reuse-values \
        --set devicePlugin.config.name=renny-time-slicing-config \
        --set devicePlugin.config.default=renny \
        --timeout 20m \
        --wait

    echo -e "${GREEN}✅ GPU time-slicing configured ($replicas_per_gpu pods per GPU)${NC}"

    # Restart device plugin daemonset
    echo "♻️  Restarting GPU device plugin..."
    kubectl delete pods -n gpu-operator -l app=nvidia-device-plugin-daemonset

    # Wait for device plugin to restart
    sleep 30

    return 0
}

# Deploy Renny application
deploy_renny_application() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Step 4: Renny Application Deployment${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo ""

    local manifests_dir="$KUBERNETES_DIR/manifests"
    local values_file="$KUBERNETES_DIR/values/renny-values.yaml"

    # Create namespace
    kubectl create namespace uneeq-renderer --dry-run=client -o yaml | kubectl apply -f -

    # Apply manifests
    echo "📦 Applying Kubernetes manifests..."

    # Create Docker registry secret
    local docker_user=$(grep "docker_username" "$TERRAFORM_DIR/terraform.tfvars" | awk -F'"' '{print $2}')
    local docker_pass=$(grep "docker_password" "$TERRAFORM_DIR/terraform.tfvars" | awk -F'"' '{print $2}')

    kubectl create secret docker-registry regcred \
        --docker-server=https://index.docker.io/v1/ \
        --docker-username="$docker_user" \
        --docker-password="$docker_pass" \
        --namespace=uneeq-renderer \
        --dry-run=client -o yaml | kubectl apply -f -

    # Deploy Renny using Helm (if Helm chart exists) or kubectl
    if [ -d "$KUBERNETES_DIR/charts/renny" ]; then
        echo "Using Helm chart for Renny deployment..."
        helm upgrade --install renny "$KUBERNETES_DIR/charts/renny" \
            --namespace uneeq-renderer \
            --values "$values_file" \
            --timeout 25m \
            --wait
    else
        echo "Applying Renny manifests with kubectl..."
        kubectl apply -f "$manifests_dir/" -n uneeq-renderer
    fi

    echo -e "${GREEN}✅ Renny application deployed${NC}"

    # Wait for pods to be ready
    echo ""
    echo "⏳ Waiting for Renny pods to be ready..."

    local ready_pods=0
    local total_pods=$(grep "totalReplicas:" "$values_file" | awk '{print $2}' || echo "2")
    local attempts=0

    while [ $ready_pods -lt $total_pods ] && [ $attempts -lt 60 ]; do
        ready_pods=$(kubectl get pods -n uneeq-renderer -l app=renny --no-headers 2>/dev/null | grep -c "Running" || echo "0")

        if [ "$DEBUG_MODE" != true ]; then
            echo -ne "\r   Renny pods ready: $ready_pods/$total_pods"
        fi

        if [ $ready_pods -lt $total_pods ]; then
            sleep 10
            ((attempts++))
        fi
    done

    if [ "$DEBUG_MODE" != true ]; then
        echo ""
    fi

    if [ $ready_pods -eq $total_pods ]; then
        echo -e "${GREEN}✅ All Renny pods are ready ($ready_pods/$total_pods)${NC}"
    else
        echo -e "${YELLOW}⚠️  Only $ready_pods/$total_pods Renny pods are ready${NC}"
        echo "Check pod status with: kubectl get pods -n uneeq-renderer"
    fi

    return 0
}

# Setup monitoring
setup_monitoring() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Step 5: Monitoring Setup${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo ""

    # Enable Azure Monitor for containers (if not already enabled)
    echo "📊 Enabling Azure Monitor for AKS..."

    local rg=$(az aks show --name "$CLUSTER_NAME" --query "resourceGroup" -o tsv 2>/dev/null || echo "$RESOURCE_GROUP_NAME")

    if ! az aks enable-addons --name "$CLUSTER_NAME" --resource-group "$rg" --addons monitoring 2>&1; then
        echo -e "${YELLOW}⚠️  Azure Monitor addon already enabled or failed to enable${NC}"
    else
        echo -e "${GREEN}✅ Azure Monitor enabled for cluster${NC}"
    fi

    echo ""
    echo -e "${CYAN}ℹ️  View logs and metrics in Azure Portal:${NC}"
    echo "   https://portal.azure.com/#resource/subscriptions/.../resourceGroups/$rg/providers/Microsoft.ContainerService/managedClusters/$CLUSTER_NAME"

    return 0
}

# Display deployment summary
show_deployment_summary() {
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════${NC}"
    echo -e "${GREEN}  🎉 Deployment Complete!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════${NC}"
    echo ""

    local end_time=$(date +%s)
    local total_time=$((end_time - START_TIME))
    local total_min=$((total_time / 60))
    local total_sec=$((total_time % 60))

    echo -e "${CYAN}Cluster Information:${NC}"
    echo "  Name: $CLUSTER_NAME"
    echo "  Region: $AZURE_REGION"
    echo "  Resource Group: $RESOURCE_GROUP_NAME"
    echo "  Deployment ID: ${DEPLOYMENT_ID:-'(none)'}"
    echo ""

    echo -e "${CYAN}Deployment Time:${NC} ${total_min}m ${total_sec}s"
    echo ""

    # Get node information
    local gpu_nodes=$(kubectl get nodes -l agentpool=rennygpu --no-headers 2>/dev/null | wc -l || echo "0")
    local total_nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "0")

    echo -e "${CYAN}Cluster Nodes:${NC}"
    echo "  Total nodes: $total_nodes"
    echo "  GPU nodes: $gpu_nodes"
    echo ""

    # Get pod information
    local renny_pods=$(kubectl get pods -n uneeq-renderer -l app=renny --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    local total_pods=$(kubectl get pods -n uneeq-renderer --no-headers 2>/dev/null | wc -l || echo "0")

    echo -e "${CYAN}Application Status:${NC}"
    echo "  Renny pods running: $renny_pods"
    echo "  Total pods: $total_pods"
    echo ""

    echo -e "${CYAN}Useful Commands:${NC}"
    echo "  # View cluster info"
    echo "  kubectl cluster-info"
    echo ""
    echo "  # List all nodes"
    echo "  kubectl get nodes -o wide"
    echo ""
    echo "  # Check GPU availability"
    echo "  kubectl get nodes -L nvidia.com/gpu"
    echo ""
    echo "  # View Renny pods"
    echo "  kubectl get pods -n uneeq-renderer"
    echo ""
    echo "  # View pod logs"
    echo "  kubectl logs -n uneeq-renderer -l app=renny -f"
    echo ""
    echo "  # Test GPU"
    echo "  kubectl run gpu-test --rm -it --restart=Never \\"
    echo "    --image=nvidia/cuda:12.4-runtime-ubuntu22.04 \\"
    echo "    --overrides='{\"spec\":{\"nodeSelector\":{\"agentpool\":\"rennygpu\"}}}' \\"
    echo "    -- nvidia-smi"
    echo ""

    echo -e "${CYAN}Next Steps:${NC}"
    echo "  1. Check deployment status: ./scripts/status.sh"
    echo "  2. Scale deployment: ./scripts/scale.sh <replicas>"
    echo "  3. View costs: Azure Portal > Cost Management"
    echo "  4. Monitor cluster: Azure Portal > Monitor"
    echo ""

    echo -e "${YELLOW}⚠️  Cost Warning:${NC}"
    echo "  This cluster is incurring costs. Estimated: ~\$$(($gpu_nodes * 36))/day"
    echo "  To stop costs: ./scripts/destroy.sh"
    echo ""
}

# =============================================================================
# Main Deployment Flow
# =============================================================================

main() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                                              ║${NC}"
    echo -e "${CYAN}║     Renny AKS Deployment (Azure)             ║${NC}"
    echo -e "${CYAN}║                                              ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
    echo ""

    # Pre-flight checks
    echo -e "${BLUE}Running pre-flight checks...${NC}"
    check_required_tools

    # Load configuration
    init_deployment_config_azure "$FORCE_NEW_DEPLOYMENT" "$PROVIDED_DEPLOYMENT_ID"

    # Check Azure authentication
    check_azure_auth

    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════${NC}"
    echo -e "${CYAN}Ready to deploy Renny to Azure AKS${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════${NC}"
    echo ""
    echo "Deployment will:"
    echo "  1. Create/update AKS infrastructure (~15-20 min)"
    echo "  2. Install NVIDIA GPU Operator (~10-15 min)"
    echo "  3. Configure GPU time-slicing (~2 min)"
    echo "  4. Deploy Renny application (~5-10 min)"
    echo "  5. Setup Azure Monitor (~2 min)"
    echo ""
    echo "Total estimated time: 35-50 minutes"
    echo ""

    read -p "Continue with deployment? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Deployment cancelled"
        exit 0
    fi

    # Check if cluster exists
    local skip_infrastructure=false
    if check_existing_cluster_azure; then
        echo -e "${CYAN}Existing healthy cluster found${NC}"
        read -p "Skip infrastructure deployment and update application only? (Y/n): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
            skip_infrastructure=true
        fi
    fi

    # Deploy infrastructure
    if [ "$skip_infrastructure" = false ]; then
        if ! deploy_infrastructure; then
            echo -e "${RED}❌ Infrastructure deployment failed${NC}"
            exit 1
        fi
    else
        echo -e "${CYAN}ℹ️  Skipping infrastructure deployment${NC}"

        # Still need to get kubeconfig
        echo "🔑 Ensuring kubectl access..."
        az aks get-credentials --resource-group "$RESOURCE_GROUP_NAME" --name "$CLUSTER_NAME" --overwrite-existing
    fi

    # Install GPU Operator
    if ! install_gpu_operator; then
        echo -e "${RED}❌ GPU Operator installation failed${NC}"
        exit 1
    fi

    # Configure GPU time-slicing
    if ! configure_gpu_time_slicing; then
        echo -e "${RED}❌ GPU time-slicing configuration failed${NC}"
        exit 1
    fi

    # Deploy Renny application
    if ! deploy_renny_application; then
        echo -e "${RED}❌ Renny application deployment failed${NC}"
        exit 1
    fi

    # Setup monitoring
    if ! setup_monitoring; then
        echo -e "${YELLOW}⚠️  Monitoring setup had issues, but continuing...${NC}"
    fi

    # Show summary
    show_deployment_summary

    return 0
}

# Run main function
main "$@"
