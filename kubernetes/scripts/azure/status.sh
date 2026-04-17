#!/bin/bash
# Azure AKS Status Check Script - shows current state of the deployment
#
# This script provides comprehensive status information for Azure AKS deployments
# with full feature parity to the AWS EKS status script.

set -e

# Source deployment functions
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Set TERRAFORM_DIR for Azure before sourcing deployment-functions.sh
TERRAFORM_DIR_AZURE="$SCRIPT_DIR/../terraform/aks"

source "$SCRIPT_DIR/deployment-functions.sh"

# Color definitions (already in deployment-functions.sh, but ensure they're available)
if [ -z "${RED:-}" ]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly CYAN='\033[0;36m'
    readonly NC='\033[0m' # No Color
fi

# Parse command line arguments
VERBOSE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Check status of Azure AKS Renny deployment"
            echo ""
            echo "Options:"
            echo "  --verbose, -v             Show verbose output"
            echo "  --help, -h                Show this help message"
            echo ""
            echo "Prerequisites:"
            echo "  - Azure CLI authenticated (az login)"
            echo "  - kubectl configured for AKS cluster"
            echo "  - terraform.tfvars in kubernetes/terraform/aks/"
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

echo "======================================"
echo "   Renny AKS Deployment Status       "
echo "   (Azure Kubernetes Service)        "
echo "======================================"
echo ""

# Check if terraform state exists
if [ ! -f "$TERRAFORM_DIR_AZURE/terraform.tfstate" ]; then
    echo -e "${RED}❌ No deployment found${NC}"
    echo "Run ./scripts/deploy-azure.sh to create a deployment"
    exit 1
fi

# Load deployment configuration
cd "$TERRAFORM_DIR_AZURE"

# Load Azure configuration (similar to AWS init but for Azure)
if [ ! -f "terraform.tfvars" ]; then
    echo -e "${RED}❌ terraform.tfvars not found${NC}"
    exit 1
fi

# Parse terraform.tfvars for Azure-specific settings
PROJECT_NAME=$(awk '/^project_name[[:space:]]*=/ {gsub(/[" ]/, "", $3); print $3}' terraform.tfvars 2>/dev/null || echo "renny")
ENVIRONMENT=$(awk '/^environment[[:space:]]*=/ {gsub(/[" ]/, "", $3); print $3}' terraform.tfvars 2>/dev/null || echo "production")
AZURE_REGION=$(awk '/^azure_region[[:space:]]*=/ {gsub(/[" ]/, "", $3); print $3}' terraform.tfvars 2>/dev/null)
RESOURCE_GROUP_NAME=$(awk '/^resource_group_name[[:space:]]*=/ {gsub(/[" ]/, "", $3); print $3}' terraform.tfvars 2>/dev/null || echo "renny-kubernetes")
DEPLOYMENT_ID=$(awk '/^deployment_id[[:space:]]*=/ {gsub(/[" ]/, "", $3); print $3}' terraform.tfvars 2>/dev/null || echo "")

# Read actual configuration from terraform.tfvars for accurate cost calculations
RENNY_DESIRED=$(awk '/^renny_desired_size[[:space:]]*=/ {gsub(/[^0-9]/, "", $3); print $3}' terraform.tfvars 2>/dev/null || echo "2")
RENNY_VM_SIZE=$(awk '/^renny_vm_size[[:space:]]*=/ {gsub(/"/, "", $3); print $3}' terraform.tfvars 2>/dev/null || echo "Standard_NC16as_T4_v3")

if [ -z "$AZURE_REGION" ]; then
    echo -e "${RED}❌ Could not get Azure region from terraform.tfvars${NC}"
    exit 1
fi

# Set cluster name
if [ -n "$DEPLOYMENT_ID" ]; then
    CLUSTER_NAME="$PROJECT_NAME-$ENVIRONMENT-$DEPLOYMENT_ID"
else
    CLUSTER_NAME="$PROJECT_NAME-$ENVIRONMENT"
