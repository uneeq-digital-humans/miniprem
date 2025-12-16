# Azure AKS Terraform Infrastructure

This directory contains Terraform configuration for deploying the MiniPrem Renny digital human platform on Azure Kubernetes Service (AKS).

## Architecture Overview

- **Cluster**: Production-ready AKS with autoscaling
- **GPU Nodes**: Standard_NC16as_T4_v3 (NVIDIA T4 GPUs)
- **Networking**: Azure CNI with NAT Gateway
- **Authentication**: Managed Identity (modern Azure authentication)
- **Scaling**: 10-20 GPU nodes with cluster autoscaler
- **Time-Slicing**: 4 Renny pods per GPU node

## Prerequisites

### 1. Azure CLI
```bash
# Install Azure CLI (macOS)
brew install azure-cli

# Login to Azure
az login

# Set default subscription
az account set --subscription "YOUR_SUBSCRIPTION_ID"

# Verify
az account show
```

### 2. Terraform
```bash
# Install Terraform (macOS)
brew install terraform

# Verify
terraform version  # Should be >= 1.0
```

### 3. kubectl
```bash
# Install kubectl (macOS)
brew install kubectl

# Verify
kubectl version --client
```

### 4. Azure Permissions
Your Azure account must have:
- Contributor role on the subscription
- Permissions to create:
  - Resource Groups
  - Virtual Networks
  - AKS Clusters
  - Managed Identities
  - Role Assignments

Check permissions:
```bash
az role assignment list --assignee $(az account show --query user.name -o tsv) --output table
```

## Configuration

### 1. Edit terraform.tfvars

Update the following required values:

```hcl
# Azure subscription ID
azure_subscription_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# DHOP credentials (from UneeQ platform)
dhop_tenant_id = "your-tenant-id"
dhop_api_key   = "your-api-key"

# Docker Hub credentials (must have UneeQ repository access)
docker_username = "your-docker-username"
docker_password = "your-docker-password"
```

### 2. Optional Configuration

Customize these values if needed:

```hcl
# Azure region
azure_region = "eastus"  # Options: eastus, westus2, westeurope

# Network configuration (PERMANENT - cannot change without rebuild)
vnet_cidr    = "10.17.0.0/16"
subnet_cidr  = "10.17.0.0/22"
service_cidr = "10.117.0.0/16"

# GPU node configuration
renny_vm_size      = "Standard_NC16as_T4_v3"  # CRITICAL: Use T4, not A10 vGPU
renny_min_size     = 10
renny_max_size     = 20
renny_desired_size = 10
```

## Critical GPU Configuration

### Why Standard_NC16as_T4_v3?

1. **Standard NVIDIA Drivers**: Uses driver 580+ (production tested)
2. **GPU Operator Compatible**: Works with standard GPU Operator workflow
3. **No vGPU Licensing**: No NVIDIA GRID license required
4. **Proven Architecture**: Same driver model as AWS EKS deployment

### DO NOT Use Standard_NVads_A10_v5

- Requires vGPU drivers (incompatible with GPU Operator)
- Requires NVIDIA GRID licensing
- Complex setup, not production tested
- Driver conflicts with standard workflows

### SkipGPUDriverInstall Tag

The GPU node pool has this critical tag:

```hcl
tags = {
  SkipGPUDriverInstall = "true"
}
```

**Why this matters**:
- Prevents Azure from pre-installing GPU drivers
- Allows GPU Operator to install driver 580 with proper configuration
- GPU Operator handles driver lifecycle (updates, rollbacks)
- Without this tag: driver conflicts and pod failures

## Deployment

### Step 1: Initialize Terraform

```bash
cd kubernetes/terraform/aks
terraform init
```

This downloads required providers:
- azurerm (~3.0)
- kubernetes (~2.23)
- helm (~2.11)

### Step 2: Plan Deployment

```bash
terraform plan -var-file=terraform.tfvars
```

Review the plan carefully. It should create:
- 1 Resource Group
- 1 Virtual Network + Subnet
- 1 NAT Gateway
- 1 AKS Cluster
- 1 System Node Pool (2 nodes)
- 1 GPU Node Pool (10 nodes initial)
- 1 Managed Identity for autoscaler
- Role assignments

### Step 3: Deploy Infrastructure

```bash
terraform apply -var-file=terraform.tfvars
```

**Deployment time**: ~15-20 minutes

### Step 4: Configure kubectl

```bash
# Get AKS credentials
az aks get-credentials \
  --resource-group $(terraform output -raw resource_group_name) \
  --name $(terraform output -raw cluster_name) \
  --overwrite-existing

# Verify connection
kubectl get nodes
kubectl get nodes -L agentpool,kubernetes.io/arch
```

