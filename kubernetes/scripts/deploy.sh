#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Parse command line arguments
AWS_PROFILE_ARG=""
SKIP_PROFILE_CHECK=false
DEBUG_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --profile)
            AWS_PROFILE_ARG="$2"
            shift 2
            ;;
        --skip-profile-check)
            SKIP_PROFILE_CHECK=true
            shift
            ;;
        --debug)
            DEBUG_MODE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --profile PROFILE_NAME    Use specific AWS profile"
            echo "  --skip-profile-check      Skip AWS profile confirmation"
            echo "  --debug                   Enable verbose debug output"
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

echo "🚀 Starting Renny EKS Deployment..."

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

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"

# Function to show elapsed time
show_elapsed() {
    local current_time=$(date +%s)
    local elapsed=$((current_time - START_TIME))
    local elapsed_min=$((elapsed / 60))
    local elapsed_sec=$((elapsed % 60))
    echo "Elapsed time: ${elapsed_min}m ${elapsed_sec}s"
}

# Adaptive waiting for cluster nodes to be ready
wait_for_cluster_nodes_ready() {
    local max_timeout="${1:-1800}"  # Default 30 minutes
    local start_time=$(date +%s)
    local last_status=""
    local expected_nodes=14  # 2 control + 10 renny + 2 a2f
    
    echo "⏰ Maximum wait time: $((max_timeout/60)) minutes"
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ $elapsed -ge $max_timeout ]; then
            echo -e "${RED}❌ Timeout waiting for cluster nodes after $((max_timeout/60)) minutes${NC}"
            kubectl get nodes -o wide
            echo "Recent events:"
            kubectl get events --sort-by='.lastTimestamp' | tail -10
            return 1
        fi
        
        # Get node status with error handling
        local nodes_output
        if ! nodes_output=$(kubectl get nodes --no-headers 2>/dev/null); then
            debug_log "Waiting for kubectl connectivity..."
            sleep 15
            continue
        fi
        
        local ready_nodes=$(echo "$nodes_output" | grep -c " Ready " || echo "0")
        local total_nodes=$(echo "$nodes_output" | wc -l || echo "0")
        local not_ready=$(echo "$nodes_output" | grep -c " NotReady " || echo "0")
        
        # Status summary
        local current_status="Ready: $ready_nodes/$total_nodes | NotReady: $not_ready"
        
        # Show status updates and progress
        if [ "$current_status" != "$last_status" ] || [ $((elapsed % 30)) -eq 0 ]; then
            local elapsed_min=$((elapsed / 60))
            local elapsed_sec=$((elapsed % 60))
            local remaining_time=$((max_timeout - elapsed))
            local remaining_min=$((remaining_time / 60))
            
            if [ "$DEBUG_MODE" = true ]; then
                debug_log "⏳ ${elapsed_min}m${elapsed_sec}s - $current_status (${remaining_min}m remaining)"
                if [ "$not_ready" -gt "0" ]; then
                    debug_log "NotReady nodes:"
                    echo "$nodes_output" | grep " NotReady " | head -3
                fi
            else
                # Progress bar for normal mode
                local progress=0
                if [ "$expected_nodes" -gt "0" ]; then
                    progress=$((ready_nodes * 100 / expected_nodes))
                    if [ $progress -gt 100 ]; then progress=100; fi
                fi
                
                local progress_bar=""
                local filled=$((progress / 5))  # 20-character bar
                for ((i=1; i<=20; i++)); do
                    if [ $i -le $filled ]; then
                        progress_bar+="█"
                    else
                        progress_bar+="░"
                    fi
                done
                echo -ne "\r🚀 Nodes joining cluster... [$progress_bar] $ready_nodes/$total_nodes ready (${elapsed_min}m${elapsed_sec}s, ~${remaining_min}m left)"
            fi
            
            last_status="$current_status"
        fi
        
        # Success condition - all nodes ready
        if [ "$total_nodes" -gt "0" ] && [ "$ready_nodes" -eq "$total_nodes" ] && [ "$ready_nodes" -ge $((expected_nodes - 2)) ]; then
            if [ "$DEBUG_MODE" != true ]; then
                echo ""  # Clear progress bar line
            fi
            echo -e "${GREEN}✓ All $total_nodes nodes are ready${NC}"
            kubectl get nodes -L uneeq.io/node-type,nvidia.com/gpu
            return 0
        fi
        
        sleep 15  # Check every 15 seconds
    done
}

# Adaptive waiting for GPU operator installation
wait_for_gpu_operator_ready() {
    local max_timeout="${1:-2400}"  # Default 40 minutes
    local start_time=$(date +%s)
    local last_status=""
    
    echo "⏰ Maximum wait time: $((max_timeout/60)) minutes"
    
    # First wait for GPU nodes to be labeled
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
        echo -e "${YELLOW}⚠️  No GPU nodes detected yet, continuing anyway${NC}"
        # Estimate based on node group configuration
        gpu_nodes=12  # 10 renny + 2 a2f
    fi
    
    echo "Targeting $gpu_nodes GPU nodes for driver installation"
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ $elapsed -ge $max_timeout ]; then
            echo -e "${RED}❌ Timeout waiting for GPU operator after $((max_timeout/60)) minutes${NC}"
            kubectl get pods -n gpu-operator -o wide
            echo "Problematic pods:"
            kubectl get pods -n gpu-operator | grep -E "CrashLoopBackOff|ImagePullBackOff|Error|Failed" || echo "No failed pods found"
            return 1
        fi
        
        # Get GPU operator status
        local driver_pods=$(kubectl get pods -n gpu-operator -l app=nvidia-driver-daemonset --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l || echo "0")
        local failed_pods=$(kubectl get pods -n gpu-operator --field-selector=status.phase=Failed --no-headers 2>/dev/null | wc -l || echo "0")
        local crashloop_pods=$(kubectl get pods -n gpu-operator --no-headers 2>/dev/null | grep -c "CrashLoopBackOff\|ImagePullBackOff\|Error" || echo "0")
        local total_pods=$(kubectl get pods -n gpu-operator --no-headers 2>/dev/null | wc -l || echo "0")
        
        # Status summary
        local current_status="Drivers: $driver_pods/$gpu_nodes | Failed: $failed_pods | Crashes: $crashloop_pods | Total: $total_pods"
        
        # Show status updates
        if [ "$current_status" != "$last_status" ] || [ $((elapsed % 45)) -eq 0 ]; then
            local elapsed_min=$((elapsed / 60))
            local elapsed_sec=$((elapsed % 60))
            local remaining_time=$((max_timeout - elapsed))
            local remaining_min=$((remaining_time / 60))
            
            if [ "$DEBUG_MODE" = true ]; then
                debug_log "⏳ ${elapsed_min}m${elapsed_sec}s - $current_status (${remaining_min}m remaining)"
                
                if [ "$failed_pods" -gt "0" ] || [ "$crashloop_pods" -gt "0" ]; then
                    debug_log "Issue detected - showing pod details:"
                    kubectl get pods -n gpu-operator --no-headers | grep -E "Failed|CrashLoopBackOff|ImagePullBackOff|Error" || debug_log "  No critical failures in current status"
                fi
            else
                # Progress bar
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
                
                if [ "$failed_pods" -gt "0" ] || [ "$crashloop_pods" -gt "0" ]; then
                    echo -ne " ⚠️ $failed_pods failed"
                fi
            fi
            
            last_status="$current_status"
        fi
        
        # Success condition
        if [ "$driver_pods" -ge "$gpu_nodes" ] && [ "$gpu_nodes" -gt "0" ]; then
            if [ "$DEBUG_MODE" != true ]; then
                echo ""  # Clear progress bar line
            fi
            echo -e "${GREEN}✓ GPU drivers installed on all $gpu_nodes GPU nodes${NC}"
            return 0
        fi
        
        # Check for persistent issues
        if [ "$failed_pods" -gt "0" ] || [ "$crashloop_pods" -gt "0" ]; then
            if [ $elapsed -gt 1200 ]; then  # After 20 minutes
                echo -e "${YELLOW}⚠️  GPU operator has persistent issues after $((elapsed/60)) minutes${NC}"
                echo "Consider using --debug flag for detailed troubleshooting"
                if [ $elapsed -gt 2000 ]; then  # After 33 minutes
                    echo -e "${RED}GPU operator installation appears to have failed${NC}"
                    return 1
                fi
            fi
        fi
        
        sleep 20  # Check every 20 seconds
    done
}

