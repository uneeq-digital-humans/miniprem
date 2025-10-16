# AKS Metrics API Documentation

## Overview

The AKS Metrics API endpoint provides comprehensive real-time metrics for Azure Kubernetes Service (AKS) clusters, including node pool health, resource utilization, cluster totals, and cost estimates.

## Endpoint

```
GET /api/kubernetes/metrics/aks
```

## Prerequisites

### Required Tools

1. **Azure CLI (az)** - Version 2.0+
   ```bash
   # Install on macOS
   brew install azure-cli

   # Install on Linux
   curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

   # Install on Windows
   # Download from: https://aka.ms/installazurecliwindows
   ```

2. **kubectl** - Version 1.20+
   ```bash
   # Install on macOS
   brew install kubectl

   # Install on Linux
   curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
   sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

   # Install on Windows
   # Download from: https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/
   ```

### Authentication Setup

1. **Azure CLI Authentication**
   ```bash
   # Login to Azure
   az login

   # Set subscription (if you have multiple)
   az account set --subscription <subscription-id>

   # Verify authentication
   az account show
   ```

2. **AKS Cluster Access**
   ```bash
   # Get credentials for AKS cluster
   az aks get-credentials --resource-group <rg-name> --name <cluster-name>

   # Verify kubectl context
   kubectl config current-context

   # Test cluster access
   kubectl cluster-info
   ```

## Response Format

### Success Response

```json
{
  "success": true,
  "metrics": {
    "cluster_name": "my-aks-cluster",
    "resource_group": "my-resource-group",
    "location": "eastus",
    "kubernetes_version": "1.28.5",
    "provisioning_state": "Succeeded",
    "fqdn": "my-aks-cluster-dns-12345678.hcp.eastus.azmk8s.io",
    "node_pools": [
      {
        "name": "agentpool",
        "vm_size": "Standard_D4s_v3",
        "current_count": 3,
        "min_count": 3,
        "max_count": 10,
        "auto_scaling_enabled": true,
        "health_status": "healthy",
        "ready_nodes": 3,
        "not_ready_nodes": 0,
        "provisioning_state": "Succeeded",
        "kubernetes_version": "1.28.5",
        "os_disk_size_gb": 128,
        "mode": "System"
      }
    ],
    "cluster_totals": {
      "total_nodes": 3,
      "ready_nodes": 3,
      "not_ready_nodes": 0,
      "total_pods": 45,
      "running_pods": 43,
      "pending_pods": 2,
      "failed_pods": 0,
      "succeeded_pods": 0,
      "namespace_count": 8
    },
    "cost_estimate": {
      "hourly_usd": 0.58,
      "daily_usd": 13.92,
      "monthly_usd": 423.60,
      "breakdown": [
        {
          "node_pool": "agentpool",
          "vm_size": "Standard_D4s_v3",
          "node_count": 3,
          "hourly_per_node": 0.192,
          "hourly_total": 0.58,
          "daily_total": 13.92,
          "monthly_total": 423.60
        }
      ],
      "last_updated": "2025-01-15T10:30:45.123456",
      "note": "Estimated costs based on US East region pricing. Actual costs may vary."
    }
  },
  "timestamp": "2025-01-15T10:30:45.123456"
}
```

### Error Response

```json
{
  "success": false,
  "error": "Current cluster is eks, not AKS. Switch to an AKS cluster context first.",
  "error_type": "wrong_provider",
  "timestamp": "2025-01-15T10:30:45.123456"
}
```

## Error Types

| Error Type | HTTP Status | Description | Resolution |
|------------|-------------|-------------|------------|
| `wrong_provider` | 400 | Current cluster is not AKS | Switch to AKS cluster context |
| `tool_not_available` | 503 | Azure CLI or kubectl not installed | Install required tools |
| `authentication_error` | 401 | Not authenticated to Azure | Run `az login` |
| `data_retrieval_error` | 500 | Failed to retrieve metrics | Check cluster access and permissions |
| `unknown_error` | 500 | Unexpected error occurred | Check logs for details |

## Node Pool Metrics

