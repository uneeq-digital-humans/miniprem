import React, { useEffect, useState } from 'react';
import { PodStatus } from '../types/monitor';
import { Activity, Box, Cpu, HardDrive, TrendingUp } from 'lucide-react';
import clsx from 'clsx';

interface ClusterMetricsProps {
  pods: PodStatus[];
  provider: string;
}

interface MetricsSummary {
  totalPods: number;
  runningPods: number;
  failedPods: number;
  pendingPods: number;
  totalNodes: number;
  readyNodes: number;
  podHealthPercentage: number;
  nodeHealthPercentage: number;
}

const ClusterMetrics: React.FC<ClusterMetricsProps> = ({ pods, provider }) => {
  const [metrics, setMetrics] = useState<MetricsSummary | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    const calculateMetrics = () => {
      setLoading(true);

      try {
        // Calculate pod metrics
        const totalPods = pods.length;
        const runningPods = pods.filter(
          (p) => p.status.toLowerCase() === 'running' && p.ready === '1/1'
        ).length;
        const failedPods = pods.filter(
          (p) => p.status.toLowerCase() === 'failed' || p.status.toLowerCase() === 'crashloopbackoff'
        ).length;
        const pendingPods = pods.filter(
          (p) => p.status.toLowerCase() === 'pending'
        ).length;

        // Calculate unique nodes
        const uniqueNodes = new Set(pods.map((p) => p.node).filter(Boolean));
        const totalNodes = uniqueNodes.size;

        // For now, assume all nodes with pods are ready (we'd need a separate API call for accurate node status)
        const readyNodes = totalNodes;

        // Calculate health percentages
        const podHealthPercentage = totalPods > 0 ? (runningPods / totalPods) * 100 : 0;
        const nodeHealthPercentage = totalNodes > 0 ? (readyNodes / totalNodes) * 100 : 100;

        setMetrics({
          totalPods,
          runningPods,
          failedPods,
          pendingPods,
          totalNodes,
          readyNodes,
          podHealthPercentage,
          nodeHealthPercentage,
        });
      } catch (error) {
        console.error('Error calculating cluster metrics:', error);
      } finally {
        setLoading(false);
      }
    };

    if (pods.length > 0) {
      calculateMetrics();

      // Refresh every 10 seconds
      const interval = setInterval(calculateMetrics, 10000);
      return () => clearInterval(interval);
    } else {
      setMetrics(null);
    }
  }, [pods]);

  if (!metrics || pods.length === 0) {
    return null;
  }

  const getHealthColor = (percentage: number) => {
    if (percentage >= 90) return 'text-green-600 dark:text-green-400';
    if (percentage >= 70) return 'text-yellow-600 dark:text-yellow-400';
    return 'text-red-600 dark:text-red-400';
  };

  const getHealthBg = (percentage: number) => {
    if (percentage >= 90) return 'bg-green-500';
    if (percentage >= 70) return 'bg-yellow-500';
    return 'bg-red-500';
  };

  return (
    <div className="bg-white dark:bg-gray-800 rounded-lg p-4 border border-gray-200 dark:border-gray-700 mt-4">
      <h3 className="font-semibold mb-4 flex items-center text-gray-900 dark:text-gray-100">
        <Activity className="w-5 h-5 mr-2 text-blue-500" />
        Cluster Metrics
        {loading && (
          <div className="ml-2 animate-spin h-3 w-3 border-2 border-gray-400 dark:border-gray-500 border-t-transparent rounded-full"></div>
        )}
      </h3>

      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        {/* Pod Count Metric */}
        <div className="bg-gray-50 dark:bg-gray-700/50 rounded-lg p-3">
          <div className="flex items-center mb-2">
            <Box className="w-4 h-4 mr-1.5 text-blue-500" />
            <span className="text-xs text-gray-600 dark:text-gray-400 font-medium">
              Pods
            </span>
          </div>
          <div className="text-2xl font-bold text-gray-900 dark:text-gray-100">
            {metrics.totalPods}
          </div>
          <div className="mt-1 flex items-center text-xs">
            <span className={clsx('font-medium', getHealthColor(metrics.podHealthPercentage))}>
              {metrics.runningPods} running
            </span>
          </div>
          {/* Health Bar */}
          <div className="mt-2 w-full bg-gray-200 dark:bg-gray-600 rounded-full h-1.5">
            <div
              className={clsx('h-1.5 rounded-full transition-all', getHealthBg(metrics.podHealthPercentage))}
              style={{ width: `${metrics.podHealthPercentage}%` }}
            />
          </div>
        </div>

        {/* Node Count Metric */}
        <div className="bg-gray-50 dark:bg-gray-700/50 rounded-lg p-3">
          <div className="flex items-center mb-2">
            <HardDrive className="w-4 h-4 mr-1.5 text-purple-500" />
            <span className="text-xs text-gray-600 dark:text-gray-400 font-medium">
              Nodes
            </span>
          </div>
          <div className="text-2xl font-bold text-gray-900 dark:text-gray-100">
            {metrics.totalNodes}
          </div>
          <div className="mt-1 flex items-center text-xs">
            <span className={clsx('font-medium', getHealthColor(metrics.nodeHealthPercentage))}>
              {metrics.readyNodes} ready
            </span>
          </div>
          {/* Health Bar */}
          <div className="mt-2 w-full bg-gray-200 dark:bg-gray-600 rounded-full h-1.5">
            <div
              className={clsx('h-1.5 rounded-full transition-all', getHealthBg(metrics.nodeHealthPercentage))}
              style={{ width: `${metrics.nodeHealthPercentage}%` }}
            />
          </div>
        </div>

        {/* Failed Pods Metric */}
        <div className="bg-gray-50 dark:bg-gray-700/50 rounded-lg p-3">
          <div className="flex items-center mb-2">
            <TrendingUp className="w-4 h-4 mr-1.5 text-red-500" />
            <span className="text-xs text-gray-600 dark:text-gray-400 font-medium">
              Failed
            </span>
          </div>
          <div
            className={clsx(
              'text-2xl font-bold',
              metrics.failedPods > 0 ? 'text-red-600 dark:text-red-400' : 'text-gray-900 dark:text-gray-100'
            )}
          >
            {metrics.failedPods}
          </div>
          <div className="mt-1 text-xs text-gray-500 dark:text-gray-400">
            {metrics.failedPods > 0 ? 'Needs attention' : 'All healthy'}
          </div>
          {/* Status indicator */}
          <div className="mt-2 flex items-center">
            <div
              className={clsx(
                'w-2 h-2 rounded-full',
                metrics.failedPods > 0 ? 'bg-red-500 animate-pulse' : 'bg-green-500'
              )}
            />
            <span className="ml-2 text-xs text-gray-600 dark:text-gray-400">
              {metrics.failedPods > 0 ? 'Issues detected' : 'No issues'}
            </span>
          </div>
        </div>

        {/* Pending Pods Metric */}
        <div className="bg-gray-50 dark:bg-gray-700/50 rounded-lg p-3">
          <div className="flex items-center mb-2">
            <Cpu className="w-4 h-4 mr-1.5 text-yellow-500" />
            <span className="text-xs text-gray-600 dark:text-gray-400 font-medium">
              Pending
            </span>
          </div>
          <div
            className={clsx(
              'text-2xl font-bold',
              metrics.pendingPods > 0 ? 'text-yellow-600 dark:text-yellow-400' : 'text-gray-900 dark:text-gray-100'
            )}
          >
            {metrics.pendingPods}
          </div>
          <div className="mt-1 text-xs text-gray-500 dark:text-gray-400">
            {metrics.pendingPods > 0 ? 'Starting up' : 'None pending'}
          </div>
          {/* Status indicator */}
          <div className="mt-2 flex items-center">
            <div
              className={clsx(
                'w-2 h-2 rounded-full',
                metrics.pendingPods > 0 ? 'bg-yellow-500 animate-pulse' : 'bg-gray-400'
              )}
            />
            <span className="ml-2 text-xs text-gray-600 dark:text-gray-400">
              {metrics.pendingPods > 0 ? 'Pods starting' : 'All scheduled'}
            </span>
          </div>
        </div>
      </div>

      {/* Overall Health Summary */}
      <div className="mt-4 pt-4 border-t border-gray-200 dark:border-gray-700">
        <div className="flex items-center justify-between">
          <span className="text-sm font-medium text-gray-700 dark:text-gray-300">
            Cluster Health
          </span>
          <div className="flex items-center">
            <div
              className={clsx(
                'w-2 h-2 rounded-full mr-2',
                metrics.podHealthPercentage >= 90 ? 'bg-green-500' : metrics.podHealthPercentage >= 70 ? 'bg-yellow-500' : 'bg-red-500'
              )}
            />
            <span className={clsx('text-sm font-semibold', getHealthColor(metrics.podHealthPercentage))}>
              {metrics.podHealthPercentage.toFixed(0)}%
            </span>
          </div>
        </div>
        <div className="mt-2 text-xs text-gray-500 dark:text-gray-400">
          {provider === 'eks' && 'AWS EKS Cluster'}
          {provider === 'aks' && 'Azure AKS Cluster'}
          {provider === 'gke' && 'Google GKE Cluster'}
          {provider === 'unknown' && 'Kubernetes Cluster'}
        </div>
      </div>
    </div>
  );
};

export default ClusterMetrics;
