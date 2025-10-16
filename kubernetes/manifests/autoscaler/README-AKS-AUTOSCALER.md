# AKS Cluster Autoscaler Setup Guide

This guide explains how to deploy the Kubernetes Cluster Autoscaler on Azure Kubernetes Service (AKS) with Azure Managed Identity authentication.

## Prerequisites

- AKS cluster running Kubernetes 1.28+
- Azure CLI installed and authenticated
- kubectl configured to access your AKS cluster
- Workload Identity enabled on the cluster

## Step 1: Enable Workload Identity on AKS

If not already enabled, enable Workload Identity on your cluster:

```bash
az aks update \
  --resource-group <RESOURCE_GROUP> \
  --name <CLUSTER_NAME> \
  --enable-workload-identity \
  --enable-oidc-issuer
```

Get the OIDC issuer URL:

```bash
export AKS_OIDC_ISSUER="$(az aks show \
  --resource-group <RESOURCE_GROUP> \
  --name <CLUSTER_NAME> \
  --query "oidcIssuerProfile.issuerUrl" \
  --output tsv)"

echo $AKS_OIDC_ISSUER
```

## Step 2: Create Azure Managed Identity

Create a managed identity for the cluster autoscaler:

```bash
export SUBSCRIPTION_ID="<YOUR_SUBSCRIPTION_ID>"
export RESOURCE_GROUP="<YOUR_RESOURCE_GROUP>"
export CLUSTER_NAME="<YOUR_CLUSTER_NAME>"
export LOCATION="eastus"
export IDENTITY_NAME="autoscaler-identity"

# Create the managed identity
az identity create \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${IDENTITY_NAME}" \
  --location "${LOCATION}"

# Get the identity client ID
export IDENTITY_CLIENT_ID="$(az identity show \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${IDENTITY_NAME}" \
  --query 'clientId' \
  --output tsv)"

echo "Identity Client ID: ${IDENTITY_CLIENT_ID}"
```

## Step 3: Assign RBAC Permissions

Get the node resource group name (starts with MC_):

```bash
export NODE_RESOURCE_GROUP="$(az aks show \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${CLUSTER_NAME}" \
  --query 'nodeResourceGroup' \
  --output tsv)"

echo "Node Resource Group: ${NODE_RESOURCE_GROUP}"
```

Assign Contributor role to the managed identity:

```bash
# Get the principal ID of the managed identity
export IDENTITY_PRINCIPAL_ID="$(az identity show \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${IDENTITY_NAME}" \
  --query 'principalId' \
  --output tsv)"

# Get the node resource group ID
export NODE_RG_ID="$(az group show \
  --name "${NODE_RESOURCE_GROUP}" \
  --query 'id' \
  --output tsv)"

# Assign Contributor role
az role assignment create \
  --assignee "${IDENTITY_PRINCIPAL_ID}" \
  --role "Contributor" \
  --scope "${NODE_RG_ID}"
```

## Step 4: Establish Federated Identity Credential

Create a federated identity credential for the Kubernetes service account:

```bash
export SERVICE_ACCOUNT_NAMESPACE="kube-system"
export SERVICE_ACCOUNT_NAME="cluster-autoscaler"

az identity federated-credential create \
  --name "autoscaler-federated-credential" \
  --identity-name "${IDENTITY_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --issuer "${AKS_OIDC_ISSUER}" \
  --subject "system:serviceaccount:${SERVICE_ACCOUNT_NAMESPACE}:${SERVICE_ACCOUNT_NAME}" \
  --audience api://AzureADTokenExchange
```

## Step 5: Configure Autoscaler Manifest

Replace placeholders in `autoscaler-aks.yaml`:

```bash
# Create a working copy
cp autoscaler-aks.yaml autoscaler-aks-configured.yaml

# Replace placeholders (macOS/Linux)
sed -i.bak "s|<AUTOSCALER_IDENTITY_CLIENT_ID>|${IDENTITY_CLIENT_ID}|g" autoscaler-aks-configured.yaml
sed -i.bak "s|<SUBSCRIPTION_ID>|${SUBSCRIPTION_ID}|g" autoscaler-aks-configured.yaml
sed -i.bak "s|<NODE_RESOURCE_GROUP>|${NODE_RESOURCE_GROUP}|g" autoscaler-aks-configured.yaml
sed -i.bak "s|<CLUSTER_NAME>|${CLUSTER_NAME}|g" autoscaler-aks-configured.yaml

# Remove backup files
rm autoscaler-aks-configured.yaml.bak

echo "Configuration complete! Review autoscaler-aks-configured.yaml before deploying."
```

**Manual replacement:**
- `<AUTOSCALER_IDENTITY_CLIENT_ID>`: Client ID from Step 2
- `<SUBSCRIPTION_ID>`: Your Azure subscription ID
- `<NODE_RESOURCE_GROUP>`: MC_* resource group from Step 3
- `<CLUSTER_NAME>`: Your AKS cluster name