Expected output:
```
NAME                                STATUS   ROLES   AGE   VERSION
aks-rennygpu-12345678-vmss000000   Ready    agent   5m    v1.31.0
aks-system-12345678-vmss000000     Ready    agent   5m    v1.31.0
aks-system-12345678-vmss000001     Ready    agent   5m    v1.31.0
```

## Post-Deployment

### 1. Install GPU Operator

The GPU Operator automatically installs NVIDIA drivers (580+) on GPU nodes.

```bash
# Add NVIDIA Helm repository
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

# Install GPU Operator
helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --create-namespace \
  --set driver.version="580" \
  --wait
```

**Installation time**: ~10-15 minutes (driver compilation)

### 2. Verify GPU Setup

```bash
# Check GPU Operator pods
kubectl get pods -n gpu-operator

# Verify NVIDIA drivers on GPU node
kubectl exec -n gpu-operator \
  $(kubectl get pods -n gpu-operator -l app=nvidia-driver-daemonset -o name | head -1) \
  -- nvidia-smi

# Check node labels
kubectl get nodes -L nvidia.com/gpu,uneeq.io/node-type
```

Expected output:
```
NAME                                nvidia.com/gpu   uneeq.io/node-type
aks-rennygpu-12345678-vmss000000   true             renny
aks-system-12345678-vmss000000     <none>           <none>
```

### 3. Deploy Renny Application

```bash
# Create namespace
kubectl create namespace uneeq-renderer

# Create Harbor registry secret
kubectl create secret docker-registry harbor-credentials \
  --namespace uneeq-renderer \
  --docker-server=https://cr.uneeq.io \
  --docker-username=$(terraform output -raw harbor_username) \
  --docker-password=$(terraform output -raw harbor_password)

# Apply Renny manifests
kubectl apply -f ../manifests/renny/
```

## Monitoring

### Check Cluster Status

```bash
# Node status
kubectl get nodes -o wide

# Pod status
kubectl get pods -n uneeq-renderer

# GPU utilization
kubectl exec -n gpu-operator \
  $(kubectl get pods -n gpu-operator -l app=nvidia-driver-daemonset -o name | head -1) \
  -- nvidia-smi
```

### View Logs

```bash
# Renny pod logs
kubectl logs -n uneeq-renderer -l app=renny --tail=100 -f

# GPU Operator logs
kubectl logs -n gpu-operator -l app=nvidia-driver-daemonset --tail=50
```

### Azure Portal Monitoring

Navigate to: Azure Portal → Resource Groups → renny-kubernetes → AKS Cluster

- **Workloads**: View pods and deployments
- **Services and ingresses**: Check service endpoints
- **Monitoring**: CPU, memory, and GPU metrics
- **Logs**: Azure Monitor integration

## Scaling

### Manual Scaling

```bash
# Scale GPU node pool
az aks nodepool update \
  --resource-group $(terraform output -raw resource_group_name) \
  --cluster-name $(terraform output -raw cluster_name) \
  --name rennygpu \
  --min-count 5 \
  --max-count 30

# Scale Renny pods
kubectl scale deployment renny -n uneeq-renderer --replicas=50
```

### Autoscaling

The cluster autoscaler automatically adjusts node count based on pod resource requests.

```bash
# Check autoscaler status
kubectl get configmap cluster-autoscaler-status -n kube-system -o yaml

# View autoscaler logs
kubectl logs -n kube-system -l app=cluster-autoscaler
```

## Cost Management

### Estimated Monthly Costs (eastus pricing)

| Resource | Quantity | Unit Cost | Monthly Cost |
|----------|----------|-----------|--------------|
| GPU Nodes (NC16as_T4_v3) | 10 | $1.20/hour | $8,640 |
| System Nodes (D4s_v3) | 2 | $0.192/hour | $280 |
| NAT Gateway | 1 | $0.045/hour | $32 |
| **Total (10 GPU nodes)** | | | **$8,952** |
| **Total (20 GPU nodes)** | | | **$17,592** |

### Cost Optimization Strategies

1. **Autoscaling**: Scale down during off-hours
   ```bash
   # Evening scale-down
   kubectl scale deployment renny -n uneeq-renderer --replicas=10

   # Morning scale-up
   kubectl scale deployment renny -n uneeq-renderer --replicas=40
   ```

2. **Reserved Instances**: Up to 72% savings with 3-year commitment
   - Navigate to: Azure Portal → Reservations
   - Select: Virtual Machine → NC16as_T4_v3
   - Term: 1-year (43% savings) or 3-year (72% savings)

3. **Stop Cluster**: Manual shutdown during extended downtime
   ```bash
   # Stop AKS cluster (preserves configuration)
   az aks stop \
     --resource-group $(terraform output -raw resource_group_name) \
     --name $(terraform output -raw cluster_name)

   # Start AKS cluster
   az aks start \
     --resource-group $(terraform output -raw resource_group_name) \
     --name $(terraform output -raw cluster_name)
   ```

