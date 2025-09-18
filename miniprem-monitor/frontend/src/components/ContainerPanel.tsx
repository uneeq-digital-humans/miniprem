import React, { useState } from 'react';
import { ContainerStatus, StatusType } from '../types/monitor';
import { StatusIndicator } from './StatusIndicator';
import { RefreshCw, Eye, EyeOff } from 'lucide-react';
import clsx from 'clsx';

interface ContainerPanelProps {
  containers: ContainerStatus[];
  loading?: boolean;
  onRefresh?: () => void;
  onViewLogs?: (containerName: string) => void;
}

export function ContainerPanel({
  containers,
  loading,
  onRefresh,
  onViewLogs
}: ContainerPanelProps) {
  const [expandedContainer, setExpandedContainer] = useState<string | null>(null);

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

  return (
    <div className="card p-6">
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-xl font-bold text-gray-900 dark:text-gray-100 flex items-center">
          <div className="w-1 h-6 bg-gradient-uneeq rounded mr-3"></div>
          Docker Containers
        </h2>
        <button
          onClick={onRefresh}
          className={clsx(
            'p-2 rounded-md hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors',
            loading && 'animate-spin'
          )}
          disabled={loading}
        >
          <RefreshCw className="w-5 h-5 text-gray-600 dark:text-gray-400" />
        </button>
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
      ) : (
        <div className="space-y-2">
          {containers.map((container, index) => (
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
                <div className="flex items-center space-x-3">
                  <StatusIndicator
                    status={getContainerStatus(container.status)}
                    size="md"
                  />
                  <div>
                    <div className="font-semibold text-gray-900 dark:text-gray-100">
                      {container.name}
                    </div>
                    <div className="text-sm text-gray-600 dark:text-gray-300">
                      {container.image} • {formatUptime(container.created)}
                    </div>
                  </div>
                </div>

                <div className="flex items-center space-x-2">
                  {container.cpu_usage && (
                    <div className="text-xs font-mono bg-gray-100 dark:bg-gray-600 dark:text-gray-200 px-2 py-1 rounded">
                      CPU: {container.cpu_usage}
                    </div>
                  )}
                  {container.memory_usage && (
                    <div className="text-xs font-mono bg-gray-100 dark:bg-gray-600 dark:text-gray-200 px-2 py-1 rounded">
                      MEM: {container.memory_usage}
                    </div>
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