import React, { useState, useRef, useEffect } from 'react';
import { ChevronDown, Settings, Cloud, Server, AlertTriangle, RefreshCw } from 'lucide-react';
import { StatusIndicator } from './StatusIndicator';
import clsx from 'clsx';

export interface ClusterInfo {
  name: string;
  context: string;
  namespace: string;
  environment: 'local' | 'eks' | 'gke' | 'aks';
  region?: string;
  status: 'connected' | 'connecting' | 'error';
  lastSync?: Date;
  latency?: number;
  podCount?: number;
}

interface ClusterSelectorProps {
  currentCluster: ClusterInfo | null;
  availableClusters: ClusterInfo[];
  onClusterSelect: (cluster: ClusterInfo) => void;
  onOpenSettings: () => void;
  loading?: boolean;
  compact?: boolean;
}

const ENVIRONMENT_ICONS = {
  local: Server,
  eks: Cloud,
  gke: Cloud,
  aks: Cloud,
} as const;

const ENVIRONMENT_LABELS = {
  local: 'Local',
  eks: 'EKS',
  gke: 'GKE',
  aks: 'AKS',
} as const;

const ENVIRONMENT_COLORS = {
  local: 'text-gray-600 dark:text-gray-400',
  eks: 'text-orange-600 dark:text-orange-400',
  gke: 'text-green-600 dark:text-green-400',
  aks: 'text-blue-600 dark:text-blue-400',
} as const;

const ENVIRONMENT_BADGES = {
  local: 'bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-300',
  eks: 'bg-orange-100 dark:bg-orange-900/30 text-orange-700 dark:text-orange-300',
  gke: 'bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-300',
  aks: 'bg-blue-100 dark:bg-blue-900/30 text-blue-700 dark:text-blue-300',
} as const;