fi

# Check Azure CLI authentication
echo "Checking Azure authentication..."
if ! az account show &>/dev/null; then
    echo -e "${RED}❌ Not authenticated with Azure${NC}"
    echo "Please run: az login"
    exit 1
fi

ACCOUNT_NAME=$(az account show --query "name" -o tsv 2>/dev/null || echo "Unknown")
echo -e "${GREEN}✅ Authenticated as: $ACCOUNT_NAME${NC}"

# Check if cluster exists
echo ""
echo "Checking AKS cluster: $CLUSTER_NAME"
if ! az aks show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP_NAME" &>/dev/null; then
    echo -e "${RED}❌ Cluster not found: $CLUSTER_NAME${NC}"
    echo "Please check:"
    echo "  - Cluster name is correct: $CLUSTER_NAME"
    echo "  - Resource group exists: $RESOURCE_GROUP_NAME"
    echo "  - Region is correct: $AZURE_REGION"
    exit 1
fi

# Get kubeconfig
echo "Configuring kubectl access..."
if ! az aks get-credentials --resource-group "$RESOURCE_GROUP_NAME" --name "$CLUSTER_NAME" --overwrite-existing &>/dev/null; then
    echo -e "${RED}❌ Could not get AKS credentials${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}📊 Cluster Overview${NC}"
echo "===================="
echo "Cluster: $CLUSTER_NAME"
echo "Region: $AZURE_REGION"
echo "Resource Group: $RESOURCE_GROUP_NAME"
if [ -n "$DEPLOYMENT_ID" ]; then
    echo "Deployment ID: $DEPLOYMENT_ID"
fi
echo ""

# Cluster status
CLUSTER_STATUS=$(az aks show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "provisioningState" -o tsv 2>/dev/null || echo "Unknown")
CLUSTER_VERSION=$(az aks show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "kubernetesVersion" -o tsv 2>/dev/null || echo "Unknown")

if [ "$CLUSTER_STATUS" = "Succeeded" ]; then
    echo -e "Status: ${GREEN}✅ $CLUSTER_STATUS${NC}"
else
    echo -e "Status: ${YELLOW}⚠️  $CLUSTER_STATUS${NC}"
fi
echo "Kubernetes Version: $CLUSTER_VERSION"

# Check for available upgrades
UPGRADE_AVAILABLE=$(az aks get-upgrades --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "controlPlaneProfile.upgrades[0].kubernetesVersion" -o tsv 2>/dev/null || echo "")
if [ -n "$UPGRADE_AVAILABLE" ] && [ "$UPGRADE_AVAILABLE" != "null" ]; then
    echo -e "${YELLOW}⚠️  Upgrade available: $UPGRADE_AVAILABLE${NC}"
fi
echo ""

# Node pool status
echo -e "${BLUE}🖥️  Node Pool Status${NC}"
echo "===================="

