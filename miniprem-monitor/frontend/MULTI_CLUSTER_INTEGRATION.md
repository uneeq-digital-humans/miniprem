# Multi-Cluster Management Integration Guide

## Overview

Enhanced the MiniPrem Monitor frontend with multi-cluster Kubernetes management capabilities. Users can now:

- View and switch between multiple Kubernetes clusters
- See provider-specific information (EKS, AKS, GKE, Local)
- Get color-coded badges for each cloud provider
- View cluster metadata (region, node count, pod count)
- Persist last selected cluster across sessions

## Files Created

### 1. Type Definitions
**File:** `/miniprem-monitor/frontend/src/types/cluster.ts`

Defines TypeScript interfaces for cluster management:
- `ClusterInfo` - Complete cluster metadata
- `CloudProvider` - Union type for supported providers
- `ClusterListResponse` - API response format
- `ContextSwitchRequest/Response` - Context switching types

### 2. Custom Hook
**File:** `/miniprem-monitor/frontend/src/hooks/useClusterManagement.ts`

React hook for cluster management operations:
- `fetchClusters()` - Retrieve cluster list from backend
- `switchCluster(contextName)` - Switch active Kubernetes context
- `refreshClusters()` - Reload cluster information
- Automatic localStorage persistence
- Error handling and loading states

**Usage Example:**
```typescript
const {
  clusters,
  currentCluster,
  loading,
  switching,
  error,
  switchCluster,
  refreshClusters
} = useClusterManagement({
  autoFetch: true,
  persistSelection: true,
  onClusterChange: (cluster) => console.log('Switched to:', cluster.cluster_name),
  onError: (error) => console.error('Cluster error:', error)
});
```

### 3. Enhanced ClusterSelector Component
**File:** `/miniprem-monitor/frontend/src/components/ClusterSelector.tsx` (Updated)

Enhanced features:
- **Provider Badges**: Color-coded badges for EKS (orange), AKS (blue), GKE (green)
- **Grouped Display**: Clusters grouped by cloud provider
- **Metadata Display**: Shows region, namespace, pod count
- **Refresh Button**: Manual cluster list refresh
- **Current Indicator**: Visual checkmark for active cluster
- **Responsive Design**: Compact mode for tight layouts

**Visual Structure:**
```
┌─────────────────────────────────────────┐
│ Kubernetes Clusters            [↻] [⚙] │
├─────────────────────────────────────────┤
│ EKS (2)                                 │
│   ● [EKS] renny-prod (us-east-1) ✓     │
│     uneeq-renderer • 12 pods            │
│   ● [EKS] renny-staging (us-east-2)    │
│     default • 8 pods                    │
│                                         │
│ AKS (1)                                 │
│   ● [AKS] renny-aks (eastus)           │
│     uneeq-renderer • 10 pods            │
│                                         │
│ GKE (1)                                 │
│   ● [GKE] renny-gke (us-central1)      │
│     default • 6 pods                    │
├─────────────────────────────────────────┤
│        Manage Clusters                  │
└─────────────────────────────────────────┘
```

## Backend API Requirements

The frontend expects these API endpoints (already implemented in backend):

### GET `/api/kubernetes/clusters/list`
**Response:**
```json
{
  "success": true,
  "clusters": [
    {
      "context_name": "arn:aws:eks:us-east-1:...:cluster/renny-prod",
      "cluster_name": "renny-prod",
      "provider": "eks",
      "region": "us-east-1",
      "is_current": true,
      "accessible": true,
      "node_count": 5,
      "pod_count": 12
    }
  ],
  "current_context": "arn:aws:eks:us-east-1:...:cluster/renny-prod"
}
```

### POST `/api/kubernetes/context/switch`
**Request:**
```json
{
  "context_name": "arn:aws:eks:us-east-2:...:cluster/renny-staging"
}
```

**Response:**
```json
{
  "success": true,
  "switched_to": "arn:aws:eks:us-east-2:...:cluster/renny-staging",
  "cluster_info": {
    "cluster_name": "renny-staging",
    "provider": "eks",
    "region": "us-east-2"
  }
}
```

## Integration Steps

### Option 1: Use the Custom Hook (Recommended)

Replace existing cluster management logic in `page.tsx`:

```typescript
import { useClusterManagement } from '../hooks/useClusterManagement';

// Inside component:
const {
  clusters,
  currentCluster,
  loading,
  error,
  switchCluster,
  refreshClusters
} = useClusterManagement({
  autoFetch: true,
  persistSelection: true,
  onClusterChange: (cluster) => {
    // Refresh pods when cluster changes
    handleRefreshPods();
  },
  onError: (error) => {
    setKubernetesError(error);
  }
});

// Convert to existing ClusterInfo format for compatibility
const compatibleClusters = clusters.map(c => ({
  name: c.cluster_name,
  context: c.context_name,
  namespace: c.namespace,
  environment: c.provider as 'eks' | 'aks' | 'gke' | 'local',
  region: c.region,
  status: c.is_current ? 'connected' as const : 'error' as const,
  podCount: c.pod_count
}));
```

### Option 2: Direct Backend Integration

If backend implements the `/api/kubernetes/clusters/list` endpoint differently, update the hook:

```typescript
// In useClusterManagement.ts, modify fetchClusters():
const response = await fetch(`/api/kubernetes/contexts?t=${Date.now()}`);
// Add transformation logic to match ClusterInfo type
```

## Color Coding

Provider badges use these colors:
- **EKS**: Orange (`bg-orange-100`, `text-orange-700`)
- **AKS**: Blue (`bg-blue-100`, `text-blue-700`)
- **GKE**: Green (`bg-green-100`, `text-green-700`)
- **Local**: Gray (`bg-gray-100`, `text-gray-700`)

## LocalStorage Persistence

The hook automatically saves the last selected cluster:
- **Key**: `miniprem-last-cluster-context`
- **Value**: Context name (string)
- **Behavior**: Auto-restores on page reload if cluster is still accessible

## Error Handling

Error states are propagated through:
1. Hook's `error` state variable
2. Optional `onError` callback
3. Visual indicators in ClusterSelector dropdown

## Testing Checklist

- [ ] Multiple clusters display correctly grouped by provider
- [ ] Current cluster shows checkmark indicator
- [ ] Switching clusters updates pod list
- [ ] Region and pod counts display accurately
- [ ] Refresh button re-fetches cluster list
- [ ] localStorage persists selection across page reloads
- [ ] Error states display user-friendly messages
- [ ] Dark mode styling works correctly
- [ ] Compact mode renders properly in tight layouts
- [ ] Settings modal opens from ClusterSelector

## Future Enhancements

Potential additions:
- **Connection Testing**: Test cluster accessibility before switching
- **Favorites**: Pin frequently used clusters to top
- **Search/Filter**: Search clusters by name or region
- **Metrics Preview**: Show cluster health in dropdown
- **Multi-Select**: Batch operations across clusters
- **Context History**: Track recently accessed clusters

## ASCII Wireframe

```
┌────────────────────────────────────────────────────────────────────┐
│ MiniPrem Monitor                       [WebSocket: Connected] [🌓] │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│ ┌────────────────────────────────────────────────────────────────┐│
│ │ System Metrics                                                ││
│ │ CPU: 45%  Memory: 62%  Disk: 38%  Network: 1.2 MB/s          ││
│ └────────────────────────────────────────────────────────────────┘│
│                                                                    │
│ ┌────────────────────────────────────────────────────────────────┐│
│ │ Kubernetes Pods                                               ││
│ │                                                                ││
│ │ Region: [us-east-1 ▼]                                          ││
│ │ EKS: [● EKS renny-prod • us-east-1 • uneeq-renderer ▼]        ││
│ │ Context: [arn:aws:eks:...:cluster/renny-prod ▼]               ││
│ │                                                                ││
│ │ [All (12)] [Running (10)] [Pending (2)] [Failed (0)]          ││
│ │                                                                ││
│ │ ● renny-avatar-5d7f9c8b-abc123                                ││
│ │   uneeq-renderer • 1/1 ready • 3h2m                           ││
│ │ ● renny-avatar-5d7f9c8b-def456                                ││
│ │   uneeq-renderer • 1/1 ready • 3h2m                           ││
│ └────────────────────────────────────────────────────────────────┘│
└────────────────────────────────────────────────────────────────────┘
```

## Support

For backend API implementation details, see:
- `/miniprem-monitor/backend/app/main.py` - API endpoints
- `/miniprem-monitor/backend/app/services/kubernetes_monitor.py` - Cluster management service

## License

Part of the MiniPrem Monitor project.
