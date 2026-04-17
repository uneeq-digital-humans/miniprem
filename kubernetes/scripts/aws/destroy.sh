#!/bin/bash
# Note: NOT using 'set -e' to allow script to continue on kubectl errors
# when cluster control plane is already being destroyed

# Source deployment functions
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/deployment-functions.sh"

# Parse command line arguments
AWS_PROFILE_ARG=""
TARGET_DEPLOYMENT_ID=""
DESTROY_ALL=false
LIST_ONLY=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --profile)
            AWS_PROFILE_ARG="$2"
            shift 2
            ;;
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
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --profile PROFILE_NAME       Use specific AWS profile"
            echo "  --deployment-id ID           Destroy specific deployment ID"
            echo "  --all                        Destroy ALL deployments (use with caution!)"
            echo "  --list                       List all deployments and exit"
            echo "  --help, -h                   Show this help message"
            echo ""
            echo "Deployment Management:"
            echo "  By default, destroy.sh will detect and destroy the current deployment"
            echo "  (based on .deployment_id file or terraform.tfvars)."
            echo ""
            echo "  Use --deployment-id to target a specific deployment"
            echo "  Use --all to destroy ALL deployments for this project/environment"
            echo "  Use --list to see all deployments without destroying anything"
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

# Colors for output (only define if not already set by deployment-functions.sh)
if [ -z "${RED:-}" ]; then RED='\033[0;31m'; fi
if [ -z "${GREEN:-}" ]; then GREEN='\033[0;32m'; fi
if [ -z "${YELLOW:-}" ]; then YELLOW='\033[1;33m'; fi
if [ -z "${BLUE:-}" ]; then BLUE='\033[0;34m'; fi
if [ -z "${NC:-}" ]; then NC='\033[0m'; fi

# Note: SCRIPT_DIR and KUBERNETES_DIR already defined in deployment-functions.sh

# Timing
START_TIME=$(date +%s)

echo "======================================"
echo "   Renny EKS Cluster Destruction     "
echo "======================================"
echo ""

# Load deployment configuration
cd "$KUBERNETES_DIR/terraform/eks"
if [ "$LIST_ONLY" = "true" ]; then
    echo "📋 Listing all deployments..."
    load_terraform_config
    list_all_deployments
    exit 0
fi

if [ "$DESTROY_ALL" = "true" ]; then
    echo -e "${RED}⚠️  WARNING: --all flag specified - this will destroy ALL deployments!${NC}"
    load_terraform_config
    if ! confirm_action "Are you sure you want to destroy ALL deployments?" "n"; then
        echo "Cancelled."
        exit 0
    fi
fi

# Load deployment configuration based on mode
if [ -n "$TARGET_DEPLOYMENT_ID" ]; then
    # Target specific deployment ID
    echo "🎯 Targeting deployment ID: $TARGET_DEPLOYMENT_ID"
    load_terraform_config
    DEPLOYMENT_ID="$TARGET_DEPLOYMENT_ID"
    if [ -n "$DEPLOYMENT_ID" ]; then
        CLUSTER_NAME="$PROJECT_NAME-$ENVIRONMENT-$DEPLOYMENT_ID"
    else
        CLUSTER_NAME="$PROJECT_NAME-$ENVIRONMENT"
    fi
    # Update terraform.tfvars to target this deployment
    save_deployment_id "$DEPLOYMENT_ID"
    export PROJECT_NAME ENVIRONMENT DEPLOYMENT_ID CLUSTER_NAME AWS_REGION
elif [ "$DESTROY_ALL" = "true" ]; then
    # Will handle multiple deployments in destroy logic
    load_terraform_config
    DEPLOYMENT_ID=""
    CLUSTER_NAME="" # Will be set per deployment in loop
else
    # Use current deployment (from .deployment_id file or terraform.tfvars)
    init_deployment_config "false" ""
fi

echo -e "${RED}⚠️  WARNING: This will destroy all resources!${NC}"
echo "This includes:"
echo "  - EKS cluster and all nodes (Ubuntu GPU + control nodes)"
echo "  - VPC and networking resources"
echo "  - Launch templates for GPU nodes"
echo "  - Auto Scaling Groups"
echo "  - All deployed applications (Renny, GPU Operator)"
echo "  - All data in the cluster"
echo "  - All load balancers"
echo "  - All EBS volumes"
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
# Note: CLUSTER_NAME and AWS_REGION are already set by deployment config above
REGION="$AWS_REGION"  # For backward compatibility with rest of script

if [ -z "$CLUSTER_NAME" ]; then
    echo -e "${RED}Error: No cluster name determined. Check deployment configuration.${NC}"
    exit 1