# Get all node pools
NODE_POOLS=$(az aks nodepool list --cluster-name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP_NAME" -o json 2>/dev/null)

if [ -z "$NODE_POOLS" ] || [ "$NODE_POOLS" = "[]" ]; then
    echo -e "${RED}❌ No node pools found${NC}"
else
    # Parse node pools
    echo "$NODE_POOLS" | jq -r '.[] | "\(.name)|\(.vmSize)|\(.count)|\(.provisioningState)|\(.enableAutoScaling)"' | while IFS='|' read -r pool_name vm_size count status autoscale; do
        if [ "$status" = "Succeeded" ]; then
            status_icon="${GREEN}✅${NC}"
        else
            status_icon="${YELLOW}⚠️${NC}"
        fi

        autoscale_text=""
        if [ "$autoscale" = "true" ]; then
            # Get min/max for autoscaling
            min_count=$(echo "$NODE_POOLS" | jq -r ".[] | select(.name==\"$pool_name\") | .minCount // \"N/A\"")
            max_count=$(echo "$NODE_POOLS" | jq -r ".[] | select(.name==\"$pool_name\") | .maxCount // \"N/A\"")
            autoscale_text=" (autoscale: $min_count-$max_count)"
        fi

        echo -e "$status_icon Pool: $pool_name"
        echo "   VM Size: $vm_size | Nodes: $count$autoscale_text"
        echo "   Status: $status"
        echo ""
    done
fi

# Node status
echo -e "${BLUE}🖥️  Kubernetes Node Status${NC}"
echo "===================="
TOTAL_NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ' || echo "0")
READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready " || echo "0")
echo "Total Nodes: $TOTAL_NODES"
echo "Ready Nodes: $READY_NODES"

if [ "$TOTAL_NODES" != "$READY_NODES" ]; then
    echo -e "${YELLOW}⚠️  Not all nodes are ready${NC}"
fi
echo ""

# Node breakdown by pool
echo "Node Groups:"
SYSTEM_NODES=$(kubectl get nodes -l agentpool --no-headers 2>/dev/null | grep -c "system" || echo "0")
GPU_NODES=$(kubectl get nodes -l agentpool --no-headers 2>/dev/null | grep -c "rennygpu" || echo "0")

echo "  System Nodes: $SYSTEM_NODES"
echo "  GPU Nodes (Renny): $GPU_NODES ($RENNY_VM_SIZE)"
echo ""

# GPU Status
echo -e "${BLUE}🎮 GPU Status${NC}"
echo "===================="

# Check for GPU operator
GPU_OP_RUNNING=$(kubectl get pods -n gpu-operator --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ' || echo "0")
if [ "$GPU_OP_RUNNING" -gt 0 ]; then
    echo -e "GPU Operator: ${GREEN}✅ Running ($GPU_OP_RUNNING pods)${NC}"

    # Check GPU driver daemonset
    GPU_DRIVER_READY=$(kubectl get pods -n gpu-operator -l app=nvidia-driver-daemonset -o jsonpath='{range .items[*]}{.status.phase}{"\n"}{end}' 2>/dev/null | grep -c "Running" || echo "0")
    echo "GPU Drivers: $GPU_DRIVER_READY/$GPU_NODES nodes"

    # Get total GPU capacity
    TOTAL_GPUS=$(kubectl get nodes -o json 2>/dev/null | jq -r '[.items[] | select(.status.capacity."nvidia.com/gpu" != null) | .status.capacity."nvidia.com/gpu" | tonumber] | add // 0')
    if [ "$TOTAL_GPUS" -gt 0 ]; then
        echo -e "Total GPUs: ${GREEN}$TOTAL_GPUS available${NC}"

        # Check time-slicing configuration
        TIME_SLICE_CONFIG=$(kubectl get configmap -n gpu-operator renny-time-slicing-config -o jsonpath='{.data.renny}' 2>/dev/null | grep -oP 'replicas: \K\d+' || echo "")
        if [ -n "$TIME_SLICE_CONFIG" ]; then
            EFFECTIVE_GPUS=$((TOTAL_GPUS * TIME_SLICE_CONFIG))
            echo "GPU Time-Slicing: ${TIME_SLICE_CONFIG}x (${EFFECTIVE_GPUS} effective GPU slots)"
        fi
    else
        echo -e "${YELLOW}⚠️  GPUs not yet available${NC}"
    fi
else
    echo -e "GPU Operator: ${RED}❌ Not running${NC}"
fi
echo ""

# Pod status
echo -e "${BLUE}🚀 Application Status${NC}"
echo "===================="

# Renny pods
RENNY_RUNNING=$(kubectl get pods -n uneeq-renderer -l app=renny --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ' || echo "0")
RENNY_TOTAL=$(kubectl get pods -n uneeq-renderer -l app=renny --no-headers 2>/dev/null | wc -l | tr -d ' ' || echo "0")

if [ "$RENNY_TOTAL" -gt 0 ]; then
    if [ "$RENNY_RUNNING" -eq "$RENNY_TOTAL" ]; then
        echo -e "Renny: ${GREEN}✅ $RENNY_RUNNING/$RENNY_TOTAL pods running${NC}"
    else
        echo -e "Renny: ${YELLOW}⚠️  $RENNY_RUNNING/$RENNY_TOTAL pods running${NC}"

        # Show pod status breakdown
        if [ "$VERBOSE" = true ]; then
            echo ""
            echo "Pod details:"
            kubectl get pods -n uneeq-renderer -l app=renny
        fi
    fi

    # Get pod readiness
    RENNY_READY=$(kubectl get pods -n uneeq-renderer -l app=renny -o json 2>/dev/null | jq '[.items[] | select(.status.conditions[] | select(.type=="Ready" and .status=="True"))] | length')
    if [ "$RENNY_READY" != "$RENNY_TOTAL" ]; then
        echo -e "   ${YELLOW}⚠️  Ready: $RENNY_READY/$RENNY_TOTAL${NC}"
    fi
else
    echo -e "Renny: ${RED}❌ Not deployed${NC}"
fi
echo ""

# Resource usage
echo -e "${BLUE}📈 Resource Usage${NC}"
echo "===================="

# Try to get resource metrics with timeout
if timeout 10s kubectl top nodes &>/dev/null; then
    echo "Node resource usage:"
    kubectl top nodes 2>/dev/null || echo "Metrics not available"
    echo ""

    if [ "$RENNY_TOTAL" -gt 0 ]; then
        echo "Renny pod resource usage (top 5):"
        kubectl top pods -n uneeq-renderer -l app=renny --no-headers 2>/dev/null | head -5 || echo "Metrics not available"
    fi
else
    echo -e "${YELLOW}⚠️  Metrics not available (metrics-server may not be ready)${NC}"
    echo "To install metrics-server:"
    echo "  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
fi
echo ""

# Azure Monitor integration
echo -e "${BLUE}📊 Azure Monitor Integration${NC}"
echo "===================="

MONITORING_ADDON=$(az aks show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "addonProfiles.omsagent.enabled" -o tsv 2>/dev/null || echo "false")
if [ "$MONITORING_ADDON" = "true" ]; then
    echo -e "${GREEN}✅ Azure Monitor enabled${NC}"
    WORKSPACE_ID=$(az aks show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "addonProfiles.omsagent.config.logAnalyticsWorkspaceResourceID" -o tsv 2>/dev/null || echo "")
    if [ -n "$WORKSPACE_ID" ]; then
        echo "Log Analytics Workspace: $(basename $WORKSPACE_ID)"
    fi
else
    echo -e "${YELLOW}⚠️  Azure Monitor not enabled${NC}"
    echo "To enable: ./scripts/deploy-azure.sh (monitoring setup step)"
fi
echo ""

# Network profile
if [ "$VERBOSE" = true ]; then
    echo -e "${BLUE}🌐 Network Configuration${NC}"
    echo "===================="

    NETWORK_PLUGIN=$(az aks show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "networkProfile.networkPlugin" -o tsv 2>/dev/null || echo "Unknown")
    SERVICE_CIDR=$(az aks show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "networkProfile.serviceCidr" -o tsv 2>/dev/null || echo "Unknown")
    DNS_SERVICE_IP=$(az aks show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "networkProfile.dnsServiceIp" -o tsv 2>/dev/null || echo "Unknown")

    echo "Network Plugin: $NETWORK_PLUGIN"
    echo "Service CIDR: $SERVICE_CIDR"
    echo "DNS Service IP: $DNS_SERVICE_IP"
    echo ""
fi

# Cost estimate based on actual configuration
echo -e "${BLUE}💰 Cost Estimate${NC}"
echo "===================="

# Azure VM pricing (USD/hour) - approximate pricing for US regions
get_vm_cost() {
    case $1 in
        "Standard_D2s_v3") echo "0.096" ;;
        "Standard_D4s_v3") echo "0.192" ;;
        "Standard_NC16as_T4_v3") echo "1.204" ;;
        "Standard_NC64as_T4_v3") echo "4.352" ;;
        *) echo "1.00" ;;  # default estimate
    esac
}