4. **Spot Instances**: Not recommended for GPU workloads (interruption risk)

## Troubleshooting

### Issue: GPU Nodes Not Ready

**Symptoms**:
```bash
kubectl get nodes
# Shows GPU nodes in NotReady state
```

**Diagnosis**:
```bash
kubectl describe node <gpu-node-name>
kubectl logs -n gpu-operator -l app=nvidia-driver-daemonset
```

**Common Causes**:
1. GPU Operator still installing drivers (wait 10-15 minutes)
2. Missing SkipGPUDriverInstall tag (driver conflict)
3. Wrong VM size (must be NC16as_T4_v3, not NVads_A10_v5)

**Resolution**:
```bash
# Check GPU Operator status
kubectl get pods -n gpu-operator

# Verify SkipGPUDriverInstall tag
az vm list --resource-group <node-resource-group> --query "[].tags"
```

### Issue: Pods Stuck in Pending

**Symptoms**:
```bash
kubectl get pods -n uneeq-renderer
# Shows pods in Pending state
```

**Diagnosis**:
```bash
kubectl describe pod <pod-name> -n uneeq-renderer
```

**Common Causes**:
1. Insufficient GPU resources (pods waiting for GPU nodes)
2. Node taints without matching tolerations
3. Missing node selectors

**Resolution**:
```bash
# Check GPU node availability
kubectl get nodes -L nvidia.com/gpu

# Verify pod tolerations
kubectl get pod <pod-name> -n uneeq-renderer -o yaml | grep -A 5 tolerations

# Check node taints
kubectl describe nodes -l uneeq.io/node-type=renny | grep Taints
```

### Issue: High Costs

**Symptoms**: Azure bill higher than expected

**Diagnosis**:
```bash
# Check node count
kubectl get nodes

# Check running pods
kubectl get pods -A

# Azure cost analysis
az consumption usage list --output table
```

**Resolution**:
1. Scale down unused resources
2. Enable autoscaling
3. Consider reserved instances
4. Stop cluster during off-hours

## Cleanup

### Destroy Infrastructure

**WARNING**: This will delete all resources and data. Make sure to backup any persistent data first.

```bash
# Destroy all resources
terraform destroy -var-file=terraform.tfvars
```

**Destruction time**: ~15-20 minutes

### Verify Cleanup

```bash
# Check resource group
az group list --query "[?name=='renny-kubernetes']"

# If stuck resources exist, force delete
az group delete --name renny-kubernetes --yes --no-wait
```

## Architecture Decisions

### Azure CNI vs Kubenet

**We use Azure CNI** because:
- Production-grade networking with native Azure integration
- Each pod gets an IP from the VNet subnet
- Better performance and security
- Advanced networking features (Network Policy, Service Endpoints)
- Required for enterprise deployments

**Kubenet** (not used):
- Basic networking with NAT
- Pods use separate IP space (not VNet IPs)
- Limited networking features
- Not recommended for production

### Managed Identity vs Service Principal

**We use Managed Identity** because:
- Automatic credential rotation (no expiration)
- No secrets to manage
- Azure RBAC integration
- Modern authentication method

**Service Principal** (legacy):
- Manual credential management
- Credentials expire (rotation required)
- Security risk if credentials leak

### System vs User Node Pools

**System Node Pool** (2x Standard_D4s_v3):
- Runs critical system pods (CoreDNS, metrics-server, etc.)
- Non-GPU instances for cost efficiency
- Always available (no autoscaling)

**GPU Node Pool** (10-20x NC16as_T4_v3):
- Runs Renny application workloads
- GPU instances with time-slicing
- Autoscaling enabled for cost optimization

## File Structure

```
kubernetes/terraform/aks/
├── README.md                  # This file
├── main.tf                    # Provider configuration and locals
├── aks.tf                     # AKS cluster resource
├── vnet.tf                    # Virtual network and NAT gateway
├── node-pools.tf              # GPU node pool configuration
├── managed-identity.tf        # Managed identity for autoscaler
├── variables.tf               # Variable definitions
├── outputs.tf                 # Output values
├── terraform.tfvars           # Configuration values (customize this)
└── .terraform/                # Provider plugins (auto-generated)
```

## Support

For issues specific to:
- **Azure/AKS**: Check Azure Portal → Support
- **GPU Operator**: https://github.com/NVIDIA/gpu-operator
- **MiniPrem**: Check project documentation
- **UneeQ Platform**: Contact UneeQ support

## Next Steps

1. **Phase 2**: Create deployment scripts (`scripts/aks/deploy.sh`, etc.)
2. **Phase 3**: Update Kubernetes manifests for AKS compatibility
3. **Phase 4**: Configure Azure Monitor integration
4. **Phase 5**: Set up Azure DevOps/GitHub Actions CI/CD
