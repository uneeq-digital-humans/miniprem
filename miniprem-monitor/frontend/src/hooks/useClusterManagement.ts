/**
 * useClusterManagement Hook
 *
 * Custom React hook for managing multi-cluster Kubernetes operations.
 * Handles fetching cluster list, switching contexts, and persisting selections.
 */

import { useState, useEffect, useCallback } from 'react';
import { ClusterInfo, ClusterListResponse, ContextSwitchResponse } from '../types/cluster';

interface UseClusterManagementOptions {
  autoFetch?: boolean;
  persistSelection?: boolean;
  onClusterChange?: (cluster: ClusterInfo) => void;
  onError?: (error: string) => void;
}

interface UseClusterManagementReturn {
  clusters: ClusterInfo[];
  currentCluster: ClusterInfo | null;
  loading: boolean;
  switching: boolean;
  error: string | null;
  fetchClusters: () => Promise<void>;
  switchCluster: (contextName: string) => Promise<boolean>;
  refreshClusters: () => Promise<void>;
}

const STORAGE_KEY = 'miniprem-last-cluster-context';

export function useClusterManagement(
  options: UseClusterManagementOptions = {}
): UseClusterManagementReturn {
  const {
    autoFetch = true,
    persistSelection = true,
    onClusterChange,
    onError,
  } = options;

  const [clusters, setClusters] = useState<ClusterInfo[]>([]);
  const [currentCluster, setCurrentCluster] = useState<ClusterInfo | null>(null);
  const [loading, setLoading] = useState(false);
  const [switching, setSwitching] = useState(false);
  const [error, setError] = useState<string | null>(null);

  /**
   * Fetch available clusters from backend
   */
  const fetchClusters = useCallback(async () => {
    setLoading(true);
    setError(null);

    try {
      const response = await fetch(`/api/kubernetes/clusters/list?t=${Date.now()}`);
      const data: ClusterListResponse = await response.json();

      if (data.success && data.clusters) {
        // Convert date strings to Date objects
        const clustersWithDates = data.clusters.map(cluster => ({
          ...cluster,
          last_sync: cluster.last_sync ? new Date(cluster.last_sync) : undefined,
        }));

        setClusters(clustersWithDates);

        // Set current cluster
        const current = clustersWithDates.find(c => c.is_current);
        if (current) {
          setCurrentCluster(current);

          // Persist selection if enabled
          if (persistSelection) {
            localStorage.setItem(STORAGE_KEY, current.context_name);
          }
        }

        console.log(`Loaded ${clustersWithDates.length} Kubernetes clusters`);
      } else {
        const errorMsg = data.error || 'Failed to fetch clusters';
        setError(errorMsg);
        onError?.(errorMsg);
      }
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : 'Network error fetching clusters';
      console.error('Error fetching clusters:', err);
      setError(errorMsg);
      onError?.(errorMsg);
    } finally {
      setLoading(false);
    }
  }, [persistSelection, onError]);

  /**
   * Switch to a different Kubernetes context
   */
  const switchCluster = useCallback(
    async (contextName: string): Promise<boolean> => {
      setSwitching(true);
      setError(null);

      try {
        const response = await fetch(`/api/kubernetes/context/switch`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ context_name: contextName }),
        });

        const data: ContextSwitchResponse = await response.json();

        if (data.success && data.switched_to) {
          console.log(`Successfully switched to context: ${data.switched_to}`);

          // Update current cluster
          const newCluster = clusters.find(c => c.context_name === contextName);
          if (newCluster) {
            setCurrentCluster(newCluster);
            onClusterChange?.(newCluster);

            // Persist selection
            if (persistSelection) {
              localStorage.setItem(STORAGE_KEY, contextName);
            }
          }

          // Refresh cluster list to update states
          await fetchClusters();

          return true;
        } else {
          const errorMsg = data.error || 'Failed to switch context';
          setError(errorMsg);
          onError?.(errorMsg);
          return false;
        }
      } catch (err) {
        const errorMsg = err instanceof Error ? err.message : 'Network error switching context';
        console.error('Error switching cluster:', err);
        setError(errorMsg);
        onError?.(errorMsg);
        return false;
      } finally {
        setSwitching(false);
      }
    },
    [clusters, persistSelection, onClusterChange, onError, fetchClusters]
  );

  /**
   * Refresh cluster list (alias for fetchClusters)
   */
  const refreshClusters = useCallback(async () => {
    await fetchClusters();
  }, [fetchClusters]);

  /**
   * Auto-fetch clusters on mount
   */
  useEffect(() => {
    if (autoFetch) {
      fetchClusters();
    }
  }, [autoFetch, fetchClusters]);

  /**
   * Restore last selected cluster from localStorage
   */
  useEffect(() => {
    if (persistSelection && clusters.length > 0 && !currentCluster) {
      const lastContext = localStorage.getItem(STORAGE_KEY);
      if (lastContext) {
        const lastCluster = clusters.find(c => c.context_name === lastContext);
        if (lastCluster && lastCluster.accessible) {
          console.log(`Restoring last selected cluster: ${lastContext}`);
          switchCluster(lastContext);
        }
      }
    }
  }, [persistSelection, clusters, currentCluster, switchCluster]);

  return {
    clusters,
    currentCluster,
    loading,
    switching,
    error,
    fetchClusters,
    switchCluster,
    refreshClusters,
  };
}