# Calculate system node costs
SYSTEM_COST=0
SYSTEM_VM_SIZE="Standard_D2s_v3"  # Default for system nodes
if [ "$SYSTEM_NODES" -gt 0 ]; then
    SYSTEM_VM_COST=$(get_vm_cost "$SYSTEM_VM_SIZE")
    SYSTEM_COST=$(echo "scale=2; $SYSTEM_NODES * $SYSTEM_VM_COST" | bc 2>/dev/null || echo "0")
fi

# Calculate GPU node costs
GPU_COST=0
if [ "$GPU_NODES" -gt 0 ]; then
    GPU_VM_COST=$(get_vm_cost "$RENNY_VM_SIZE")
    GPU_COST=$(echo "scale=2; $GPU_NODES * $GPU_VM_COST" | bc 2>/dev/null || echo "0")
fi

# Total costs
HOURLY_COST=$(echo "scale=2; $SYSTEM_COST + $GPU_COST" | bc 2>/dev/null || echo "0")
DAILY_COST=$(echo "scale=2; $HOURLY_COST * 24" | bc 2>/dev/null || echo "0")
MONTHLY_COST=$(echo "scale=2; $DAILY_COST * 30" | bc 2>/dev/null || echo "0")

echo "Instance breakdown:"
if [ "$SYSTEM_NODES" -gt 0 ]; then
    echo "  System ($SYSTEM_VM_SIZE): $SYSTEM_NODES × \$$SYSTEM_VM_COST/hr = \$$SYSTEM_COST/hr"
