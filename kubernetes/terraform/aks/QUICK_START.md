# AKS Quick Start Guide

**5-minute guide to deploy Renny on Azure AKS**

## Prerequisites

```bash
# 1. Install Azure CLI
brew install azure-cli

# 2. Login to Azure
az login

# 3. Set subscription
az account set --subscription "YOUR_SUBSCRIPTION_ID"

# 4. Verify
az account show
```

## Configuration

```bash
# 1. Navigate to AKS directory
cd kubernetes/terraform/aks

# 2. Edit terraform.tfvars
vim terraform.tfvars

# Required: Update these values
azure_subscription_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
dhop_tenant_id        = "your-tenant-id"
dhop_api_key          = "your-api-key"

# Harbor registry credentials (contact help@uneeq.com for robot account)
harbor_username       = "robot$your-customer-name"
harbor_password       = "your-robot-password"
```

## Deployment

```bash
# 1. Initialize Terraform
terraform init

# 2. Review plan
terraform plan -var-file=terraform.tfvars

# 3. Deploy (15-20 minutes)
terraform apply -var-file=terraform.tfvars

# 4. Configure kubectl
az aks get-credentials \
  --resource-group $(terraform output -raw resource_group_name) \
  --name $(terraform output -raw cluster_name)

# 5. Verify nodes
kubectl get nodes
```

## Install GPU Operator

```bash
# 1. Add NVIDIA Helm repo
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

# 2. Install GPU Operator (10-15 minutes)
helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --create-namespace \
  --set driver.version="580" \
  --wait

# 3. Verify GPU detection
kubectl exec -n gpu-operator \
  $(kubectl get pods -n gpu-operator -l app=nvidia-driver-daemonset -o name | head -1) \
  -- nvidia-smi
```

## Deploy Renny

```bash
# 1. Create namespace
kubectl create namespace uneeq-renderer

# 2. Create Harbor registry secret
kubectl create secret docker-registry harbor-credentials \
  --namespace uneeq-renderer \
  --docker-server=https://cr.uneeq.io \
  --docker-username=$(terraform output -raw harbor_username) \
  --docker-password=$(terraform output -raw harbor_password)

# 3. Deploy Renny
kubectl apply -f ../manifests/renny/

# 4. Check status
kubectl get pods -n uneeq-renderer
```

## Verification

```bash
# Node status
kubectl get nodes -L nvidia.com/gpu,uneeq.io/node-type

# Pod status
kubectl get pods -n uneeq-renderer

# GPU utilization
kubectl exec -n gpu-operator \
  $(kubectl get pods -n gpu-operator -l app=nvidia-driver-daemonset -o name | head -1) \
  -- nvidia-smi

# Logs
kubectl logs -n uneeq-renderer -l app=renny --tail=50
```

## Common Issues

### GPU Nodes Not Ready
**Wait 10-15 minutes** for GPU Operator to compile drivers.

```bash
# Check GPU Operator status
kubectl get pods -n gpu-operator

# View driver installation logs
kubectl logs -n gpu-operator -l app=nvidia-driver-daemonset
```

### Pods Stuck in Pending
Check GPU availability:

```bash
kubectl get nodes -L nvidia.com/gpu
kubectl describe pod <pod-name> -n uneeq-renderer
```

### Authentication Errors
Verify Azure credentials:

```bash
az account show
az aks get-credentials --resource-group renny-kubernetes --name <cluster-name>
```

## Cleanup

```bash
# Destroy all resources (15-20 minutes)
terraform destroy -var-file=terraform.tfvars
```

## Cost Estimates

| GPU Nodes | Monthly Cost |
|-----------|--------------|
| 10 | $8,952 |
| 15 | $13,272 |
| 20 | $17,592 |

## Support

- **Documentation**: See `README.md` for complete guide
- **Architecture**: See `IMPLEMENTATION_SUMMARY.md` for details
- **Azure Support**: Azure Portal → Support
- **GPU Issues**: https://github.com/NVIDIA/gpu-operator

## Key Commands Reference

```bash
# Azure CLI
az account show                          # Current subscription
az aks list -o table                     # List AKS clusters
az aks get-credentials --resource-group <rg> --name <cluster>

# Terraform
terraform init                           # Initialize
terraform plan -var-file=terraform.tfvars # Review changes
terraform apply -var-file=terraform.tfvars # Deploy
terraform destroy -var-file=terraform.tfvars # Cleanup
terraform output -raw <output-name>      # Get output value

# Kubernetes
kubectl get nodes                        # Node status
kubectl get pods -A                      # All pods
kubectl describe pod <name> -n <namespace> # Pod details
kubectl logs <pod> -n <namespace> -f     # Follow logs
kubectl exec -it <pod> -n <namespace> -- bash # Shell into pod

# GPU Verification
kubectl get nodes -L nvidia.com/gpu      # GPU labels
kubectl exec -n gpu-operator $(kubectl get pods -n gpu-operator -l app=nvidia-driver-daemonset -o name | head -1) -- nvidia-smi
```

## File Structure

```
kubernetes/terraform/aks/
├── QUICK_START.md         ← You are here
├── README.md              ← Complete deployment guide
├── IMPLEMENTATION_SUMMARY.md ← Architecture details
├── main.tf                ← Provider configuration
├── aks.tf                 ← AKS cluster
├── vnet.tf                ← Network infrastructure
├── node-pools.tf          ← GPU nodes
├── managed-identity.tf    ← Autoscaler identity
├── variables.tf           ← All parameters
├── outputs.tf             ← Output values
└── terraform.tfvars       ← Your configuration
```

## Next Steps

1. **Deploy**: Follow deployment steps above
2. **Monitor**: Check Azure Portal for resource status
3. **Scale**: Adjust `renny_desired_size` in terraform.tfvars
4. **Optimize**: Enable autoscaling and reserved instances

**Deployment Time**: ~30-45 minutes total
- Terraform apply: 15-20 min
- GPU Operator: 10-15 min
- Renny deployment: 5-10 min
