# Azure AKS Scaling Quick Start Guide

## Overview

The `scale-azure.sh` script provides production-ready node pool scaling for Azure AKS clusters running Renny digital human workloads with GPU support.

## Prerequisites

Before scaling:

1. **Azure CLI authenticated**:
   ```bash
   az login
   # or
   az login --use-device-code
   ```

2. **AKS cluster deployed**:
   ```bash
   cd kubernetes/
   ./scripts/deploy-azure.sh
   ```

3. **kubectl access configured**:
   ```bash
   az aks get-credentials --resource-group renny-kubernetes --name <cluster-name>
   ```

## Quick Usage

### Scale to Specific Node Count

```bash
cd kubernetes/
./scripts/scale-azure.sh 15
```

This will:
- ✅ Validate Azure authentication
- ✅ Check current node count
- ✅ Show cost impact
- ✅ Ask for confirmation
- ✅ Scale the node pool
- ✅ Scale Renny pods (with time-slicing)
- ✅ Monitor progress
- ✅ Verify final state

### Common Scaling Operations

```bash
# Scale up to 15 nodes (production load)
./scripts/scale-azure.sh 15

# Scale down to 2 nodes (minimal/testing)
./scripts/scale-azure.sh 2

# Scale to maximum (20 nodes)
./scripts/scale-azure.sh 20

# Debug mode for troubleshooting
./scripts/scale-azure.sh --debug 10
```

### View Help

```bash
./scripts/scale-azure.sh --help
```

## Example Output

### Successful Scaling Operation

```
🚀 Azure AKS Node Pool Scaling

✅ Pre-flight checks passed

╔═══════════════════════════════════════════════════════╗
║              Cluster Configuration                    ║
╚═══════════════════════════════════════════════════════╝

Cluster: renny-production-abc123
Resource Group: renny-kubernetes
Region: westus3
Node Pool: rennygpu

📊 Current Renny status:
Current Renny nodes: 10

╔═══════════════════════════════════════════════════════╗
║                   Scaling Confirmation                ║
╚═══════════════════════════════════════════════════════╝

Component: Renny
Current nodes: 10
Target nodes: 15
Range: 2 - 20

This will ADD 5 nodes (scale up)

Cost Impact:
  Current: $15.00/hour (~$10950/month)
  New:     $22.50/hour (~$16425/month)
  Change:  +$7.50/hour (+$5475/month)

Proceed with scaling? (y/N): y

🔄 Scaling Renny to 15 nodes...

Updating node pool configuration...
✅ Node pool scaling initiated

📦 Scaling Renny deployment...
   GPU time-slicing: 2 pods per GPU
   Total pods: 30 (15 nodes × 2 pods/node)
✅ Deployment scaled to 30 pods

⏳ Scaling in progress...
This process may take 5-15 minutes to complete.

📊 Monitoring scaling progress...

   Progress: 15/15 nodes ready | State: Succeeded | Elapsed: 8m23s

✅ Scaling completed successfully

🔍 Post-scale verification...

📊 Node scaling status:
NAME                              STATUS   ROLES   AGE   VERSION
aks-rennygpu-12345678-vmss000000  Ready    agent   45m   v1.31.0
aks-rennygpu-12345678-vmss000001  Ready    agent   45m   v1.31.0
... (15 nodes total)

🚀 Renny pod status:
NAME                     READY   STATUS    RESTARTS   AGE
renny-5b7c8d9f4-2xk4w   1/1     Running   0          5m
renny-5b7c8d9f4-3jm5q   1/1     Running   0          5m
... (30 pods total)

═══════════════════════════════════════════════════════
  🎉 Scaling Complete!
═══════════════════════════════════════════════════════

Summary:
  Component: Renny
  Previous nodes: 10
  Target nodes: 15
  Final nodes: 15 ready / 15 total

Cost Impact:
  Previous: $15.00/hour (~$10950/month)
  New:      $22.50/hour (~$16425/month)
  Change:   +$7.50/hour (+$5475/month)
```

## Configuration Files

### Primary Configuration
**File**: `kubernetes/terraform/aks/terraform.tfvars`

```hcl
# Node Scaling Configuration
renny_min_size     = 2
renny_max_size     = 20
renny_desired_size = 10
```

### GPU Time-Slicing Configuration
**File**: `kubernetes/values/renny-values.yaml`

```yaml
gpuTimeSlicing:
  replicasPerGpu: 2  # Pods per GPU

deployment:
  totalReplicas: 20  # Must be multiple of replicasPerGpu
```

## Scaling Limits

| Limit | Value | Source |
|-------|-------|--------|
| Minimum nodes | 2 | `terraform.tfvars` |
| Maximum nodes | 20 | `terraform.tfvars` |
| Default nodes | 10 | `terraform.tfvars` |
| Pods per GPU | 2-4 | `renny-values.yaml` |

### Changing Limits

To modify scaling limits:

1. Edit `kubernetes/terraform/aks/terraform.tfvars`:
   ```hcl
   renny_min_size = 5   # New minimum
   renny_max_size = 30  # New maximum
   ```

2. Apply changes:
   ```bash
   cd kubernetes/terraform/aks
   terraform apply
   ```

3. Scale as needed:
   ```bash
   cd kubernetes/
   ./scripts/scale-azure.sh 25  # Now within new limits
   ```

## Cost Management

### Standard_NC16as_T4_v3 Pricing (westus3)

