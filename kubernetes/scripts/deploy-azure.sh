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

# Set TERRAFORM_DIR for Azure BEFORE sourcing (so deployment-functions.sh won't override)
readonly TERRAFORM_DIR="$(cd "$SCRIPT_DIR/../terraform/aks" && pwd)"

# Source shared deployment functions (includes color definitions and utility functions)
source "$SCRIPT_DIR/deployment-functions.sh"

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
    azure_region=$(echo "var.azure_region" | terraform console 2>/dev/null | tr -d '"')

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

    # Parse terraform.tfvars using Terraform's own parser (more robust than AWK)
    PROJECT_NAME=$(echo "var.project_name" | terraform console 2>/dev/null | tr -d '"' || echo "renny")
    ENVIRONMENT=$(echo "var.environment" | terraform console 2>/dev/null | tr -d '"' || echo "production")
    AZURE_REGION=$(echo "var.azure_region" | terraform console 2>/dev/null | tr -d '"')
    RESOURCE_GROUP_NAME=$(echo "var.resource_group_name" | terraform console 2>/dev/null | tr -d '"' || echo "renny-kubernetes")

    if [ -z "$AZURE_REGION" ] || [ "$AZURE_REGION" = "null" ]; then
        echo -e "${RED}Error: azure_region not set in terraform.tfvars${NC}" >&2
        echo "Please add: azure_region = \"eastus\"  (or your preferred region)" >&2
        return 1
    fi

    # Check if deployment_id is already set in terraform.tfvars
    local tfvars_deployment_id
    tfvars_deployment_id=$(echo "var.deployment_id" | terraform console 2>/dev/null | tr -d '"' || echo "")

    if [ -n "$tfvars_deployment_id" ]; then
        DEPLOYMENT_ID="$tfvars_deployment_id"
    fi

    # GPU node configuration
    RENNY_DESIRED_SIZE=$(echo "var.renny_desired_size" | terraform console 2>/dev/null | tr -d '"' || echo "2")
    RENNY_VM_SIZE=$(echo "var.renny_vm_size" | terraform console 2>/dev/null | tr -d '"' || echo "Standard_NC16as_T4_v3")

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
    local has_missing=false

    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        missing_tools+=("az")
        has_missing=true
    fi

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
        has_missing=true
    fi

    # Check kubelogin (required for Azure AD authentication)
    if ! command -v kubelogin &> /dev/null; then
        missing_tools+=("kubelogin")
        has_missing=true
    fi

    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        missing_tools+=("terraform")
        has_missing=true
    fi

    # Check Helm
    if ! command -v helm &> /dev/null; then
        missing_tools+=("helm")
        has_missing=true
    fi

    # Check jq
    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
        has_missing=true
    fi

    if [ "$has_missing" = true ]; then
        echo -e "${RED}❌ Missing required tools:${NC}"
        for tool in "${missing_tools[@]}"; do
            echo "  - $tool"
        done
        echo ""

        # Provide installation instructions
        echo -e "${CYAN}Installation Instructions:${NC}"
        echo ""

        for tool in "${missing_tools[@]}"; do
            case "$tool" in
                az)
                    echo -e "${YELLOW}Azure CLI (az):${NC}"
                    echo "  macOS:   brew install azure-cli"
                    echo "  Linux:   curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
                    echo "  Windows: Download from https://aka.ms/installazurecliwindows"
                    echo ""
                    ;;
                kubectl)
                    echo -e "${YELLOW}kubectl:${NC}"
                    echo "  macOS:   brew install kubectl"
                    echo "  Linux:   curl -LO \"https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl\""
                    echo "           sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl"
                    echo "  Windows: choco install kubernetes-cli"
                    echo "           OR download from https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/"
                    echo ""
                    ;;
                kubelogin)
                    echo -e "${YELLOW}kubelogin (Azure Kubernetes Authentication):${NC}"
                    echo "  macOS:   brew install Azure/kubelogin/kubelogin"
                    echo "  Linux:   # Download latest release"
                    echo "           curl -L https://github.com/Azure/kubelogin/releases/latest/download/kubelogin-linux-amd64.zip -o kubelogin.zip"
                    echo "           unzip kubelogin.zip"
                    echo "           sudo mv bin/linux_amd64/kubelogin /usr/local/bin/"
                    echo "           sudo chmod +x /usr/local/bin/kubelogin"
                    echo "  Windows: choco install kubelogin"
                    echo "           OR download from https://github.com/Azure/kubelogin/releases"
                    echo ""
                    ;;
                terraform)
                    echo -e "${YELLOW}Terraform:${NC}"
                    echo "  macOS:   brew install terraform"
                    echo "  Linux:   wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg"
                    echo "           echo \"deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com \$(lsb_release -cs) main\" | sudo tee /etc/apt/sources.list.d/hashicorp.list"
                    echo "           sudo apt update && sudo apt install terraform"
                    echo "  Windows: choco install terraform"
                    echo ""
                    ;;
                helm)
                    echo -e "${YELLOW}Helm:${NC}"
                    echo "  macOS:   brew install helm"
                    echo "  Linux:   curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
                    echo "  Windows: choco install kubernetes-helm"
                    echo ""
                    ;;
                jq)
                    echo -e "${YELLOW}jq (JSON processor):${NC}"
                    echo "  macOS:   brew install jq"
                    echo "  Linux:   sudo apt-get install jq  (Debian/Ubuntu)"
                    echo "           sudo yum install jq      (RHEL/CentOS)"
                    echo "  Windows: choco install jq"
                    echo ""
                    ;;
            esac
        done

        echo -e "${RED}Please install all missing tools and try again.${NC}"
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

# =============================================================================
# GPU Operator Adaptive Monitoring Functions
# =============================================================================

# Global variables for GPU operator adaptive monitoring (bash 3.2 compatible)
GPU_PROGRESS_LAST=""
GPU_PROGRESS_LAST_CHANGE_TIME=0
GPU_MONITORING_MODE="normal"