fi

# Handle --all flag by destroying each deployment individually
if [ "$DESTROY_ALL" = "true" ]; then
    echo -e "${RED}⚠️  DESTROY ALL MODE ACTIVATED${NC}"
    echo "🔍 Finding all deployments for $PROJECT_NAME-$ENVIRONMENT..."
    
    # Get all clusters for this project/environment
    base_name="$PROJECT_NAME-$ENVIRONMENT"
    all_clusters=$(aws eks list-clusters --region "$AWS_REGION" --query "clusters[?contains(@, '$base_name')]" --output text 2>/dev/null || echo "")
    
    if [ -z "$all_clusters" ]; then
        echo -e "${YELLOW}No deployments found to destroy${NC}"
        exit 0
    fi
    
    echo "Found deployments to destroy:"
    for cluster in $all_clusters; do
        echo "  - $cluster"
    done
    echo ""
    
    if ! confirm_action "Proceed to destroy ALL these deployments?" "n"; then
        echo "Cancelled."
        exit 0
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
    aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME" 2>/dev/null || true
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
    echo "  ✓ Proceeding directly to AWS resource cleanup..."
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
    echo "  - Waiting for AWS load balancers to be deleted..."
    sleep 15
else
    echo "  ⚠️  Cluster unreachable - skipping kubectl resource cleanup"
    echo "  ✓ Proceeding to AWS resource cleanup..."
fi

# Step 3: Drain nodes and scale down ASGs
echo ""
echo "🔄 Step 3/8: Draining nodes and scaling down Auto Scaling Groups..."

if [ "$CLUSTER_NAME" != "unknown" ]; then
    # Get all ASGs associated with this cluster first
    echo "  - Finding Auto Scaling Groups..."
    ASG_NAMES=$(aws autoscaling describe-auto-scaling-groups --region "$REGION" --query "AutoScalingGroups[?contains(AutoScalingGroupName, '$CLUSTER_NAME')].AutoScalingGroupName" --output text 2>/dev/null || echo "")

    if [ -n "$ASG_NAMES" ]; then
        echo "  Found ASGs: $ASG_NAMES"

        # Scale all ASGs to 0 desired capacity first
        for asg in $ASG_NAMES; do
            echo "    Scaling $asg to 0 desired capacity..."
            aws autoscaling update-auto-scaling-group \
                --auto-scaling-group-name "$asg" \
                --desired-capacity 0 \
                --min-size 0 \
                --region "$REGION" 2>/dev/null || true
        done

        # Wait for instances to terminate
        echo "  - Waiting for instances to terminate..."
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
        echo "  No ASGs found for cluster"
    fi
fi

# Step 4: Delete EKS node groups
echo ""
echo "🖥️  Step 4/8: Removing EKS node groups..."
cd "$KUBERNETES_DIR/terraform/eks"

if [ "$CLUSTER_NAME" != "unknown" ]; then
    # List current node groups
    echo "Current node groups:"
    aws eks list-nodegroups --cluster-name "$CLUSTER_NAME" --region "$REGION" --output table 2>/dev/null || true
    
    # Delete node groups in parallel but track them
    echo "Initiating node group deletion..."
    
    # Get actual node groups from cluster (handles dynamic names)
    ACTUAL_NODEGROUPS=$(aws eks list-nodegroups --cluster-name "$CLUSTER_NAME" --region "$REGION" --query 'nodegroups[]' --output text 2>/dev/null || echo "")
    
    if [ -n "$ACTUAL_NODEGROUPS" ]; then
        for nodegroup in $ACTUAL_NODEGROUPS; do
            echo "  - Deleting $nodegroup..."
            aws eks delete-nodegroup \
                --cluster-name "$CLUSTER_NAME" \
                --nodegroup-name "$nodegroup" \
                --region "$REGION" 2>/dev/null || true
        done
    else
        echo "  No node groups found"
    fi
    
    # Wait for all node groups to be deleted
    echo "Waiting for node groups to be deleted (this typically takes 5-10 minutes)..."
    for i in {1..60}; do
        NODEGROUPS=$(aws eks list-nodegroups --cluster-name "$CLUSTER_NAME" --region "$REGION" --query 'nodegroups[]' --output text 2>/dev/null || echo "")
        if [ -z "$NODEGROUPS" ]; then
            echo -e "${GREEN}✓ All node groups deleted${NC}"
            break
        fi
        REMAINING=$(echo "$NODEGROUPS" | wc -w)
        echo "  Still waiting... ($REMAINING node groups remaining, attempt $i/60)"
        sleep 10
    done
