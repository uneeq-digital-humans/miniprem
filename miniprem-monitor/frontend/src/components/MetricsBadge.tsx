import React from 'react';
import { PrometheusMetrics } from '../types/monitor';
import clsx from 'clsx';

interface MetricsBadgeProps {
  metrics: PrometheusMetrics;
  className?: string;
}

/**
 * Display Prometheus metrics as compact colored badges.
 *
 * Color coding:
 * - Green: < 60% (healthy)
 * - Yellow: 60-80% (warning)
 * - Red: > 80% (critical)
 */
export function MetricsBadge({ metrics, className }: MetricsBadgeProps) {
  const getColorClass = (value: number | null | undefined): string => {
    if (value === null || value === undefined) return 'bg-gray-100 dark:bg-gray-600 text-gray-700 dark:text-gray-300';
    if (value < 60) return 'bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-300';
    if (value < 80) return 'bg-yellow-100 dark:bg-yellow-900/30 text-yellow-700 dark:text-yellow-300';
    return 'bg-red-100 dark:bg-red-900/30 text-red-700 dark:text-red-300';
  };

  const formatBytes = (bytes: number | null | undefined): string => {
    if (bytes === null || bytes === undefined) return 'N/A';
    const gb = bytes / (1024 ** 3);
    if (gb >= 1) return `${gb.toFixed(1)}GB`;
    const mb = bytes / (1024 ** 2);
    return `${mb.toFixed(0)}MB`;
  };

  const formatUptime = (seconds: number | null | undefined): string => {
    if (seconds === null || seconds === undefined) return 'N/A';
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    if (hours > 24) {
      const days = Math.floor(hours / 24);
      return `${days}d ${hours % 24}h`;
    }
    if (hours > 0) return `${hours}h ${minutes}m`;
    return `${minutes}m`;
  };

  const hasAnyMetrics = Object.values(metrics).some(value => value !== null && value !== undefined);

  if (!hasAnyMetrics) return null;

  return (
    <div className={clsx('flex items-center space-x-1', className)} data-testid="metrics-badge">
      {/* GPU Usage */}
      {metrics.gpu_percent !== null && metrics.gpu_percent !== undefined && (
        <div
          className={clsx(
            'text-xs font-mono px-2 py-1 rounded transition-colors',
            getColorClass(metrics.gpu_percent)
          )}
          title={`GPU Utilization: ${metrics.gpu_percent.toFixed(1)}%`}
          data-testid="gpu-badge"
        >
          GPU {metrics.gpu_percent.toFixed(0)}%
        </div>
      )}

      {/* CPU Usage */}
      {metrics.cpu_percent !== null && metrics.cpu_percent !== undefined && (
        <div
          className={clsx(
            'text-xs font-mono px-2 py-1 rounded transition-colors',
            getColorClass(metrics.cpu_percent)
          )}
          title={`CPU Usage: ${metrics.cpu_percent.toFixed(1)}%`}
          data-testid="cpu-badge"
        >
          CPU {metrics.cpu_percent.toFixed(0)}%
        </div>
      )}

      {/* Memory Usage */}
      {metrics.memory_percent !== null && metrics.memory_percent !== undefined && (
        <div
          className={clsx(
            'text-xs font-mono px-2 py-1 rounded transition-colors',
            getColorClass(metrics.memory_percent)
          )}
          title={`Memory Usage: ${metrics.memory_percent.toFixed(1)}%${metrics.memory_bytes ? ` (${formatBytes(metrics.memory_bytes)})` : ''}`}
          data-testid="memory-badge"
        >
          MEM {metrics.memory_percent.toFixed(0)}%
        </div>
      )}

      {/* Request Count */}
      {metrics.request_count !== null && metrics.request_count !== undefined && (
        <div
          className="text-xs font-mono px-2 py-1 rounded bg-blue-100 dark:bg-blue-900/30 text-blue-700 dark:text-blue-300"
          title={`Total Requests: ${metrics.request_count.toLocaleString()}`}
          data-testid="requests-badge"
        >
          {metrics.request_count > 1000
            ? `${(metrics.request_count / 1000).toFixed(1)}K req`
            : `${metrics.request_count} req`
          }
        </div>
      )}

      {/* Uptime */}
      {metrics.uptime_seconds !== null && metrics.uptime_seconds !== undefined && (
        <div
          className="text-xs font-mono px-2 py-1 rounded bg-gray-100 dark:bg-gray-600 text-gray-700 dark:text-gray-300"
          title={`Uptime: ${metrics.uptime_seconds.toFixed(0)} seconds`}
          data-testid="uptime-badge"
        >
          ⏱ {formatUptime(metrics.uptime_seconds)}
        </div>
      )}
    </div>
  );
}
