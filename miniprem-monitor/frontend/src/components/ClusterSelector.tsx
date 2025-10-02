import React, { useState, useRef, useEffect } from 'react';
import { ChevronDown, Settings, Cloud, Server, AlertTriangle } from 'lucide-react';
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

export function ClusterSelector({
  currentCluster,
  availableClusters,
  onClusterSelect,
  onOpenSettings,
  loading = false,
  compact = false
}: ClusterSelectorProps) {
  const [isOpen, setIsOpen] = useState(false);
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
    const name = cluster.name.length > 15
      ? `${cluster.name.substring(0, 12)}...`
      : cluster.name;
    return `${envLabel} ${name}`;
  };

  const formatNamespace = (namespace: string) => {
    return namespace.length > 12
      ? `${namespace.substring(0, 9)}..`
      : namespace;
  };

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
            <div className="flex items-center space-x-1">
              <span className="font-medium text-primary">
                {formatClusterName(currentCluster)}
              </span>
              {!compact && currentCluster.namespace && (
                <>
                  <span className="text-muted">•</span>
                  <span className="text-secondary">
                    {formatNamespace(currentCluster.namespace)}
                  </span>
                </>
              )}
            </div>
            {currentCluster.podCount && !compact && (
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
        <div className="absolute top-full left-0 mt-2 w-80 bg-white dark:bg-gray-800 rounded-lg shadow-lg border border-gray-200 dark:border-gray-700 z-50">
          {/* Header */}
          <div className="px-4 py-3 border-b border-gray-200 dark:border-gray-700">
            <div className="flex items-center justify-between">
              <h3 className="text-sm font-semibold text-primary">Kubernetes Clusters</h3>
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

          {/* Cluster list */}
          <div className="max-h-64 overflow-y-auto custom-scrollbar">
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
                {availableClusters.map((cluster) => {
                  const IconComponent = ENVIRONMENT_ICONS[cluster.environment];
                  const isSelected = currentCluster?.context === cluster.context;

                  return (
                    <button
                      key={`${cluster.context}-${cluster.namespace}`}
                      onClick={() => {
                        onClusterSelect(cluster);
                        setIsOpen(false);
                      }}
                      className={clsx(
                        'w-full px-4 py-3 text-left hover:bg-gray-50 dark:hover:bg-gray-700 transition-colors',
                        isSelected && 'bg-blue-50 dark:bg-blue-900/20'
                      )}
                      data-testid="cluster-option"
                    >
                      <div className="flex items-center space-x-3">
                        <IconComponent className="w-4 h-4 text-uneeq-primary flex-shrink-0" />
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center space-x-2">
                            <StatusIndicator
                              status={getStatusForCluster(cluster)}
                              size="sm"
                            />
                            <span className="font-medium text-primary truncate">
                              {cluster.name}
                            </span>
                            {cluster.region && (
                              <span className="text-xs text-muted">
                                ({cluster.region})
                              </span>
                            )}
                          </div>
                          <div className="text-sm text-secondary mt-1">
                            {cluster.namespace}
                            {cluster.podCount && (
                              <span className="ml-2">• {cluster.podCount} pods</span>
                            )}
                          </div>
                          {(cluster.lastSync || cluster.latency) && (
                            <div className="text-xs text-muted mt-1">
                              {cluster.lastSync && (
                                <span>
                                  Last sync: {new Date(cluster.lastSync).toLocaleTimeString()}
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
            )}
          </div>

          {/* Footer */}
          <div className="px-4 py-3 border-t border-gray-200 dark:border-gray-700">
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