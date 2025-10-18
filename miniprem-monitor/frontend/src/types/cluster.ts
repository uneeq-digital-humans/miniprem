/**
 * Cluster Management Type Definitions
 *
 * Type definitions for multi-cluster Kubernetes management functionality.
 */

export type CloudProvider = 'eks' | 'aks' | 'gke' | 'local' | 'unknown';

export interface ClusterInfo {
  // Identification
  context_name: string;
  cluster_name: string;
  namespace: string;

  // Provider information
  provider: CloudProvider;
  region?: string;

  // Status
  is_current: boolean;
  accessible: boolean;

  // Metrics
  node_count: number;
  pod_count: number;

  // Additional metadata
  api_server?: string;
  version?: string;
  last_sync?: Date;
  latency?: number;
}

export interface ClusterListResponse {
  success: boolean;
  clusters: ClusterInfo[];
  current_context: string;
  error?: string;
  error_type?: string;
  timestamp: string;
}

export interface ContextSwitchRequest {
  context_name: string;
}

export interface ContextSwitchResponse {
  success: boolean;
  switched_to?: string;
  new_context?: string;
  cluster_info?: Partial<ClusterInfo>;
  error?: string;
  error_type?: string;
  timestamp: string;
}

export interface ClusterHealth {
  healthy: boolean;
  message?: string;
  issues?: string[];
}

export interface ClusterSelectorProps {
  onClusterChange?: (cluster: ClusterInfo) => void;
  onError?: (error: string) => void;
  compact?: boolean;
  className?: string;
}