# Function to wait for large image pulls with detailed monitoring
wait_for_large_images() {
    local app_label="$1"
    local namespace="$2"
    local max_timeout="${3:-2400}"  # Default 40 minutes for large images
    local start_time=$(date +%s)
    local last_status=""
    
    echo "Monitoring $app_label pods for large image pulls..."
    echo "⏰ Timeout: $((max_timeout/60)) minutes"
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ $elapsed -ge $max_timeout ]; then
            echo -e "${RED}❌ Timeout waiting for $app_label pods after $((max_timeout/60)) minutes${NC}"
            kubectl get pods -n "$namespace" -l "app=$app_label" -o wide
            echo "Recent events:"
            kubectl get events -n "$namespace" --field-selector involvedObject.kind=Pod --sort-by='.lastTimestamp' | tail -10
            return 1
        fi
        
        # Get pod status
        local pods_info=$(kubectl get pods -n "$namespace" -l "app=$app_label" --no-headers 2>/dev/null || echo "")
        local ready_count=$(echo "$pods_info" | grep -c "Running" 2>/dev/null || echo "0")
        local total_count=$(echo "$pods_info" | wc -l | tr -d ' ')
        
        # Check for image pull issues
        local pulling_count=$(echo "$pods_info" | grep -c "ContainerCreating\|Pending" 2>/dev/null || echo "0")
        local failed_count=$(echo "$pods_info" | grep -c "ErrImagePull\|ImagePullBackOff\|Evicted\|ContainerStatusUnknown" 2>/dev/null || echo "0")
        
        # Status summary
        local current_status="Ready: $ready_count/$total_count | Pulling: $pulling_count | Failed: $failed_count"
        
        # Show status based on debug mode and changes
        if [ "$current_status" != "$last_status" ] || [ $((elapsed % 45)) -eq 0 ]; then
            local elapsed_min=$((elapsed / 60))
            local elapsed_sec=$((elapsed % 60))
            local remaining_time=$((max_timeout - elapsed))
            local remaining_min=$((remaining_time / 60))
            
            if [ "$DEBUG_MODE" = true ]; then
                debug_log "⏳ ${elapsed_min}m${elapsed_sec}s - $current_status (${remaining_min}m remaining)"
                
                # Show detailed issues in debug mode
                if [ "$failed_count" -gt "0" ]; then
                    debug_log "⚠️  Issues detected - checking for disk pressure and image pull errors..."
                    kubectl get pods -n "$namespace" -l "app=$app_label" | grep -E "ErrImagePull|ImagePullBackOff|Evicted|ContainerStatusUnknown" || debug_log "No critical pod failures found"
                fi
            else
                # Simple progress for normal mode
                local progress_bar=""
                if [ "$total_count" -gt "0" ]; then
                    local filled=$((ready_count * 20 / total_count))
                    for ((i=1; i<=20; i++)); do
                        if [ $i -le $filled ]; then
                            progress_bar+="█"
                        else
                            progress_bar+="░"
                        fi
                    done
                    echo -ne "\r🖼️ Pulling $app_label images... [$progress_bar] $ready_count/$total_count ready (${elapsed_min}m${elapsed_sec}s, ~${remaining_min}m left)"
                    
                    # Show brief warning for failures in normal mode
                    if [ "$failed_count" -gt "0" ]; then
                        echo -ne " ⚠️ $failed_count issues"
                    fi
                else
                    echo -ne "\r🖼️ Pulling $app_label images... Waiting for pods... (${elapsed_min}m${elapsed_sec}s, ~${remaining_min}m left)"
                fi
            fi
            
            last_status="$current_status"
        fi
        
        # Success condition - all pods ready
        if [ "$total_count" -gt "0" ] && [ "$ready_count" -eq "$total_count" ]; then
            if [ "$DEBUG_MODE" != true ]; then
                echo ""  # Clear progress bar line
            fi
            echo -e "${GREEN}✓ All $app_label pods are ready ($ready_count/$total_count)${NC}"
            return 0
        fi
        
        sleep 15  # Check every 15 seconds for large images
    done
}

# AWS Profile detection and confirmation
check_aws_profile() {
    if [ "$SKIP_PROFILE_CHECK" = true ]; then
        return 0
    fi
    
    echo "🔍 Checking AWS Profile Configuration..."
    
    # Set profile if provided via command line
    if [ -n "$AWS_PROFILE_ARG" ]; then
        export AWS_PROFILE="$AWS_PROFILE_ARG"
        echo -e "${BLUE}Using profile from command line: ${AWS_PROFILE}${NC}"
    fi
    
    # Get current profile info
    local current_profile=""
    local account_id=""
    local identity_arn=""
    local region=""
    
    # Try to get current AWS identity
    if ! aws sts get-caller-identity &> /dev/null; then
        echo -e "${RED}❌ AWS credentials not configured or expired${NC}"
        echo ""
        echo "Available options:"
        echo "1. Run 'aws configure' to set up credentials"
        echo "2. Run 'aws sso login --profile <profile-name>' for SSO"
        echo "3. Set AWS_PROFILE environment variable"
        echo "4. Use --profile flag: $0 --profile <profile-name>"
        echo ""
        exit 1
    fi
    
    # Get identity information
    identity_arn=$(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null || echo "Unknown")
    account_id=$(aws sts get-caller-identity --query 'Account' --output text 2>/dev/null || echo "Unknown")
    region=$(aws configure get region 2>/dev/null || echo "Not set")
    
    # Try to get current profile name
    if [ -n "$AWS_PROFILE" ]; then
        current_profile="$AWS_PROFILE"
    else
        current_profile="default"
    fi
    
    # Display current AWS configuration
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           AWS Profile Information          ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
    echo -e "${BLUE}Profile:${NC} $current_profile"
    echo -e "${BLUE}Account ID:${NC} $account_id"
    echo -e "${BLUE}Region:${NC} $region"
    echo -e "${BLUE}Identity:${NC} $identity_arn"
    echo ""
    
    # Check if this looks like SSO
    if [[ "$identity_arn" == *"assumed-role"* && "$identity_arn" == *"AWSReservedSSO"* ]]; then
        echo -e "${GREEN}✅ SSO session detected${NC}"
        
        # Check if credentials might be expired soon
        local expiration=$(aws configure get sso_session.expiration 2>/dev/null || echo "")
        if [ -n "$expiration" ]; then
            echo -e "${BLUE}SSO Session:${NC} Active"
        fi
    fi
    
    # Confirm with user
    echo -e "${YELLOW}Is this the correct AWS profile/account for your EKS deployment? (y/N)${NC}"
    read -r response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}✅ Proceeding with current AWS configuration${NC}"
        echo ""
    else
        echo ""
        echo -e "${YELLOW}Available options to change your AWS profile:${NC}"
        echo ""
        echo "1. Run with specific profile:"
        echo "   $0 --profile your-profile-name"
        echo ""
        echo "2. Set environment variable:"
        echo "   export AWS_PROFILE=your-profile-name"
        echo "   $0"
        echo ""
        echo "3. For SSO profiles, ensure you're logged in:"
        echo "   aws sso login --profile your-profile-name"
        echo "   AWS_PROFILE=your-profile-name $0"
        echo ""
        echo "4. List available profiles:"
        echo "   aws configure list-profiles"
        echo ""
        echo "5. Skip this check (advanced users):"
        echo "   $0 --skip-profile-check"
        echo ""
        exit 1
    fi
}

