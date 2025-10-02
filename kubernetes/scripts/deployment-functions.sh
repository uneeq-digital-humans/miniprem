#!/bin/bash

# Deployment ID Management Functions
# Source this file in other scripts: source "$(dirname "$0")/deployment-functions.sh"

set -euo pipefail

# Colors for output (only set if not already defined)
if [ -z "${RED:-}" ]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly CYAN='\033[0;36m'
    readonly NC='\033[0m' # No Color
fi

# Configuration
readonly DEPLOYMENT_ID_FILE=".deployment_id"
# Directory variables (only set if not already defined)
if [ -z "${SCRIPT_DIR:-}" ]; then
    readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
if [ -z "${PROJECT_DIR:-}" ]; then
    readonly PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi
if [ -z "${KUBERNETES_DIR:-}" ]; then
    readonly KUBERNETES_DIR="$PROJECT_DIR/kubernetes"
fi
if [ -z "${TERRAFORM_DIR:-}" ]; then
    readonly TERRAFORM_DIR="$PROJECT_DIR/kubernetes/terraform"
fi

# Global variables (set by functions)
PROJECT_NAME=""
ENVIRONMENT=""
DEPLOYMENT_ID=""
CLUSTER_NAME=""
AWS_REGION=""

# Generate a deployment ID
generate_deployment_id() {
    local method="${1:-auto}"
    
    case "$method" in
        "git")
            if git rev-parse --git-dir >/dev/null 2>&1; then
                git rev-parse --short HEAD 2>/dev/null || echo ""
            else
                echo ""
            fi
            ;;
        "timestamp")
            date +"%Y%m%d-%H%M%S"
            ;;
        "auto"|*)
            local git_id
            git_id=$(generate_deployment_id "git")
            if [ -n "$git_id" ]; then
                echo "$git_id"
            else
                generate_deployment_id "timestamp"
            fi
            ;;
    esac
}

# Validate deployment ID format
validate_deployment_id() {
    local id="$1"
    if [[ "$id" =~ ^[a-z0-9-]+$ ]]; then
        return 0
    else
        echo -e "${RED}Error: Deployment ID must contain only lowercase letters, numbers, and hyphens${NC}" >&2
        return 1
    fi
}

