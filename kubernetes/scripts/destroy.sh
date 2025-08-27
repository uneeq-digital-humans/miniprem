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
echo -e "${YELLOW}Estimated time: 15-20 minutes${NC}"
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

# Step 1: Delete Helm releases
echo ""
echo "📦 Step 1/7: Removing Helm releases..."

echo "  - Removing Renny..."
helm uninstall renny -n uneeq-renderer --wait 2>/dev/null || true

echo "  - Removing Audio2Face..."
helm uninstall a2f -n uneeq-renderer --wait 2>/dev/null || true

echo "  - Removing GPU Operator..."
helm uninstall gpu-operator -n gpu-operator --wait 2>/dev/null || true

echo "  - Removing Cluster Autoscaler..."
helm uninstall cluster-autoscaler -n kube-system --wait 2>/dev/null || true

# Wait for pods to terminate
echo "⏳ Waiting for all pods to terminate..."
kubectl wait --for=delete pod --all -n uneeq-renderer --timeout=120s 2>/dev/null || true
kubectl wait --for=delete pod --all -n gpu-operator --timeout=120s 2>/dev/null || true

# Step 2: Clean up Kubernetes resources
echo ""
echo "🗑️  Step 2/7: Cleaning up Kubernetes resources..."

# Delete any services that might have created load balancers
echo "  - Deleting services with load balancers..."
kubectl delete svc --all -n uneeq-renderer --ignore-not-found=true 2>/dev/null || true

# Delete PVCs before namespaces
echo "  - Deleting persistent volume claims..."
kubectl delete pvc --all -n uneeq-renderer --ignore-not-found=true --wait=true 2>/dev/null || true

# Delete namespaces
echo "  - Deleting namespaces..."
kubectl delete namespace uneeq-renderer --ignore-not-found=true --wait=true --timeout=120s 2>/dev/null || true
kubectl delete namespace gpu-operator --ignore-not-found=true --wait=true --timeout=120s 2>/dev/null || true

# Wait for load balancers to be deleted
echo "  - Waiting for AWS load balancers to be deleted..."
sleep 30

# Step 3: Delete EKS node groups
echo ""
echo "🖥️  Step 3/7: Removing EKS node groups..."
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

# Step 4: Check for any remaining AWS resources
echo ""
echo "🔍 Step 4/7: Checking for remaining AWS resources..."

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
    
    # Check for any remaining EBS volumes
    echo "  - Checking for EBS volumes..."
    VOLUMES=$(aws ec2 describe-volumes --region "$REGION" --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=owned" --query "Volumes[].VolumeId" --output text 2>/dev/null || echo "")
    if [ -n "$VOLUMES" ]; then
        echo "  Found EBS volumes: $VOLUMES"
        for vol in $VOLUMES; do
            echo "    Deleting $vol..."
            aws ec2 delete-volume --volume-id "$vol" --region "$REGION" 2>/dev/null || true
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

# Step 5: Destroy infrastructure with Terraform
echo ""
echo "🏗️  Step 5/7: Destroying infrastructure with Terraform..."
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

# Step 6: Verify all resources are deleted
echo ""
echo "🔍 Step 6/7: Verifying resource deletion..."

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

# Step 7: Clean up local files
echo ""
echo "🧹 Step 7/7: Cleaning up local files..."
cd "$PROJECT_DIR"
rm -f values/renny-values-deployed.yaml
rm -f values/a2f-values-deployed.yaml
rm -f terraform/tfplan
rm -f terraform/.terraform.lock.hcl
rm -rf terraform/.terraform
rm -f terraform/terraform.tfstate*

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
echo "The following items may still exist:"
echo "  - CloudWatch log groups (will expire based on retention settings)"
echo "  - S3 buckets if you configured Terraform state backend"
echo "  - DNS entries (will expire based on TTL)"
echo ""
echo "Cost savings:"
echo "  - You've stopped approximately \$15-20/hour in compute costs"
echo "  - Monthly savings: ~\$10,000-15,000"
echo ""
echo "To redeploy, run: ./scripts/deploy.sh"