- **Per node**: $1.50/hour
- **Per day**: $36.00/day per node
- **Per month**: $1,095/month per node (730 hours)

### Cost Examples

| Nodes | Hourly | Daily | Monthly |
|-------|--------|-------|---------|
| 2     | $3.00  | $72   | $2,190  |
| 5     | $7.50  | $180  | $5,475  |
| 10    | $15.00 | $360  | $10,950 |
| 15    | $22.50 | $540  | $16,425 |
| 20    | $30.00 | $720  | $21,900 |

### Cost Optimization Tips

1. **Off-hours scaling**: Scale down during nights/weekends
   ```bash
   # End of day
   ./scripts/scale-azure.sh 2

   # Start of day
   ./scripts/scale-azure.sh 15
   ```

2. **GPU time-slicing**: Run 2-4 pods per GPU
   - Reduces required nodes by 50-75%
   - Edit `kubernetes/values/renny-values.yaml`

3. **Azure Reserved Instances**: Up to 72% savings with 3-year commitment

4. **Spot instances**: 60-80% discount (for non-critical workloads)

## Monitoring After Scaling

### Watch Node Status
```bash
kubectl get nodes -l uneeq.io/node-type=renny -w
```

### Watch Pod Status
```bash
kubectl get pods -n uneeq-renderer -l app=renny -w
```

### Check GPU Availability
```bash
kubectl get nodes -L nvidia.com/gpu
```

### View Application Logs
```bash
kubectl logs -n uneeq-renderer -l app=renny --tail=50 -f
```

### Azure Portal Monitoring
```bash
# Get portal URL (from script output)
https://portal.azure.com/#resource/subscriptions/.../resourceGroups/renny-kubernetes/providers/Microsoft.ContainerService/managedClusters/<cluster-name>
```

## Troubleshooting

### Authentication Errors

**Error**: "Not logged in to Azure"

**Solution**:
```bash
az login
# or
az login --use-device-code
```

### Cluster Not Found

**Error**: "AKS cluster not found"

**Solution**:
```bash
# Verify cluster exists
az aks list --output table

# Check resource group
az group list --output table

# Deploy if needed
cd kubernetes/
./scripts/deploy-azure.sh
```

### Scaling Bounds Exceeded

**Error**: "Desired count must be between 2 and 20"

**Solution**: Use a count within limits or modify `terraform.tfvars` and run `terraform apply`

### Timeout During Scaling

**Error**: Scaling times out after 15 minutes

**Possible causes**:
- Azure quota limits reached
- Network connectivity issues
- Azure service degradation

**Solution**:
```bash
# Check Azure status
az vm list-skus --location westus3 --size Standard_NC --output table

# Check node pool status
az aks nodepool show --name rennygpu --cluster-name <cluster> --resource-group renny-kubernetes

# Check Azure service health
# Navigate to: Azure Portal > Service Health
```

### Pods Not Scaling

**Error**: Nodes scale but pods remain at old count

**Solution**:
```bash
# Manually scale deployment
kubectl scale deployment renny -n uneeq-renderer --replicas=30

# Check deployment status
kubectl describe deployment renny -n uneeq-renderer

# Check for resource constraints
kubectl describe nodes -l uneeq.io/node-type=renny | grep -A5 "Allocated resources"
```

## Debug Mode

Enable verbose output for troubleshooting:

```bash
./scripts/scale-azure.sh --debug 15
```

Debug mode shows:
- Azure CLI version
- Subscription details
- Configuration loading steps
- API call parameters
- Progress monitoring details

## Integration with CI/CD

### GitHub Actions Example

```yaml
name: Scale AKS Cluster
on:
  schedule:
    - cron: '0 8 * * 1-5'  # 8 AM weekdays (scale up)
    - cron: '0 18 * * 1-5' # 6 PM weekdays (scale down)

jobs:
  scale:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Azure Login
        uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}

      - name: Scale Cluster
        run: |
          if [ "$(date +%H)" -eq 8 ]; then
            # Morning: Scale up
            cd kubernetes/
            echo "y" | ./scripts/scale-azure.sh 15
          else
            # Evening: Scale down
            cd kubernetes/
            echo "y" | ./scripts/scale-azure.sh 2
          fi
```

## Best Practices

1. **Always test in development first**: Scale between 2-4 nodes before production scaling

2. **Monitor costs**: Check Azure Cost Management after scaling

3. **Verify application health**: Ensure pods reschedule correctly after scaling

4. **Use time-slicing**: Maximize GPU utilization before adding nodes

5. **Plan for peak load**: Set `renny_max_size` higher than typical peak to allow for growth

6. **Document scaling decisions**: Note why specific node counts were chosen

7. **Set up alerts**: Use Azure Monitor to alert on high resource usage

8. **Regular reviews**: Monthly review of scaling patterns and costs

## Related Documentation

- **AWS Scaling**: `kubernetes/scripts/scale-aws.sh` (EKS equivalent)
- **Comparison**: `kubernetes/scripts/SCALING_COMPARISON.md` (Feature parity matrix)
- **Deployment**: `kubernetes/scripts/deploy-azure.sh` (Initial cluster setup)
- **Azure Setup**: `kubernetes/AZURE_SETUP.md` (Complete Azure guide)

## Support

For issues or questions:
1. Check debug output with `--debug` flag
2. Review Azure Portal for detailed error messages
3. Check Azure service health status
4. Verify quota limits in subscription
5. Review script logs for specific error messages