# Get AWS region from terraform.tfvars (single source of truth)
# Usage: get_aws_region [terraform_dir]
get_aws_region() {
    local terraform_dir="${1:-terraform}"
    local original_dir="$(pwd)"
    
    # Navigate to terraform directory (handle both relative and absolute paths)
    if [[ "$terraform_dir" = /* ]]; then
        cd "$terraform_dir" 2>/dev/null || {
            echo -e "${RED}Error: Cannot access terraform directory: $terraform_dir${NC}" >&2
            return 1
        }
    else
        cd "$PROJECT_DIR/$terraform_dir" 2>/dev/null || cd "$terraform_dir" 2>/dev/null || {
            echo -e "${RED}Error: Cannot find terraform.tfvars. Please ensure you're running from the correct directory.${NC}" >&2
            echo "Expected location: $PROJECT_DIR/$terraform_dir/terraform.tfvars" >&2
            return 1
        }
    fi
    
    # Check if terraform.tfvars exists
    if [ ! -f "terraform.tfvars" ]; then
        echo -e "${RED}Error: terraform.tfvars not found${NC}" >&2
        echo "Please create terraform.tfvars with aws_region = \"your-region\"" >&2
        cd "$original_dir"
        return 1
    fi
    
    # Extract region from terraform.tfvars
    local aws_region
    aws_region=$(awk '/^aws_region[[:space:]]*=/ {gsub(/[" ]/, "", $3); print $3}' terraform.tfvars 2>/dev/null)
    
    cd "$original_dir"
    
    # Validate region is set
    if [ -z "$aws_region" ] || [ "$aws_region" = "null" ]; then
        echo -e "${RED}Error: aws_region not set in terraform.tfvars${NC}" >&2
        echo "Please add: aws_region = \"us-east-2\"  (or your preferred region)" >&2
        echo "terraform.tfvars should be the single source of truth for AWS region configuration." >&2
        return 1
    fi
    
    echo "$aws_region"
    return 0
}

# Load configuration from terraform.tfvars
load_terraform_config() {
    cd "$TERRAFORM_DIR"
    
    if [ ! -f "terraform.tfvars" ]; then
        echo -e "${RED}Error: terraform.tfvars not found in $TERRAFORM_DIR${NC}" >&2
        return 1
    fi
    
    # Parse terraform.tfvars
    PROJECT_NAME=$(awk '/^project_name[[:space:]]*=/ {gsub(/[" ]/, "", $3); print $3}' terraform.tfvars 2>/dev/null || echo "renny")
    ENVIRONMENT=$(awk '/^environment[[:space:]]*=/ {gsub(/[" ]/, "", $3); print $3}' terraform.tfvars 2>/dev/null || echo "production")
    # Read AWS region directly since we're already in terraform directory
    AWS_REGION=$(awk '/^aws_region[[:space:]]*=/ {gsub(/[" ]/, "", $3); print $3}' terraform.tfvars 2>/dev/null)
    if [ -z "$AWS_REGION" ] || [ "$AWS_REGION" = "null" ]; then
        echo -e "${RED}Error: aws_region not set in terraform.tfvars${NC}" >&2
        echo "Please add: aws_region = \"us-east-2\"  (or your preferred region)" >&2
        echo "terraform.tfvars should be the single source of truth for AWS region configuration." >&2
        return 1
    fi
    
    # Check if deployment_id is already set in terraform.tfvars
    local tfvars_deployment_id
    tfvars_deployment_id=$(awk '/^deployment_id[[:space:]]*=/ {gsub(/[" ]/, "", $3); print $3}' terraform.tfvars 2>/dev/null || echo "")
    
    if [ -n "$tfvars_deployment_id" ]; then
        DEPLOYMENT_ID="$tfvars_deployment_id"
    fi
}

# Save deployment ID to persistent storage
save_deployment_id() {
    local id="$1"
    echo "$id" > "$PROJECT_DIR/$DEPLOYMENT_ID_FILE"

    # Also update terraform.tfvars
    cd "$TERRAFORM_DIR"
    if grep -q "^deployment_id[[:space:]]*=" terraform.tfvars; then
        # Update existing line
        sed -i.bak "s/^deployment_id[[:space:]]*=.*/deployment_id = \"$id\"/" terraform.tfvars
    else
        # Add new line with proper newline
        echo "" >> terraform.tfvars
        echo "deployment_id = \"$id\"" >> terraform.tfvars
    fi
}

# Load deployment ID from persistent storage
load_deployment_id() {
    if [ -f "$PROJECT_DIR/$DEPLOYMENT_ID_FILE" ]; then
        local file_id
        file_id=$(cat "$PROJECT_DIR/$DEPLOYMENT_ID_FILE" 2>/dev/null | tr -d '\\n\\r\\s' || echo "")
        if [ -n "$file_id" ]; then
            DEPLOYMENT_ID="$file_id"
            return 0
        fi
    fi
    return 1
}

# List existing deployments in AWS
list_existing_deployments() {
    local base_name="$PROJECT_NAME-$ENVIRONMENT"
    
    echo -e "${BLUE}🔍 Scanning for existing deployments...${NC}"
    
    # Get all EKS clusters with our base name pattern
    local clusters
    clusters=$(aws eks list-clusters --region "$AWS_REGION" --query "clusters[?contains(@, '$base_name')]" --output text 2>/dev/null || echo "")
    
    if [ -z "$clusters" ]; then
        echo -e "${GREEN}No existing deployments found${NC}"
        return 1
    fi
    
    echo -e "${CYAN}Found existing deployments:${NC}"
    local count=0
    for cluster in $clusters; do
        count=$((count + 1))
        local status
        status=$(aws eks describe-cluster --name "$cluster" --region "$AWS_REGION" --query 'cluster.status' --output text 2>/dev/null || echo "UNKNOWN")
        
        local created
        created=$(aws eks describe-cluster --name "$cluster" --region "$AWS_REGION" --query 'cluster.createdAt' --output text 2>/dev/null || echo "")
        if [ -n "$created" ]; then
            created=$(date -d "$created" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$created")
        fi
        
        # Extract deployment ID if present
        local deployment_id=""
        if [[ "$cluster" =~ ^${base_name}-(.+)$ ]]; then
            deployment_id="${BASH_REMATCH[1]}"
        fi
        
        printf "  %d) %s\\n" "$count" "$cluster"
        printf "     Status: %s | Created: %s\\n" "$status" "${created:-unknown}"
        if [ -n "$deployment_id" ]; then
            printf "     Deployment ID: %s\\n" "$deployment_id"
        else
            printf "     %sLegacy deployment (no deployment ID)%s\\n" "$YELLOW" "$NC"
        fi
        echo ""
    done
    
    return 0
}

# Interactive deployment selection
select_deployment_action() {
    local base_name="$PROJECT_NAME-$ENVIRONMENT"
    
    if ! list_existing_deployments; then
        # No existing deployments
        echo -e "${GREEN}✨ This will be a fresh deployment${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}What would you like to do?${NC}"
    echo "1) Create new deployment with fresh ID"
    echo "2) Update existing deployment (reuse existing resources)"
    echo "3) List all deployments and choose one"
    echo "4) Cancel"
    echo ""
    
    while true; do
        read -p "Enter choice (1-4): " choice
        case "$choice" in
            1)
                echo -e "${GREEN}✨ Creating new deployment${NC}"
                return 0
                ;;
            2)
                # Find most recent deployment
                local latest_cluster
                latest_cluster=$(aws eks list-clusters --region "$AWS_REGION" --query "clusters[?contains(@, '$base_name')]" --output text 2>/dev/null | head -1)
                if [ -n "$latest_cluster" ]; then
                    if [[ "$latest_cluster" =~ ^${base_name}-(.+)$ ]]; then
                        DEPLOYMENT_ID="${BASH_REMATCH[1]}"
                        echo -e "${GREEN}🔄 Updating existing deployment: $latest_cluster${NC}"
                        save_deployment_id "$DEPLOYMENT_ID"
                        return 0
                    else
                        # Legacy deployment without ID
                        DEPLOYMENT_ID=""
                        echo -e "${YELLOW}🔄 Updating legacy deployment: $latest_cluster${NC}"
                        return 0
                    fi
                else
                    echo -e "${RED}Error: No deployments found${NC}"
                fi
                ;;
            3)
                select_specific_deployment
                return $?
                ;;
            4)
                echo -e "${YELLOW}Cancelled${NC}"
                exit 0
                ;;
            *)
                echo "Invalid choice. Please enter 1-4."
                ;;
        esac
    done
}