# Check AWS credential expiration and validity
check_aws_credentials() {
    debug_log "Checking AWS credential expiration..."
    
    # Get current credentials info
    local identity_output
    if ! identity_output=$(aws sts get-caller-identity 2>/dev/null); then
        echo -e "${RED}❌ AWS credentials not configured or expired${NC}"
        return 1
    fi
    
    # Check if this is an assumed role (SSO or assume role)
    local identity_arn=$(echo "$identity_output" | jq -r '.Arn' 2>/dev/null || echo "")
    if [[ "$identity_arn" == *"assumed-role"* ]]; then
        debug_log "Detected assumed role credentials: $identity_arn"
        
        # Try to get session token info if available
        local session_info
        if session_info=$(aws sts get-session-token --duration-seconds 900 2>/dev/null); then
            debug_log "Credentials appear to be valid for session operations"
        else
            echo -e "${YELLOW}⚠️  Warning: Unable to test credential duration. Deployment may fail if credentials expire during the ~60-90 minute deployment process.${NC}"
            echo "Consider refreshing your credentials before proceeding:"
            echo "  AWS SSO: aws sso login --profile $AWS_PROFILE"
            echo ""
            echo -e "${YELLOW}Continue anyway? (y/N)${NC}"
            read -r response
            if [[ ! "$response" =~ ^[Yy]$ ]]; then
                echo "Deployment cancelled. Please refresh credentials and retry."
                exit 1
            fi
        fi
    fi
    
    debug_log "✅ AWS credentials validated"
    return 0
}

