#!/bin/bash
set -e

echo "🚀 Starting Renny EKS Deployment..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Check prerequisites
check_prerequisites() {
    echo "📋 Checking prerequisites..."
    
    # Check for required tools
    for tool in terraform aws kubectl helm; do
        if ! command -v $tool &> /dev/null; then
            echo -e "${RED}❌ $tool is not installed${NC}"
            echo "Please install $tool and try again"
            exit 1
        fi
    done
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        echo -e "${RED}❌ AWS credentials not configured${NC}"
        echo "Please configure AWS credentials and try again"
        exit 1
    fi
    
    # Check for Helm chart
    if [ ! -f "$PROJECT_DIR/renny-chart.tgz" ]; then
        echo -e "${YELLOW}⚠️  renny-chart.tgz not found in $PROJECT_DIR${NC}"
        echo "Please place the Renny Helm chart tar file in the kubernetes/ directory"
        exit 1
    fi
    
    echo -e "${GREEN}✅ All prerequisites met${NC}"
}

# Create terraform.tfvars if it doesn't exist
create_tfvars() {
    if [ ! -f "$PROJECT_DIR/terraform/terraform.tfvars" ]; then
        echo "📝 Creating terraform.tfvars template..."
        cat > "$PROJECT_DIR/terraform/terraform.tfvars" <<EOF
# REQUIRED: Please fill in these values before running the deployment

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
    if grep -q '""' "$PROJECT_DIR/terraform/terraform.tfvars"; then
        echo -e "${RED}❌ terraform.tfvars contains empty values${NC}"
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
    echo "  - 10 GPU nodes for Renny (g5.2xlarge)"
    echo "  - 2 GPU nodes for Audio2Face (g5.2xlarge)"
    echo "  - 2 control plane nodes (t3.large)"
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
    
    # Wait for nodes to be ready
    echo "Waiting for all nodes to be ready..."
    local max_attempts=60
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready " || echo "0")
        TOTAL_NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "0")
        
        if [ "$TOTAL_NODES" -ge "14" ] && [ "$READY_NODES" -eq "$TOTAL_NODES" ]; then
            echo -e "${GREEN}✓ All $TOTAL_NODES nodes are ready${NC}"
            kubectl get nodes
            break
        fi
        
        echo "  Waiting for nodes... ($READY_NODES/$TOTAL_NODES ready, attempt $attempt/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        echo -e "${YELLOW}⚠ Some nodes may not be fully ready yet${NC}"
        kubectl get nodes
    fi
}