# Select specific deployment from list
select_specific_deployment() {
    local base_name="$PROJECT_NAME-$ENVIRONMENT"
    local clusters
    clusters=$(aws eks list-clusters --region "$AWS_REGION" --query "clusters[?contains(@, '$base_name')]" --output text 2>/dev/null || echo "")
    
    if [ -z "$clusters" ]; then
        echo -e "${RED}No deployments found${NC}"
        return 1
    fi
    
    # Convert to array
    local cluster_array=($clusters)
    local count=${#cluster_array[@]}
    
    echo -e "${CYAN}Available deployments:${NC}"
    for i in "${!cluster_array[@]}"; do
        local cluster="${cluster_array[$i]}"
        local status
        status=$(aws eks describe-cluster --name "$cluster" --region "$AWS_REGION" --query 'cluster.status' --output text 2>/dev/null || echo "UNKNOWN")
        printf "  %d) %s (%s)\\n" "$((i + 1))" "$cluster" "$status"
    done
    echo "  $((count + 1))) Cancel"
    echo ""
    
    while true; do
        read -p "Select deployment (1-$((count + 1))): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le $((count + 1)) ]; then
            if [ "$choice" -eq $((count + 1)) ]; then
                echo -e "${YELLOW}Cancelled${NC}"
                exit 0
            else
                local selected_cluster="${cluster_array[$((choice - 1))]}"
                echo -e "${GREEN}Selected: $selected_cluster${NC}"
                
                # Extract deployment ID
                if [[ "$selected_cluster" =~ ^${base_name}-(.+)$ ]]; then
                    DEPLOYMENT_ID="${BASH_REMATCH[1]}"
                    save_deployment_id "$DEPLOYMENT_ID"
                else
                    # Legacy deployment
                    DEPLOYMENT_ID=""
                fi
                
                return 0
            fi
        else
            echo "Invalid choice. Please enter a number between 1 and $((count + 1))."
        fi
    done
}

# Initialize deployment configuration
init_deployment_config() {
    local force_new="${1:-false}"
    local provided_id="${2:-}"
    
    echo -e "${BLUE}🚀 Initializing deployment configuration...${NC}"
    
    # Load terraform configuration
    load_terraform_config
    
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
        # Force new deployment
        DEPLOYMENT_ID=$(generate_deployment_id)
        save_deployment_id "$DEPLOYMENT_ID"
        echo -e "${GREEN}✅ Generated new deployment ID: $DEPLOYMENT_ID${NC}"
    else
        # Try to load existing deployment ID
        if load_deployment_id; then
            echo -e "${GREEN}✅ Loaded existing deployment ID: $DEPLOYMENT_ID${NC}"
        else
            # No existing deployment ID, check for existing infrastructure
            select_deployment_action
            
            # If still no deployment ID, generate one
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
    
    # Export variables for use by calling script
    export PROJECT_NAME ENVIRONMENT DEPLOYMENT_ID CLUSTER_NAME AWS_REGION
    
    echo -e "${CYAN}Configuration:${NC}"
    echo "  Project: $PROJECT_NAME"
    echo "  Environment: $ENVIRONMENT"
    echo "  Deployment ID: ${DEPLOYMENT_ID:-'(legacy)'}"
    echo "  Cluster Name: $CLUSTER_NAME"
    echo "  Region: $AWS_REGION"
}

# Cleanup deployment ID (for destroy operations)
cleanup_deployment_id() {
    if [ -f "$PROJECT_DIR/$DEPLOYMENT_ID_FILE" ]; then
        rm -f "$PROJECT_DIR/$DEPLOYMENT_ID_FILE"
        echo -e "${GREEN}✅ Cleaned up deployment ID file${NC}"
    fi
    
    # Reset deployment_id in terraform.tfvars
    cd "$TERRAFORM_DIR"
    if grep -q "^deployment_id[[:space:]]*=" terraform.tfvars; then
        sed -i.bak 's/^deployment_id[[:space:]]*=.*/deployment_id = ""/' terraform.tfvars
    fi
    echo -e "${GREEN}✅ Reset deployment ID in terraform.tfvars${NC}"
}

# List all deployments for management
list_all_deployments() {
    local base_name="$PROJECT_NAME-$ENVIRONMENT"
    
    echo -e "${BLUE}📋 All deployments for $base_name:${NC}"
    echo ""
    
    local clusters
    clusters=$(aws eks list-clusters --region "$AWS_REGION" --query "clusters[?contains(@, '$base_name')]" --output text 2>/dev/null || echo "")
    
    if [ -z "$clusters" ]; then
        echo -e "${YELLOW}No deployments found${NC}"
        return 1
    fi
    
    # Sort clusters by creation time (newest first)
    local sorted_clusters=()
    while IFS= read -r cluster; do
        if [ -n "$cluster" ]; then
            sorted_clusters+=("$cluster")
        fi
    done < <(printf '%s\\n' $clusters | while read -r cluster; do
        if [ -n "$cluster" ]; then
            local created
            created=$(aws eks describe-cluster --name "$cluster" --region "$AWS_REGION" --query 'cluster.createdAt' --output text 2>/dev/null || echo "")
            printf '%s %s\\n' "$created" "$cluster"
        fi
    done | sort -r | cut -d' ' -f2-)
    
    for cluster in "${sorted_clusters[@]}"; do
        if [ -n "$cluster" ]; then
            local status
            status=$(aws eks describe-cluster --name "$cluster" --region "$AWS_REGION" --query 'cluster.status' --output text 2>/dev/null || echo "UNKNOWN")
            
            local created
            created=$(aws eks describe-cluster --name "$cluster" --region "$AWS_REGION" --query 'cluster.createdAt' --output text 2>/dev/null || echo "")
            if [ -n "$created" ]; then
                created=$(date -d "$created" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$created")
            fi
            
            # Check node group status
            local node_groups
            node_groups=$(aws eks list-nodegroups --cluster-name "$cluster" --region "$AWS_REGION" --query 'length(nodegroups)' --output text 2>/dev/null || echo "0")
            
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
            printf "  Status: %s | Created: %s | Node Groups: %s\\n" "$status" "${created:-unknown}" "$node_groups"
            if [ -n "$deployment_id" ]; then
                printf "  Type: %s | Deployment ID: %s\\n" "$cluster_type" "$deployment_id"
            else
                printf "  Type: %s%s%s (no deployment ID)\\n" "$YELLOW" "$cluster_type" "$NC"
            fi
            
            # Estimate costs (simplified)
            if [ "$status" = "ACTIVE" ]; then
                printf "  %sACTIVE - Incurring costs%s\\n" "$GREEN" "$NC"
            elif [ "$status" = "CREATING" ] || [ "$status" = "UPDATING" ]; then
                printf "  %sIN PROGRESS%s\\n" "$YELLOW" "$NC"
            else
                printf "  %sNOT ACTIVE%s\\n" "$RED" "$NC"
            fi
            echo ""
        fi
    done
    
    return 0
}

# Utility function to wait for user confirmation
confirm_action() {
    local message="$1"
    local default="${2:-n}"
    
    if [ "$default" = "y" ]; then
        read -p "$message [Y/n]: " -n 1 -r
    else
        read -p "$message [y/N]: " -n 1 -r
    fi
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 0
    elif [[ $REPLY =~ ^[Nn]$ ]]; then
        return 1
    else
        # Use default
        if [ "$default" = "y" ]; then
            return 0
        else
            return 1
        fi
    fi
}