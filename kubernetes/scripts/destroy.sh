#!/bin/bash
set -e

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

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"

# Timing
START_TIME=$(date +%s)

echo "======================================"
echo "   Renny EKS Cluster Destruction     "
echo "======================================"
echo ""
echo -e "${RED}⚠️  WARNING: This will destroy all resources!${NC}"
echo "This includes:"
echo "  - EKS cluster and all nodes (Ubuntu GPU + control nodes)"
echo "  - VPC and networking resources"
echo "  - Launch templates for GPU nodes"
echo "  - Auto Scaling Groups"
echo "  - All deployed applications (Renny, A2F, GPU Operator)"
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

# Get cluster info first
cd "$PROJECT_DIR/terraform"
CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "unknown")
REGION=$(terraform output -raw region 2>/dev/null || echo "us-east-1")
cd "$PROJECT_DIR"

# Configure kubectl if possible
if [ "$CLUSTER_NAME" != "unknown" ]; then
    echo "Configuring kubectl for cluster: $CLUSTER_NAME"
    aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME" 2>/dev/null || true
fi

# Step 1: Force terminate all applications (no graceful shutdown)
echo ""
echo "🛑 Step 1/8: Force terminating all applications..."

echo "  - Force killing all Renny sessions and pods..."
kubectl delete pods -l app=renderer -n uneeq-renderer --force --grace-period=0 --wait=false 2>/dev/null || true

echo "  - Force killing all A2F pods..."  
kubectl delete pods -l app=a2f -n uneeq-renderer --force --grace-period=0 --wait=false 2>/dev/null || true

echo "  - Uninstalling Renny (with force)..."
helm uninstall renny -n uneeq-renderer --timeout=60s 2>/dev/null || true

echo "  - Uninstalling Audio2Face (with force)..."
helm uninstall a2f -n uneeq-renderer --timeout=60s 2>/dev/null || true

echo "  - Force killing GPU operator pods..."
kubectl delete pods -l app=nvidia-driver-daemonset -n gpu-operator --force --grace-period=0 --wait=false 2>/dev/null || true
kubectl delete pods -l app=nvidia-device-plugin-daemonset -n gpu-operator --force --grace-period=0 --wait=false 2>/dev/null || true

echo "  - Uninstalling GPU Operator..."
helm uninstall gpu-operator -n gpu-operator --timeout=60s 2>/dev/null || true

echo "  - Uninstalling Cluster Autoscaler..."
helm uninstall cluster-autoscaler -n kube-system --timeout=60s 2>/dev/null || true

# Force delete any remaining pods
echo "  - Force deleting any remaining pods..."
kubectl delete pods --all -n uneeq-renderer --force --grace-period=0 --wait=false 2>/dev/null || true
kubectl delete pods --all -n gpu-operator --force --grace-period=0 --wait=false 2>/dev/null || true

# Give pods a moment to terminate
sleep 15

# Step 2: Clean up Kubernetes resources and configurations
echo ""
echo "🗑️  Step 2/8: Cleaning up Kubernetes resources and configurations..."

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

# Delete any custom resource definitions we might have created
echo "  - Cleaning up CRDs..."
kubectl delete crd clusterpolicies.nvidia.com --ignore-not-found=true 2>/dev/null || true

# Force delete namespaces
echo "  - Force deleting namespaces..."
kubectl delete namespace uneeq-renderer --force --grace-period=0 --ignore-not-found=true --timeout=60s 2>/dev/null || true
kubectl delete namespace gpu-operator --force --grace-period=0 --ignore-not-found=true --timeout=60s 2>/dev/null || true

# Wait for load balancers to be deleted
echo "  - Waiting for AWS load balancers to be deleted..."
sleep 15

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
        
        # Drain all nodes before deletion
        echo "  - Draining all Kubernetes nodes..."
        kubectl get nodes --no-headers -o custom-columns=":metadata.name" | while read node; do
            echo "    Draining $node..."
            kubectl drain "$node" --ignore-daemonsets --delete-emptydir-data --force --grace-period=0 --timeout=60s 2>/dev/null || true
        done
    else
        echo "  No ASGs found for cluster"
    fi
fi

# Step 4: Delete EKS node groups
echo ""
echo "🖥️  Step 4/8: Removing EKS node groups..."
cd "$PROJECT_DIR/terraform"

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
    echo "  - Checking for launch templates..."
    LAUNCH_TEMPLATES=$(aws ec2 describe-launch-templates --region "$REGION" --filters "Name=tag:ManagedBy,Values=Terraform" "Name=launch-template-name,Values=${CLUSTER_NAME}*" --query "LaunchTemplates[].LaunchTemplateId" --output text 2>/dev/null || echo "")
    if [ -n "$LAUNCH_TEMPLATES" ]; then
        echo "  Found launch templates: $LAUNCH_TEMPLATES"
        for template in $LAUNCH_TEMPLATES; do
            echo "    Deleting $template..."
            aws ec2 delete-launch-template --launch-template-id "$template" --region "$REGION" 2>/dev/null || true
        done
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
echo "🧹 Final local cleanup..."
cd "$PROJECT_DIR"
# Clean up local files and temporary configs
rm -f terraform/tfplan
rm -f terraform/.terraform.lock.hcl
rm -rf terraform/.terraform
rm -f terraform/terraform.tfstate*
# gpu-time-slicing-config.yaml is a committed config file, not auto-generated
rm -f renny-chart.tgz                # Remove any temporary chart packages
rm -f .kubectl_context_backup        # Remove any kubectl context backups

# Calculate elapsed time
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
ELAPSED_MIN=$((ELAPSED / 60))
ELAPSED_SEC=$((ELAPSED % 60))

echo ""
echo "======================================"
echo -e "${GREEN}✅ All resources destroyed successfully${NC}"
echo "======================================"
echo ""
echo "Time elapsed: ${ELAPSED_MIN} minutes ${ELAPSED_SEC} seconds"
echo ""
echo "🧹 DESTRUCTION SUMMARY:"
echo "✅ Applications force-terminated (Renny, A2F, GPU Operator)"
echo "✅ Kubernetes resources cleaned (secrets, configs, time-slicing)"
echo "✅ Nodes drained and ASGs scaled to 0"
echo "✅ EKS node groups deleted"
echo "✅ EC2 instances force-terminated"
echo "✅ EBS volumes deleted (NO BACKUPS)"
echo "✅ Network interfaces cleaned up"
echo "✅ Launch templates deleted"
echo "✅ Load balancers deleted"
echo "✅ CloudWatch logs deleted"
echo "✅ EKS cluster destroyed"
echo "✅ VPC and networking destroyed"
echo "✅ IAM roles and policies cleaned up"
echo ""
echo "The following items may still exist:"
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