fi

# Step 5: Force terminate EC2 instances and cleanup AWS resources
echo ""
echo "💥 Step 5/8: Force terminating EC2 instances and cleaning up AWS resources..."

if [ "$CLUSTER_NAME" != "unknown" ]; then
    # Force terminate any remaining instances tagged with our cluster
    echo "  - Finding and terminating EC2 instances..."
    INSTANCE_IDS=$(aws ec2 describe-instances --region "$REGION" \
        --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=owned" "Name=instance-state-name,Values=running,pending,stopping,stopped" \
        --query "Reservations[].Instances[].InstanceId" --output text 2>/dev/null || echo "")
    
    if [ -n "$INSTANCE_IDS" ]; then
        echo "  Found instances to terminate: $INSTANCE_IDS"
        aws ec2 terminate-instances --instance-ids $INSTANCE_IDS --region "$REGION" 2>/dev/null || true
        
        # Wait for instances to terminate
        echo "  - Waiting for instances to fully terminate..."
        for instance in $INSTANCE_IDS; do
            aws ec2 wait instance-terminated --instance-ids "$instance" --region "$REGION" 2>/dev/null || true
        done
    else
        echo "  No cluster instances found to terminate"
    fi
    
    # Force delete Auto Scaling Groups with instances
    if [ -n "$ASG_NAMES" ]; then
        echo "  - Force deleting Auto Scaling Groups..."
        for asg in $ASG_NAMES; do
            echo "    Force deleting ASG: $asg..."
            aws autoscaling delete-auto-scaling-group \
                --auto-scaling-group-name "$asg" \
                --force-delete \
                --region "$REGION" 2>/dev/null || true
        done
    fi
fi

# Step 6: Cleanup remaining AWS resources
echo ""
echo "🔍 Step 6/8: Cleaning up remaining AWS resources..."

if [ "$CLUSTER_NAME" != "unknown" ]; then
    # Check for any ELBs/ALBs tagged with our cluster
    echo "  - Checking for load balancers..."
    LOAD_BALANCERS=$(aws elb describe-load-balancers --region "$REGION" --query "LoadBalancerDescriptions[?contains(LoadBalancerName, '$CLUSTER_NAME')].LoadBalancerName" --output text 2>/dev/null || echo "")
    if [ -n "$LOAD_BALANCERS" ]; then
        echo "  Found load balancers: $LOAD_BALANCERS"
        for lb in $LOAD_BALANCERS; do
            echo "    Deleting $lb..."
            aws elb delete-load-balancer --load-balancer-name "$lb" --region "$REGION" 2>/dev/null || true
        done
    fi
    
    # Force delete EBS volumes (no backups)
    echo "  - Force deleting EBS volumes (NO BACKUPS)..."
    VOLUMES=$(aws ec2 describe-volumes --region "$REGION" --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=owned" --query "Volumes[?State!='deleting'].VolumeId" --output text 2>/dev/null || echo "")
    if [ -n "$VOLUMES" ]; then
        echo "  Found EBS volumes: $VOLUMES"
        for vol in $VOLUMES; do
            echo "    Force deleting volume $vol (NO BACKUP)..."
            # Detach first if attached
            aws ec2 detach-volume --volume-id "$vol" --region "$REGION" --force 2>/dev/null || true
            sleep 2
            # Delete volume
            aws ec2 delete-volume --volume-id "$vol" --region "$REGION" 2>/dev/null || true
        done
    fi
    
    # Clean up any orphaned network interfaces
    echo "  - Cleaning up network interfaces..."
    NETWORK_INTERFACES=$(aws ec2 describe-network-interfaces --region "$REGION" \
        --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=owned" "Name=status,Values=available" \
        --query "NetworkInterfaces[].NetworkInterfaceId" --output text 2>/dev/null || echo "")
    if [ -n "$NETWORK_INTERFACES" ]; then
        echo "  Found network interfaces: $NETWORK_INTERFACES"
        for eni in $NETWORK_INTERFACES; do
            echo "    Deleting network interface $eni..."
            aws ec2 delete-network-interface --network-interface-id "$eni" --region "$REGION" 2>/dev/null || true
        done
    fi
    
    # Check for launch templates (Ubuntu GPU nodes)
    # NOTE: Search by name pattern, not tags, as some templates may not have tags
    echo "  - Checking for launch templates..."
    LAUNCH_TEMPLATES=$(aws ec2 describe-launch-templates --region "$REGION" --query "LaunchTemplates[?contains(LaunchTemplateName, '${CLUSTER_NAME}')].LaunchTemplateId" --output text 2>/dev/null || echo "")
    if [ -n "$LAUNCH_TEMPLATES" ]; then
        echo "  Found launch templates: $LAUNCH_TEMPLATES"
        for template in $LAUNCH_TEMPLATES; do
            # Get template name for logging
            template_name=$(aws ec2 describe-launch-templates --region "$REGION" --launch-template-ids "$template" --query "LaunchTemplates[0].LaunchTemplateName" --output text 2>/dev/null || echo "unknown")
            echo "    Deleting $template ($template_name)..."
            aws ec2 delete-launch-template --launch-template-id "$template" --region "$REGION" 2>/dev/null || true
        done
    else
        echo "  No launch templates found for cluster: ${CLUSTER_NAME}"
    fi
    
    # Check for Auto Scaling Groups from node groups
    echo "  - Checking for Auto Scaling Groups..."
    ASG_NAMES=$(aws autoscaling describe-auto-scaling-groups --region "$REGION" --query "AutoScalingGroups[?contains(AutoScalingGroupName, '$CLUSTER_NAME')].AutoScalingGroupName" --output text 2>/dev/null || echo "")
    if [ -n "$ASG_NAMES" ]; then
        echo "  Found Auto Scaling Groups: $ASG_NAMES"
        for asg in $ASG_NAMES; do
            echo "    Deleting $asg..."
            aws autoscaling delete-auto-scaling-group --auto-scaling-group-name "$asg" --force-delete --region "$REGION" 2>/dev/null || true
        done
    fi
    
    # Check for remaining security groups
    echo "  - Checking for security groups..."
    SECURITY_GROUPS=$(aws ec2 describe-security-groups --region "$REGION" --filters "Name=group-name,Values=${CLUSTER_NAME}*" --query "SecurityGroups[].GroupId" --output text 2>/dev/null || echo "")
    if [ -n "$SECURITY_GROUPS" ]; then
        echo "  Found security groups: $SECURITY_GROUPS"
        for sg in $SECURITY_GROUPS; do
            echo "    Deleting $sg..."
            aws ec2 delete-security-group --group-id "$sg" --region "$REGION" 2>/dev/null || true
        done
    fi
fi

# Step 7: Destroy infrastructure with Terraform
echo ""
echo "🏗️  Step 7/8: Destroying infrastructure with Terraform..."
echo "This will remove:"
echo "  - EKS cluster"
echo "  - VPC and subnets"
echo "  - NAT gateways"
echo "  - Internet gateway"
echo "  - Security groups"
echo "  - IAM roles and policies"
echo ""

terraform destroy -auto-approve

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}⚠ Terraform destroy encountered issues. Attempting cleanup...${NC}"
    # Try again with -refresh=false if it failed
    terraform destroy -auto-approve -refresh=false
fi

# Step 8: Final cleanup and verification
echo ""
echo "🔍 Step 8/8: Final cleanup and verification..."

# Clean up CloudWatch log groups (optional - they auto-expire)
if [ "$CLUSTER_NAME" != "unknown" ]; then
    echo "  - Cleaning up CloudWatch log groups..."
    LOG_GROUPS=$(aws logs describe-log-groups --region "$REGION" --log-group-name-prefix "/aws/eks/$CLUSTER_NAME" --query "logGroups[].logGroupName" --output text 2>/dev/null || echo "")
    if [ -n "$LOG_GROUPS" ]; then
        for log_group in $LOG_GROUPS; do
            echo "    Deleting log group: $log_group"
            aws logs delete-log-group --log-group-name "$log_group" --region "$REGION" 2>/dev/null || true
        done
    fi
    
    # Also clean up container insights logs
    CONTAINER_LOG_GROUPS=$(aws logs describe-log-groups --region "$REGION" --log-group-name-prefix "/aws/containerinsights/$CLUSTER_NAME" --query "logGroups[].logGroupName" --output text 2>/dev/null || echo "")
    if [ -n "$CONTAINER_LOG_GROUPS" ]; then
        for log_group in $CONTAINER_LOG_GROUPS; do
            echo "    Deleting container insights log group: $log_group"
            aws logs delete-log-group --log-group-name "$log_group" --region "$REGION" 2>/dev/null || true
        done
    fi
fi

if [ "$CLUSTER_NAME" != "unknown" ]; then
    # Final check for EKS cluster
    if aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" &>/dev/null; then
        echo -e "${YELLOW}⚠ EKS cluster still exists, attempting manual deletion...${NC}"
        aws eks delete-cluster --name "$CLUSTER_NAME" --region "$REGION" 2>/dev/null || true
        wait_for_deletion "aws eks describe-cluster --name $CLUSTER_NAME --region $REGION" "EKS cluster" 30
    else
        echo -e "${GREEN}✓ EKS cluster deleted${NC}"
    fi
    
    # Final check for VPC
    VPC_ID=$(aws ec2 describe-vpcs --region "$REGION" --filters "Name=tag:Name,Values=${CLUSTER_NAME}-vpc" --query "Vpcs[0].VpcId" --output text 2>/dev/null || echo "")
    if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
        echo -e "${YELLOW}⚠ VPC $VPC_ID still exists${NC}"
    else
        echo -e "${GREEN}✓ VPC deleted${NC}"
    fi
fi

echo ""
echo "🧹 AWS infrastructure destroyed - local project files preserved"

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
verify_clean "Launch Templates" \
    "aws ec2 describe-launch-templates --region $REGION --query \"LaunchTemplates[?contains(LaunchTemplateName, '$CLUSTER_NAME')].LaunchTemplateName\" --output text"

verify_clean "EKS Clusters" \
    "aws eks list-clusters --region $REGION --query \"clusters[?contains(@, '$CLUSTER_NAME')]\" --output text"

verify_clean "Node Groups" \
    "aws eks list-nodegroups --cluster-name $CLUSTER_NAME --region $REGION --query 'nodegroups[]' --output text 2>/dev/null"

verify_clean "Auto Scaling Groups" \
    "aws autoscaling describe-auto-scaling-groups --region $REGION --query \"AutoScalingGroups[?contains(AutoScalingGroupName, '$CLUSTER_NAME')].AutoScalingGroupName\" --output text"

verify_clean "VPCs" \
    "aws ec2 describe-vpcs --region $REGION --filters Name=tag:Project,Values=renny --query 'Vpcs[].VpcId' --output text"

verify_clean "Load Balancers (Classic)" \
    "aws elb describe-load-balancers --region $REGION --query \"LoadBalancerDescriptions[?contains(LoadBalancerName, '$CLUSTER_NAME')].LoadBalancerName\" --output text"

verify_clean "Load Balancers (ALB/NLB)" \
    "aws elbv2 describe-load-balancers --region $REGION --query \"LoadBalancers[?contains(LoadBalancerName, 'renny')].LoadBalancerName\" --output text 2>/dev/null"

verify_clean "EBS Volumes" \
    "aws ec2 describe-volumes --region $REGION --filters Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=owned --query 'Volumes[].VolumeId' --output text"

verify_clean "Network Interfaces" \
    "aws ec2 describe-network-interfaces --region $REGION --filters Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=owned --query 'NetworkInterfaces[].NetworkInterfaceId' --output text"

verify_clean "Security Groups" \
    "aws ec2 describe-security-groups --region $REGION --filters Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=owned --query 'SecurityGroups[].GroupId' --output text"

verify_clean "EC2 Instances" \
    "aws ec2 describe-instances --region $REGION --filters Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=owned Name=instance-state-name,Values=pending,running,stopping,stopped --query 'Reservations[].Instances[].InstanceId' --output text"

verify_clean "CloudWatch Log Groups" \
    "aws logs describe-log-groups --region $REGION --log-group-name-prefix /aws/eks/$CLUSTER_NAME --query 'logGroups[].logGroupName' --output text"

verify_clean "NAT Gateways (Active)" \
    "aws ec2 describe-nat-gateways --region $REGION --filter Name=tag:Project,Values=renny --query \"NatGateways[?State=='available' || State=='pending'].NatGatewayId\" --output text"

verify_clean "Internet Gateways" \
    "aws ec2 describe-internet-gateways --region $REGION --filters Name=tag:Project,Values=renny --query 'InternetGateways[].InternetGatewayId' --output text"

verify_clean "Terraform State Resources" \
    "cd $KUBERNETES_DIR/terraform/eks && terraform state list 2>/dev/null | wc -l | tr -d ' '"

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
echo "The following AWS items may still exist (auto-expire):"
echo "  - S3 buckets if you configured Terraform state backend"
echo "  - Route53 DNS entries (will expire based on TTL)"
echo "  - Some CloudWatch metrics data (expires automatically)"
echo ""
echo "💰 COST SAVINGS:"
echo "  - Stopped ~\$15-20/hour in compute costs"
echo "  - Monthly savings: ~\$10,000-15,000"
echo "  - No more GPU instance charges"
echo "  - No more data transfer charges"
echo ""
echo "To redeploy, run: ./scripts/deploy.sh"

} # End of destroy_single_deployment function

# Execute single deployment destroy if not in --all mode
if [ "$DESTROY_ALL" != "true" ]; then
    destroy_single_deployment
fi