### Fields Description

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Node pool name |
| `vm_size` | string | Azure VM size (e.g., "Standard_D4s_v3") |
| `current_count` | integer | Current number of nodes |
| `min_count` | integer | Minimum nodes (if autoscaling enabled) |
| `max_count` | integer | Maximum nodes (if autoscaling enabled) |
| `auto_scaling_enabled` | boolean | Whether cluster autoscaler is enabled |
| `health_status` | string | "healthy", "degraded", or "unhealthy" |
| `ready_nodes` | integer | Number of ready nodes |
| `not_ready_nodes` | integer | Number of not ready nodes |
| `provisioning_state` | string | Azure provisioning state |
| `kubernetes_version` | string | Kubernetes version for node pool |
| `os_disk_size_gb` | integer | OS disk size in GB |
| `mode` | string | "System" or "User" node pool |

### Health Status Definitions

- **healthy**: All nodes ready, provisioning succeeded
- **degraded**: Some nodes not ready, or provisioning in progress
- **unhealthy**: No nodes ready, or provisioning failed

## Cluster Totals

| Field | Type | Description |
|-------|------|-------------|
| `total_nodes` | integer | Total nodes across all node pools |
| `ready_nodes` | integer | Number of ready nodes |
| `not_ready_nodes` | integer | Number of not ready nodes |
| `total_pods` | integer | Total pods across all namespaces |
| `running_pods` | integer | Pods in Running phase |
| `pending_pods` | integer | Pods in Pending phase |
| `failed_pods` | integer | Pods in Failed phase |
| `succeeded_pods` | integer | Pods in Succeeded phase |
| `namespace_count` | integer | Total number of namespaces |

## Cost Estimates

### VM Pricing Table

Cost estimates use baseline pricing from **US East** region:

| VM Size | Hourly (USD) | Monthly (USD) | vCPUs | Memory (GB) |
|---------|--------------|---------------|-------|-------------|
| Standard_B2s | $0.0416 | $30.37 | 2 | 4 |
| Standard_B4ms | $0.166 | $121.18 | 4 | 16 |
| Standard_D2s_v3 | $0.096 | $70.08 | 2 | 8 |
| Standard_D4s_v3 | $0.192 | $140.16 | 4 | 16 |
| Standard_D8s_v3 | $0.384 | $280.32 | 8 | 32 |
| Standard_D16s_v3 | $0.768 | $560.64 | 16 | 64 |
| Standard_DS2_v2 | $0.107 | $78.11 | 2 | 7 |
| Standard_DS3_v2 | $0.214 | $156.22 | 4 | 14 |
| Standard_DS4_v2 | $0.428 | $312.44 | 8 | 28 |
| Standard_E4s_v3 | $0.252 | $183.96 | 4 | 32 |
| Standard_E8s_v3 | $0.504 | $367.92 | 8 | 64 |
| Standard_NC6s_v3 | $3.06 | $2,233.80 | 6 | 112 (1 GPU) |
| Standard_NC12s_v3 | $6.12 | $4,467.60 | 12 | 224 (2 GPUs) |
| Standard_NC24s_v3 | $12.24 | $8,935.20 | 24 | 448 (4 GPUs) |

**Note**: Actual costs may vary by:
- Azure region (prices differ across regions)
- Reserved instance discounts
- Spot instance pricing
- Azure Hybrid Benefit
- Support plans and additional services

### Monthly Cost Calculation

Monthly cost = Hourly rate × 730 hours (average hours per month)

## Caching

The endpoint implements intelligent caching to reduce Azure API calls:

- **Cache TTL**: 30 seconds
- **Cache Key**: `aks_metrics`
- **Behavior**: First request fetches fresh data, subsequent requests within 30 seconds return cached data

### Cache Invalidation

Cache automatically expires after 30 seconds. To force refresh, wait 30 seconds between requests.

## Example Usage

### cURL

```bash
# Basic request
curl http://localhost:8000/api/kubernetes/metrics/aks

# With formatted output
curl http://localhost:8000/api/kubernetes/metrics/aks | jq

# Extract specific metrics
curl -s http://localhost:8000/api/kubernetes/metrics/aks | jq '.metrics.cluster_totals'

# Get cost estimate only
curl -s http://localhost:8000/api/kubernetes/metrics/aks | jq '.metrics.cost_estimate'

# Check node pool health
curl -s http://localhost:8000/api/kubernetes/metrics/aks | \
  jq '.metrics.node_pools[] | {name, health_status, ready_nodes, current_count}'
```

### Python