export function ClusterSelector({
  currentCluster,
  availableClusters,
  onClusterSelect,
  onOpenSettings,
  loading = false,
  compact = false
}: ClusterSelectorProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  // Close dropdown when clicking outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        setIsOpen(false);
      }
    };

    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  const getStatusForCluster = (cluster: ClusterInfo) => {
    switch (cluster.status) {
      case 'connected': return 'healthy';
      case 'connecting': return 'warning';
      case 'error': return 'error';
      default: return 'unknown';
    }
  };

  const formatClusterName = (cluster: ClusterInfo) => {
    const envLabel = ENVIRONMENT_LABELS[cluster.environment];
    const name = cluster.name.length > 30
      ? `${cluster.name.substring(0, 27)}...`
      : cluster.name;
    return `${envLabel}: ${name}`;
  };

  const formatNamespace = (namespace: string) => {
    return namespace.length > 12
      ? `${namespace.substring(0, 9)}..`
      : namespace;
  };

  const handleRefresh = async (e: React.MouseEvent) => {
    e.stopPropagation();
    setRefreshing(true);
    // Trigger refresh by calling onOpenSettings or a dedicated refresh handler
    // For now, we'll just show the animation
    setTimeout(() => setRefreshing(false), 1000);
  };

  // Group clusters by provider
  const groupedClusters = availableClusters.reduce((acc, cluster) => {
    const provider = cluster.environment;
    if (!acc[provider]) {
      acc[provider] = [];
    }
    acc[provider].push(cluster);
    return acc;
  }, {} as Record<string, ClusterInfo[]>);

  if (!currentCluster && availableClusters.length === 0) {
    return (
      <div className="flex items-center space-x-2">
        <button
          onClick={onOpenSettings}
          className="flex items-center space-x-2 px-3 py-1 rounded-full bg-white dark:bg-gray-700 shadow-sm border border-gray-200 dark:border-gray-600 hover:bg-gray-50 dark:hover:bg-gray-600 transition-colors"
          data-testid="setup-kubernetes"
        >
          <AlertTriangle className="w-4 h-4 text-status-warning" />
          <span className="text-sm font-medium text-secondary">Setup Kubernetes</span>
        </button>
      </div>
    );
  }

  return (
    <div className="relative" ref={dropdownRef}>
      {/* Current cluster display */}
      <button
        onClick={() => setIsOpen(!isOpen)}
        className={clsx(
          'flex items-center space-x-2 px-3 py-1 rounded-full bg-white dark:bg-gray-700 shadow-sm border border-gray-200 dark:border-gray-600 hover:bg-gray-50 dark:hover:bg-gray-600 transition-colors',
          isOpen && 'ring-2 ring-uneeq-primary ring-opacity-20',
          compact ? 'text-xs' : 'text-sm'
        )}
        data-testid="cluster-selector"
      >
        {currentCluster ? (
          <>
            <StatusIndicator
              status={getStatusForCluster(currentCluster)}
              size="sm"
            />
            {/* Provider Badge */}
            <span className={clsx(
              'px-2 py-0.5 rounded text-xs font-semibold',
              ENVIRONMENT_BADGES[currentCluster.environment]
            )}>
              {ENVIRONMENT_LABELS[currentCluster.environment]}
            </span>
            <div className="flex items-center space-x-1">
              <span className="font-medium text-primary">
                {currentCluster.name}
              </span>
              {!compact && currentCluster.region && (
                <>
                  <span className="text-muted">•</span>
                  <span className="text-xs text-secondary">
                    {currentCluster.region}
                  </span>
                </>
              )}
              {!compact && currentCluster.namespace && (
                <>
                  <span className="text-muted">•</span>
                  <span className="text-secondary">
                    {formatNamespace(currentCluster.namespace)}
                  </span>
                </>
              )}
            </div>
            {currentCluster.podCount !== undefined && !compact && (
              <>
                <span className="text-muted">•</span>
                <span className="text-xs text-secondary">
                  {currentCluster.podCount} pods
                </span>
              </>
            )}
          </>
        ) : (
          <>
            <StatusIndicator status="unknown" size="sm" />
            <span className="font-medium text-muted">No cluster selected</span>
          </>
        )}
        <ChevronDown className={clsx(
          'w-4 h-4 text-muted transition-transform',
          isOpen && 'transform rotate-180'
        )} />
      </button>

      {/* Dropdown menu */}
      {isOpen && (
        <div className="absolute top-full left-0 mt-2 w-96 bg-white dark:bg-gray-800 rounded-lg shadow-lg border border-gray-200 dark:border-gray-700 z-50">
          {/* Header */}
          <div className="px-4 py-3 border-b border-gray-200 dark:border-gray-700">
            <div className="flex items-center justify-between">
              <div className="flex items-center space-x-2">
                <h3 className="text-sm font-semibold text-primary">Kubernetes Clusters</h3>
                <span className={clsx(
                  'px-2 py-0.5 rounded-full text-xs font-medium',
                  'bg-gray-100 dark:bg-gray-700 text-gray-600 dark:text-gray-300'
                )}>
                  {availableClusters.length}
                </span>
              </div>
              <div className="flex items-center space-x-1">
                <button
                  onClick={handleRefresh}
                  className="btn-icon p-1"
                  title="Refresh cluster list"
                  disabled={refreshing}
                  data-testid="refresh-clusters"
                >
                  <RefreshCw className={clsx(
                    'w-4 h-4',
                    refreshing && 'animate-spin'
                  )} />
                </button>
                <button
                  onClick={() => {
                    setIsOpen(false);
                    onOpenSettings();
                  }}
                  className="btn-icon p-1"
                  data-testid="open-k8s-settings"
                >
                  <Settings className="w-4 h-4" />
                </button>
              </div>
            </div>
          </div>

          {/* Cluster list */}
          <div className="max-h-96 overflow-y-auto custom-scrollbar">
            {availableClusters.length === 0 ? (
              <div className="px-4 py-6 text-center">
                <div className="text-muted mb-2">No clusters configured</div>
                <button
                  onClick={() => {
                    setIsOpen(false);
                    onOpenSettings();
                  }}
                  className="text-xs text-uneeq-primary hover:text-uneeq-pink font-medium"
                >
                  Configure clusters
                </button>
              </div>
            ) : (
              <div className="py-2">
                {Object.entries(groupedClusters).map(([provider, clusters]) => (
                  <div key={provider}>
                    {/* Provider Group Header */}
                    <div className="px-4 py-2 text-xs font-semibold text-gray-500 dark:text-gray-400 uppercase tracking-wider bg-gray-50 dark:bg-gray-750">
                      <div className="flex items-center space-x-2">
                        {React.createElement(ENVIRONMENT_ICONS[provider as keyof typeof ENVIRONMENT_ICONS], {
                          className: clsx('w-3 h-3', ENVIRONMENT_COLORS[provider as keyof typeof ENVIRONMENT_COLORS])
                        })}
                        <span>{ENVIRONMENT_LABELS[provider as keyof typeof ENVIRONMENT_LABELS]}</span>
                        <span className="text-gray-400 dark:text-gray-500">({clusters.length})</span>
                      </div>
                    </div>

                    {/* Clusters in this group */}
                    {clusters.map((cluster) => {
                      const isSelected = currentCluster?.context === cluster.context;

                      return (
                        <button
                          key={`${cluster.context}-${cluster.namespace}`}
                          onClick={() => {
                            onClusterSelect(cluster);
                            setIsOpen(false);
                          }}
                          className={clsx(
                            'w-full px-4 py-3 text-left hover:bg-gray-50 dark:hover:bg-gray-700 transition-colors border-l-4',
                            isSelected
                              ? 'bg-blue-50 dark:bg-blue-900/20 border-blue-500'
                              : 'border-transparent'
                          )}
                          data-testid="cluster-option"
                        >
                          <div className="flex items-center space-x-3">
                            <StatusIndicator
                              status={getStatusForCluster(cluster)}
                              size="sm"
                            />
                            <div className="flex-1 min-w-0">
                              <div className="flex items-center space-x-2">
                                <span className="font-medium text-primary truncate">
                                  {cluster.name}
                                </span>
                                {cluster.region && (
                                  <span className="text-xs px-2 py-0.5 rounded bg-gray-100 dark:bg-gray-700 text-gray-600 dark:text-gray-300">
                                    {cluster.region}
                                  </span>
                                )}
                                {isSelected && (
                                  <span className="text-xs text-green-600 dark:text-green-400 font-semibold">
                                    ✓ Current
                                  </span>
                                )}
                              </div>
                              <div className="text-sm text-secondary mt-1">
                                {cluster.namespace}
                                {cluster.podCount !== undefined && (
                                  <span className="ml-2">• {cluster.podCount} pods</span>
                                )}
                              </div>
                              {(cluster.lastSync || cluster.latency) && (
                                <div className="text-xs text-muted mt-1">
                                  {cluster.lastSync && (
                                    <span>
                                      Last sync: {typeof cluster.lastSync === 'string'
                                        ? cluster.lastSync
                                        : cluster.lastSync instanceof Date
                                        ? cluster.lastSync.toLocaleTimeString()
                                        : 'Unknown'}
                                    </span>
                                  )}
                                  {cluster.latency && (
                                    <span className="ml-2">• {cluster.latency}ms</span>
                                  )}
                                </div>
                              )}
                            </div>
                          </div>
                        </button>
                      );
                    })}
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* Footer */}
          <div className="px-4 py-3 border-t border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-750">
            <button
              onClick={() => {
                setIsOpen(false);
                onOpenSettings();
              }}
              className="w-full text-center text-sm text-uneeq-primary hover:text-uneeq-pink font-medium"
              data-testid="manage-clusters"
            >
              Manage Clusters
            </button>
          </div>
        </div>
      )}

      {/* Loading overlay */}
      {loading && (
        <div className="absolute inset-0 bg-white/50 dark:bg-gray-800/50 rounded-full flex items-center justify-center">
          <div className="w-4 h-4 border-2 border-uneeq-primary border-t-transparent rounded-full animate-spin" />
        </div>
      )}
    </div>
  );
}