# Check AWS service limits and resource availability
check_aws_limits() {
    echo "🔍 Checking AWS service limits and availability..."
    local region=$(aws configure get region 2>/dev/null || echo "us-east-1")
    
    # Check VPC limit using existing script
    echo "Checking VPC availability..."
    local vpc_check_output
    if vpc_check_output=$("$SCRIPT_DIR/check-vpc-usage.sh" --region "$region" 2>&1); then
        debug_log "✅ VPC availability check passed"
        # Look for warning indicators in output
        if echo "$vpc_check_output" | grep -qi "limit\|warning\|full"; then
            echo -e "${YELLOW}⚠️  VPC usage warning detected${NC}"
            echo "Run './scripts/check-vpc-usage.sh' for details"
            echo ""
            echo -e "${YELLOW}Continue anyway? (y/N)${NC}"
            read -r response
            if [[ ! "$response" =~ ^[Yy]$ ]]; then
                echo "Please free up VPC capacity and retry"
                exit 1
            fi
        fi
    else
        echo -e "${RED}❌ VPC availability check failed${NC}"
        echo "Error output:"
        echo "$vpc_check_output"
        echo ""
        echo "This may indicate:"
        echo "  1. VPC limit exceeded (default: 5 per region)"
        echo "  2. Insufficient permissions to check VPCs"
        echo "  3. Network connectivity issues"
        echo ""
        echo -e "${YELLOW}Continue anyway? (y/N)${NC}"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "Please resolve VPC issues and retry"
            exit 1
        fi
    fi
    
    # Check instance type availability for g5.2xlarge
    echo "Checking GPU instance availability..."
    local instance_types=("g5.2xlarge" "g5.xlarge" "g5.4xlarge")
    local available_types=()
    
    for instance_type in "${instance_types[@]}"; do
        if aws ec2 describe-instance-type-offerings \
           --location-type availability-zone \
           --filters "Name=instance-type,Values=$instance_type" \
           --region "$region" \
           --query 'InstanceTypeOfferings[0].InstanceType' \
           --output text 2>/dev/null | grep -q "$instance_type"; then
            available_types+=("$instance_type")
            debug_log "✅ $instance_type available in $region"
        else
            debug_log "❌ $instance_type not available in $region"
        fi
    done
    
    if [ ${#available_types[@]} -eq 0 ]; then
        echo -e "${RED}❌ No GPU instance types (g5.xlarge, g5.2xlarge, g5.4xlarge) available in region $region${NC}"
        echo "Consider:"
        echo "  1. Changing to a different region with GPU availability"
        echo "  2. Requesting quota increase for GPU instances"
        echo "  3. Using different instance types (modify terraform/variables.tf)"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Available GPU instance types in $region: ${available_types[*]}${NC}"
    
    # Check Elastic IP limits (each NAT gateway needs one)
    echo "Checking Elastic IP availability..."
    local eip_used=$(aws ec2 describe-addresses --region "$region" --query 'Addresses[?Domain==`vpc`]' --output json | jq length)
    local eip_limit=5  # Default AWS limit
    
    # We need 1 EIP for single NAT or 3 EIPs for HA NAT
    local eip_needed=1
    if [ "${CONFIGURED_NAT_HA:-true}" = "true" ]; then
        eip_needed=3
    fi
    
    if [ $((eip_used + eip_needed)) -gt $eip_limit ]; then
        echo -e "${RED}❌ Insufficient Elastic IP addresses${NC}"
        echo "Current usage: $eip_used/$eip_limit"
        echo "This deployment needs: $eip_needed additional EIPs"
        echo "Consider:"
        echo "  1. Release unused Elastic IPs"
        echo "  2. Request EIP limit increase"
        echo "  3. Use single NAT gateway (set enable_nat_ha = false)"
        exit 1
    fi
    
    debug_log "✅ Elastic IP check passed: $eip_used/$eip_limit used, need $eip_needed more"
    
    echo -e "${GREEN}✅ AWS service limits check passed${NC}"
}

# Validate network CIDR configuration for conflicts
validate_network_config() {
    echo "🌐 Validating network configuration..."
    local vpc_cidr="$CONFIGURED_VPC_CIDR"
    local service_cidr="$CONFIGURED_SERVICE_CIDR"
    local region=$(aws configure get region 2>/dev/null || echo "us-east-1")
    
    # Basic CIDR format validation
    if ! [[ "$vpc_cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo -e "${RED}❌ Invalid VPC CIDR format: $vpc_cidr${NC}"
        exit 1
    fi
    
    if ! [[ "$service_cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo -e "${RED}❌ Invalid Service CIDR format: $service_cidr${NC}"
        exit 1
    fi
    
    # Check for overlap between VPC and Service CIDRs
    # This is a simplified check - a full implementation would use proper CIDR math
    local vpc_prefix=$(echo "$vpc_cidr" | cut -d'.' -f1-2)
    local service_prefix=$(echo "$service_cidr" | cut -d'.' -f1-2)
    
    if [ "$vpc_prefix" = "$service_prefix" ]; then
        echo -e "${RED}❌ VPC CIDR ($vpc_cidr) and Service CIDR ($service_cidr) appear to overlap${NC}"
        echo "VPC and Kubernetes service networks must use different IP ranges"
        exit 1
    fi
    
    # Check for conflicts with existing VPCs in region
    echo "Checking for conflicts with existing VPCs..."
    local existing_cidrs
    existing_cidrs=$(aws ec2 describe-vpcs --region "$region" --query 'Vpcs[].CidrBlock' --output text 2>/dev/null || echo "")
    
    if [ -n "$existing_cidrs" ]; then
        local conflict_found=false
        while IFS= read -r existing_cidr; do
            if [ "$existing_cidr" = "$vpc_cidr" ]; then
                echo -e "${RED}❌ VPC CIDR $vpc_cidr already exists in region $region${NC}"
                echo "Choose a different VPC CIDR range to avoid conflicts"
                exit 1
            fi
            
            # Basic overlap check (simplified)
            local existing_prefix=$(echo "$existing_cidr" | cut -d'.' -f1-2)
            if [ "$existing_prefix" = "$vpc_prefix" ]; then
                echo -e "${YELLOW}⚠️  Warning: VPC CIDR $vpc_cidr may overlap with existing VPC $existing_cidr${NC}"
                echo -e "${YELLOW}Continue anyway? (y/N)${NC}"
                read -r response
                if [[ ! "$response" =~ ^[Yy]$ ]]; then
                    echo "Please choose a different VPC CIDR range"
                    exit 1
                fi
            fi
        done <<< "$existing_cidrs"
    fi
    
    # Check for reserved/problematic ranges
    case "$vpc_cidr" in
        "169.254."*) 
            echo -e "${RED}❌ VPC CIDR cannot use link-local range (169.254.0.0/16)${NC}"
            exit 1
            ;;
        "127."*)
            echo -e "${RED}❌ VPC CIDR cannot use loopback range (127.0.0.0/8)${NC}"
            exit 1
            ;;
        "224."*|"225."*|"226."*|"227."*|"228."*|"229."*|"230."*|"231."*|"232."*|"233."*|"234."*|"235."*|"236."*|"237."*|"238."*|"239."*)
            echo -e "${RED}❌ VPC CIDR cannot use multicast range (224.0.0.0/4)${NC}"
            exit 1
            ;;
    esac
    
    echo -e "${GREEN}✅ Network configuration validated${NC}"
    echo "  VPC CIDR: $vpc_cidr"
    echo "  Service CIDR: $service_cidr" 
}

# Test external service connectivity
test_external_dependencies() {
    echo "🔗 Testing external service connectivity..."
    
    # Test Docker Hub connectivity
    echo "Testing Docker Hub connectivity..."
    if ! curl -s --connect-timeout 10 https://index.docker.io/v2/ > /dev/null; then
        echo -e "${RED}❌ Cannot reach Docker Hub (https://index.docker.io)${NC}"
        echo "Check your internet connection and firewall settings"
        exit 1
    fi
    debug_log "✅ Docker Hub connectivity verified"
    
    # Test AWS API connectivity
    echo "Testing AWS API connectivity..."
    if ! aws sts get-caller-identity --query 'Account' --output text > /dev/null; then
        echo -e "${RED}❌ Cannot reach AWS API${NC}"
        echo "Check your internet connection and AWS credentials"
        exit 1
    fi
    debug_log "✅ AWS API connectivity verified"
    
    # Test Helm chart file
    echo "Validating Helm chart..."
    if [ ! -f "$PROJECT_DIR/renny-chart.tgz" ]; then
        echo -e "${RED}❌ renny-chart.tgz not found in $PROJECT_DIR${NC}"
        echo "Please place the Renny Helm chart tar file in the kubernetes/ directory"
        exit 1
    fi
    
    # Basic validation that it's a valid tar file
    if ! tar -tzf "$PROJECT_DIR/renny-chart.tgz" > /dev/null 2>&1; then
        echo -e "${RED}❌ renny-chart.tgz appears to be corrupted${NC}"
        echo "Please obtain a fresh copy of the Renny Helm chart"
        exit 1
    fi
    debug_log "✅ Helm chart file validated"
    
    echo -e "${GREEN}✅ External dependencies verified${NC}"
}

# Check prerequisites
check_prerequisites() {
    echo "📋 Checking prerequisites..."
    
    # Check for required tools
    for tool in terraform aws kubectl helm jq curl; do
        if ! command -v $tool &> /dev/null; then
            echo -e "${RED}❌ $tool is not installed${NC}"
            echo "Please install $tool and try again"
            if [ "$tool" = "jq" ]; then
                echo "Install jq: https://stedolan.github.io/jq/download/"
            fi
            exit 1
        fi
    done
    
    # Check AWS CLI version (need 2.3.0+ for proper kubectl auth)
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    local required_version="2.3.0"
    if [ "$(printf '%s\n' "$required_version" "$aws_version" | sort -V | head -n1)" != "$required_version" ]; then
        echo -e "${YELLOW}⚠️  AWS CLI version $aws_version detected. Version 2.3.0+ recommended${NC}"
        echo "Older versions may cause kubectl authentication issues"
        echo "Update with: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        echo ""
        echo -e "${YELLOW}Continue anyway? (y/N)${NC}"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    debug_log "✅ AWS CLI version $aws_version"
    
    echo -e "${GREEN}✅ All prerequisites met${NC}"
}

# Network and cost configuration prompts
prompt_network_configuration() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              Network Configuration Setup              ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Before deploying your EKS cluster, we need to configure network settings.${NC}"
    echo -e "${YELLOW}⚠️  IMPORTANT: Some decisions are permanent and require cluster rebuild to change.${NC}"
    echo ""
    
    # VPC CIDR Configuration
    echo -e "${CYAN}1. VPC Network Range (PERMANENT DECISION)${NC}"
    echo "This sets the IP range for your entire AWS network infrastructure."
    echo "Choose a range that won't conflict with your existing networks."
    echo ""
    echo "Common options:"
    echo "  A) 10.17.0.0/16    - Recommended (65,534 IPs)"
    echo "  B) 10.50.0.0/16    - Alternative if 10.17.x conflicts"
    echo "  C) 192.168.0.0/16  - Private network standard"
    echo "  D) Custom range    - Enter your own CIDR"
    echo ""
    echo -e "${RED}⚠️  This cannot be changed without destroying and rebuilding the cluster${NC}"
    echo -e "${YELLOW}Enter your choice (A/B/C/D):${NC}"
    
    local vpc_choice
    read -r vpc_choice
    
    local vpc_cidr
    case $vpc_choice in
        A|a) vpc_cidr="10.17.0.0/16" ;;
        B|b) vpc_cidr="10.50.0.0/16" ;;
        C|c) vpc_cidr="192.168.0.0/16" ;;
        D|d) 
            echo "Enter custom CIDR (e.g., 10.100.0.0/16):"
            read -r vpc_cidr
            if ! [[ "$vpc_cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
                echo -e "${RED}Invalid CIDR format. Using default 10.17.0.0/16${NC}"
                vpc_cidr="10.17.0.0/16"
            fi
            ;;
        *) 
            echo -e "${YELLOW}Invalid choice. Using default 10.17.0.0/16${NC}"
            vpc_cidr="10.17.0.0/16"
            ;;
    esac
    
    echo -e "${GREEN}✓ VPC CIDR: $vpc_cidr${NC}"
    echo ""
    
    # EKS Service CIDR Configuration
    echo -e "${CYAN}2. Kubernetes Service Network (PERMANENT DECISION)${NC}"
    echo "This sets the IP range for Kubernetes internal services and DNS."
    echo "Must not overlap with your VPC range."
    echo ""
    
    # Suggest compatible service CIDR based on VPC choice
    local service_cidr
    if [[ "$vpc_cidr" == "10.17.0.0/16" ]]; then
        service_cidr="10.117.0.0/16"
        echo "Recommended: 10.117.0.0/16 (compatible with your VPC choice)"
    elif [[ "$vpc_cidr" == "10.50.0.0/16" ]]; then
        service_cidr="10.150.0.0/16"
        echo "Recommended: 10.150.0.0/16 (compatible with your VPC choice)"
    elif [[ "$vpc_cidr" == "192.168.0.0/16" ]]; then
        service_cidr="10.117.0.0/16"
        echo "Recommended: 10.117.0.0/16 (compatible with your VPC choice)"
    else
        service_cidr="10.117.0.0/16"
        echo "Recommended: 10.117.0.0/16"
    fi
    
    echo ""
    echo -e "${RED}⚠️  This cannot be changed without destroying and rebuilding the cluster${NC}"
    echo -e "${YELLOW}Use recommended setting? (Y/n):${NC}"
    
    local service_choice
    read -r service_choice
    
    if [[ "$service_choice" =~ ^[Nn]$ ]]; then
        echo "Enter custom service CIDR (e.g., 10.100.0.0/16):"
        read -r service_cidr
        if ! [[ "$service_cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
            echo -e "${RED}Invalid CIDR format. Using default 10.117.0.0/16${NC}"
            service_cidr="10.117.0.0/16"
        fi
    fi
    
    echo -e "${GREEN}✓ Service CIDR: $service_cidr${NC}"
    echo ""
    
    # NAT Gateway Configuration
    echo -e "${CYAN}3. NAT Gateway Configuration (Can be changed later)${NC}"
    echo "NAT Gateways provide internet access to your private nodes."
    echo ""
    echo "Options:"
    echo "  A) High Availability - 3 NAT Gateways (~\$135/month extra)"
    echo "     • One per availability zone"
    echo "     • Survives single AZ failures"  
    echo "     • Recommended for production"
    echo ""
    echo "  B) Cost Optimized - 1 NAT Gateway (~\$45/month)"
    echo "     • Single point of failure"
    echo "     • Good for development/testing"
    echo ""
    echo -e "${GREEN}✓ This setting can be changed after deployment without cluster rebuild${NC}"
    echo -e "${YELLOW}Choose NAT Gateway setup (A for HA, B for cost-optimized):${NC}"
    
    local nat_choice
    read -r nat_choice
    
    local enable_nat_ha
    case $nat_choice in
        A|a) 
            enable_nat_ha="true"
            echo -e "${GREEN}✓ High availability NAT Gateways selected${NC}"
            ;;
        B|b) 
            enable_nat_ha="false"
            echo -e "${GREEN}✓ Cost-optimized single NAT Gateway selected${NC}"
            ;;
        *) 
            enable_nat_ha="true"
            echo -e "${YELLOW}Invalid choice. Using high availability (recommended)${NC}"
            ;;
    esac
    
    echo ""
    echo -e "${CYAN}═══════════════ Configuration Summary ═══════════════${NC}"
    echo "VPC Network Range:      $vpc_cidr (PERMANENT)"
    echo "Service Network Range:  $service_cidr (PERMANENT)"
    echo "NAT Gateway Setup:      $([ "$enable_nat_ha" = "true" ] && echo "High Availability" || echo "Cost Optimized") (changeable)"
    echo ""
    echo -e "${YELLOW}Is this configuration correct? (yes/no):${NC}"
    
    local confirm
    read -r confirm
    
    if [[ "$confirm" != "yes" ]]; then
        echo "Configuration cancelled. Please restart deployment to reconfigure."
        exit 1
    fi
    
    # Store configuration in variables for terraform.tfvars creation
    CONFIGURED_VPC_CIDR="$vpc_cidr"
    CONFIGURED_SERVICE_CIDR="$service_cidr"
    CONFIGURED_NAT_HA="$enable_nat_ha"
    
    echo -e "${GREEN}✓ Network configuration saved${NC}"
    echo ""
}

