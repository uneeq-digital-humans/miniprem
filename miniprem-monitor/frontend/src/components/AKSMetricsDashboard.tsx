import React, { useEffect, useState, useCallback } from 'react';
import clsx from 'clsx';
import {
  Activity,
  AlertTriangle,
  Box,
  DollarSign,
  HardDrive,
  Server,
  TrendingUp,
  Loader2,
} from 'lucide-react';
import CloudProviderBadge from './CloudProviderBadge';
import {
  AKSMetricsResponse,
  AKSNodePoolMetrics,
  getHealthStatus,
  getHealthColorClasses,
  formatCurrency,
  isHighCost,
} from '../types/aks-metrics';

interface AKSMetricsDashboardProps {
  provider: string;
  clusterContext?: string;
}

const AKSMetricsDashboard: React.FC<AKSMetricsDashboardProps> = ({
  provider,
  clusterContext,
}) => {
  const [metrics, setMetrics] = useState<AKSMetricsResponse | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null);

  // Fetch AKS metrics from backend
  const fetchMetrics = useCallback(async () => {
    if (provider !== 'aks') {
      setMetrics(null);
      setError(null);
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const response = await fetch('/api/kubernetes/metrics/aks');
      const data = await response.json();

      if (response.ok && data.success) {
        setMetrics(data);
        setLastUpdated(new Date());
      } else {
        setError(data.error || 'Failed to fetch AKS metrics');
      }
    } catch (err) {
      console.error('Error fetching AKS metrics:', err);
      setError('Network error fetching AKS metrics');
    } finally {
      setLoading(false);
    }
  }, [provider]);

  // Initial fetch and auto-refresh every 30 seconds
  useEffect(() => {
    if (provider === 'aks') {
      fetchMetrics();

      const interval = setInterval(fetchMetrics, 30000);
      return () => clearInterval(interval);
    }
  }, [provider, clusterContext, fetchMetrics]);

  // Don't render if not AKS
  if (provider !== 'aks') return null;

  // Loading skeleton
  if (loading && !metrics) {
    return (
      <div className="bg-white dark:bg-gray-800 rounded-lg p-6 border border-gray-200 dark:border-gray-700 mt-6">
        <div className="flex items-center space-x-3 mb-6">
          <Loader2 className="w-6 h-6 text-blue-500 animate-spin" />
          <h2 className="text-xl font-semibold text-gray-900 dark:text-gray-100">
            Loading AKS Metrics...
          </h2>
        </div>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {[1, 2, 3, 4, 5, 6].map((i) => (
            <div
              key={i}
              className="h-32 bg-gray-100 dark:bg-gray-700 rounded-lg animate-pulse"
            />
          ))}
        </div>
      </div>
    );
  }

  // Error state
  if (error) {
    return (
      <div className="bg-red-50 dark:bg-red-900/20 rounded-lg p-6 border border-red-200 dark:border-red-800 mt-6">
        <div className="flex items-center space-x-3 mb-2">
          <AlertTriangle className="w-6 h-6 text-red-600 dark:text-red-400" />
          <h2 className="text-xl font-semibold text-red-700 dark:text-red-300">
            AKS Metrics Error
          </h2>
        </div>
        <p className="text-red-600 dark:text-red-400">{error}</p>
        <button
          onClick={fetchMetrics}
          className="mt-4 px-4 py-2 bg-red-600 hover:bg-red-700 text-white rounded-lg transition-colors"
        >
          Retry
        </button>
      </div>
    );
  }

  // No metrics available
  if (!metrics) return null;

  const {
    cluster_overview,
    node_pools,
    cluster_totals,
    cost_estimate,
  } = metrics;

  return (
    <div className="bg-white dark:bg-gray-800 rounded-lg p-6 border border-gray-200 dark:border-gray-700 mt-6">
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center space-x-3">
          <Activity className="w-6 h-6 text-blue-500" />
          <h2 className="text-xl font-semibold text-gray-900 dark:text-gray-100">
            Azure AKS Metrics
          </h2>
          {loading && (
            <Loader2 className="w-4 h-4 text-gray-400 animate-spin" />
          )}
        </div>
        {lastUpdated && (
          <span className="text-xs text-gray-500 dark:text-gray-400">
            Last updated: {lastUpdated.toLocaleTimeString()}
          </span>
        )}
      </div>

      {/* Cluster Overview Card */}
      <div className="mb-6 p-4 rounded-lg border-2 border-blue-500/30 bg-gradient-to-br from-blue-50 to-purple-50 dark:from-blue-900/20 dark:to-purple-900/20">
        <div className="flex items-start justify-between mb-3">
          <div>
            <h3 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-1">
              {cluster_overview.cluster_name}
            </h3>
            <p className="text-sm text-gray-600 dark:text-gray-400">
              {cluster_overview.resource_group} • {cluster_overview.location}
            </p>
          </div>
          <CloudProviderBadge provider="aks" />
        </div>
        <div className="flex items-center space-x-4 text-sm">
          <div className="flex items-center space-x-1.5">
            <Server className="w-4 h-4 text-blue-500" />
            <span className="text-gray-700 dark:text-gray-300">
              K8s v{cluster_overview.kubernetes_version}
            </span>
          </div>
          {cluster_overview.fqdn && (
            <div className="text-gray-500 dark:text-gray-400 truncate max-w-xs">
              {cluster_overview.fqdn}
            </div>
          )}
        </div>
      </div>

      {/* Node Pools Grid */}
      <div className="mb-6">
        <h3 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-4 flex items-center">
          <HardDrive className="w-5 h-5 mr-2 text-purple-500" />
          Node Pools
        </h3>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {node_pools.map((pool) => {
            const healthStatus = getHealthStatus(pool.health.percentage);
            const colorClasses = getHealthColorClasses(healthStatus);

            return (
              <div
                key={pool.name}
                className={clsx(
                  'p-4 rounded-lg border-2 transition-all hover:shadow-md',
                  'bg-gradient-to-br from-gray-50 to-gray-100',
                  'dark:from-gray-800 dark:to-gray-750',
                  colorClasses.border
                )}
              >
                {/* Pool Header */}
                <div className="flex items-start justify-between mb-3">
                  <div className="flex-1">
                    <h4 className="font-semibold text-gray-900 dark:text-gray-100 mb-1">
                      {pool.name}
                    </h4>
                    <span className="text-xs bg-gray-200 dark:bg-gray-700 text-gray-700 dark:text-gray-300 px-2 py-1 rounded">
                      {pool.vm_size}
                    </span>
                  </div>
                  {pool.auto_scaling_enabled && (
                    <span className="text-xs bg-blue-500 text-white px-2 py-1 rounded flex items-center space-x-1">
                      <TrendingUp className="w-3 h-3" />
                      <span>Auto-scale</span>
                    </span>
                  )}
                </div>

                {/* Node Counts */}
                <div className="mb-3">
                  <div className="flex items-center justify-between text-sm mb-1">
                    <span className="text-gray-600 dark:text-gray-400">Nodes</span>
                    <span className="font-semibold text-gray-900 dark:text-gray-100">
                      {pool.node_count.current} /{' '}
                      {pool.auto_scaling_enabled
                        ? `${pool.node_count.min}-${pool.node_count.max}`
                        : pool.node_count.max}
                    </span>
                  </div>

                  {/* Health Bar */}
                  <div className="w-full bg-gray-200 dark:bg-gray-700 rounded-full h-2">
                    <div
                      className={clsx(
                        'h-2 rounded-full transition-all',
                        colorClasses.bg
                      )}
                      style={{ width: `${pool.health.percentage}%` }}
                    />
                  </div>
                </div>

                {/* Health Status */}
                <div className="flex items-center justify-between text-sm">
                  <div className="flex items-center space-x-1.5">
                    <div
                      className={clsx(
                        'w-2 h-2 rounded-full',
                        healthStatus === 'healthy' && 'bg-green-500',
                        healthStatus === 'warning' && 'bg-yellow-500 animate-pulse',
                        healthStatus === 'error' && 'bg-red-500 animate-pulse'
                      )}
                    />
                    <span className={colorClasses.text}>
                      {pool.health.ready_nodes} ready
                    </span>
                  </div>
                  <span className="text-xs text-gray-500 dark:text-gray-400 capitalize">
                    {pool.provisioning_state.toLowerCase()}
                  </span>
                </div>
              </div>
            );
          })}
        </div>
      </div>

      {/* Cluster Totals Grid */}
      <div className="mb-6">
        <h3 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-4 flex items-center">
          <Box className="w-5 h-5 mr-2 text-green-500" />
          Cluster Totals
        </h3>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          {/* Total Nodes */}
          <div className="p-4 rounded-lg bg-gray-50 dark:bg-gray-700/50 border border-gray-200 dark:border-gray-600">
            <div className="flex items-center mb-2">
              <HardDrive className="w-4 h-4 mr-1.5 text-purple-500" />
              <span className="text-xs text-gray-600 dark:text-gray-400 font-medium">
                Total Nodes
              </span>
            </div>
            <div className="text-2xl font-bold text-gray-900 dark:text-gray-100">
              {cluster_totals.total_nodes}
            </div>
            <div className="mt-1 text-xs">
              <span className="text-green-600 dark:text-green-400 font-medium">
                {cluster_totals.ready_nodes} ready
              </span>
              {cluster_totals.not_ready_nodes > 0 && (
                <span className="text-red-600 dark:text-red-400 ml-2">
                  {cluster_totals.not_ready_nodes} not ready
                </span>
              )}
            </div>
            <div className="mt-2 w-full bg-gray-200 dark:bg-gray-600 rounded-full h-1.5">
              <div
                className={clsx(
                  'h-1.5 rounded-full transition-all',
                  getHealthColorClasses(
                    getHealthStatus(
                      (cluster_totals.ready_nodes / cluster_totals.total_nodes) * 100
                    )
                  ).bg
                )}
                style={{
                  width: `${(cluster_totals.ready_nodes / cluster_totals.total_nodes) * 100}%`,
                }}
              />
            </div>
          </div>

          {/* Total Pods */}
          <div className="p-4 rounded-lg bg-gray-50 dark:bg-gray-700/50 border border-gray-200 dark:border-gray-600">
            <div className="flex items-center mb-2">
              <Box className="w-4 h-4 mr-1.5 text-blue-500" />
              <span className="text-xs text-gray-600 dark:text-gray-400 font-medium">
                Total Pods
              </span>
            </div>
            <div className="text-2xl font-bold text-gray-900 dark:text-gray-100">
              {cluster_totals.total_pods}
            </div>
            <div className="mt-1 text-xs">
              <span className="text-green-600 dark:text-green-400 font-medium">
                {cluster_totals.running_pods} running
              </span>
            </div>
            <div className="mt-2 w-full bg-gray-200 dark:bg-gray-600 rounded-full h-1.5">
              <div
                className={clsx(
                  'h-1.5 rounded-full transition-all',
                  getHealthColorClasses(
                    getHealthStatus(
                      (cluster_totals.running_pods / cluster_totals.total_pods) * 100
                    )
                  ).bg
                )}
                style={{
                  width: `${(cluster_totals.running_pods / cluster_totals.total_pods) * 100}%`,
                }}
              />
            </div>
          </div>

          {/* Pending Pods */}
          <div className="p-4 rounded-lg bg-gray-50 dark:bg-gray-700/50 border border-gray-200 dark:border-gray-600">
            <div className="flex items-center mb-2">
              <Loader2
                className={clsx(
                  'w-4 h-4 mr-1.5 text-yellow-500',
                  cluster_totals.pending_pods > 0 && 'animate-spin'
                )}
              />
              <span className="text-xs text-gray-600 dark:text-gray-400 font-medium">
                Pending
              </span>
            </div>
            <div
              className={clsx(
                'text-2xl font-bold',
                cluster_totals.pending_pods > 0
                  ? 'text-yellow-600 dark:text-yellow-400'
                  : 'text-gray-900 dark:text-gray-100'
              )}
            >
              {cluster_totals.pending_pods}
            </div>
            <div className="mt-1 text-xs text-gray-500 dark:text-gray-400">
              {cluster_totals.pending_pods > 0 ? 'Starting up' : 'None pending'}
            </div>
          </div>

          {/* Failed Pods */}
          <div className="p-4 rounded-lg bg-gray-50 dark:bg-gray-700/50 border border-gray-200 dark:border-gray-600">
            <div className="flex items-center mb-2">
              <AlertTriangle className="w-4 h-4 mr-1.5 text-red-500" />
              <span className="text-xs text-gray-600 dark:text-gray-400 font-medium">
                Failed
              </span>
            </div>
            <div
              className={clsx(
                'text-2xl font-bold',
                cluster_totals.failed_pods > 0
                  ? 'text-red-600 dark:text-red-400'
                  : 'text-gray-900 dark:text-gray-100'
              )}
            >
              {cluster_totals.failed_pods}
            </div>
            <div className="mt-1 flex items-center">
              <div
                className={clsx(
                  'w-2 h-2 rounded-full',
                  cluster_totals.failed_pods > 0
                    ? 'bg-red-500 animate-pulse'
                    : 'bg-green-500'
                )}
              />
              <span className="ml-2 text-xs text-gray-600 dark:text-gray-400">
                {cluster_totals.failed_pods > 0 ? 'Issues detected' : 'All healthy'}
              </span>
            </div>
          </div>
        </div>

        {/* Namespaces */}
        <div className="mt-4 p-3 rounded-lg bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800">
          <div className="flex items-center text-sm">
            <Server className="w-4 h-4 mr-2 text-blue-500" />
            <span className="text-gray-700 dark:text-gray-300">
              <span className="font-semibold">{cluster_totals.namespace_count}</span>{' '}
              namespaces in cluster
            </span>
          </div>
        </div>
      </div>

      {/* Cost Estimate Card */}
      <div className="p-4 rounded-lg border-2 border-green-500/30 bg-gradient-to-br from-green-50 to-emerald-50 dark:from-green-900/20 dark:to-emerald-900/20">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-semibold text-gray-900 dark:text-gray-100 flex items-center">
            <DollarSign className="w-5 h-5 mr-2 text-green-600" />
            Estimated Cost
          </h3>
          {isHighCost(cost_estimate.monthly) && (
            <span className="px-2 py-1 bg-orange-500 text-white text-xs rounded flex items-center space-x-1">
              <AlertTriangle className="w-3 h-3" />
              <span>High Cost</span>
            </span>
          )}
        </div>

        {/* Cost Summary */}
        <div className="grid grid-cols-3 gap-4 mb-4">
          <div className="text-center">
            <div className="text-xs text-gray-600 dark:text-gray-400 mb-1">Hourly</div>
            <div className="text-lg font-bold text-green-700 dark:text-green-400">
              {formatCurrency(cost_estimate.hourly, cost_estimate.currency)}
            </div>
          </div>
          <div className="text-center">
            <div className="text-xs text-gray-600 dark:text-gray-400 mb-1">Daily</div>
            <div className="text-lg font-bold text-green-700 dark:text-green-400">
              {formatCurrency(cost_estimate.daily, cost_estimate.currency)}
            </div>
          </div>
          <div className="text-center">
            <div className="text-xs text-gray-600 dark:text-gray-400 mb-1">Monthly</div>
            <div className="text-xl font-bold text-green-700 dark:text-green-400">
              {formatCurrency(cost_estimate.monthly, cost_estimate.currency)}
            </div>
          </div>
        </div>

        {/* Cost Breakdown */}
        <div className="pt-3 border-t border-green-200 dark:border-green-800">
          <h4 className="text-sm font-semibold text-gray-700 dark:text-gray-300 mb-2">
            Cost Breakdown by Node Pool
          </h4>
          <div className="space-y-2">
            {cost_estimate.breakdown.map((item) => (
              <div
                key={item.node_pool}
                className="flex items-center justify-between text-sm"
              >
                <div className="flex items-center space-x-2">
                  <span className="font-medium text-gray-900 dark:text-gray-100">
                    {item.node_pool}
                  </span>
                  <span className="text-xs text-gray-500 dark:text-gray-400">
                    ({item.vm_size} × {item.node_count})
                  </span>
                </div>
                <span className="font-semibold text-green-700 dark:text-green-400">
                  {formatCurrency(item.hourly_cost, cost_estimate.currency)}/hr
                </span>
              </div>
            ))}
          </div>
        </div>

        {/* Disclaimer */}
        <div className="mt-3 pt-3 border-t border-green-200 dark:border-green-800">
          <p className="text-xs text-gray-500 dark:text-gray-400 italic">
            * Estimates based on VM pricing only. Actual costs may include storage, networking, and other Azure services.
          </p>
        </div>
      </div>
    </div>
  );
};

export default AKSMetricsDashboard;
