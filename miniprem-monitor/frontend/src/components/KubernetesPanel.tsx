import React, { useState, useCallback, useMemo } from 'react';
import { PodStatus, StatusType, SystemInfo } from '../types/monitor';
import { StatusIndicator } from './StatusIndicator';
import { ClusterSelector, ClusterInfo } from './ClusterSelector';
import { RegionSelector } from './RegionSelector';
import { RefreshCw, Eye, Filter, Play, Square, Loader2 } from 'lucide-react';
import clsx from 'clsx';

export interface ClusterStatus {
  name: string;
  context: string;
  namespace: string;
  environment: 'local' | 'eks' | 'gke' | 'aks';
  region?: string;
  status: 'connected' | 'connecting' | 'error';
  lastSync?: string;
  latency?: number;
  podCount?: number;
  nodeCount?: number;
  connectionError?: string;
}

// Define pod status filter types
type PodStatusFilter = 'all' | 'running' | 'pending' | 'failed' | 'succeeded' | 'unknown';

interface KubernetesPanelProps {
  pods: PodStatus[];
  clusterStatus?: ClusterStatus | null;
  availableClusters?: ClusterInfo[];
  currentCluster?: ClusterInfo | null;
  currentRegion?: string;
  availableRegions?: string[];
  availableContexts?: Array<{ name: string; current: boolean; cluster?: string; user?: string; namespace?: string }>;
  currentContext?: string;
  loading?: boolean;
  error?: string;
  onRefresh?: () => void;
  onViewLogs?: (podName: string, namespace: string) => void;
  onOpenSettings?: () => void;
  onClusterSelect?: (cluster: ClusterInfo) => void;
  onContextSwitch?: (context: string) => void;
  onRegionSelect?: (region: string) => void;
  onStartService?: (region: string) => void;
  onStopService?: (region: string) => void;
  serviceLoading?: boolean;
  systemInfo?: SystemInfo | null;
}