fi
if [ "$GPU_NODES" -gt 0 ]; then
    echo "  GPU ($RENNY_VM_SIZE): $GPU_NODES × \$$GPU_VM_COST/hr = \$$GPU_COST/hr"
fi
echo ""

echo "Estimated costs (USD):"
echo "  Hourly: ~\$$HOURLY_COST"
echo "  Daily: ~\$$DAILY_COST"
echo "  Monthly: ~\$$MONTHLY_COST"
echo ""

echo -e "${YELLOW}Note: Costs may vary by region and include additional charges for:${NC}"
echo "  - Storage (managed disks)"
echo "  - Network egress"
echo "  - Load balancers"
echo "  - Log Analytics (if enabled)"
echo ""

# Recent events with better formatting
echo -e "${BLUE}📋 Recent Events${NC}"
echo "===================="
if kubectl get events -n uneeq-renderer --sort-by='.lastTimestamp' 2>/dev/null | tail -5 > /tmp/events.tmp; then
    if [ -s /tmp/events.tmp ]; then
        cat /tmp/events.tmp
    else
        echo "No recent events in uneeq-renderer namespace"
    fi
    rm -f /tmp/events.tmp
else
    echo "Could not retrieve events (namespace may not exist yet)"
fi

echo ""

# Health summary
echo -e "${BLUE}🏥 Health Summary${NC}"
echo "===================="

HEALTH_SCORE=0
HEALTH_MAX=6
HEALTH_ISSUES=()

# Check cluster status
if [ "$CLUSTER_STATUS" = "Succeeded" ]; then
    ((HEALTH_SCORE++))
else
    HEALTH_ISSUES+=("Cluster provisioning state: $CLUSTER_STATUS")
fi

# Check node readiness
if [ "$TOTAL_NODES" -eq "$READY_NODES" ] && [ "$TOTAL_NODES" -gt 0 ]; then
    ((HEALTH_SCORE++))
else
    HEALTH_ISSUES+=("Not all nodes ready: $READY_NODES/$TOTAL_NODES")
fi

# Check GPU operator
if [ "$GPU_OP_RUNNING" -gt 0 ]; then
    ((HEALTH_SCORE++))