# Display throttling controls for GPU monitoring
LAST_GPU_DISPLAY_TIME=0
LAST_GPU_FULL_STATUS_TIME=0
DISPLAY_INTERVAL_GPU_NORMAL=30      # Update progress every 30 seconds
DISPLAY_INTERVAL_GPU_DIAGNOSTIC=120 # Update in diagnostic mode every 2 minutes
DISPLAY_INTERVAL_GPU_FULL_STATUS=120 # Show full status every 2 minutes
GPU_INVESTIGATION_PHASE="monitoring" # monitoring|investigating|monitoring_stalled|escalated
GPU_DIAGNOSTIC_RUN_ONCE=false       # Track if diagnostic output shown

# Display throttling helper functions (bash 3.2 compatible)
should_update_gpu_display() {
    local interval=$1
    local current_time=$(date +%s)
    local time_since_last=$((current_time - LAST_GPU_DISPLAY_TIME))

    if [[ $time_since_last -ge $interval ]]; then
        LAST_GPU_DISPLAY_TIME=$current_time
        return 0  # Should display
    fi
    return 1  # Skip display
}

should_show_gpu_full_status() {
    local current_time=$(date +%s)
    local time_since_last=$((current_time - LAST_GPU_FULL_STATUS_TIME))

    if [[ $time_since_last -ge $DISPLAY_INTERVAL_GPU_FULL_STATUS ]]; then
        LAST_GPU_FULL_STATUS_TIME=$current_time
        return 0
    fi
    return 1
}

# Check GPU pod health in background (non-blocking)
check_gpu_pod_health_background() {
    # Get failed GPU operator pods
    local failed_pods=$(kubectl get pods -n gpu-operator --field-selector=status.phase!=Running,status.phase!=Succeeded --no-headers 2>/dev/null)

    # Check for critical failures
    local critical_crashes=$(echo "$failed_pods" | grep -E "CrashLoopBackOff|ImagePullBackOff|Error|ErrImagePull" | wc -l | tr -d ' \n')

    if [ "$critical_crashes" -gt 0 ]; then
        # Store for diagnostic display
        echo "$critical_crashes" > /tmp/gpu_critical_pods.count 2>/dev/null || true
        echo "$failed_pods" > /tmp/gpu_failed_pods.txt 2>/dev/null || true
    fi
}

# Detect if GPU operator progress has stalled (bash 3.2 compatible)
detect_gpu_stall() {
    local current_progress="$1"
    local current_time
    current_time=$(date +%s)

    # Initialize on first run
    if [[ -z "$GPU_PROGRESS_LAST" ]]; then
        GPU_PROGRESS_LAST="$current_progress"
        GPU_PROGRESS_LAST_CHANGE_TIME=$current_time
        return 1  # Not stalled
    fi

    # Check if progress has changed
    if [[ "$current_progress" != "$GPU_PROGRESS_LAST" ]]; then
        GPU_PROGRESS_LAST="$current_progress"
        GPU_PROGRESS_LAST_CHANGE_TIME=$current_time
        return 1  # Making progress
    fi

    # Same progress - check time elapsed
    local time_diff=$((current_time - GPU_PROGRESS_LAST_CHANGE_TIME))
    if [[ $time_diff -ge 300 ]]; then
        return 0  # Stalled (5+ minutes)
    fi

    return 1  # Not stalled
}