# Install NVIDIA GPU Operator
install_gpu_operator() {
    echo "🎮 Installing NVIDIA GPU Operator..."
    echo -e "${BLUE}This will take approximately 5-10 minutes${NC}"
    
    # Add NVIDIA Helm repository
    helm repo add nvidia https://helm.ngc.nvidia.com/nvidia || true
    helm repo update
    
    # Create namespace
    kubectl create namespace gpu-operator --dry-run=client -o yaml | kubectl apply -f -
    
    # Install GPU Operator
    echo "Installing GPU operator..."
    helm upgrade --install gpu-operator nvidia/gpu-operator \
        --namespace gpu-operator \
        --set operator.defaultRuntime=containerd \
        --set driver.enabled=true \
        --set toolkit.enabled=true \
        --set devicePlugin.enabled=true \
        --set dcgmExporter.enabled=true \
        --wait --timeout 15m
    
    echo "⏳ Waiting for GPU operator pods to be ready..."
    kubectl wait --for=condition=ready pod -l app=nvidia-operator -n gpu-operator --timeout=600s || true
    
    # Wait for GPU drivers to be installed on all GPU nodes
    echo "Waiting for GPU drivers to be installed on all nodes..."
    local gpu_nodes=$(kubectl get nodes -l nvidia.com/gpu=true --no-headers | wc -l)
    local max_attempts=60
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        READY_DRIVERS=$(kubectl get pods -n gpu-operator -l app=nvidia-driver-daemonset --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l || echo "0")
        
        if [ "$READY_DRIVERS" -ge "$gpu_nodes" ]; then
            echo -e "${GREEN}✓ GPU drivers installed on all $gpu_nodes GPU nodes${NC}"
            break
        fi
        
        echo "  Waiting for GPU drivers... ($READY_DRIVERS/$gpu_nodes ready, attempt $attempt/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    
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
    echo -e "${BLUE}This will take approximately 3-5 minutes${NC}"
    
    # Get Docker credentials
    cd "$PROJECT_DIR/terraform"
    DOCKER_USERNAME=$(grep docker_username terraform.tfvars | cut -d'"' -f2)
    DOCKER_PASSWORD=$(grep docker_password terraform.tfvars | cut -d'"' -f2)
    cd "$PROJECT_DIR"
    
    # Login to Docker Hub with Helm
    echo "Logging into Docker Hub..."
    echo "$DOCKER_PASSWORD" | helm registry login registry-1.docker.io -u "$DOCKER_USERNAME" --password-stdin
    
    # Install A2F
    echo "Installing Audio2Face Helm chart..."
    helm upgrade --install a2f oci://registry-1.docker.io/facemeproduction/a2f \
        --version 0.1-alpha \
        --namespace uneeq-renderer \
        -f "$PROJECT_DIR/values/a2f-values.yaml" \
        --wait --timeout 10m
    
    # Wait for A2F pods to be ready
    echo "Waiting for Audio2Face pods to be ready..."
    kubectl wait --for=condition=ready pod -l app=a2f -n uneeq-renderer --timeout=300s || true
    
    # Verify A2F deployment
    echo "Audio2Face deployment status:"
    kubectl get pods -n uneeq-renderer -l app=a2f
    
    echo -e "${GREEN}✓ Audio2Face installed successfully${NC}"
    show_elapsed
}

# Install Renny
install_renny() {
    echo "🤖 Installing Renny..."
    echo -e "${BLUE}This will take approximately 5-10 minutes${NC}"
    
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
    
    # Install Renny
    echo "Installing Renny Helm chart with 10 replicas..."
    helm upgrade --install renny "$PROJECT_DIR/renny-chart.tgz" \
        --namespace uneeq-renderer \
        -f "$PROJECT_DIR/values/renny-values-deployed.yaml" \
        --wait --timeout 15m
    
    # Wait for Renny pods to be ready
    echo "Waiting for Renny pods to be ready..."
    local max_attempts=60
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        READY_PODS=$(kubectl get pods -n uneeq-renderer -l app=renny --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l || echo "0")
        
        if [ "$READY_PODS" -ge "10" ]; then
            echo -e "${GREEN}✓ $READY_PODS Renny pods are running${NC}"
            break
        fi
        
        echo "  Waiting for Renny pods... ($READY_PODS/10 running, attempt $attempt/$max_attempts)"
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
    cd "$PROJECT_DIR"
    
    # Add autoscaler repo
    helm repo add autoscaler https://kubernetes.github.io/autoscaler || true
    helm repo update
    
    # Install cluster autoscaler
    echo "Installing cluster autoscaler for cluster: $CLUSTER_NAME"
    helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
        --namespace kube-system \
        --set autoDiscovery.clusterName=$CLUSTER_NAME \
        --set awsRegion=us-east-1 \
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
    cd "$PROJECT_DIR"
    
    echo "📊 Cluster Info:"
    echo "Cluster Name: $CLUSTER_NAME"
    echo "Region: us-east-1"
    echo ""
    
    echo "📋 Node Summary:"
    echo "  - Control nodes: 2x t3.large"
    echo "  - Renny GPU nodes: 10x g5.2xlarge"
    echo "  - A2F GPU nodes: 2x g5.2xlarge"
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
    echo "  - Access cluster: aws eks update-kubeconfig --region us-east-1 --name $CLUSTER_NAME"
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
    
    check_prerequisites
    create_tfvars
    deploy_infrastructure
    configure_kubectl
    install_gpu_operator
    setup_kubernetes_resources
    install_a2f
    install_renny
    install_autoscaler
    display_status
}

# Handle errors
trap 'echo -e "${RED}❌ An error occurred. Deployment failed.${NC}"' ERR

# Run main function
main