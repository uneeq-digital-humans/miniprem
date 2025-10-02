import React from 'react';
import { SystemMetrics } from '../types/monitor';
import { Cpu, HardDrive, MemoryStick, Network } from 'lucide-react';

interface MetricsCardProps {
  metrics: SystemMetrics | null;
  loading?: boolean;
}

export function MetricsCard({ metrics, loading }: MetricsCardProps) {
  const formatBytes = (bytes: number) => {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
  };

  const getUsageColor = (percentage: number) => {
    if (percentage < 60) return 'text-status-healthy';
    if (percentage < 80) return 'text-status-warning';
    return 'text-status-error';
  };

  if (loading) {
    return (
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6" data-testid="metrics-section-loading">
        {Array.from({ length: 4 }).map((_, index) => (
          <div key={index} className="metric-card animate-pulse" data-testid={`metrics-card-loading-${index}`}>
            <div className="flex flex-col space-y-2">
              <div className="h-4 bg-gray-200 dark:bg-gray-600 rounded w-16"></div>
              <div className="h-8 bg-gray-200 dark:bg-gray-600 rounded w-12"></div>
            </div>
            <div className="w-8 h-8 bg-gray-200 dark:bg-gray-600 rounded"></div>
          </div>
        ))}
      </div>
    );
  }

  if (!metrics) {
    return (
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6" data-testid="metrics-section-empty">
        <div className="metric-card" data-testid="metrics-empty-state">
          <div className="text-center text-gray-500 dark:text-gray-400 py-4">No metrics available</div>
        </div>
      </div>
    );
  }

  return (
    <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6" data-testid="metrics-section">
      {/* CPU Usage */}
      <div className="metric-card" data-testid="cpu-metrics-card">
        <div>
          <div className="metric-label" data-testid="cpu-label">CPU Usage</div>
          <div className={`metric-value ${getUsageColor(metrics.cpu_percent)}`} data-testid="cpu-value">
            {metrics.cpu_percent.toFixed(1)}%
          </div>
        </div>
        <Cpu className="metric-icon" data-testid="cpu-icon" />
      </div>

      {/* Memory Usage */}
      <div className="metric-card" data-testid="memory-metrics-card">
        <div>
          <div className="metric-label" data-testid="memory-label">Memory</div>
          <div className={`metric-value ${getUsageColor(metrics.memory_percent)}`} data-testid="memory-value">
            {metrics.memory_percent.toFixed(1)}%
          </div>
        </div>
        <MemoryStick className="metric-icon" data-testid="memory-icon" />
      </div>

      {/* Disk Usage */}
      <div className="metric-card" data-testid="disk-metrics-card">
        <div>
          <div className="metric-label" data-testid="disk-label">Disk</div>
          <div className={`metric-value ${getUsageColor(metrics.disk_percent)}`} data-testid="disk-value">
            {metrics.disk_percent.toFixed(1)}%
          </div>
        </div>
        <HardDrive className="metric-icon" data-testid="disk-icon" />
      </div>

      {/* Network */}
      <div className="metric-card" data-testid="network-metrics-card">
        <div>
          <div className="metric-label" data-testid="network-label">Network I/O</div>
          <div className="flex flex-col text-sm">
            <div className="text-status-healthy" data-testid="network-sent">
              ↑ {formatBytes(metrics.network_io.bytes_sent)}
            </div>
            <div className="text-uneeq-primary" data-testid="network-received">
              ↓ {formatBytes(metrics.network_io.bytes_recv)}
            </div>
          </div>
        </div>
        <Network className="metric-icon" data-testid="network-icon" />
      </div>
    </div>
  );
}