# Create terraform.tfvars if it doesn't exist
create_tfvars() {
    if [ ! -f "$PROJECT_DIR/terraform/terraform.tfvars" ]; then
        echo "📝 Creating terraform.tfvars with your configuration..."
        cat > "$PROJECT_DIR/terraform/terraform.tfvars" <<EOF
# Network Configuration (configured during deployment)
vpc_cidr = "$CONFIGURED_VPC_CIDR"
service_cidr = "$CONFIGURED_SERVICE_CIDR"
enable_nat_ha = $CONFIGURED_NAT_HA

# REQUIRED: Please fill in these values before continuing

# DHOP Configuration
dhop_tenant_id = ""  # Your DHOP tenant ID
dhop_api_key = ""    # Your DHOP API key (base64 encoded)

# Docker Hub Credentials
docker_username = ""  # Your Docker Hub username with access to UneeQ repos
docker_password = ""  # Your Docker Hub password

# Optional: Override default values
# aws_region = "us-east-1"
# renny_instance_type = "g5.2xlarge"
# a2f_instance_type = "g5.2xlarge"
# renny_min_size = 10
# renny_max_size = 20
# renny_desired_size = 10
EOF
        echo -e "${YELLOW}⚠️  Please edit terraform/terraform.tfvars with your credentials${NC}"
        echo "Required values:"
        echo "  - dhop_tenant_id: Your DHOP tenant ID"
        echo "  - dhop_api_key: Your DHOP API key (base64 encoded)"
        echo "  - docker_username: Docker Hub username"
        echo "  - docker_password: Docker Hub password"
        exit 1
    fi
    
    # Validate that required values are filled
    if grep -q 'dhop_tenant_id = ""' "$PROJECT_DIR/terraform/terraform.tfvars" || grep -q 'dhop_api_key = ""' "$PROJECT_DIR/terraform/terraform.tfvars"; then
        echo -e "${RED}❌ terraform.tfvars contains empty DHOP values${NC}"
        echo "Please fill in all required values in terraform/terraform.tfvars"
        exit 1
    fi
    
    if grep -q 'docker_username = ""' "$PROJECT_DIR/terraform/terraform.tfvars" || grep -q 'docker_password = ""' "$PROJECT_DIR/terraform/terraform.tfvars"; then
        echo -e "${RED}❌ terraform.tfvars contains empty Docker credentials${NC}"
        echo "Please fill in all required values in terraform/terraform.tfvars"
        exit 1
    fi
}