export function KubernetesPanel({
  pods,
  clusterStatus,
  availableClusters = [],
  currentCluster = null,
  currentRegion = 'us-east-1',
  availableRegions = ['us-east-1', 'us-east-2'],
  availableContexts = [],
  currentContext,
  loading,
  error,
  onRefresh,
  onViewLogs,
  onOpenSettings,
  onClusterSelect,
  onContextSwitch,
  onRegionSelect,
  onStartService,
  onStopService,
  serviceLoading = false,
  systemInfo = null
}: KubernetesPanelProps) {
  const [expandedPod, setExpandedPod] = useState<string | null>(null);
  const [namespaceFilter, setNamespaceFilter] = useState<string>('all');
  const [statusFilter, setStatusFilter] = useState<PodStatusFilter>('all');

  const getPodStatus = (status: string, ready: string): StatusType => {
    if (status === 'Running' && ready === '1/1') return 'healthy';
    if (status === 'Pending') return 'warning';
    if (status === 'Failed' || status === 'CrashLoopBackOff') return 'error';
    if (status === 'Succeeded') return 'healthy';
    return 'unknown';
  };

  const mapStatusToFilter = (status: string): PodStatusFilter => {
    const normalizedStatus = status.toLowerCase();
    if (normalizedStatus === 'running') return 'running';
    if (normalizedStatus === 'pending') return 'pending';
    if (normalizedStatus === 'failed' || normalizedStatus === 'crashloopbackoff') return 'failed';
    if (normalizedStatus === 'succeeded') return 'succeeded';
    return 'unknown';
  };

  const getUniqueNamespaces = () => {
    const namespaces = Array.from(new Set(pods.map(pod => pod.namespace)));
    // If no pods available, provide common default namespaces
    if (namespaces.length === 0) {
      return ['all', 'default', 'kube-system', 'uneeq-renderer'];
    }
    return ['all', ...namespaces.sort()];
  };

  // Filter pods based on namespace and status
  const filteredPods = useMemo(() => {
    let filtered = namespaceFilter === 'all'
      ? pods
      : pods.filter(pod => pod.namespace === namespaceFilter);

    if (statusFilter === 'all') {
      return filtered;
    }

    return filtered.filter(pod => {
      const podStatusFilter = mapStatusToFilter(pod.status);
      return podStatusFilter === statusFilter;
    });
  }, [pods, namespaceFilter, statusFilter]);

  // Calculate counts for each pod status filter
  const statusFilterCounts = useMemo(() => {
    const namespacePods = namespaceFilter === 'all'
      ? pods
      : pods.filter(pod => pod.namespace === namespaceFilter);

    const all = namespacePods.length;
    const running = namespacePods.filter(p => mapStatusToFilter(p.status) === 'running').length;
    const pending = namespacePods.filter(p => mapStatusToFilter(p.status) === 'pending').length;
    const failed = namespacePods.filter(p => mapStatusToFilter(p.status) === 'failed').length;
    const succeeded = namespacePods.filter(p => mapStatusToFilter(p.status) === 'succeeded').length;
    const unknown = namespacePods.filter(p => mapStatusToFilter(p.status) === 'unknown').length;

    return { all, running, pending, failed, succeeded, unknown };
  }, [pods, namespaceFilter]);

  const getClusterStatusIndicator = (status?: ClusterStatus) => {
    if (!status) return 'unknown';
    switch (status.status) {
      case 'connected': return 'healthy';
      case 'connecting': return 'warning';
      case 'error': return 'error';
      default: return 'unknown';
    }
  };

  const formatEnvironmentName = (environment?: string) => {
    if (!environment) return 'Unknown';
    switch (environment) {
      case 'eks': return 'EKS';
      case 'gke': return 'GKE';
      case 'aks': return 'AKS';
      case 'local': return 'Local';
      default: return environment.toUpperCase();
    }
  };

  return (
    <div className="card p-6" data-testid="kubernetes-panel">
      {/* Title Row */}
      <div className="mb-4">
        <h2 className="text-xl font-bold text-gray-900 dark:text-gray-100 flex items-center mb-3">
          <div className="w-1 h-6 bg-gradient-uneeq rounded mr-3"></div>
          Kubernetes Pods
          {systemInfo && systemInfo.kubernetes && (
            <div
              className={clsx(
                'ml-3 w-3 h-3 rounded-full',
                systemInfo.kubernetes.available ? 'bg-status-healthy' : 'bg-status-error'
              )}
              title={systemInfo.kubernetes.available ? 'Available' : `Unavailable: ${systemInfo.kubernetes.error || 'Unknown error'}`}
            />
          )}
        </h2>

        {/* Controls - Responsive Layout */}
        <div className="space-y-3">
          {/* First Control Row - Wide: all on one row, Narrow: split */}
          <div className="lg:flex lg:items-center lg:justify-between">
            <div className="flex flex-wrap items-center gap-3 lg:gap-4">
              {/* Region Selector */}
              {onRegionSelect && (
                <div className="flex items-center space-x-2">
                  <span className="text-sm text-gray-600 dark:text-gray-300 font-medium">Region:</span>
                  <RegionSelector
                    currentRegion={currentRegion}
                    availableRegions={availableRegions}
                    onRegionSelect={onRegionSelect}
                    loading={loading}
                    compact={true}
                  />
                </div>
              )}

              {/* Cluster Selector */}
              {onClusterSelect && onOpenSettings && (
                <div className="flex items-center space-x-2">
                  <span className="text-sm text-gray-600 dark:text-gray-300 font-medium">EKS:</span>
                  <div className="max-w-[300px]">
                    <ClusterSelector
                      currentCluster={currentCluster}
                      availableClusters={availableClusters}
                      onClusterSelect={onClusterSelect}
                      onOpenSettings={onOpenSettings}
                      loading={loading}
                      compact={true}
                    />
                  </div>
                </div>
              )}

              {/* Context Selector */}
              {onContextSwitch && availableContexts.length > 0 && (
                <div className="flex items-center space-x-2">
                  <span className="text-sm text-gray-600 dark:text-gray-300 font-medium">Context:</span>
                  <select
                    value={currentContext || ''}
                    onChange={(e) => onContextSwitch(e.target.value)}
                    disabled={loading}
                    className={clsx(
                      'px-2 py-1 text-sm rounded-md border transition-colors max-w-[200px] truncate',
                      'bg-white dark:bg-gray-800',
                      'border-gray-300 dark:border-gray-600',
                      'text-gray-900 dark:text-gray-100',
                      loading
                        ? 'cursor-not-allowed opacity-50'
                        : 'hover:border-blue-400 dark:hover:border-blue-500 focus:border-blue-500 dark:focus:border-blue-400 focus:ring-1 focus:ring-blue-500 dark:focus:ring-blue-400'
                    )}
                    title={currentContext ? `Current context: ${currentContext}` : 'Select kubectl context'}
                  >
                    {availableContexts.map((context) => (
                      <option key={context.name} value={context.name}>
                        {context.name.length > 40
                          ? `...${context.name.slice(-37)}`
                          : context.name}
                        {context.current ? ' (current)' : ''}
                      </option>
                    ))}
                  </select>
                </div>
              )}

              {/* Namespace Filter - Hidden on narrow, shown on wide */}
              <div className="hidden lg:flex items-center space-x-2">
                <span className="text-sm text-gray-600 dark:text-gray-300 font-medium">NS:</span>
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
              </div>
            </div>

            {/* Refresh button - Always shown on wide screens */}
            <div className="hidden lg:block">
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

          {/* Second Control Row - Only shown on narrow screens */}
          <div className="lg:hidden flex flex-wrap items-center justify-between gap-3">
            <div className="flex flex-wrap items-center gap-3">
              {/* Service Control Buttons - Shown on narrow */}
              {(onStartService || onStopService) && currentRegion && (
                <div className="flex items-center space-x-2">
                  <span className="text-sm text-gray-600 dark:text-gray-300 font-medium">Service:</span>
                  <div className="flex items-center space-x-1">
                    {onStartService && (
                      <button
                        onClick={() => onStartService(currentRegion)}
                        disabled={serviceLoading}
                        className={clsx(
                          'flex items-center space-x-1 px-2 py-1 text-sm rounded-md border transition-colors',
                          serviceLoading
                            ? 'border-gray-300 dark:border-gray-600 text-gray-400 dark:text-gray-500 cursor-not-allowed'
                            : 'border-green-300 dark:border-green-600 text-green-700 dark:text-green-300 hover:bg-green-50 dark:hover:bg-green-900/20'
                        )}
                        title={`Start Kubernetes services in ${currentRegion}`}
                      >
                        {serviceLoading ? (
                          <Loader2 className="w-3 h-3 animate-spin" />
                        ) : (
                          <Play className="w-3 h-3" />
                        )}
                        <span>Start</span>
                      </button>
                    )}
                    {onStopService && (
                      <button
                        onClick={() => onStopService(currentRegion)}
                        disabled={serviceLoading}
                        className={clsx(
                          'flex items-center space-x-1 px-2 py-1 text-sm rounded-md border transition-colors',
                          serviceLoading
                            ? 'border-gray-300 dark:border-gray-600 text-gray-400 dark:text-gray-500 cursor-not-allowed'
                            : 'border-red-300 dark:border-red-600 text-red-700 dark:text-red-300 hover:bg-red-50 dark:hover:bg-red-900/20'
                        )}
                        title={`Stop Kubernetes services in ${currentRegion}`}
                      >
                        {serviceLoading ? (
                          <Loader2 className="w-3 h-3 animate-spin" />
                        ) : (
                          <Square className="w-3 h-3" />
                        )}
                        <span>Stop</span>
                      </button>
                    )}
                  </div>
                </div>
              )}

              {/* Namespace Filter - Shown on narrow */}
              <div className="flex items-center space-x-2">
                <span className="text-sm text-gray-600 dark:text-gray-300 font-medium">NS:</span>
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
              </div>
            </div>

            {/* Refresh button - Shown on narrow screens */}
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

          {/* Pod Status Filter - Always shown as separate row */}
          <div className="flex items-center justify-between">
            <div
              className="inline-flex bg-gray-100 dark:bg-gray-700 rounded-lg p-1 flex-wrap gap-1"
              role="tablist"
              aria-label="Pod status filter"
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
                data-testid="pod-filter-all"
              >
                All
                {statusFilterCounts.all > 0 && (
                  <span className={clsx(
                    'ml-2 px-2 py-0.5 rounded-full text-xs',
                    statusFilter === 'all'
                      ? 'bg-gray-100 dark:bg-gray-500 text-gray-600 dark:text-gray-300'
                      : 'bg-gray-200 dark:bg-gray-600 text-gray-500 dark:text-gray-400'
                  )}>
                    {statusFilterCounts.all}
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
                data-testid="pod-filter-running"
              >
                <div className="flex items-center">
                  <div className="w-2 h-2 bg-status-healthy rounded-full mr-1.5"></div>
                  Running
                  {statusFilterCounts.running > 0 && (
                    <span className={clsx(
                      'ml-2 px-2 py-0.5 rounded-full text-xs',
                      statusFilter === 'running'
                        ? 'bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-300'
                        : 'bg-gray-200 dark:bg-gray-600 text-gray-500 dark:text-gray-400'
                    )}>
                      {statusFilterCounts.running}
                    </span>
                  )}
                </div>
              </button>

              <button
                onClick={() => setStatusFilter('pending')}
                className={clsx(
                  'px-3 py-1.5 text-sm font-medium rounded-md transition-all duration-200 focus:outline-none focus:ring-2 focus:ring-uneeq-primary focus:ring-offset-2 focus:ring-offset-white dark:focus:ring-offset-gray-800',
                  statusFilter === 'pending'
                    ? 'bg-white dark:bg-gray-600 text-gray-900 dark:text-gray-100 shadow-sm'
                    : 'text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-200'
                )}
                role="tab"
                aria-selected={statusFilter === 'pending'}
                data-testid="pod-filter-pending"
              >
                <div className="flex items-center">
                  <div className="w-2 h-2 bg-status-warning rounded-full mr-1.5"></div>
                  Pending
                  {statusFilterCounts.pending > 0 && (
                    <span className={clsx(
                      'ml-2 px-2 py-0.5 rounded-full text-xs',
                      statusFilter === 'pending'
                        ? 'bg-yellow-100 dark:bg-yellow-900/30 text-yellow-700 dark:text-yellow-300'
                        : 'bg-gray-200 dark:bg-gray-600 text-gray-500 dark:text-gray-400'
                    )}>
                      {statusFilterCounts.pending}
                    </span>
                  )}
                </div>
              </button>

              <button
                onClick={() => setStatusFilter('failed')}
                className={clsx(
                  'px-3 py-1.5 text-sm font-medium rounded-md transition-all duration-200 focus:outline-none focus:ring-2 focus:ring-uneeq-primary focus:ring-offset-2 focus:ring-offset-white dark:focus:ring-offset-gray-800',
                  statusFilter === 'failed'
                    ? 'bg-white dark:bg-gray-600 text-gray-900 dark:text-gray-100 shadow-sm'
                    : 'text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-200'
                )}
                role="tab"
                aria-selected={statusFilter === 'failed'}
                data-testid="pod-filter-failed"
              >
                <div className="flex items-center">
                  <div className="w-2 h-2 bg-status-error rounded-full mr-1.5"></div>
                  Failed
                  {statusFilterCounts.failed > 0 && (
                    <span className={clsx(
                      'ml-2 px-2 py-0.5 rounded-full text-xs',
                      statusFilter === 'failed'
                        ? 'bg-red-100 dark:bg-red-900/30 text-red-700 dark:text-red-300'
                        : 'bg-gray-200 dark:bg-gray-600 text-gray-500 dark:text-gray-400'
                    )}>
                      {statusFilterCounts.failed}
                    </span>
                  )}
                </div>
              </button>

              <button
                onClick={() => setStatusFilter('succeeded')}
                className={clsx(
                  'px-3 py-1.5 text-sm font-medium rounded-md transition-all duration-200 focus:outline-none focus:ring-2 focus:ring-uneeq-primary focus:ring-offset-2 focus:ring-offset-white dark:focus:ring-offset-gray-800',
                  statusFilter === 'succeeded'
                    ? 'bg-white dark:bg-gray-600 text-gray-900 dark:text-gray-100 shadow-sm'
                    : 'text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-200'
                )}
                role="tab"
                aria-selected={statusFilter === 'succeeded'}
                data-testid="pod-filter-succeeded"
              >
                <div className="flex items-center">
                  <div className="w-2 h-2 bg-blue-500 rounded-full mr-1.5"></div>
                  Succeeded
                  {statusFilterCounts.succeeded > 0 && (
                    <span className={clsx(
                      'ml-2 px-2 py-0.5 rounded-full text-xs',
                      statusFilter === 'succeeded'
                        ? 'bg-blue-100 dark:bg-blue-900/30 text-blue-700 dark:text-blue-300'
                        : 'bg-gray-200 dark:bg-gray-600 text-gray-500 dark:text-gray-400'
                    )}>
                      {statusFilterCounts.succeeded}
                    </span>
                  )}
                </div>
              </button>

              {/* Only show Unknown filter if there are unknown pods */}
              {statusFilterCounts.unknown > 0 && (
                <button
                  onClick={() => setStatusFilter('unknown')}
                  className={clsx(
                    'px-3 py-1.5 text-sm font-medium rounded-md transition-all duration-200 focus:outline-none focus:ring-2 focus:ring-uneeq-primary focus:ring-offset-2 focus:ring-offset-white dark:focus:ring-offset-gray-800',
                    statusFilter === 'unknown'
                      ? 'bg-white dark:bg-gray-600 text-gray-900 dark:text-gray-100 shadow-sm'
                      : 'text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-200'
                  )}
                  role="tab"
                  aria-selected={statusFilter === 'unknown'}
                  data-testid="pod-filter-unknown"
                >
                  <div className="flex items-center">
                    <div className="w-2 h-2 bg-gray-400 rounded-full mr-1.5"></div>
                    Unknown
                    <span className={clsx(
                      'ml-2 px-2 py-0.5 rounded-full text-xs',
                      statusFilter === 'unknown'
                        ? 'bg-gray-100 dark:bg-gray-500 text-gray-600 dark:text-gray-300'
                        : 'bg-gray-200 dark:bg-gray-600 text-gray-500 dark:text-gray-400'
                    )}>
                      {statusFilterCounts.unknown}
                    </span>
                  </div>
                </button>
              )}
            </div>

            {/* Results count */}
            <div className="text-sm text-gray-500 dark:text-gray-400">
              {loading ? 'Loading...' : `${filteredPods.length} pod${filteredPods.length !== 1 ? 's' : ''}`}
            </div>
          </div>
        </div>
      </div>

      {/* Cluster Status Bar */}
      {clusterStatus && (
        <div className="mb-4 p-4 bg-surface-secondary border border-surface rounded-lg">
          <div className="flex items-center justify-between">
            <div className="flex items-center space-x-3">
              <StatusIndicator
                status={getClusterStatusIndicator(clusterStatus)}
                size="md"
              />
              <div>
                <div className="flex items-center space-x-2">
                  <span className="font-semibold text-primary">
                    {formatEnvironmentName(clusterStatus.environment)} {clusterStatus.name}
                  </span>
                  {clusterStatus.region && (
                    <span className="text-xs text-muted px-2 py-1 bg-surface rounded">
                      {clusterStatus.region}
                    </span>
                  )}
                </div>
                <div className="text-sm text-secondary mt-1">
                  Context: {clusterStatus.context && clusterStatus.context.length > 40
                    ? `${clusterStatus.context.substring(0, 37)}...`
                    : (clusterStatus.context || 'Unknown')}
                </div>
                <div className="text-sm text-secondary">
                  Namespace: {clusterStatus.namespace}
                  {clusterStatus.podCount && (
                    <span className="ml-2">• {clusterStatus.podCount} pods</span>
                  )}
                  {clusterStatus.nodeCount && (
                    <span className="ml-2">• {clusterStatus.nodeCount} nodes</span>
                  )}
                </div>
              </div>
            </div>

            <div className="text-right">
              {clusterStatus.status === 'connected' && clusterStatus.lastSync && (
                <div className="text-xs text-secondary">
                  Last sync: {new Date(clusterStatus.lastSync).toLocaleTimeString()}
                </div>
              )}
              {clusterStatus.latency && (
                <div className="text-xs text-secondary">
                  Latency: {clusterStatus.latency}ms
                </div>
              )}
              {clusterStatus.status === 'error' && clusterStatus.connectionError && (
                <div className="text-xs text-status-error">
                  {clusterStatus.connectionError}
                </div>
              )}
            </div>
          </div>
        </div>
      )}

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
        <div className="text-center py-8" data-testid="no-pods">
          {error ? (
            <div className="text-red-600 dark:text-red-400">
              <div className="text-4xl mb-2">❌</div>
              <p className="font-medium">Kubernetes Connection Error</p>
              <div className="mt-2 p-3 bg-red-50 dark:bg-red-900/20 rounded-lg border border-red-200 dark:border-red-800">
                <p className="text-sm text-left">{error}</p>
              </div>
            </div>
          ) : (
            <div className="text-gray-500 dark:text-gray-400">
              <div className="text-4xl mb-2">⎈</div>
              <p>No pods found</p>
              <p className="text-sm">
                {statusFilter === 'all' && namespaceFilter === 'all'
                  ? 'Kubernetes may not be accessible'
                  : statusFilter !== 'all' && namespaceFilter === 'all'
                  ? `No pods with status "${statusFilter}"`
                  : statusFilter === 'all' && namespaceFilter !== 'all'
                  ? `No pods in namespace "${namespaceFilter}"`
                  : `No pods with status "${statusFilter}" in namespace "${namespaceFilter}"`}
              </p>
            </div>
          )}
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