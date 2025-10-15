import React, { useState, useMemo } from 'react';
import { ContainerStatus, StatusType, SystemInfo } from '../types/monitor';
import { StatusIndicator } from './StatusIndicator';
import { InlineMetrics } from './InlineMetrics';
import { MetricSelector } from './MetricSelector';
import { useMetricPreferences } from '../hooks/useMetricPreferences';
import { RefreshCw, Eye, EyeOff, Play, Square, Loader2 } from 'lucide-react';
import clsx from 'clsx';

interface ContainerPanelProps {
  containers: ContainerStatus[];
  loading?: boolean;
  onRefresh?: () => void;
  onViewLogs?: (containerName: string) => void;
  onStartContainer?: (containerName: string) => void;
  onStopContainer?: (containerName: string) => void;
  containerLoading?: string | null;
  systemInfo?: SystemInfo | null;
}

// Define filter types
type FilterType = 'all' | 'running' | 'stopped';

export function ContainerPanel({
  containers,
  loading,
  onRefresh,
  onViewLogs,
  onStartContainer,
  onStopContainer,
  containerLoading = null,
  systemInfo = null
}: ContainerPanelProps) {
  const [expandedContainer, setExpandedContainer] = useState<string | null>(null);
  const [statusFilter, setStatusFilter] = useState<FilterType>('all');
  const { selectedMetrics } = useMetricPreferences();

  const getContainerStatus = (status: string): StatusType => {
    if (status.toLowerCase().includes('up')) return 'healthy';
    if (status.toLowerCase().includes('exited')) return 'error';
    if (status.toLowerCase().includes('starting')) return 'warning';
    return 'unknown';
  };

  const formatUptime = (created: string): string => {
    if (!created) return 'Unknown';
    try {
      const createdDate = new Date(created);
      const now = new Date();
      const diffMs = now.getTime() - createdDate.getTime();
      const diffHours = Math.floor(diffMs / (1000 * 60 * 60));
      const diffDays = Math.floor(diffHours / 24);

      if (diffDays > 0) return `${diffDays}d ${diffHours % 24}h`;
      if (diffHours > 0) return `${diffHours}h`;
      return '<1h';
    } catch {
      return 'Unknown';
    }
  };

  const formatPorts = (ports: string[] | string | null | undefined): { ports: string[]; hasValidPorts: boolean } => {
    // Handle null or undefined
    if (!ports) {
      return { ports: [], hasValidPorts: false };
    }

    // Handle string array (expected format)
    if (Array.isArray(ports)) {
      return { ports: ports.filter(port => port && typeof port === 'string'), hasValidPorts: ports.length > 0 };
    }

    // Handle single string
    if (typeof ports === 'string') {
      const trimmed = ports.trim();
      if (trimmed) {
        // If it's a comma-separated string, split it
        const portArray = trimmed.includes(',')
          ? trimmed.split(',').map(p => p.trim()).filter(p => p)
          : [trimmed];
        return { ports: portArray, hasValidPorts: portArray.length > 0 };
      }
    }

    // Fallback for any other type
    return { ports: [], hasValidPorts: false };
  };

  // Filter containers based on status
  const filteredContainers = useMemo(() => {
    if (statusFilter === 'all') {
      return containers;
    }

    return containers.filter(container => {
      const status = getContainerStatus(container.status);
      if (statusFilter === 'running') {
        return status === 'healthy';
      }
      if (statusFilter === 'stopped') {
        return status === 'error' || status === 'unknown';
      }
      return true;
    });
  }, [containers, statusFilter]);

  // Calculate counts for each filter
  const filterCounts = useMemo(() => {
    const all = containers.length;
    const running = containers.filter(c => getContainerStatus(c.status) === 'healthy').length;
    const stopped = containers.filter(c => {
      const status = getContainerStatus(c.status);
      return status === 'error' || status === 'unknown';
    }).length;

    return { all, running, stopped };
  }, [containers]);

  return (
    <div className="card p-6">
      {/* Improved Header */}
      <div className="mb-6">
        {/* Title and Controls Row */}
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-xl font-bold text-gray-900 dark:text-gray-100 flex items-center">
            <div className="w-1 h-6 bg-gradient-uneeq rounded mr-3"></div>
            Docker Containers
            {systemInfo && systemInfo.docker && (
              <div
                className={clsx(
                  'ml-3 w-3 h-3 rounded-full',
                  systemInfo.docker.available ? 'bg-status-healthy' : 'bg-status-error'
                )}
                title={systemInfo.docker.available ? 'Available' : `Unavailable: ${systemInfo.docker.error || 'Unknown error'}`}
              />
            )}
          </h2>

          <div className="flex items-center space-x-2">
            <MetricSelector />
            <button
              onClick={onRefresh}
              className={clsx(
                'btn-icon',
                loading && 'animate-spin'
              )}
              disabled={loading}
              title="Refresh containers"
              aria-label="Refresh containers"
            >
              <RefreshCw className="w-5 h-5" />
            </button>
          </div>
        </div>

        {/* Status Filter - Segmented Control */}
        <div className="flex items-center justify-between">
          <div
            className="inline-flex bg-gray-100 dark:bg-gray-700 rounded-lg p-1"
            role="tablist"
            aria-label="Container status filter"
          >
            <button
              onClick={() => setStatusFilter('all')}
              className={clsx(
                'px-3 py-1.5 text-sm font-medium rounded-md transition-all duration-200 focus:outline-none focus:ring-2 focus:ring-uneeq-primary focus:ring-offset-2 focus:ring-offset-white dark:focus:ring-offset-gray-800',
                statusFilter === 'all'
                  ? 'bg-white dark:bg-gray-600 text-gray-900 dark:text-gray-100 shadow-sm'
                  : 'text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-200'
              )}
              role="tab"
              aria-selected={statusFilter === 'all'}
              aria-controls="container-list"
              data-testid="filter-all"
            >
              All
              {filterCounts.all > 0 && (
                <span className={clsx(
                  'ml-2 px-2 py-0.5 rounded-full text-xs',
                  statusFilter === 'all'
                    ? 'bg-gray-100 dark:bg-gray-500 text-gray-600 dark:text-gray-300'
                    : 'bg-gray-200 dark:bg-gray-600 text-gray-500 dark:text-gray-400'
                )}>
                  {filterCounts.all}
                </span>
              )}
            </button>

            <button
              onClick={() => setStatusFilter('running')}
              className={clsx(
                'px-3 py-1.5 text-sm font-medium rounded-md transition-all duration-200 focus:outline-none focus:ring-2 focus:ring-uneeq-primary focus:ring-offset-2 focus:ring-offset-white dark:focus:ring-offset-gray-800',
                statusFilter === 'running'
                  ? 'bg-white dark:bg-gray-600 text-gray-900 dark:text-gray-100 shadow-sm'
                  : 'text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-200'
              )}
              role="tab"
              aria-selected={statusFilter === 'running'}
              aria-controls="container-list"
              data-testid="filter-running"
            >
              <div className="flex items-center">
                <div className="w-2 h-2 bg-status-healthy rounded-full mr-1.5"></div>
                Running
                {filterCounts.running > 0 && (
                  <span className={clsx(
                    'ml-2 px-2 py-0.5 rounded-full text-xs',
                    statusFilter === 'running'
                      ? 'bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-300'
                      : 'bg-gray-200 dark:bg-gray-600 text-gray-500 dark:text-gray-400'
                  )}>
                    {filterCounts.running}
                  </span>
                )}
              </div>
            </button>

            <button
              onClick={() => setStatusFilter('stopped')}
              className={clsx(
                'px-3 py-1.5 text-sm font-medium rounded-md transition-all duration-200 focus:outline-none focus:ring-2 focus:ring-uneeq-primary focus:ring-offset-2 focus:ring-offset-white dark:focus:ring-offset-gray-800',
                statusFilter === 'stopped'
                  ? 'bg-white dark:bg-gray-600 text-gray-900 dark:text-gray-100 shadow-sm'
                  : 'text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-200'
              )}
              role="tab"
              aria-selected={statusFilter === 'stopped'}
              aria-controls="container-list"
              data-testid="filter-stopped"
            >
              <div className="flex items-center">
                <div className="w-2 h-2 bg-status-error rounded-full mr-1.5"></div>
                Stopped
                {filterCounts.stopped > 0 && (
                  <span className={clsx(
                    'ml-2 px-2 py-0.5 rounded-full text-xs',
                    statusFilter === 'stopped'
                      ? 'bg-red-100 dark:bg-red-900/30 text-red-700 dark:text-red-300'
                      : 'bg-gray-200 dark:bg-gray-600 text-gray-500 dark:text-gray-400'
                  )}>
                    {filterCounts.stopped}
                  </span>
                )}
              </div>
            </button>
          </div>

          {/* Results count */}
          <div className="text-sm text-gray-500 dark:text-gray-400">
            {loading ? 'Loading...' : `${filteredContainers.length} container${filteredContainers.length !== 1 ? 's' : ''}`}
          </div>
        </div>
      </div>

      {loading ? (
        <div className="space-y-3" data-testid="container-loading">
          {Array.from({ length: 3 }).map((_, index) => (
            <div key={index} className="animate-pulse">
              <div className="flex items-center space-x-3 p-3 bg-gray-100 dark:bg-gray-700 rounded">
                <div className="w-3 h-3 bg-gray-300 dark:bg-gray-500 rounded-full"></div>
                <div className="flex-1">
                  <div className="h-4 bg-gray-300 dark:bg-gray-500 rounded w-32 mb-1"></div>
                  <div className="h-3 bg-gray-300 dark:bg-gray-500 rounded w-24"></div>
                </div>
              </div>
            </div>
          ))}
        </div>
      ) : containers.length === 0 ? (
        <div className="text-center py-8 text-gray-500 dark:text-gray-400" data-testid="no-containers">
          <div className="text-4xl mb-2">🐳</div>
          <p>No containers found</p>
          <p className="text-sm">Docker may not be running or accessible</p>
        </div>
      ) : filteredContainers.length === 0 ? (
        <div className="text-center py-8 text-gray-500 dark:text-gray-400" data-testid="no-filtered-containers">
          <div className="text-2xl mb-2">🔍</div>
          <p>No {statusFilter === 'running' ? 'running' : statusFilter === 'stopped' ? 'stopped' : ''} containers</p>
          <p className="text-sm">Try changing the filter or check container status</p>
        </div>
      ) : (
        <div className="space-y-2" id="container-list" role="tabpanel">
          {filteredContainers.map((container, index) => (
            <div
              key={container.name || index}
              className={clsx(
                'border rounded-lg p-3 transition-all duration-200',
                expandedContainer === container.name
                  ? 'border-uneeq-primary bg-blue-50 dark:bg-blue-900/20'
                  : 'border-gray-200 dark:border-gray-600 hover:border-gray-300 dark:hover:border-gray-500'
              )}
              data-testid="container-item"
              data-container-item={container.name}
            >
              <div
                className="flex items-center justify-between cursor-pointer"
                onClick={() => setExpandedContainer(
                  expandedContainer === container.name ? null : container.name
                )}
              >
                <div className="flex items-center space-x-4 flex-1">
                  <StatusIndicator
                    status={getContainerStatus(container.status)}
                    size="md"
                  />
                  <div className="flex-1">
                    <div className="font-semibold text-gray-900 dark:text-gray-100">
                      {container.name}
                    </div>
                    <div className="text-sm text-gray-600 dark:text-gray-300">
                      {container.image} • {formatUptime(container.created)}
                    </div>
                  </div>

                  {/* Inline Metrics - displayed directly on the container row */}
                  {container.metrics && (
                    <InlineMetrics metrics={container.metrics} selectedMetrics={selectedMetrics} />
                  )}
                </div>

                <div className="flex items-center space-x-2 ml-4">
                  {/* Fallback to Docker stats if no Prometheus metrics */}
                  {!container.metrics && container.cpu_usage && (
                    <div className="text-xs font-mono bg-gray-100 dark:bg-gray-600 dark:text-gray-200 px-2 py-1 rounded">
                      CPU: {container.cpu_usage}
                    </div>
                  )}
                  {!container.metrics && container.memory_usage && (
                    <div className="text-xs font-mono bg-gray-100 dark:bg-gray-600 dark:text-gray-200 px-2 py-1 rounded">
                      MEM: {container.memory_usage}
                    </div>
                  )}

                  {/* Per-Container Control Buttons */}
                  {getContainerStatus(container.status) === 'error' && onStartContainer && (
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        onStartContainer(container.name);
                      }}
                      disabled={containerLoading === container.name}
                      className={clsx(
                        'flex items-center space-x-1 px-2 py-1 text-xs rounded border transition-colors',
                        containerLoading === container.name
                          ? 'border-gray-300 dark:border-gray-600 text-gray-400 dark:text-gray-500 cursor-not-allowed'
                          : 'border-green-300 dark:border-green-600 text-green-700 dark:text-green-300 hover:bg-green-50 dark:hover:bg-green-900/20'
                      )}
                      title={`Start ${container.name}`}
                    >
                      {containerLoading === container.name ? (
                        <Loader2 className="w-3 h-3 animate-spin" />
                      ) : (
                        <Play className="w-3 h-3" />
                      )}
                      <span>Start</span>
                    </button>
                  )}

                  {getContainerStatus(container.status) === 'healthy' && onStopContainer && (
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        onStopContainer(container.name);
                      }}
                      disabled={containerLoading === container.name}
                      className={clsx(
                        'flex items-center space-x-1 px-2 py-1 text-xs rounded border transition-colors',
                        containerLoading === container.name
                          ? 'border-gray-300 dark:border-gray-600 text-gray-400 dark:text-gray-500 cursor-not-allowed'
                          : 'border-red-300 dark:border-red-600 text-red-700 dark:text-red-300 hover:bg-red-50 dark:hover:bg-red-900/20'
                      )}
                      title={`Stop ${container.name}`}
                    >
                      {containerLoading === container.name ? (
                        <Loader2 className="w-3 h-3 animate-spin" />
                      ) : (
                        <Square className="w-3 h-3" />
                      )}
                      <span>Stop</span>
                    </button>
                  )}

                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      onViewLogs?.(container.name);
                    }}
                    className="p-1 rounded hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors"
                    title="View logs"
                  >
                    <Eye className="w-4 h-4 text-gray-600 dark:text-gray-400" />
                  </button>
                </div>
              </div>

              {expandedContainer === container.name && (
                <div className="mt-3 pt-3 border-t border-gray-200 dark:border-gray-600">
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm">
                    <div>
                      <div className="font-medium text-gray-700 dark:text-gray-300 mb-1">Status</div>
                      <div className="text-gray-600 dark:text-gray-400">{container.status}</div>
                    </div>
                    <div>
                      <div className="font-medium text-gray-700 dark:text-gray-300 mb-1">Image</div>
                      <div className="text-gray-600 dark:text-gray-400 font-mono">{container.image}</div>
                    </div>
                    {(() => {
                      const { ports, hasValidPorts } = formatPorts(container.ports);
                      return hasValidPorts && (
                        <div>
                          <div className="font-medium text-gray-700 dark:text-gray-300 mb-1">Ports</div>
                          <div className="text-gray-600 dark:text-gray-400 font-mono">
                            {ports.join(', ')}
                          </div>
                        </div>
                      );
                    })()}
                    <div>
                      <div className="font-medium text-gray-700 dark:text-gray-300 mb-1">Created</div>
                      <div className="text-gray-600 dark:text-gray-400">{container.created}</div>
                    </div>
                  </div>
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}