# Deploy infrastructure
deploy_infrastructure() {
    echo "🏗️  Deploying infrastructure with Terraform..."
    echo -e "${BLUE}This will take approximately 15-20 minutes${NC}"
    cd "$PROJECT_DIR/terraform"
    
    # Initialize Terraform
    echo "Initializing Terraform..."
    terraform init
    
    # Plan the deployment
    echo "Planning infrastructure deployment..."
    terraform plan -out=tfplan
    
    echo -e "${YELLOW}Review the plan above. Do you want to proceed with the deployment? (yes/no)${NC}"
    read -r response
    if [[ "$response" != "yes" ]]; then
        echo "Deployment cancelled"
        rm -f tfplan
        exit 0
    fi
    
    # Apply the plan
    echo ""
    echo "Applying infrastructure changes..."
    echo "Creating:"
    echo "  - VPC with 3 availability zones"
    echo "  - EKS cluster v1.31"
    
    # Get values from terraform.tfvars with robust parsing
    local renny_desired=$(awk '/^renny_desired_size[[:space:]]*=/ {gsub(/[^0-9]/, "", $3); print $3}' terraform.tfvars || echo "10")
    local renny_instance=$(awk '/^renny_instance_type[[:space:]]*=/ {gsub(/"/, "", $3); print $3}' terraform.tfvars || echo "g5.2xlarge")
    local a2f_desired=$(awk '/^a2f_desired_size[[:space:]]*=/ {gsub(/[^0-9]/, "", $3); print $3}' terraform.tfvars || echo "2")
    local a2f_instance=$(awk '/^a2f_instance_type[[:space:]]*=/ {gsub(/"/, "", $3); print $3}' terraform.tfvars || echo "g5.2xlarge")
    
    echo "  - $renny_desired GPU nodes for Renny ($renny_instance, Ubuntu 22.04)"
    echo "  - $a2f_desired GPU nodes for Audio2Face ($a2f_instance, Ubuntu 22.04)"
    echo "  - 2 control plane nodes (t3.large)"
    echo ""
    echo "Ubuntu GPU nodes provide:"
    echo "  - Fast cluster join (~3 minutes) without NVIDIA driver delays"
    echo "  - NVIDIA GPU Operator will install latest compatible drivers"
    echo "  - Vulkan API compatibility for Unreal Engine"
    echo "  - CUDA 12.4+ for latest AI workloads"
    echo "  - 150GB storage for large container images"
    echo ""
    terraform apply tfplan
    rm -f tfplan
    
    echo -e "${GREEN}✓ Infrastructure deployed successfully${NC}"
    show_elapsed
    
    cd "$PROJECT_DIR"
}

# Configure kubectl
configure_kubectl() {
    echo "🔧 Configuring kubectl..."
    cd "$PROJECT_DIR/terraform"
    CLUSTER_NAME=$(terraform output -raw cluster_name)
    REGION=$(terraform output -raw region)
    cd "$PROJECT_DIR"
    
    echo "Updating kubeconfig for cluster: $CLUSTER_NAME"
    aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME
    
    # Create access entry for the current user to enable kubectl access
    echo "🔑 Setting up cluster access for current user..."
    CURRENT_USER_ARN=$(aws sts get-caller-identity --query 'Arn' --output text)
    echo "Current user: $CURRENT_USER_ARN"
    
    # Determine the correct principal ARN based on authentication type
    if [[ "$CURRENT_USER_ARN" == *":assumed-role/"* ]]; then
        # For assumed roles, we need the base role ARN
        if [[ "$CURRENT_USER_ARN" == *"AWSReservedSSO"* ]]; then
            # Handle AWS SSO roles with special path structure
            ROLE_NAME=$(echo "$CURRENT_USER_ARN" | sed 's/.*:assumed-role\/\([^/]*\).*/\1/')
            ACCOUNT_ID=$(echo "$CURRENT_USER_ARN" | cut -d: -f5)
            # Detect region from the role structure (some SSO roles include region)
            if aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text 2>/dev/null | grep -q "aws-reserved"; then
                # Get the actual SSO role path from IAM
                ACTUAL_ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text 2>/dev/null)
                if [ -n "$ACTUAL_ROLE_ARN" ]; then
                    BASE_ROLE_ARN="$ACTUAL_ROLE_ARN"
                else
                    # Fallback to constructed path (works for most SSO setups)
                    BASE_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/aws-reserved/sso.amazonaws.com/ap-southeast-2/${ROLE_NAME}"
                fi
            else
                BASE_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/aws-reserved/sso.amazonaws.com/ap-southeast-2/${ROLE_NAME}"
            fi
            echo "Detected AWS SSO role"
        else
            # Handle regular assumed roles (EC2 instance roles, cross-account roles, etc.)
            ROLE_NAME=$(echo "$CURRENT_USER_ARN" | sed 's/.*:assumed-role\/\([^/]*\).*/\1/')
            ACCOUNT_ID=$(echo "$CURRENT_USER_ARN" | cut -d: -f5)
            BASE_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
            echo "Detected regular assumed role"
        fi
        echo "Using base role ARN for access entry: $BASE_ROLE_ARN"
        PRINCIPAL_ARN="$BASE_ROLE_ARN"
    elif [[ "$CURRENT_USER_ARN" == *":user/"* ]]; then
        # For regular IAM users (access key/secret key authentication)
        echo "Detected IAM user authentication"
        PRINCIPAL_ARN="$CURRENT_USER_ARN"
    elif [[ "$CURRENT_USER_ARN" == *":root"* ]]; then
        # For root user authentication (not recommended but some customers use it)
        echo "Detected root user authentication"
        PRINCIPAL_ARN="$CURRENT_USER_ARN"
    else
        # Fallback for other authentication types
        echo "Detected unknown authentication type, using ARN directly"
        PRINCIPAL_ARN="$CURRENT_USER_ARN"
    fi
    
    echo "Principal ARN for access entry: $PRINCIPAL_ARN"
    
    # Check if access entry already exists
    if aws eks describe-access-entry --cluster-name "$CLUSTER_NAME" --principal-arn "$PRINCIPAL_ARN" --region "$REGION" &>/dev/null; then
        echo "  ✅ Access entry already exists"
    else
        echo "  Creating access entry for cluster admin access..."
        aws eks create-access-entry \
            --cluster-name "$CLUSTER_NAME" \
            --principal-arn "$PRINCIPAL_ARN" \
            --region "$REGION" \
            --tags "CreatedBy=deploy-script,Purpose=cluster-admin" || {
            echo -e "${YELLOW}⚠️  Could not create access entry, but kubectl should still work${NC}"
        }
        
        # Associate cluster admin policy
        echo "  Associating cluster admin policy..."
        aws eks associate-access-policy \
            --cluster-name "$CLUSTER_NAME" \
            --principal-arn "$PRINCIPAL_ARN" \
            --policy-arn "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy" \
            --access-scope type=cluster \
            --region "$REGION" || {
            echo -e "${YELLOW}⚠️  Could not associate admin policy${NC}"
        }
        
        echo "  ✅ Cluster admin access configured"
    fi
    
    # Fix kubectl authentication compatibility for older AWS CLI versions
    echo "Ensuring kubectl authentication compatibility..."
    if grep -q "client.authentication.k8s.io/v1alpha1" ~/.kube/config 2>/dev/null; then
        echo "  Detected old authentication API version, fixing..."
        sed -i '' 's/client.authentication.k8s.io\/v1alpha1/client.authentication.k8s.io\/v1beta1/g' ~/.kube/config
        echo "  ✅ Kubeconfig authentication fixed"
    fi
    
    # Wait for nodes to be ready (fast cluster join without NVIDIA drivers)
    echo "🚀 Waiting for nodes to join cluster (fast boot without GPU drivers)..."
    wait_for_cluster_nodes_ready 1800  # 30 minutes max for node readiness
}

