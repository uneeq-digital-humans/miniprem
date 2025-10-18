# Cluster Management API Documentation

Multi-cluster Kubernetes management API endpoints for MiniPrem Monitor.

**Version:** 1.0.0
**Date:** 2025-10-16
**Author:** MiniPrem Monitor Backend Team

---

## Overview

The Cluster Management API provides endpoints for managing multiple Kubernetes clusters across different cloud providers (AWS EKS, Azure AKS, Google GKE) and local clusters. The API uses subprocess-based kubectl commands to interact with clusters, avoiding Python SDK dependency conflicts.

### Key Features

- **Multi-cloud support:** EKS, AKS, GKE, and local clusters
- **Provider detection:** Automatic identification of cloud provider from server URL
- **Region extraction:** Intelligent region parsing from context names and endpoints
- **Accessibility checks:** Real-time validation of cluster connectivity
- **Resource counting:** Node and pod counts for accessible clusters
- **Context switching:** Safe context switching with validation and rollback support

---

## Architecture

### Approach: CLI-Based (Not Python SDKs)

**Why CLI?**
- Avoids dependency conflicts (Docker SDK urllib3>=2.0 vs Kubernetes SDK urllib3<2.0)
- More reliable cross-platform compatibility
- Matches existing patterns in `kubernetes_monitor.py`

**Implementation:**
- `kubectl_service.py`: Helper functions for kubectl operations
- `cluster_management.py`: FastAPI route handlers
- `cluster_models.py`: Pydantic models for request/response validation

---

## Endpoints

### 1. List Clusters

**Endpoint:** `GET /api/kubernetes/clusters/list`

**Description:** Retrieve all available kubectl contexts with comprehensive metadata.

**Query Parameters:** None

**Response:** `ClusterListResponse`

```json
{
  "success": true,
  "clusters": [
    {
      "context_name": "arn:aws:eks:us-east-1:123456789012:cluster/renny-prod",
      "cluster_name": "renny-prod",
      "provider": "eks",
      "region": "us-east-1",
      "is_current": true,
      "accessible": true,
      "node_count": 12,
      "pod_count": 48,
      "last_sync": "2025-10-16T10:30:00Z",
      "server_url": "https://XXXXX.gr7.us-east-1.eks.amazonaws.com"
    },
    {
      "context_name": "renny-aks-eastus",
      "cluster_name": "renny-aks",
      "provider": "aks",
      "region": "eastus",
      "is_current": false,
      "accessible": false,
      "node_count": 0,
      "pod_count": 0,
      "last_sync": "2025-10-16T10:30:00Z",
      "server_url": "https://renny-aks-xxx.eastus.azmk8s.io"
    }
  ],
  "current_context": "arn:aws:eks:us-east-1:123456789012:cluster/renny-prod",
  "total_count": 2,
  "accessible_count": 1,
  "timestamp": "2025-10-16T10:30:00Z",
  "error": null
}
```

**Status Codes:**
- `200 OK`: Success
- `503 Service Unavailable`: kubectl not installed
- `500 Internal Server Error`: Unexpected error

**curl Example:**
```bash
curl -X GET "http://localhost:8000/api/kubernetes/clusters/list" | jq '.'
```

---

### 2. Switch Context

**Endpoint:** `POST /api/kubernetes/context/switch`

**Description:** Switch kubectl context to a different cluster.

**Request Body:** `ContextSwitchRequest`

```json
{
  "context_name": "renny-aks-eastus"
}
```

**Response:** `ContextSwitchResponse`

```json
{
  "success": true,
  "new_context": "renny-aks-eastus",
  "cluster_info": {
    "cluster_name": "renny-aks",
    "provider": "aks",
    "region": "eastus",
    "node_count": 10,
    "pod_count": 40,
    "accessible": true
  },
  "previous_context": "arn:aws:eks:us-east-1:123456789012:cluster/renny-prod",
  "timestamp": "2025-10-16T10:35:00Z",
  "error": null
}
```

**Status Codes:**
- `200 OK`: Success (context switched)
- `404 Not Found`: Context not found in kubeconfig
- `500 Internal Server Error`: Switch operation failed
- `502 Bad Gateway`: Cluster not accessible after switch

**curl Example:**
```bash
curl -X POST "http://localhost:8000/api/kubernetes/context/switch" \
  -H "Content-Type: application/json" \
  -d '{"context_name": "renny-aks-eastus"}' | jq '.'
```

---

## Provider Detection

### Supported Providers

| Provider | Detection Pattern | Example Server URL |
|----------|-------------------|-------------------|
| **EKS** | `eks.amazonaws.com` | `https://XXXXX.gr7.us-east-1.eks.amazonaws.com` |
| **AKS** | `azmk8s.io` | `https://renny-xxx.eastus.azmk8s.io` |
| **GKE** | `container.googleapis.com`, `gke.io` | `https://xxx.container.googleapis.com` |
| **Local** | `localhost`, `127.0.0.1` | `https://127.0.0.1:6443` |
| **Unknown** | None of the above | Any other URL |