## Step 6: Label Node Pools for Autoscaling

Enable autoscaler discovery on your GPU node pool:

```bash
# Get the node pool name
export NODE_POOL_NAME="gpupool"

# Enable autoscaler on the node pool
az aks nodepool update \
  --resource-group "${RESOURCE_GROUP}" \
  --cluster-name "${CLUSTER_NAME}" \
  --name "${NODE_POOL_NAME}" \
  --enable-cluster-autoscaler \
  --min-count 1 \
  --max-count 10

# Add discovery label
kubectl label nodes -l agentpool=${NODE_POOL_NAME} \
  k8s.io/cluster-autoscaler-enabled=true
```

## Step 7: Deploy the Autoscaler

Deploy the configured manifest:

```bash
kubectl apply -f autoscaler-aks-configured.yaml
```

## Step 8: Verify Deployment

Check autoscaler pod status:

```bash
# View pod
kubectl get pods -n kube-system -l app=cluster-autoscaler

# Check logs
kubectl logs -n kube-system -l app=cluster-autoscaler -f
```

Expected log output:
```
I1016 12:34:56.789012       1 main.go:123] Cluster Autoscaler 1.31.0
I1016 12:34:56.789012       1 azure_manager.go:123] Using Azure cloud provider
I1016 12:34:56.789012       1 azure_manager.go:456] Discovered node group: gpupool
```

## Troubleshooting

### Identity Authentication Issues

Check service account annotations:

```bash
kubectl get serviceaccount cluster-autoscaler -n kube-system -o yaml
```

Verify federated credential:

```bash
az identity federated-credential show \
  --name "autoscaler-federated-credential" \
  --identity-name "${IDENTITY_NAME}" \
  --resource-group "${RESOURCE_GROUP}"
```

### Autoscaler Not Scaling

Check autoscaler status:

```bash
kubectl get configmap cluster-autoscaler-status -n kube-system -o yaml
```

View detailed logs:

```bash
kubectl logs -n kube-system -l app=cluster-autoscaler --tail=100
```

Common issues:
- **Insufficient permissions**: Verify Contributor role assignment
- **Node pool not labeled**: Ensure `k8s.io/cluster-autoscaler-enabled=true` label
- **OIDC issuer mismatch**: Verify OIDC issuer URL in federated credential

### Scale-Down Not Working

Check pod annotations:

```bash
kubectl get pods -n uneeq-renderer -o yaml | grep cluster-autoscaler
```

The `safe-to-evict: "false"` annotation prevents scale-down. Remove if needed:

```bash
kubectl annotate pods -n uneeq-renderer <pod-name> \
  cluster-autoscaler.kubernetes.io/safe-to-evict-
```

## Configuration Options

### Adjust Autoscaler Behavior

Edit the deployment to modify autoscaler flags:

```bash
kubectl edit deployment cluster-autoscaler -n kube-system
```

Useful flags:
- `--scale-down-delay-after-add=10m`: Wait 10 minutes after scale-up before scale-down
- `--scale-down-unneeded-time=10m`: Node must be unneeded for 10 minutes
- `--max-node-provision-time=15m`: Timeout for node provisioning
- `--expander=priority`: Use priority-based expander for multiple node pools

### Enable Priority Expander

Create priority ConfigMap:

```bash
kubectl create configmap cluster-autoscaler-priority-expander \
  -n kube-system \
  --from-literal=priorities='
10:
  - .*gpupool.*
5:
  - .*systempool.*
'
```

## Cost Optimization

### Set Appropriate Scale Ranges

Balance cost and availability:

```bash
az aks nodepool update \
  --resource-group "${RESOURCE_GROUP}" \
  --cluster-name "${CLUSTER_NAME}" \
  --name "${NODE_POOL_NAME}" \
  --min-count 2 \
  --max-count 10
```

### Use Scale-Down Delay

Prevent thrashing during traffic spikes:

```bash
# In autoscaler deployment:
- --scale-down-delay-after-add=15m
- --scale-down-unneeded-time=15m
```

## Monitoring

View autoscaler metrics:

```bash
kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1 | jq .
```

Check node capacity:

```bash
kubectl top nodes
kubectl describe nodes -l agentpool=${NODE_POOL_NAME}
```

## Cleanup

Remove autoscaler:

```bash
kubectl delete -f autoscaler-aks-configured.yaml
```

Remove Azure resources:

```bash
az identity federated-credential delete \
  --name "autoscaler-federated-credential" \
  --identity-name "${IDENTITY_NAME}" \
  --resource-group "${RESOURCE_GROUP}"

az identity delete \
  --name "${IDENTITY_NAME}" \
  --resource-group "${RESOURCE_GROUP}"
```

## References

- [AKS Cluster Autoscaler Documentation](https://learn.microsoft.com/en-us/azure/aks/cluster-autoscaler)
- [Workload Identity Documentation](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview)
- [Kubernetes Autoscaler GitHub](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler/cloudprovider/azure)