# Install NVIDIA GPU Operator
install_gpu_operator() {
    echo "🎮 Installing NVIDIA GPU Operator..."
    echo -e "${BLUE}This will install GPU drivers automatically (10-25 minutes)${NC}"
    echo "GPU Operator will:"
    echo "  - Install NVIDIA driver 570+ on all GPU nodes"
    echo "  - Configure containerd with NVIDIA runtime"
    echo "  - Enable GPU device plugin and monitoring"
    
    # Add NVIDIA Helm repository
    helm repo add nvidia https://helm.ngc.nvidia.com/nvidia || true
    helm repo update
    
    # Create namespace
    kubectl create namespace gpu-operator --dry-run=client -o yaml | kubectl apply -f -
    
    # Install GPU Operator with longer timeout for driver compilation
    echo "Installing GPU operator..."
    helm upgrade --install gpu-operator nvidia/gpu-operator \
        --namespace gpu-operator \
        --set operator.defaultRuntime=containerd \
        --set driver.enabled=true \
        --set toolkit.enabled=true \
        --set devicePlugin.enabled=true \
        --set dcgmExporter.enabled=true \
        --wait --timeout 25m
    
    echo "⏳ Waiting for GPU operator pods to be ready..."
    kubectl wait --for=condition=ready pod -l app=nvidia-operator -n gpu-operator --timeout=900s || true
    
    # Wait for GPU drivers using adaptive waiting
    echo "Waiting for GPU drivers to be installed on all nodes..."
    wait_for_gpu_operator_ready 2400  # 40 minutes max for driver installation
    
    # Verify GPU nodes
    echo "GPU node status:"
    kubectl get nodes -L nvidia.com/gpu,uneeq.io/node-type
    
    show_elapsed
}

# Create namespace and secrets
setup_kubernetes_resources() {
    echo "☸️  Setting up Kubernetes resources..."
    
    # Create namespace
    kubectl apply -f "$PROJECT_DIR/manifests/namespace.yaml"
    
    # Get Docker credentials from terraform vars
    cd "$PROJECT_DIR/terraform"
    DOCKER_USERNAME=$(grep docker_username terraform.tfvars | cut -d'"' -f2)
    DOCKER_PASSWORD=$(grep docker_password terraform.tfvars | cut -d'"' -f2)
    cd "$PROJECT_DIR"
    
    # Create Docker registry secret
    echo "Creating Docker registry secret..."
    kubectl create secret docker-registry docker-config \
        --docker-server=https://index.docker.io/v1/ \
        --docker-username="$DOCKER_USERNAME" \
        --docker-password="$DOCKER_PASSWORD" \
        --namespace=uneeq-renderer \
        --dry-run=client -o yaml | kubectl apply -f -
}

# Install Audio2Face
install_a2f() {
    echo "🎭 Installing Audio2Face..."
    echo -e "${BLUE}This will take approximately 10-20 minutes (35GB images)${NC}"
    
    # Get Docker credentials
    cd "$PROJECT_DIR/terraform"
    DOCKER_USERNAME=$(grep docker_username terraform.tfvars | cut -d'"' -f2)
    DOCKER_PASSWORD=$(grep docker_password terraform.tfvars | cut -d'"' -f2)
    cd "$PROJECT_DIR"
    
    # Login to Docker Hub with Helm
    echo "Logging into Docker Hub..."
    echo "$DOCKER_PASSWORD" | helm registry login registry-1.docker.io -u "$DOCKER_USERNAME" --password-stdin
    
    # Install A2F with extended timeout for large images
    echo "Installing Audio2Face Helm chart..."
    helm upgrade --install a2f oci://registry-1.docker.io/facemeproduction/a2f \
        --version 0.1-alpha \
        --namespace uneeq-renderer \
        -f "$PROJECT_DIR/values/a2f-values.yaml" \
        --wait --timeout 30m
    
    # Wait for A2F pods to be ready with enhanced monitoring
    echo "Waiting for Audio2Face pods to be ready (this may take 10-20 minutes for 35GB images)..."
    wait_for_large_images "a2f" "uneeq-renderer" 1800  # 30 minutes for massive images
    
    # Verify A2F deployment
    echo "Audio2Face deployment status:"
    kubectl get pods -n uneeq-renderer -l app=a2f
    
    echo -e "${GREEN}✓ Audio2Face installed successfully${NC}"
    show_elapsed
}