### Provider Detection Logic

```python
def detect_provider_from_server(server_url: str) -> str:
    """Detect cloud provider from Kubernetes API server URL"""
    if 'eks.amazonaws.com' in server_url or '.eks.' in server_url:
        return 'eks'
    elif 'azmk8s.io' in server_url or '.aks.' in server_url:
        return 'aks'
    elif 'gke.io' in server_url or 'container.googleapis.com' in server_url:
        return 'gke'
    elif 'localhost' in server_url or '127.0.0.1' in server_url:
        return 'local'
    else:
        return 'unknown'
```

---

## Region Extraction

### EKS (AWS)

**Pattern:** `(us|eu|ap|ca|sa|me|af)-[a-z]+-\d+`

**Examples:**
- Context: `arn:aws:eks:us-east-1:123456789012:cluster/renny-prod` → `us-east-1`
- Server: `https://XXXXX.gr7.us-west-2.eks.amazonaws.com` → `us-west-2`

### AKS (Azure)

**Pattern:** Predefined Azure region list matching

**Examples:**
- Context: `renny-aks-eastus` → `eastus`
- Server: `https://renny-xxx.westeurope.azmk8s.io` → `westeurope`

**Supported Regions:** eastus, westus, centralus, northeurope, westeurope, southeastasia, japaneast, etc.

### GKE (Google Cloud)

**Pattern:** `(us|europe|asia|australia)-[a-z0-9-]+`

**Examples:**
- Context: `gke_myproject_us-central1_mycluster` → `us-central1`
- Context: `gke_myproject_europe-west1_mycluster` → `europe-west1`

---

## Error Handling

### Error Response Model

```json
{
  "success": false,
  "error": "Context 'invalid-cluster' not found in kubeconfig",
  "error_type": "context_not_found",
  "timestamp": "2025-10-16T10:40:00Z"
}
```

### Error Types

| Error Type | HTTP Status | Description |
|------------|-------------|-------------|
| `kubectl_not_available` | 503 | kubectl not installed or not in PATH |
| `no_contexts` | 200* | No kubectl contexts found (empty list) |
| `context_not_found` | 404 | Specified context doesn't exist |
| `cluster_not_accessible` | 502 | Cluster exists but not reachable |
| `switch_failed` | 500 | kubectl use-context failed |
| `server_error` | 500 | Unexpected error occurred |

*Note: Empty cluster list returns 200 with `success: true` and empty `clusters` array.

---

## Performance Considerations

### Caching Strategy

**Current Implementation:**
- No caching (real-time data on every request)
- Accessibility checks only for current context in `/clusters/list`
- Full stats (nodes, pods) only for accessible contexts

**Recommended Optimization:**
```python
from functools import lru_cache
from datetime import datetime, timedelta

_cluster_cache = None
_cache_time = None
CACHE_DURATION = timedelta(seconds=30)

def get_cached_cluster_list():
    global _cluster_cache, _cache_time

    if _cluster_cache is None or (datetime.now() - _cache_time) > CACHE_DURATION:
        _cluster_cache = fetch_cluster_list()
        _cache_time = datetime.now()

    return _cluster_cache
```

### Timeout Settings

| Operation | Timeout | Reason |
|-----------|---------|--------|
| `kubectl config view` | 10s | Local file read (fast) |
| `kubectl cluster-info` | 5s | Network request (medium) |
| `kubectl get nodes` | 10s | Network request (can be slow) |
| `kubectl get pods --all-namespaces` | 10s | Network request (can be slow) |

---

## Testing

### Automated Test Script

Run the comprehensive test suite:

```bash
cd /Users/tyler/Software_Development/miniprem-2025/miniprem-monitor/backend
./test_cluster_api.sh http://localhost:8000
```

**Test Coverage:**
1. List all clusters
2. Switch context (if multiple contexts exist)
3. Error handling (invalid context)
4. Provider detection validation
5. Accessibility checks

### Manual Testing

**Test 1: List Clusters**
```bash
curl -X GET "http://localhost:8000/api/kubernetes/clusters/list" | jq '.'
```

**Test 2: Switch Context**
```bash
# Get available contexts first
CONTEXTS=$(curl -s http://localhost:8000/api/kubernetes/clusters/list | jq -r '.clusters[].context_name')
echo "$CONTEXTS"

# Switch to first context
FIRST_CONTEXT=$(echo "$CONTEXTS" | head -1)
curl -X POST "http://localhost:8000/api/kubernetes/context/switch" \
  -H "Content-Type: application/json" \
  -d "{\"context_name\": \"$FIRST_CONTEXT\"}" | jq '.'
```

**Test 3: Error Handling**
```bash
curl -X POST "http://localhost:8000/api/kubernetes/context/switch" \
  -H "Content-Type: application/json" \
  -d '{"context_name": "invalid-cluster-context"}' | jq '.'
```

---

## Security Considerations

### Input Validation