```python
import requests

# Get metrics
response = requests.get("http://localhost:8000/api/kubernetes/metrics/aks")
data = response.json()

if data["success"]:
    metrics = data["metrics"]

    # Print cluster info
    print(f"Cluster: {metrics['cluster_name']}")
    print(f"Total Nodes: {metrics['cluster_totals']['total_nodes']}")
    print(f"Monthly Cost: ${metrics['cost_estimate']['monthly_usd']}")

    # Check node pool health
    for np in metrics["node_pools"]:
        print(f"\nNode Pool: {np['name']}")
        print(f"  Health: {np['health_status']}")
        print(f"  Ready: {np['ready_nodes']}/{np['current_count']}")
else:
    print(f"Error: {data['error']}")
```

### JavaScript/TypeScript

```typescript
interface AKSMetrics {
  cluster_name: string;
  node_pools: NodePool[];
  cluster_totals: ClusterTotals;
  cost_estimate: CostEstimate;
}

async function getAKSMetrics(): Promise<AKSMetrics> {
  const response = await fetch("http://localhost:8000/api/kubernetes/metrics/aks");
  const data = await response.json();

  if (!data.success) {
    throw new Error(data.error);
  }

  return data.metrics;
}

// Usage
try {
  const metrics = await getAKSMetrics();
  console.log(`Cluster: ${metrics.cluster_name}`);
  console.log(`Monthly Cost: $${metrics.cost_estimate.monthly_usd}`);
} catch (error) {
  console.error("Failed to get metrics:", error.message);
}
```

## Testing

### Unit Test

```bash
# Run unit tests
cd miniprem-monitor/backend
python test_aks_metrics.py
```

### Integration Test

```bash
# Start the backend server
cd miniprem-monitor/backend
python -m app.main

# In another terminal, test the endpoint
curl http://localhost:8000/api/kubernetes/metrics/aks | jq
```

## Troubleshooting

### Common Issues

1. **"Azure CLI (az) is not available"**
   - Install Azure CLI: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli
   - Verify installation: `az version`

2. **"kubectl is not available"**
   - Install kubectl: https://kubernetes.io/docs/tasks/tools/
   - Verify installation: `kubectl version --client`

3. **"Current cluster is not AKS"**
   - Check current context: `kubectl config current-context`
   - List available contexts: `kubectl config get-contexts`
   - Switch to AKS context: `kubectl config use-context <aks-context>`

4. **"Failed to get AKS cluster information"**
   - Ensure Azure CLI is authenticated: `az login`
   - Verify subscription: `az account show`
   - Check cluster access: `az aks list`

5. **"Authentication error"**
   - Re-authenticate: `az login`
   - Check token expiration: `az account get-access-token`

6. **Incorrect cost estimates**
   - Verify VM size names match Azure documentation
   - Check region-specific pricing at: https://azure.microsoft.com/en-us/pricing/calculator/

## Performance Considerations

- **First Request**: ~2-5 seconds (fetches from Azure API)
- **Cached Requests**: ~10-50ms (returns cached data)
- **Concurrent Requests**: Safe (cache is thread-safe)
- **Memory Usage**: ~1-2 MB per cached metrics response

## Security

- Uses **subprocess** for CLI commands (no shell injection risk)
- Respects Azure RBAC permissions
- No credentials stored or transmitted
- All commands run with user's Azure CLI session

## Rate Limiting

Azure API has rate limits:
- **Azure Resource Manager**: 12,000 reads per hour
- **Kubernetes API**: No hard limit (depends on cluster size)

The 30-second cache helps stay within these limits.

## Future Enhancements

Potential improvements:

1. Historical metrics tracking
2. Alerting for unhealthy node pools
3. Recommendations for cost optimization
4. Multi-cluster aggregation
5. Custom VM pricing profiles
6. Detailed pod-level metrics per node pool
7. Network and disk I/O metrics
8. GPU utilization for NC-series VMs

## Related Endpoints

- `GET /api/kubernetes/cluster/info/enhanced` - General cluster info with provider detection
- `GET /api/kubernetes/aks/nodepools` - Basic node pool listing (kubectl-based)
- `GET /api/kubernetes/contexts` - List available Kubernetes contexts

## Support

For issues or questions:
1. Check the logs: `docker logs miniprem-monitor`
2. Verify prerequisites are met
3. Test individual components with `test_aks_metrics.py`
4. Review Azure CLI and kubectl documentation
