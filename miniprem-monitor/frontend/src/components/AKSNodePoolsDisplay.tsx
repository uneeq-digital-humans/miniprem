import React, { useEffect, useState } from 'react';
import clsx from 'clsx';

interface NodePool {
  name: string;
  vm_size: string;
  nodes: {
    name: string;
    ready: boolean;
    status?: string;
    version?: string;
    created?: string;
  }[];
}

interface AKSNodePoolsDisplayProps {
  provider: string;
}

const AKSNodePoolsDisplay: React.FC<AKSNodePoolsDisplayProps> = ({ provider }) => {
  const [nodePools, setNodePools] = useState<NodePool[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (provider !== 'aks') {
      setNodePools([]);
      setError(null);
      return;
    }

    const fetchNodePools = async () => {
      setLoading(true);
      setError(null);

      try {
        const response = await fetch('/api/kubernetes/aks/nodepools');
        const data = await response.json();

        if (data.success) {
          setNodePools(data.node_pools || []);
        } else {
          setError(data.error || 'Failed to fetch node pools');
        }
      } catch (err) {
        console.error('Error fetching AKS node pools:', err);
        setError('Network error fetching node pools');
      } finally {
        setLoading(false);
      }
    };

    fetchNodePools();

    // Refresh every 30 seconds
    const interval = setInterval(fetchNodePools, 30000);

    return () => clearInterval(interval);
  }, [provider]);

  // Don't render anything if provider is not AKS
  if (provider !== 'aks') return null;

  // Loading state (only show on initial load)
  if (loading && nodePools.length === 0) {
    return (
      <div className="bg-gray-100 dark:bg-gray-700 rounded-lg p-4 mt-4">
        <h3 className="font-semibold mb-3 flex items-center">
          <span className="mr-2">🖥️</span>
          AKS Node Pools
        </h3>
        <div className="text-sm text-gray-500 dark:text-gray-400 flex items-center">
          <div className="animate-spin mr-2 h-4 w-4 border-2 border-gray-400 dark:border-gray-500 border-t-transparent rounded-full"></div>
          Loading node pools...
        </div>
      </div>
    );
  }

  // Error state
  if (error) {
    return (
      <div className="bg-red-50 dark:bg-red-900/20 rounded-lg p-4 mt-4 border border-red-200 dark:border-red-800">
        <h3 className="font-semibold mb-2 flex items-center text-red-700 dark:text-red-300">
          <span className="mr-2">⚠️</span>
          AKS Node Pools
        </h3>
        <div className="text-sm text-red-600 dark:text-red-400">
          Error: {error}
        </div>
      </div>
    );
  }

  // No node pools found
  if (nodePools.length === 0) {
    return (
      <div className="bg-gray-100 dark:bg-gray-700 rounded-lg p-4 mt-4">
        <h3 className="font-semibold mb-3 flex items-center">
          <span className="mr-2">🖥️</span>
          AKS Node Pools
        </h3>
        <div className="text-sm text-gray-500 dark:text-gray-400">
          No node pools found
        </div>
      </div>
    );
  }

  return (
    <div className="bg-gray-100 dark:bg-gray-700 rounded-lg p-4 mt-4">
      <h3 className="font-semibold mb-3 flex items-center text-gray-900 dark:text-gray-100">
        <span className="mr-2">🖥️</span>
        AKS Node Pools
        {loading && (
          <div className="ml-2 animate-spin h-3 w-3 border-2 border-gray-400 dark:border-gray-500 border-t-transparent rounded-full"></div>
        )}
      </h3>

      {nodePools.map((pool) => {
        const readyNodes = pool.nodes.filter((n) => n.ready).length;
        const totalNodes = pool.nodes.length;
        const healthPercentage = totalNodes > 0 ? (readyNodes / totalNodes) * 100 : 0;

        return (
          <div
            key={pool.name}
            className="mb-3 pb-3 border-b border-gray-300 dark:border-gray-600 last:border-0 last:mb-0 last:pb-0"
          >
            <div className="flex justify-between items-center mb-2">
              <span className="font-medium text-sm text-gray-900 dark:text-gray-100">
                {pool.name}
              </span>
              <span className="text-xs bg-gray-200 dark:bg-gray-600 text-gray-700 dark:text-gray-300 px-2 py-1 rounded">
                {pool.vm_size}
              </span>
            </div>

            <div className="flex items-center gap-2">
              {/* Health Bar */}
              <div className="flex-1 bg-gray-200 dark:bg-gray-600 rounded-full h-2">
                <div
                  className={clsx(
                    'h-2 rounded-full transition-all',
                    healthPercentage === 100
                      ? 'bg-green-500'
                      : healthPercentage >= 50
                      ? 'bg-yellow-500'
                      : 'bg-red-500'
                  )}
                  style={{ width: `${healthPercentage}%` }}
                />
              </div>

              {/* Node Counts */}
              <span className="text-sm whitespace-nowrap">
                <span className="text-green-600 dark:text-green-400 font-medium">
                  {readyNodes}
                </span>
                <span className="text-gray-500 dark:text-gray-400"> / {totalNodes}</span>
              </span>
            </div>

            {/* Node Details (only show if 5 or fewer nodes) */}
            {pool.nodes.length <= 5 && (
              <div className="mt-2 space-y-1">
                {pool.nodes.map((node) => (
                  <div
                    key={node.name}
                    className="text-xs flex items-center gap-2"
                  >
                    <span
                      className={clsx(
                        'flex-shrink-0',
                        node.ready ? 'text-green-500' : 'text-red-500'
                      )}
                      title={node.ready ? 'Ready' : 'Not Ready'}
                    >
                      {node.ready ? '●' : '○'}
                    </span>
                    <span className="truncate text-gray-600 dark:text-gray-400 flex-1">
                      {node.name}
                    </span>
                    {node.version && (
                      <span className="text-gray-400 dark:text-gray-500 text-xs">
                        v{node.version}
                      </span>
                    )}
                  </div>
                ))}
              </div>
            )}

            {/* Summary for large node pools */}
            {pool.nodes.length > 5 && (
              <div className="mt-2 text-xs text-gray-500 dark:text-gray-400">
                {pool.nodes.length} nodes total
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
};

export default AKSNodePoolsDisplay;