- Context names validated against kubeconfig
- No shell injection vulnerabilities (using subprocess with list arguments)
- Pydantic validation for all request bodies

### Access Control

**Current:** No authentication (local development)
**Production:** Implement authentication middleware:
- JWT token validation
- Role-based access control (RBAC)
- Audit logging for context switches

---

## Integration with Frontend

### React Hook Example

```typescript
// hooks/useKubernetesClusters.ts
import { useState, useEffect } from 'react';

interface Cluster {
  context_name: string;
  cluster_name: string;
  provider: string;
  region: string;
  is_current: boolean;
  accessible: boolean;
  node_count: number;
  pod_count: number;
}

export function useKubernetesClusters() {
  const [clusters, setClusters] = useState<Cluster[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetch('http://localhost:8000/api/kubernetes/clusters/list')
      .then(res => res.json())
      .then(data => {
        setClusters(data.clusters);
        setLoading(false);
      })
      .catch(err => {
        setError(err.message);
        setLoading(false);
      });
  }, []);

  const switchContext = async (contextName: string) => {
    const response = await fetch('http://localhost:8000/api/kubernetes/context/switch', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ context_name: contextName })
    });

    if (!response.ok) {
      throw new Error(`Failed to switch context: ${response.statusText}`);
    }

    return response.json();
  };

  return { clusters, loading, error, switchContext };
}
```

### Next.js Page Example

```typescript
// pages/clusters.tsx
import { useKubernetesClusters } from '../hooks/useKubernetesClusters';

export default function ClustersPage() {
  const { clusters, loading, error, switchContext } = useKubernetesClusters();

  if (loading) return <div>Loading clusters...</div>;
  if (error) return <div>Error: {error}</div>;

  return (
    <div>
      <h1>Kubernetes Clusters</h1>
      <ul>
        {clusters.map(cluster => (
          <li key={cluster.context_name}>
            <strong>{cluster.cluster_name}</strong> ({cluster.provider})
            <br />
            Region: {cluster.region} | Nodes: {cluster.node_count} | Pods: {cluster.pod_count}
            <br />
            {cluster.is_current ? (
              <span style={{ color: 'green' }}>✓ Current</span>
            ) : (
              <button onClick={() => switchContext(cluster.context_name)}>
                Switch to this cluster
              </button>
            )}
          </li>
        ))}
      </ul>
    </div>
  );
}
```

---

## kubectl Commands Reference

### Commands Used by API

| Operation | Command | Purpose |
|-----------|---------|---------|
| Get all contexts | `kubectl config view -o json` | Parse kubeconfig file |
| Get current context | `kubectl config current-context` | Identify active cluster |
| Switch context | `kubectl config use-context <name>` | Change active cluster |
| Check accessibility | `kubectl --context <name> cluster-info --request-timeout=5s` | Validate connectivity |
| Count nodes | `kubectl --context <name> get nodes --no-headers` | Resource counting |
| Count pods | `kubectl --context <name> get pods --all-namespaces --no-headers` | Resource counting |

---

## Troubleshooting

### Common Issues

**Issue 1: kubectl not found**
```
Error: kubectl_not_available
Status: 503
```
**Solution:** Install kubectl and ensure it's in PATH

**Issue 2: Context not accessible**
```
Context listed but accessible: false
```
**Solution:** Check AWS SSO session, Azure login, or GCP authentication

**Issue 3: Wrong region detected**
```
Region shows 'unknown' for valid cluster
```
**Solution:** Ensure context name or server URL contains region pattern

### Debug Logging

Enable debug logging in backend:
```python
import logging
logging.basicConfig(level=logging.DEBUG)
```

View logs:
```bash
docker logs miniprem-monitor -f | grep "cluster_management"
```

---

## Future Enhancements

### Planned Features

1. **Caching Layer:** 30-second cache for cluster list
2. **Background Polling:** Continuous accessibility monitoring
3. **Metrics History:** Track cluster resource trends over time
4. **Namespace Filtering:** Per-namespace pod counts
5. **Cost Integration:** Real-time cost calculation for each cluster
6. **Health Checks:** Node health, pod restart counts, error events
7. **Multi-Context Operations:** Batch operations across clusters

### API Evolution

**v1.1:** Add caching and background monitoring
**v1.2:** Add namespace-level details
**v1.3:** Add cluster health metrics
**v2.0:** Add write operations (create/delete clusters)

---

## Contributing

### Code Style

- Follow Google-style docstrings
- Use Python 3.13+ type hints
- Add comprehensive error handling
- Write unit tests for all functions

### Pull Request Template

```markdown
## Description
[Brief description of changes]

## Testing
- [ ] Manual testing completed
- [ ] Automated tests added
- [ ] curl examples verified
- [ ] Frontend integration tested

## Provider Support
- [ ] EKS (AWS)
- [ ] AKS (Azure)
- [ ] GKE (Google)
- [ ] Local clusters
```

---

## License

Copyright © 2025 MiniPrem Monitor Backend Team
Licensed under the MIT License
