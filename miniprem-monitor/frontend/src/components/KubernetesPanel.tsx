import React, { useState } from 'react';
import { PodStatus, StatusType } from '../types/monitor';
import { StatusIndicator } from './StatusIndicator';
import { RefreshCw, Eye, Filter } from 'lucide-react';
import clsx from 'clsx';

interface KubernetesPanelProps {
  pods: PodStatus[];
  loading?: boolean;
  onRefresh?: () => void;
  onViewLogs?: (podName: string, namespace: string) => void;
}

export function KubernetesPanel({
  pods,
  loading,
  onRefresh,
  onViewLogs
}: KubernetesPanelProps) {
  const [expandedPod, setExpandedPod] = useState<string | null>(null);
  const [namespaceFilter, setNamespaceFilter] = useState<string>('all');

  const getPodStatus = (status: string, ready: string): StatusType => {
    if (status === 'Running' && ready === '1/1') return 'healthy';
    if (status === 'Pending') return 'warning';
    if (status === 'Failed' || status === 'CrashLoopBackOff') return 'error';
    if (status === 'Succeeded') return 'healthy';
    return 'unknown';
  };

  const getUniqueNamespaces = () => {
    const namespaces = [...new Set(pods.map(pod => pod.namespace))];
    return ['all', ...namespaces.sort()];
  };

  const filteredPods = namespaceFilter === 'all'
    ? pods
    : pods.filter(pod => pod.namespace === namespaceFilter);

  return (
    <div className="card p-6">
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-xl font-bold text-gray-900 dark:text-gray-100 flex items-center">
          <div className="w-1 h-6 bg-gradient-uneeq rounded mr-3"></div>
          Kubernetes Pods
        </h2>
        <div className="flex items-center space-x-2">
          {/* Namespace Filter */}
          <div className="relative">
            <select
              value={namespaceFilter}
              onChange={(e) => setNamespaceFilter(e.target.value)}
              className="appearance-none bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100 border border-gray-300 dark:border-gray-600 rounded px-3 py-1 pr-8 text-sm focus:outline-none focus:ring-2 focus:ring-uneeq-primary focus:border-transparent"
            >
              {getUniqueNamespaces().map(ns => (
                <option key={ns} value={ns}>
                  {ns === 'all' ? 'All Namespaces' : ns}
                </option>
              ))}
            </select>
            <Filter className="absolute right-2 top-1/2 transform -translate-y-1/2 w-3 h-3 text-gray-400 dark:text-gray-500 pointer-events-none" />
          </div>

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
      </div>

      {loading ? (
        <div className="space-y-3" data-testid="pods-loading">
          {Array.from({ length: 3 }).map((_, index) => (
            <div key={index} className="animate-pulse">
              <div className="flex items-center space-x-3 p-3 bg-gray-100 dark:bg-gray-700 rounded">
                <div className="w-3 h-3 bg-gray-300 dark:bg-gray-500 rounded-full"></div>
                <div className="flex-1">
                  <div className="h-4 bg-gray-300 dark:bg-gray-500 rounded w-40 mb-1"></div>
                  <div className="h-3 bg-gray-300 dark:bg-gray-500 rounded w-32"></div>
                </div>
              </div>
            </div>
          ))}
        </div>
      ) : filteredPods.length === 0 ? (
        <div className="text-center py-8 text-gray-500 dark:text-gray-400" data-testid="no-pods">
          <div className="text-4xl mb-2">⎈</div>
          <p>No pods found</p>
          <p className="text-sm">
            {namespaceFilter === 'all'
              ? 'Kubernetes may not be accessible'
              : `No pods in namespace "${namespaceFilter}"`}
          </p>
        </div>
      ) : (
        <div className="space-y-2">
          {filteredPods.map((pod, index) => (
            <div
              key={`${pod.namespace}/${pod.name}` || index}
              data-testid="pod-item"
              data-pod-item={pod.name}
              className={clsx(
                'border rounded-lg p-3 transition-all duration-200',
                expandedPod === `${pod.namespace}/${pod.name}`
                  ? 'border-uneeq-primary bg-blue-50 dark:bg-blue-900/20'
                  : 'border-gray-200 dark:border-gray-600 hover:border-gray-300 dark:hover:border-gray-500'
              )}
            >
              <div
                className="flex items-center justify-between cursor-pointer"
                onClick={() => setExpandedPod(
                  expandedPod === `${pod.namespace}/${pod.name}`
                    ? null
                    : `${pod.namespace}/${pod.name}`
                )}
              >
                <div className="flex items-center space-x-3">
                  <StatusIndicator
                    status={getPodStatus(pod.status, pod.ready)}
                    size="md"
                  />
                  <div>
                    <div className="font-semibold text-gray-900 dark:text-gray-100">
                      {pod.name}
                    </div>
                    <div className="text-sm text-gray-600 dark:text-gray-300">
                      {pod.namespace} • {pod.ready} ready • {pod.age}
                    </div>
                  </div>
                </div>

                <div className="flex items-center space-x-2">
                  <div className="text-xs font-mono bg-gray-100 dark:bg-gray-600 dark:text-gray-200 px-2 py-1 rounded">
                    {pod.status}
                  </div>
                  {pod.restarts > 0 && (
                    <div className="text-xs font-mono bg-status-warning px-2 py-1 rounded text-white">
                      {pod.restarts} restarts
                    </div>
                  )}
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      onViewLogs?.(pod.name, pod.namespace);
                    }}
                    className="p-1 rounded hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors"
                    title="View logs"
                  >
                    <Eye className="w-4 h-4 text-gray-600 dark:text-gray-400" />
                  </button>
                </div>
              </div>

              {expandedPod === `${pod.namespace}/${pod.name}` && (
                <div className="mt-3 pt-3 border-t border-gray-200 dark:border-gray-600">
                  <div className="grid grid-cols-1 md:grid-cols-3 gap-4 text-sm">
                    <div>
                      <div className="font-medium text-gray-700 dark:text-gray-300 mb-1">Status</div>
                      <div className="text-gray-600 dark:text-gray-400">{pod.status}</div>
                    </div>
                    <div>
                      <div className="font-medium text-gray-700 dark:text-gray-300 mb-1">Ready</div>
                      <div className="text-gray-600 dark:text-gray-400">{pod.ready}</div>
                    </div>
                    <div>
                      <div className="font-medium text-gray-700 dark:text-gray-300 mb-1">Restarts</div>
                      <div className="text-gray-600 dark:text-gray-400">{pod.restarts}</div>
                    </div>
                    <div>
                      <div className="font-medium text-gray-700 dark:text-gray-300 mb-1">Age</div>
                      <div className="text-gray-600 dark:text-gray-400">{pod.age}</div>
                    </div>
                    <div>
                      <div className="font-medium text-gray-700 dark:text-gray-300 mb-1">Namespace</div>
                      <div className="text-gray-600 dark:text-gray-400 font-mono">{pod.namespace}</div>
                    </div>
                    {pod.node && (
                      <div>
                        <div className="font-medium text-gray-700 dark:text-gray-300 mb-1">Node</div>
                        <div className="text-gray-600 dark:text-gray-400 font-mono">{pod.node}</div>
                      </div>
                    )}
                  </div>

                  {(pod.cpu_usage || pod.memory_usage) && (
                    <div className="mt-3 pt-3 border-t border-gray-100 dark:border-gray-700">
                      <div className="font-medium text-gray-700 dark:text-gray-300 mb-2">Resource Usage</div>
                      <div className="flex space-x-4">
                        {pod.cpu_usage && (
                          <div className="text-xs font-mono bg-gray-100 dark:bg-gray-600 dark:text-gray-200 px-2 py-1 rounded">
                            CPU: {pod.cpu_usage}
                          </div>
                        )}
                        {pod.memory_usage && (
                          <div className="text-xs font-mono bg-gray-100 dark:bg-gray-600 dark:text-gray-200 px-2 py-1 rounded">
                            MEM: {pod.memory_usage}
                          </div>
                        )}
                      </div>
                    </div>
                  )}
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}