else
    HEALTH_ISSUES+=("GPU operator not running")
fi

# Check GPU availability
if [ "${TOTAL_GPUS:-0}" -gt 0 ]; then
    ((HEALTH_SCORE++))
else
    HEALTH_ISSUES+=("No GPUs available")
fi

# Check Renny pods
if [ "$RENNY_TOTAL" -gt 0 ]; then
    ((HEALTH_SCORE++))
    if [ "$RENNY_RUNNING" -eq "$RENNY_TOTAL" ]; then
        ((HEALTH_SCORE++))
    else
        HEALTH_ISSUES+=("Not all Renny pods running: $RENNY_RUNNING/$RENNY_TOTAL")
    fi
else
    HEALTH_ISSUES+=("No Renny pods deployed")
fi

# Calculate health percentage
HEALTH_PERCENT=$((HEALTH_SCORE * 100 / HEALTH_MAX))

if [ "$HEALTH_PERCENT" -ge 80 ]; then
    HEALTH_COLOR="$GREEN"
    HEALTH_STATUS="Healthy"
elif [ "$HEALTH_PERCENT" -ge 50 ]; then
    HEALTH_COLOR="$YELLOW"
    HEALTH_STATUS="Degraded"
else
    HEALTH_COLOR="$RED"
    HEALTH_STATUS="Unhealthy"
fi

echo -e "Overall Health: ${HEALTH_COLOR}${HEALTH_STATUS} (${HEALTH_SCORE}/${HEALTH_MAX})${NC}"

if [ ${#HEALTH_ISSUES[@]} -gt 0 ]; then
    echo ""
    echo "Issues detected:"
    for issue in "${HEALTH_ISSUES[@]}"; do
        echo "  - $issue"
    done
fi
echo ""

# Recommendations
echo -e "${BLUE}💡 Recommendations${NC}"
echo "===================="

if [ "$UPGRADE_AVAILABLE" != "" ] && [ "$UPGRADE_AVAILABLE" != "null" ]; then
    echo "• Consider upgrading to Kubernetes $UPGRADE_AVAILABLE"
fi

if [ "$MONITORING_ADDON" = "false" ]; then
    echo "• Enable Azure Monitor for better observability"
fi

if [ "${TOTAL_GPUS:-0}" -eq 0 ] && [ "$GPU_NODES" -gt 0 ]; then
    echo "• GPU nodes present but GPUs not available - check GPU operator logs"
fi

if [ "$RENNY_TOTAL" -gt 0 ] && [ "$RENNY_RUNNING" -lt "$RENNY_TOTAL" ]; then
    echo "• Some Renny pods are not running - check pod logs and events"
fi

if [ "$MONTHLY_COST" != "0" ]; then
    COST_CHECK=$(echo "$MONTHLY_COST > 5000" | bc 2>/dev/null || echo "0")
    if [ "$COST_CHECK" -eq 1 ]; then
        echo "• High monthly costs detected (~\$$MONTHLY_COST) - consider cost optimization"
    fi
fi

echo ""
echo "======================================"
echo -e "${GREEN}Status check complete${NC}"
echo ""
echo "Useful Commands:"
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
echo "  kubectl logs -n uneeq-renderer -l app=renny --tail=50"
echo ""
echo "  # Test GPU"
echo "  kubectl run gpu-test --rm -it --restart=Never \\"
echo "    --image=nvidia/cuda:12.4-runtime-ubuntu22.04 \\"
echo "    --overrides='{\"spec\":{\"nodeSelector\":{\"agentpool\":\"rennygpu\"}}}' \\"
echo "    -- nvidia-smi"
echo ""
echo "Management Commands:"
echo "  # Scale Renny: ./scripts/scale-azure.sh <count>"
echo "  # Destroy: ./scripts/destroy-azure.sh"
echo "  # View in Azure Portal:"
echo "  #   https://portal.azure.com/#resource/subscriptions/.../resourceGroups/$RESOURCE_GROUP_NAME"
echo ""