# Display normal GPU operator progress with throttling (bash 3.2 compatible)
display_normal_gpu_progress() {
    local driver_pods="$1"
    local gpu_nodes="$2"
    local elapsed="$3"
    local max_timeout="$4"

    # Only update if throttle interval has passed
    if ! should_update_gpu_display "$DISPLAY_INTERVAL_GPU_NORMAL"; then
        return 0
    fi

    local elapsed_min=$((elapsed / 60))
    local elapsed_sec=$((elapsed % 60))
    local remaining_time=$((max_timeout - elapsed))
    local remaining_min=$((remaining_time / 60))

    # Calculate progress percentage
    local progress=0
    if [ "$gpu_nodes" -gt "0" ]; then
        progress=$((driver_pods * 100 / gpu_nodes))
        if [ $progress -gt 100 ]; then progress=100; fi
    fi

    # Build progress bar
    local progress_bar=$(build_progress_bar "$progress")

    # Show full status every 2 minutes, otherwise just progress bar
    if should_show_gpu_full_status; then
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "📊 GPU Operator Status ($(date '+%H:%M:%S'))"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        local device_plugin_pods=$(kubectl get pods -n gpu-operator -l app=nvidia-device-plugin-daemonset --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        local toolkit_pods=$(kubectl get pods -n gpu-operator -l app=nvidia-container-toolkit-daemonset --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        echo "  Ready Nodes: $driver_pods/$gpu_nodes"
        echo "  Device Plugin: $device_plugin_pods pods"
        echo "  Toolkit: $toolkit_pods pods"
        echo "  Progress: [$progress_bar] $progress%"
        echo "  Elapsed: ${elapsed_min}m${elapsed_sec}s | Est. remaining: ~${remaining_min}m"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    else
        # Just update progress bar in place
        printf "\r⏳ GPU Installation: [$progress_bar] $progress%% ($driver_pods/$gpu_nodes nodes) | ${elapsed_min}m${elapsed_sec}s elapsed    "
    fi
}

# Display GPU operator diagnostic information when stalled (with throttling)
display_gpu_diagnostic_info() {
    local driver_pods="$1"
    local gpu_nodes="$2"
    local elapsed="$3"
    local stall_duration="$4"

    local elapsed_min=$((elapsed / 60))
    local elapsed_sec=$((elapsed % 60))
    local stall_min=$((stall_duration / 60))
    local stall_sec=$((stall_duration % 60))

    # Only show full diagnostic output if throttle interval has passed
    if should_update_gpu_display "$DISPLAY_INTERVAL_GPU_DIAGNOSTIC"; then
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "🔍 GPU Diagnostic Mode ($(date '+%H:%M:%S'))"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  ℹ️  Installation progress: $driver_pods/$gpu_nodes GPU nodes ready"
        echo "  ⏳ Stalled for: ${stall_min}m${stall_sec}s (elapsed: ${elapsed_min}m${elapsed_sec}s)"
        echo ""

        # Show component status
        local device_plugin_pods=$(kubectl get pods -n gpu-operator -l app=nvidia-device-plugin-daemonset --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        local toolkit_pods=$(kubectl get pods -n gpu-operator -l app=nvidia-container-toolkit-daemonset --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        local operator_pods=$(kubectl get pods -n gpu-operator -l app=gpu-operator --no-headers 2>/dev/null | grep -c "Running" || echo "0")

        echo "  📊 Component Status:"
        echo "     • GPU Operator: $operator_pods pods running"
        echo "     • Device Plugin: $device_plugin_pods pods running"
        echo "     • Container Toolkit: $toolkit_pods pods running"

        # Show any pod failures
        if [ -f /tmp/gpu_critical_pods.count ]; then
            local critical_count=$(cat /tmp/gpu_critical_pods.count)
            if [ "$critical_count" -gt 0 ]; then
                echo ""
                echo "  ⚠️  Failed GPU pods detected: $critical_count"
                if [ -f /tmp/gpu_failed_pods.txt ]; then
                    echo "  📋 Details:"
                    head -3 /tmp/gpu_failed_pods.txt | sed 's/^/     /' 2>/dev/null || true
                fi
            fi
        fi

        echo ""
        echo "  💡 GPU driver installation typically takes 10-15 minutes per node"
        echo "     Background: NVIDIA drivers are being downloaded, compiled, and loaded"
        echo "     Status: Deep diagnostics ran ${stall_min}m ago (see output above)"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    else
        # Just show minimal status line between full outputs
        printf "\r🔍 Diagnostic Mode: $driver_pods/$gpu_nodes ready | Stalled ${stall_min}m${stall_sec}s | ${elapsed_min}m${elapsed_sec}s elapsed    "
    fi
}

# Deep GPU diagnostics with actual log analysis (bash 3.2 compatible)
run_gpu_deep_diagnostics() {
    echo ""
    echo "🔍 Running deep GPU operator diagnostics..."

    # Get driver pod name
    local driver_pod=$(kubectl get pods -n gpu-operator -l app=nvidia-driver-daemonset -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [[ -z "$driver_pod" ]]; then
        echo "  ⚠️  No GPU driver pods found"
        echo "     💡 GPU Operator may still be initializing"
        echo ""
        return 1
    fi

    echo "  📊 Analyzing logs from: $driver_pod"

    # Fetch recent logs (last 100 lines)
    local logs=$(kubectl logs "$driver_pod" -n gpu-operator --tail=100 2>/dev/null)

    # Pattern matching for specific issues
    local issue_found=false

    # Check for driver download failures
    if echo "$logs" | grep -qi "failed to download\|download.*error\|curl.*failed"; then
        echo "  ❌ Issue: Driver download failure detected"
        echo "     💡 Solution: Check internet connectivity and NVIDIA driver repository access"
        echo "     🔧 Command: kubectl logs $driver_pod -n gpu-operator | grep -i download"
        issue_found=true
    fi

    # Check for kernel compilation failures
    if echo "$logs" | grep -qi "kernel.*compilation.*failed\|make.*error\|cc1.*error"; then
        echo "  ❌ Issue: Kernel module compilation failure"
        echo "     💡 Solution: Kernel headers may be missing or incompatible"
        echo "     🔧 Command: kubectl exec $driver_pod -n gpu-operator -- uname -r"
        issue_found=true
    fi

    # Check for GPU hardware detection issues
    if echo "$logs" | grep -qi "no nvidia gpu\|no devices found\|lspci.*empty\|no gpu found"; then
        echo "  ❌ Issue: No NVIDIA GPUs detected on node"
        echo "     💡 Solution: Verify GPU node pool is using correct VM size (Standard_NC16as_T4_v3)"
        echo "     🔧 Command: kubectl describe node | grep -A 5 'instance-type'"
        issue_found=true
    fi

    # Check for container runtime issues
    if echo "$logs" | grep -qi "container runtime.*error\|nvidia-container-runtime.*failed\|containerd.*error"; then
        echo "  ❌ Issue: Container runtime configuration problem"
        echo "     💡 Solution: NVIDIA Container Toolkit may not be configured correctly"
        echo "     🔧 Command: kubectl logs $driver_pod -n gpu-operator | grep runtime"
        issue_found=true
    fi

    if [[ "$issue_found" = false ]]; then
        echo "  ℹ️  Driver installation in progress - no errors detected"
        echo "     ⏳ NVIDIA driver installation typically takes 10-15 minutes per node"
        echo "     💡 Drivers are being downloaded, compiled, and loaded in the background"
        echo "     📝 Current phase: Downloading, compiling, and loading kernel modules"
    fi

    echo ""
}

# Wait for GPU operator to be ready with adaptive monitoring
wait_for_gpu_operator_ready_azure() {
    local max_timeout="${1:-2400}"
    local start_time=$(date +%s)
    local last_check_time=0
    local check_interval=20

    echo "⏰ Waiting for GPU operator to be ready..."
    echo "   Maximum wait time: $((max_timeout/60)) minutes"
    echo ""

    # Clean up old temp files
    rm -f /tmp/gpu_critical_pods.count /tmp/gpu_failed_pods.txt 2>/dev/null || true

    # Wait for GPU nodes to be labeled
    local gpu_nodes=0
    local attempts=0
    echo "🔍 Detecting GPU nodes..."
    while [ $gpu_nodes -eq 0 ] && [ $attempts -lt 60 ]; do
        gpu_nodes=$(kubectl get nodes -l nvidia.com/gpu.present=true --no-headers 2>/dev/null | wc -l || echo "0")
        gpu_nodes=$(echo "$gpu_nodes" | tr -d ' \n' | grep -o '[0-9]*' || echo "0")

        if [ $gpu_nodes -eq 0 ]; then
            debug_log "Waiting for GPU nodes to be detected..."
            sleep 10
            ((attempts++))
        fi
    done

    if [ $gpu_nodes -eq 0 ]; then
        echo -e "${YELLOW}⚠️  No GPU nodes detected yet, using expected count${NC}"
        gpu_nodes=$GPU_NODES
        echo "Using expected GPU nodes: $gpu_nodes"
    else
        echo -e "${GREEN}✅ Detected $gpu_nodes GPU nodes${NC}"
    fi
    echo ""

    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        # Check timeout
        if [ $elapsed -ge $max_timeout ]; then
            echo -e "\n${RED}❌ Timeout waiting for GPU operator after $((max_timeout/60)) minutes${NC}"
            kubectl get pods -n gpu-operator -o wide
            return 1
        fi

        # Only check every N seconds
        if [ $((current_time - last_check_time)) -lt $check_interval ]; then
            sleep 2
            continue
        fi
        last_check_time=$current_time

        # Background GPU pod health check (non-blocking)
        check_gpu_pod_health_background &

        # Check if Azure pre-installed drivers (driver daemonset desired=0)
        local driver_daemonset_desired=$(kubectl get daemonset -n gpu-operator nvidia-driver-daemonset -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "-1")

        # Get GPU operator status
        local driver_pods=$(kubectl get pods -n gpu-operator -l app=nvidia-driver-daemonset -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.phase}{" "}{.status.containerStatuses[0].ready}{"\n"}{end}' 2>/dev/null | awk '$2=="Running" && $3=="true"' | wc -l | tr -d ' \n' || echo "0")
        driver_pods=$(echo "$driver_pods" | tr -d ' \n' | grep -o '[0-9]*' || echo "0")

        # Azure pre-installed driver scenario: check GPU capacity directly
        if [ "$driver_daemonset_desired" = "0" ]; then
            local gpu_capacity=$(kubectl get nodes -o json 2>/dev/null | jq -r '.items[] | select(.metadata.labels."nvidia.com/gpu" == "true") | .status.capacity."nvidia.com/gpu" // "0"' 2>/dev/null | awk '{sum += $1} END {print sum+0}')

            if [ "$gpu_capacity" -ge "$gpu_nodes" ] && [ "$gpu_nodes" -gt "0" ]; then
                # Get actual driver version from node labels
                local driver_version=$(kubectl get nodes -l nvidia.com/gpu=true -o jsonpath='{.items[0].metadata.labels.nvidia\.com/cuda\.driver-version\.full}' 2>/dev/null || echo "unknown")

                if [ "$DEBUG_MODE" != true ]; then
                    echo ""
                fi
                echo -e "${GREEN}✅ Azure AKS detected with pre-installed NVIDIA drivers (v$driver_version)${NC}"
                echo -e "${GREEN}✅ $gpu_capacity GPUs available across $gpu_nodes nodes${NC}"
                echo -e "${CYAN}ℹ️  Note: To use custom driver 580+, see: kubernetes/terraform/aks/node-pools.tf${NC}"

                # Clean up temp files
                rm -f /tmp/gpu_critical_pods.count /tmp/gpu_failed_pods.txt 2>/dev/null || true
                return 0
            fi
            # Set driver_pods to gpu_capacity for progress display
            driver_pods=$gpu_capacity
        fi

        # Detect stall and switch monitoring mode
        if detect_gpu_stall "$driver_pods"; then
            if [ "$GPU_MONITORING_MODE" = "normal" ]; then
                GPU_MONITORING_MODE="diagnostic"
                check_interval=10  # Check more frequently in diagnostic mode
                GPU_DIAGNOSTIC_RUN_ONCE=false  # Reset for diagnostic mode
                echo -e "\n${YELLOW}⚠️  GPU driver installation stalled for 5 minutes - enabling diagnostic mode${NC}"
            fi

            # Run deep diagnostics ONCE per stall period
            if [[ "$GPU_DIAGNOSTIC_RUN_ONCE" = false ]]; then
                run_gpu_deep_diagnostics
                GPU_DIAGNOSTIC_RUN_ONCE=true
            fi
        else
            GPU_MONITORING_MODE="normal"
        fi

        # Display based on monitoring mode
        if [ "$DEBUG_MODE" != true ]; then
            case "$GPU_MONITORING_MODE" in
                normal)
                    display_normal_gpu_progress "$driver_pods" "$gpu_nodes" "$elapsed" "$max_timeout"
                    ;;
                diagnostic)
                    local stall_duration=$((current_time - GPU_PROGRESS_LAST_CHANGE_TIME))
                    display_gpu_diagnostic_info "$driver_pods" "$gpu_nodes" "$elapsed" "$stall_duration"
                    ;;
            esac
        elif [ "$DEBUG_MODE" = true ]; then
            echo "   GPU Driver Pods: $driver_pods/$gpu_nodes ready"
        fi

        # Success condition
        if [ "$driver_pods" -ge "$gpu_nodes" ] && [ "$gpu_nodes" -gt "0" ]; then
            local gpu_capacity=$(kubectl get nodes -o json 2>/dev/null | jq -r '.items[] | select(.metadata.labels."nvidia.com/gpu" == "true") | .status.capacity."nvidia.com/gpu" // "0"' 2>/dev/null | awk '{sum += $1} END {print sum+0}')

            if [ "$gpu_capacity" -gt "0" ]; then
                if [ "$DEBUG_MODE" != true ]; then
                    echo ""
                fi
                echo -e "${GREEN}✅ GPU drivers installed on all $gpu_nodes GPU nodes ($gpu_capacity total GPUs available)${NC}"

                # Clean up temp files
                rm -f /tmp/gpu_critical_pods.count /tmp/gpu_failed_pods.txt 2>/dev/null || true
                return 0
            fi
        fi

        sleep 2
    done
}

# =============================================================================
# Adaptive Monitoring Functions (Cluster Provisioning)
# =============================================================================

# Global variables for adaptive monitoring (bash 3.2 compatible)
PROGRESS_LAST=""
PROGRESS_LAST_CHANGE_TIME=0
MONITORING_MODE="normal"

# Check pod health in background (non-blocking)
check_pod_health_background() {
    # Get failed pods across all namespaces
    local failed_pods=$(kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded --no-headers 2>/dev/null)

    # Check for critical failures (CrashLoopBackOff, ImagePullBackOff)
    local critical_crashes=$(echo "$failed_pods" | grep -E "CrashLoopBackOff|ImagePullBackOff|Error|ErrImagePull" | wc -l | tr -d ' \n')

    if [ "$critical_crashes" -gt 0 ]; then
        # Store for diagnostic display
        echo "$critical_crashes" > /tmp/k8s_critical_pods.count 2>/dev/null || true
        echo "$failed_pods" > /tmp/k8s_failed_pods.txt 2>/dev/null || true
    fi
}

# Detect if progress has stalled (bash 3.2 compatible)
detect_stall() {
    local current_progress="$1"
    local current_time
    current_time=$(date +%s)

    # Initialize on first run
    if [[ -z "$PROGRESS_LAST" ]]; then
        PROGRESS_LAST="$current_progress"
        PROGRESS_LAST_CHANGE_TIME=$current_time
        return 1  # Not stalled
    fi

    # Check if progress has changed
    if [[ "$current_progress" != "$PROGRESS_LAST" ]]; then
        PROGRESS_LAST="$current_progress"
        PROGRESS_LAST_CHANGE_TIME=$current_time
        return 1  # Making progress
    fi

    # Same progress - check time elapsed
    local time_diff=$((current_time - PROGRESS_LAST_CHANGE_TIME))
    if [[ $time_diff -ge 300 ]]; then
        return 0  # Stalled (5+ minutes)
    fi

    return 1  # Not stalled
}

# Build progress bar string
build_progress_bar() {
    local progress="$1"
    local progress_bar=""
    local filled=$((progress / 5))

    for ((i=1; i<=20; i++)); do
        if [ $i -le $filled ]; then
            progress_bar+="█"
        else
            progress_bar+="░"
        fi
    done

    echo "$progress_bar"
}

# Display normal progress with periodic status updates
display_normal_progress() {
    local progress="$1"
    local elapsed="$2"
    local max_timeout="$3"
    local cluster_state="$4"
    local system_state="$5"
    local gpu_state="$6"
    local ready_nodes="$7"

    local elapsed_min=$((elapsed / 60))
    local elapsed_sec=$((elapsed % 60))
    local remaining_time=$((max_timeout - elapsed))
    local remaining_min=$((remaining_time / 60))

    # Build progress bar
    local progress_bar=$(build_progress_bar "$progress")

    # Main progress line (always shown)
    echo -ne "\r⏰ Provisioning cluster... [$progress_bar] $progress% (${elapsed_min}m${elapsed_sec}s, ~${remaining_min}m left)    "

    # Show detailed status every 60 seconds
    if [ $((elapsed % 60)) -lt 15 ]; then
        echo ""
        echo "  📊 Status: Cluster=$cluster_state | System=$system_state | GPU=$gpu_state | Nodes=$ready_nodes"
    fi
}

# Display diagnostic information when stalled
display_diagnostic_info() {
    local progress="$1"
    local elapsed="$2"
    local stall_duration="$3"
    local cluster_state="$4"
    local system_state="$5"
    local gpu_state="$6"
    local ready_nodes="$7"

    local elapsed_min=$((elapsed / 60))
    local elapsed_sec=$((elapsed % 60))
    local stall_min=$((stall_duration / 60))
    local stall_sec=$((stall_duration % 60))

    echo -ne "\r🔍 Diagnostic mode: $progress% (${elapsed_min}m${elapsed_sec}s) - Stalled ${stall_min}m${stall_sec}s    "
    echo ""
    echo "  🔴 Cluster: $cluster_state"
    echo "  🔴 System Pool: $system_state"
    echo "  🔴 GPU Pool: $gpu_state"
    echo "  🔴 Kubernetes Nodes: $ready_nodes ready"

    # Show any pod failures
    if [ -f /tmp/k8s_critical_pods.count ]; then
        local critical_count=$(cat /tmp/k8s_critical_pods.count)
        if [ "$critical_count" -gt 0 ]; then
            echo "  ⚠️  Failed pods detected: $critical_count"
            if [ -f /tmp/k8s_failed_pods.txt ]; then
                echo "  📋 Top failed pods:"
                head -3 /tmp/k8s_failed_pods.txt | sed 's/^/    /' 2>/dev/null || true
            fi
        fi
    fi
}

# Run smart diagnostics to identify common issues
run_smart_diagnostics() {
    echo ""
    echo "🔍 Running smart diagnostics..."

    # Get recent events
    local events=$(kubectl get events -A --sort-by='.lastTimestamp' 2>/dev/null | tail -20)

    # Pattern matching for common failures
    local found_issues=false

    # Check for image pull issues
    if echo "$events" | grep -q "ImagePullBackOff\|ErrImagePull"; then
        echo "  💡 Issue: Cannot pull container images"
        echo "     Suggestion: Check Docker registry credentials or network connectivity"
        found_issues=true
    fi

    # Check for scheduling issues
    if echo "$events" | grep -q "FailedScheduling"; then
        echo "  💡 Issue: Pods cannot be scheduled"
        echo "     Suggestion: Check node resources, taints, and pod requirements"
        found_issues=true
    fi

    # Check for network issues
    if echo "$events" | grep -q "NetworkNotReady\|CNI"; then
        echo "  💡 Issue: Network configuration problems"
        echo "     Suggestion: Check Azure CNI configuration and subnet capacity"
        found_issues=true
    fi

    # Check for volume mount issues
    if echo "$events" | grep -q "FailedMount\|VolumeMount"; then
        echo "  💡 Issue: Volume mounting failures"
        echo "     Suggestion: Check persistent volume claims and storage classes"
        found_issues=true
    fi

    if [ "$found_issues" = false ]; then
        echo "  ℹ️  No obvious issues detected - cluster may just need more time"
        echo "     Tip: Use --debug flag for more detailed output"
    fi

    echo ""
}

# Wait for AKS cluster to be fully ready with adaptive monitoring
wait_for_cluster_ready_azure() {
    local cluster_name="$1"
    local resource_group="$2"
    local max_timeout="${3:-1800}"  # 30 min default

    echo "⏰ Waiting for cluster to be fully provisioned..."
    echo "   Maximum wait time: $((max_timeout/60)) minutes"
    echo ""

    local start_time=$(date +%s)
    local last_check_time=0
    local check_interval=15

    # Clean up old temp files
    rm -f /tmp/k8s_critical_pods.count /tmp/k8s_failed_pods.txt 2>/dev/null || true

    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        # Check timeout
        if [ $elapsed -ge $max_timeout ]; then
            echo -e "\n${RED}❌ Timeout waiting for cluster after $((max_timeout/60)) minutes${NC}"
            return 1
        fi

        # Only check every N seconds
        if [ $((current_time - last_check_time)) -lt $check_interval ]; then
            sleep 2
            continue
        fi
        last_check_time=$current_time

        # Background pod health check (non-blocking)
        check_pod_health_background &

        # Get cluster provisioning state
        local cluster_state=$(az aks show --name "$cluster_name" --resource-group "$resource_group" --query "provisioningState" -o tsv 2>/dev/null || echo "Unknown")

        # Get node pool states
        local system_pool_state=$(az aks nodepool show --cluster-name "$cluster_name" --resource-group "$resource_group" --name "system" --query "provisioningState" -o tsv 2>/dev/null || echo "Unknown")
        local gpu_pool_state=$(az aks nodepool show --cluster-name "$cluster_name" --resource-group "$resource_group" --name "rennygpu" --query "provisioningState" -o tsv 2>/dev/null || echo "Unknown")

        # Get ready nodes count
        local ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" 2>/dev/null || echo "0")
        ready_nodes=$(echo "$ready_nodes" | tr -d ' \n' | grep -o '[0-9]*' || echo "0")

        # Calculate progress percentage
        local progress=0
        if [ "$cluster_state" = "Succeeded" ]; then progress=$((progress + 33)); fi
        if [ "$system_pool_state" = "Succeeded" ]; then progress=$((progress + 33)); fi
        if [ "$gpu_pool_state" = "Succeeded" ]; then progress=$((progress + 34)); fi

        # Detect stall and switch monitoring mode
        if detect_stall "$progress"; then
            if [ "$MONITORING_MODE" = "normal" ]; then
                MONITORING_MODE="diagnostic"
                check_interval=10  # Check more frequently in diagnostic mode
                echo -e "\n${YELLOW}⚠️  Progress stalled for 5 minutes - enabling diagnostic mode${NC}"
                run_smart_diagnostics
            fi
        else
            MONITORING_MODE="normal"
        fi

        # Display based on monitoring mode
        if [ "$DEBUG_MODE" != true ]; then
            case "$MONITORING_MODE" in
                normal)
                    display_normal_progress "$progress" "$elapsed" "$max_timeout" "$cluster_state" "$system_pool_state" "$gpu_pool_state" "$ready_nodes"
                    ;;
                diagnostic)
                    local stall_duration=$((current_time - PROGRESS_LAST_CHANGE_TIME))
                    display_diagnostic_info "$progress" "$elapsed" "$stall_duration" "$cluster_state" "$system_pool_state" "$gpu_pool_state" "$ready_nodes"
                    ;;
            esac
        elif [ "$DEBUG_MODE" = true ]; then
            echo "   Cluster: $cluster_state | System Pool: $system_pool_state | GPU Pool: $gpu_pool_state | Nodes: $ready_nodes"
        fi

        # Success condition: all components ready
        if [ "$cluster_state" = "Succeeded" ] && [ "$system_pool_state" = "Succeeded" ] && [ "$gpu_pool_state" = "Succeeded" ]; then
            # Wait for nodes to register with Kubernetes (if not already)
            if [ "$ready_nodes" -eq 0 ]; then
                local attempts=0
                while [ "$ready_nodes" -eq 0 ] && [ "$attempts" -lt 30 ]; do
                    ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" 2>/dev/null || echo "0")
                    ready_nodes=$(echo "$ready_nodes" | tr -d ' \n' | grep -o '[0-9]*' || echo "0")
                    if [ "$ready_nodes" -eq 0 ]; then
                        sleep 10
                        ((attempts++))
                    fi
                done
            fi

            if [ "$DEBUG_MODE" != true ]; then
                echo ""
            fi
            echo -e "${GREEN}✅ Cluster fully provisioned with $ready_nodes ready nodes${NC}"

            # Clean up temp files
            rm -f /tmp/k8s_critical_pods.count /tmp/k8s_failed_pods.txt 2>/dev/null || true
            return 0
        fi

        sleep 2
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
    if ! terraform plan -var="deployment_id=$DEPLOYMENT_ID" -out=tfplan 2>&1; then
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

    if ! az aks get-credentials --resource-group "$rg" --name "$cluster" --admin --overwrite-existing 2>&1; then
        echo -e "${RED}❌ Failed to get AKS credentials${NC}"
        return 1
    fi

    # Fix kubeconfig permissions (security best practice)
    chmod 600 ~/.kube/config 2>/dev/null || true
    echo -e "${GREEN}✅ Kubectl configured for cluster: $cluster (admin credentials)${NC}"
    echo -e "${GREEN}✅ Kubeconfig permissions secured (600)${NC}"

    # Wait for cluster to be ready with progress bar (system node pool only)
    echo ""
    echo "⏳ Waiting for system node pool to be ready..."
    sleep 30  # Give system pool time to initialize

    # Create GPU node pool with --gpu-driver None
    echo ""
    echo "🎮 Creating GPU node pool with driver 580+ support..."
    echo ""

    # Get configuration from terraform.tfvars using Terraform's own parser (more robust than AWK)
    cd "$TERRAFORM_DIR"
    local renny_min_size=$(echo "var.renny_min_size" | terraform console 2>/dev/null | tr -d '"' || echo "2")
    local renny_max_size=$(echo "var.renny_max_size" | terraform console 2>/dev/null | tr -d '"' || echo "4")
    local renny_desired_size=$(echo "var.renny_desired_size" | terraform console 2>/dev/null | tr -d '"' || echo "2")
    local renny_vm_size=$(echo "var.renny_vm_size" | terraform console 2>/dev/null | tr -d '"' || echo "Standard_NC16as_T4_v3")

    echo "  VM Size: $renny_vm_size"
    echo "  Node Count: $renny_desired_size (min: $renny_min_size, max: $renny_max_size)"
    echo "  GPU Driver: None (GPU Operator will install driver 580+)"
    echo ""

    # Check if node pool already exists
    local nodepool_exists=$(az aks nodepool show --cluster-name "$cluster" --resource-group "$rg" --name "rennygpu" --query "name" -o tsv 2>/dev/null || echo "")

    if [ -n "$nodepool_exists" ]; then
        echo -e "${CYAN}ℹ️  GPU node pool 'rennygpu' already exists - skipping creation${NC}"
    else
        echo "Creating GPU node pool (this will take 5-10 minutes)..."

        if ! az aks nodepool add \
            --resource-group "$rg" \
            --cluster-name "$cluster" \
            --name "rennygpu" \
            --node-count "$renny_desired_size" \
            --min-count "$renny_min_size" \
            --max-count "$renny_max_size" \
            --enable-cluster-autoscaler \
            --gpu-driver None \
            --node-vm-size "$renny_vm_size" \
            --node-taints "nvidia.com/gpu=true:NoSchedule" \
            --labels "uneeq.io/node-type=renny" "workload-type=gpu" "nvidia.com/gpu=true" \
            --node-osdisk-size 256 \
            --no-wait 2>&1; then
            echo -e "${RED}❌ Failed to create GPU node pool${NC}"
            echo ""
            echo "Troubleshooting:"
            echo "  1. Check GPU quota: az vm list-usage --location $AZURE_REGION | grep NCasT4_v3"
            echo "  2. Verify aks-preview extension: az extension list | grep aks-preview"
            echo "  3. Check Azure CLI version: az version (need 2.72.2+)"
            return 1
        fi

        echo -e "${GREEN}✅ GPU node pool creation initiated${NC}"
        echo ""
        echo "⏳ Waiting for GPU node pool to be ready..."

        # Wait for node pool to be ready
        local attempts=0
        local max_attempts=60
        while [ $attempts -lt $max_attempts ]; do
            local pool_state=$(az aks nodepool show --cluster-name "$cluster" --resource-group "$rg" --name "rennygpu" --query "provisioningState" -o tsv 2>/dev/null || echo "Unknown")

            if [ "$pool_state" = "Succeeded" ]; then
                echo -e "${GREEN}✅ GPU node pool ready${NC}"
                break
            elif [ "$pool_state" = "Failed" ]; then
                echo -e "${RED}❌ GPU node pool creation failed${NC}"
                return 1
            else
                echo -ne "\r   Node pool status: $pool_state (attempt $((attempts + 1))/$max_attempts)"
                sleep 10
                ((attempts++))
            fi
        done

        if [ $attempts -ge $max_attempts ]; then
            echo -e "\n${YELLOW}⚠️  Timeout waiting for GPU node pool, but continuing...${NC}"
        fi
    fi

    echo ""
    echo -e "${GREEN}✅ Infrastructure deployment complete${NC}"
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
    # Note: driver.version not specified - GPU Operator will automatically select
    # the latest compatible NVIDIA driver (580+ series) for the hardware
    if ! helm upgrade --install gpu-operator nvidia/gpu-operator \
        --namespace gpu-operator \
        --set driver.enabled=true \
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

    local helm_chart_dir="$KUBERNETES_DIR/renny"
    local values_file="$KUBERNETES_DIR/values/renny-values.yaml"

    # Validate prerequisites
    if [ ! -f "$values_file" ]; then
        echo -e "${RED}❌ Values file not found: $values_file${NC}"
        return 1
    fi

    if [ ! -d "$helm_chart_dir" ]; then
        echo -e "${RED}❌ Helm chart directory not found: $helm_chart_dir${NC}"
        echo "Expected location: $helm_chart_dir"
        return 1
    fi

    # Create namespace
    echo "📦 Creating Kubernetes namespace..."
    if ! kubectl create namespace uneeq-renderer --dry-run=client -o yaml | kubectl apply -f - 2>&1; then
        echo -e "${RED}❌ Failed to create namespace${NC}"
        return 1
    fi

    # Extract Docker credentials from terraform.tfvars
    echo "🔑 Setting up Docker registry credentials..."
    local docker_user docker_pass

    # Try to extract Docker credentials - more robust parsing
    docker_user=$(grep "docker_username" "$TERRAFORM_DIR/terraform.tfvars" 2>/dev/null | grep -oP '"\K[^"]+' | head -1)
    docker_pass=$(grep "docker_password" "$TERRAFORM_DIR/terraform.tfvars" 2>/dev/null | grep -oP '"\K[^"]+' | head -1)

    if [ -z "$docker_user" ] || [ -z "$docker_pass" ]; then
        echo -e "${YELLOW}⚠️  Docker credentials not found in terraform.tfvars, using placeholder${NC}"
        docker_user="${docker_user:-docker-user}"
        docker_pass="${docker_pass:-docker-pass}"
    fi

    # Create Docker registry secret
    if ! kubectl create secret docker-registry regcred \
        --docker-server=https://index.docker.io/v1/ \
        --docker-username="$docker_user" \
        --docker-password="$docker_pass" \
        --namespace=uneeq-renderer \
        --dry-run=client -o yaml | kubectl apply -f - 2>&1; then
        echo -e "${RED}❌ Failed to create Docker registry secret${NC}"
        return 1
    fi

    # Deploy Renny using Helm chart (MUST use Helm - not kubectl apply)
    echo ""
    echo "🚀 Deploying Renny application with Helm..."

    if ! helm upgrade --install renny "$helm_chart_dir" \
        --namespace uneeq-renderer \
        --values "$values_file" \
        --timeout 25m \
        --wait 2>&1; then
        echo -e "${RED}❌ Helm deployment failed${NC}"
        echo ""
        echo "Debugging information:"
        kubectl get pods -n uneeq-renderer -o wide 2>/dev/null || true
        kubectl describe deployment renny -n uneeq-renderer 2>/dev/null || true
        return 1
    fi

    echo -e "${GREEN}✅ Helm deployment successful${NC}"

    # Wait for pods to be ready with extended timeout and better validation
    echo ""
    echo "⏳ Waiting for Renny pods to be ready..."

    local ready_pods=0
    local total_pods=0
    local attempts=0
    local max_attempts=120  # 20 minutes (120 * 10 seconds)

    # Get expected replicas from deployment
    local get_attempts=0
    while [ $get_attempts -lt 30 ] && [ $total_pods -eq 0 ]; do
        total_pods=$(kubectl get deployment renny -n uneeq-renderer -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
        if [ "$total_pods" -eq 0 ]; then
            sleep 5
            ((get_attempts++))
        fi
    done

    if [ $total_pods -eq 0 ]; then
        total_pods=$(grep "totalReplicas:" "$values_file" 2>/dev/null | awk '{print $2}' || echo "2")
    fi

    attempts=0
    while [ $ready_pods -lt $total_pods ] && [ $attempts -lt $max_attempts ]; do
        ready_pods=$(kubectl get pods -n uneeq-renderer -l app=renny --no-headers 2>/dev/null | awk '$3 == "Running"' | wc -l)
        local pod_count=$(kubectl get pods -n uneeq-renderer -l app=renny --no-headers 2>/dev/null | wc -l)

        if [ "$DEBUG_MODE" != true ]; then
            echo -ne "\r   Renny pods ready: $ready_pods/$total_pods (total created: $pod_count)"
        fi

        if [ $ready_pods -lt $total_pods ]; then
            sleep 10
            ((attempts++))
        else
            break
        fi
    done

    if [ "$DEBUG_MODE" != true ]; then
        echo ""
    fi

    # Final validation - MUST return error if pods didn't deploy
    if [ $ready_pods -ge $total_pods ] && [ $ready_pods -gt 0 ]; then
        echo -e "${GREEN}✅ All Renny pods are ready ($ready_pods/$total_pods)${NC}"
        return 0
    else
        echo -e "${RED}❌ Deployment FAILED: Only $ready_pods/$total_pods Renny pods are running (expected $total_pods)${NC}"
        echo ""
        echo "Pod status:"
        kubectl get pods -n uneeq-renderer -l app=renny -o wide 2>/dev/null || true
        echo ""
        echo "Pod events:"
        kubectl describe pods -n uneeq-renderer -l app=renny 2>/dev/null | grep -A 5 "Events:" || true
        echo ""
        echo "Troubleshooting:"
        echo "  1. Check pod logs: kubectl logs -n uneeq-renderer -l app=renny --all-containers=true"
        echo "  2. Check deployment status: kubectl describe deployment renny -n uneeq-renderer"
        echo "  3. Check resource availability: kubectl describe nodes"
        echo "  4. Check namespace events: kubectl get events -n uneeq-renderer"
        return 1
    fi
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
    local renny_pods=$(kubectl get pods -n uneeq-renderer -l app=renny --no-headers 2>/dev/null | awk '$3 == "Running"' | wc -l || echo "0")
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
        az aks get-credentials --resource-group "$RESOURCE_GROUP_NAME" --name "$CLUSTER_NAME" --admin --overwrite-existing
        chmod 600 ~/.kube/config 2>/dev/null || true
        echo -e "${GREEN}✅ Kubeconfig permissions secured (600)${NC}"
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

    # Deploy Renny application (MUST succeed before continuing)
    if ! deploy_renny_application; then
        echo -e "${RED}❌ Renny application deployment FAILED - aborting deployment${NC}"
        echo ""
        echo "The cluster infrastructure is running but Renny pods could not be deployed."
        echo "To troubleshoot:"
        echo "  1. Run: kubectl get pods -n uneeq-renderer -o wide"
        echo "  2. Run: kubectl describe deployment renny -n uneeq-renderer"
        echo "  3. Check pod logs: kubectl logs -n uneeq-renderer -l app=renny"
        echo ""
        echo "To retry deployment:"
        echo "  1. Ensure renny-values.yaml is configured correctly"
        echo "  2. Ensure docker credentials are in terraform.tfvars"
        echo "  3. Run this script again"
        exit 1
    fi

    # Setup monitoring (optional - don't fail if this has issues)
    if ! setup_monitoring; then
        echo -e "${YELLOW}⚠️  Monitoring setup had issues, but continuing...${NC}"
    fi

    # Show summary
    show_deployment_summary

    return 0
}

# Run main function
main "$@"