# Install Renny
install_renny() {
    echo "🤖 Installing Renny..."
    echo -e "${BLUE}This will take approximately 10-15 minutes (large container images)${NC}"
    
    # Get DHOP credentials from terraform vars
    cd "$PROJECT_DIR/terraform"
    DHOP_TENANT_ID=$(grep dhop_tenant_id terraform.tfvars | cut -d'"' -f2)
    DHOP_API_KEY=$(grep dhop_api_key terraform.tfvars | cut -d'"' -f2)
    cd "$PROJECT_DIR"
    
    # Update Renny values with DHOP credentials
    cp "$PROJECT_DIR/values/renny-values.yaml" "$PROJECT_DIR/values/renny-values-deployed.yaml"
    
    # Use sed to update the values (works on both Mac and Linux)
    sed -i.bak "s/tenantId: \"\"/tenantId: \"$DHOP_TENANT_ID\"/" "$PROJECT_DIR/values/renny-values-deployed.yaml"
    sed -i.bak "s/apiKey: \"\"/apiKey: \"$DHOP_API_KEY\"/" "$PROJECT_DIR/values/renny-values-deployed.yaml"
    rm -f "$PROJECT_DIR/values/renny-values-deployed.yaml.bak"
    
    # Install Renny with extended timeout
    echo "Installing Renny Helm chart with 10 replicas..."
    helm upgrade --install renny "$PROJECT_DIR/renny-chart.tgz" \
        --namespace uneeq-renderer \
        -f "$PROJECT_DIR/values/renny-values-deployed.yaml" \
        --wait --timeout 25m
    
    # Wait for Renny pods to be ready
    echo "Waiting for Renny pods to be ready..."
    local max_attempts=60
    local attempt=1
    
    # Get expected replica count from the deployment
    local expected_replicas=$(kubectl get deployment renny -n uneeq-renderer -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    
    while [ $attempt -le $max_attempts ]; do
        READY_PODS=$(kubectl get pods -n uneeq-renderer -l app=renny --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l || echo "0")
        
        if [ "$expected_replicas" -gt "0" ] && [ "$READY_PODS" -ge "$expected_replicas" ]; then
            echo -e "${GREEN}✓ $READY_PODS/$expected_replicas Renny pods are running${NC}"
            break
        fi
        
        echo "  Waiting for Renny pods... ($READY_PODS/$expected_replicas running, attempt $attempt/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    
    # Show Renny pod status
    echo "Renny deployment status:"
    kubectl get pods -n uneeq-renderer -l app=renny
    
    echo -e "${GREEN}✓ Renny installed successfully${NC}"
    show_elapsed
}

# Install cluster autoscaler
install_autoscaler() {
    echo "⚖️  Installing Cluster Autoscaler..."
    
    cd "$PROJECT_DIR/terraform"
    CLUSTER_NAME=$(terraform output -raw cluster_name)
    AUTOSCALER_ROLE_ARN=$(terraform output -raw cluster_autoscaler_role_arn)
    REGION=$(terraform output -raw region)
    cd "$PROJECT_DIR"
    
    # Add autoscaler repo
    helm repo add autoscaler https://kubernetes.github.io/autoscaler || true
    helm repo update
    
    # Install cluster autoscaler
    echo "Installing cluster autoscaler for cluster: $CLUSTER_NAME"
    helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
        --namespace kube-system \
        --set autoDiscovery.clusterName=$CLUSTER_NAME \
        --set awsRegion=$REGION \
        --set rbac.serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$AUTOSCALER_ROLE_ARN" \
        --set rbac.serviceAccount.create=true \
        --set rbac.create=true \
        --wait
    
    echo "Cluster autoscaler installed"
}

# Display final status
display_status() {
    # Calculate total elapsed time
    END_TIME=$(date +%s)
    TOTAL_ELAPSED=$((END_TIME - START_TIME))
    TOTAL_MIN=$((TOTAL_ELAPSED / 60))
    TOTAL_SEC=$((TOTAL_ELAPSED % 60))
    
    echo ""
    echo "======================================"
    echo -e "${GREEN}✅ Deployment completed successfully!${NC}"
    echo "======================================"
    echo ""
    echo "Total deployment time: ${TOTAL_MIN} minutes ${TOTAL_SEC} seconds"
    echo ""
    
    cd "$PROJECT_DIR/terraform"
    CLUSTER_NAME=$(terraform output -raw cluster_name)
    REGION=$(terraform output -raw region)
    cd "$PROJECT_DIR"
    
    echo "📊 Cluster Info:"
    echo "Cluster Name: $CLUSTER_NAME"
    echo "Region: $REGION"
    echo ""
    
    echo "📋 Node Summary:"
    echo "  - Control nodes: 2x t3.large (Amazon Linux 2023)"
    echo "  - Renny GPU nodes: 10x g5.2xlarge (Ubuntu 22.04)"
    echo "  - A2F GPU nodes: 2x g5.2xlarge (Ubuntu 22.04)"
    kubectl get nodes -L uneeq.io/node-type,nvidia.com/gpu
    echo ""
    
    echo "🚀 Renny Deployment Status:"
    kubectl get pods -n uneeq-renderer -l app=renny --no-headers | head -5
    RENNY_COUNT=$(kubectl get pods -n uneeq-renderer -l app=renny --no-headers | wc -l)
    echo "Total Renny pods: $RENNY_COUNT"
    echo ""
    
    echo "🎭 Audio2Face Status:"
    kubectl get pods -n uneeq-renderer -l app=a2f
    echo ""
    
    echo "💵 Estimated Costs:"
    echo "  - Hourly: ~\$15-20/hour"
    echo "  - Daily: ~\$360-480/day"
    echo "  - Monthly: ~\$10,800-14,400/month"
    echo ""
    
    echo "📝 Next Steps:"
    echo "1. Configure your TURN server details with UneeQ"
    echo "2. Add any required TTS API keys to values/renny-values.yaml"
    echo "3. Scale Renny instances using: ./scripts/scale.sh <desired_count>"
    echo "4. Monitor GPU usage: kubectl top nodes"
    echo ""
    echo "🔧 Useful Commands:"
    echo "  - Access cluster: aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME"
    echo "  - Scale Renny: ./scripts/scale.sh 15"
    echo "  - View logs: kubectl logs -n uneeq-renderer -l app=renny --tail=100"
    echo "  - Destroy all: ./scripts/destroy.sh"
    echo ""
    echo -e "${YELLOW}⚠️  Remember to run ./scripts/destroy.sh when done testing to avoid charges${NC}"
}

# Main deployment flow
main() {
    echo "======================================"
    echo "   Renny EKS One-Click Deployment    "
    echo "======================================"
    echo ""
    
    # Pre-flight checks
    check_aws_profile
    check_prerequisites
    check_aws_credentials
    prompt_network_configuration
    validate_network_config
    check_aws_limits
    test_external_dependencies
    create_tfvars
    
    # Infrastructure deployment
    deploy_infrastructure
    configure_kubectl
    install_gpu_operator
    setup_kubernetes_resources
    install_a2f
    install_renny
    install_autoscaler
    display_status
}

# Enhanced error handling and cleanup
cleanup_on_error() {
    local exit_code=$?
    echo ""
    echo -e "${RED}❌ Deployment failed with exit code $exit_code${NC}"
    echo ""
    
    # Show helpful information for common failure points
    if [ -f "$PROJECT_DIR/terraform/terraform.tfstate" ]; then
        echo "⚠️  Partial infrastructure may have been created."
        echo "Check your AWS console for resources that may be incurring charges."
        echo ""
        echo "To clean up:"
        echo "1. Run: ./scripts/destroy.sh"
        echo "2. Or manually check AWS console for:"
        echo "   - EKS clusters"
        echo "   - EC2 instances"
        echo "   - VPCs and NAT gateways"
        echo "   - Load balancers"
    fi
    
    # Show recent events if kubectl is working
    if kubectl get nodes &>/dev/null; then
        echo ""
        echo "Recent cluster events:"
        kubectl get events --sort-by='.lastTimestamp' | tail -5 || true
    fi
    
    echo ""
    echo "💡 Troubleshooting tips:"
    echo "1. Re-run with --debug flag for verbose output"
    echo "2. Check AWS service limits and quotas"
    echo "3. Verify your credentials haven't expired"
    echo "4. Check the specific error messages above"
    echo ""
    
    exit $exit_code
}

# Handle errors with enhanced cleanup
trap cleanup_on_error ERR

# Run main function
main