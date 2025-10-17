'use client'

import React, { useMemo } from 'react'
import { HardDrive, Package, AlertTriangle, Info } from 'lucide-react'
import { MetricsChart, MetricsDataPoint } from './MetricsChart'
import { MetricsHistoryPoint, SystemInfo, SystemMetrics } from '../../types/monitor'

/**
 * Props interface for the DiskDetailView component
 */
export interface DiskDetailViewProps {
  /** Historical metrics data for time-series visualization */
  metricsHistory: MetricsHistoryPoint[]
  /** System information including disk specifications */
  systemInfo: SystemInfo
  /** Current real-time system metrics */
  currentMetrics: SystemMetrics
}

/**
 * Docker system df data interface
 */
interface DockerSystemDf {
  Images?: Array<{ Size: number }>
  Containers?: Array<{ SizeRw: number }>
  Volumes?: Array<{ UsageData?: { Size: number } }>
  BuildCache?: Array<{ Size: number }>
}

/**
 * Formats disk space in gigabytes
 *
 * @param gb - Disk space in gigabytes
 * @returns Formatted string (e.g., "250.5 GB")
 *
 * @example
 * formatDiskGB(250.456)  // "250.5 GB"
 * formatDiskGB(0.123)    // "0.1 GB"
 */
const formatDiskGB = (gb: number): string => {
  return `${gb.toFixed(1)} GB`
}

/**
 * Calculates used disk space from percentage and total
 *
 * @param percent - Disk usage percentage (0-100)
 * @param totalGB - Total disk capacity in gigabytes
 * @returns Used disk space in gigabytes
 */
const calculateUsedDisk = (percent: number, totalGB: number): number => {
  return (percent / 100) * totalGB
}

/**
 * Generates warning message based on disk usage percentage
 *
 * @param percent - Disk usage percentage (0-100)
 * @returns Warning message string or null if no warning
 */
const getWarningMessage = (percent: number): string | null => {
  if (percent > 90) return 'Critical: Disk usage above 90%'
  if (percent > 70) return 'Warning: Disk usage above 70%'
  return null
}

/**
 * Determines color class based on disk usage percentage
 *
 * @param value - Disk percentage (0-100)
 * @returns Tailwind CSS color class string
 *
 * @example
 * getColorClass(45) // "text-status-healthy"
 * getColorClass(75) // "text-status-warning"
 * getColorClass(92) // "text-status-error"
 */
const getColorClass = (value: number): string => {
  if (value < 70) return 'text-status-healthy'
  if (value < 90) return 'text-status-warning'
  return 'text-status-error'
}

/**
 * Calculates Docker disk usage from system df data
 *
 * @param systemDf - Docker system df data object
 * @returns Docker disk usage breakdown with total
 */
const calculateDockerUsage = (
  systemDf: DockerSystemDf | undefined
): {
  images: number
  containers: number
  volumes: number
  buildCache: number
  total: number
} | null => {
  if (!systemDf) return null

  try {
    // Calculate images size (bytes to GB)
    const imagesBytes =
      systemDf.Images?.reduce((sum, img) => sum + (img.Size || 0), 0) || 0
    const imagesGB = imagesBytes / (1024 * 1024 * 1024)

    // Calculate containers size
    const containersBytes =
      systemDf.Containers?.reduce((sum, container) => sum + (container.SizeRw || 0), 0) || 0
    const containersGB = containersBytes / (1024 * 1024 * 1024)

    // Calculate volumes size
    const volumesBytes =
      systemDf.Volumes?.reduce(
        (sum, volume) => sum + (volume.UsageData?.Size || 0),
        0
      ) || 0
    const volumesGB = volumesBytes / (1024 * 1024 * 1024)

    // Calculate build cache size
    const buildCacheBytes =
      systemDf.BuildCache?.reduce((sum, cache) => sum + (cache.Size || 0), 0) || 0
    const buildCacheGB = buildCacheBytes / (1024 * 1024 * 1024)

    const total = imagesGB + containersGB + volumesGB + buildCacheGB

    return {
      images: imagesGB,
      containers: containersGB,
      volumes: volumesGB,
      buildCache: buildCacheGB,
      total
    }
  } catch (error) {
    console.error('Error calculating Docker usage:', error)
    return null
  }
}

/**
 * DiskDetailView component displays comprehensive disk metrics including:
 * - Live disk usage graph (5-minute rolling window)
 * - Disk breakdown (total, used, free, mount point)
 * - Disk statistics (current, average, peak, min)
 * - Docker disk usage breakdown (if available)
 * - Warning banners for high disk usage
 *
 * This component is designed to be rendered inside a modal (SystemMetricsModal)
 * and provides detailed disk analysis for system monitoring.
 *
 * @example
 * ```tsx
 * <DiskDetailView
 *   metricsHistory={metricsHistory}
 *   systemInfo={systemInfo}
 *   currentMetrics={currentMetrics}
 * />
 * ```
 */
export function DiskDetailView({
  metricsHistory,
  systemInfo,
  currentMetrics
}: DiskDetailViewProps): JSX.Element {
  /**
   * Transform metrics history into chart-compatible format
   * Maps disk_percent from historical data
   */
  const chartData: MetricsDataPoint[] = useMemo(() => {
    return metricsHistory.map(point => ({
      timestamp: point.timestamp,
      value: point.disk_percent,
      event: point.event
        ? {
            type: point.event.type === 'container_start' ? 'start' : 'stop',
            label: `${point.event.containerName} ${point.event.type === 'container_start' ? 'started' : 'stopped'}`
          }
        : undefined
    }))
  }, [metricsHistory])

  /**
   * Calculate disk statistics from historical data
   */
  const statistics = useMemo(() => {
    if (metricsHistory.length === 0) {
      return {
        current: currentMetrics.disk_percent,
        average: currentMetrics.disk_percent,
        peak: currentMetrics.disk_percent,
        min: currentMetrics.disk_percent
      }
    }

    const values = metricsHistory.map(point => point.disk_percent)
    return {
      current: currentMetrics.disk_percent,
      average: values.reduce((sum, val) => sum + val, 0) / values.length,
      peak: Math.max(...values),
      min: Math.min(...values)
    }
  }, [metricsHistory, currentMetrics.disk_percent])

  /**
   * Calculate disk breakdown values
   */
  const diskBreakdown = useMemo(() => {
    const totalGB = systemInfo.system.disk_total_gb
    const usedGB = calculateUsedDisk(currentMetrics.disk_percent, totalGB)
    const freeGB = totalGB - usedGB

    return {
      total: totalGB,
      used: usedGB,
      free: freeGB,
      usedPercent: currentMetrics.disk_percent
    }
  }, [systemInfo.system.disk_total_gb, currentMetrics.disk_percent])

  /**
   * Calculate Docker disk usage
   */
  const dockerUsage = useMemo(() => {
    return calculateDockerUsage(systemInfo.docker.system_df)
  }, [systemInfo.docker.system_df])

  /**
   * Calculate Docker usage percentages
   */
  const dockerPercentages = useMemo(() => {
    if (!dockerUsage) return null

    const totalDiskGB = systemInfo.system.disk_total_gb
    return {
      images: (dockerUsage.images / totalDiskGB) * 100,
      containers: (dockerUsage.containers / totalDiskGB) * 100,
      volumes: (dockerUsage.volumes / totalDiskGB) * 100,
      buildCache: (dockerUsage.buildCache / totalDiskGB) * 100,
      total: (dockerUsage.total / totalDiskGB) * 100
    }
  }, [dockerUsage, systemInfo.system.disk_total_gb])

  /**
   * Check if Docker usage cleanup recommendation should be shown
   */
  const showCleanupRecommendation = dockerPercentages && dockerPercentages.total > 15

  /**
   * Warning message for high disk usage
   */
  const warningMessage = getWarningMessage(currentMetrics.disk_percent)

  return (
    <div className="space-y-6" data-testid="disk-detail-view">
      {/* Warning Banner */}
      {warningMessage && (
        <div
          className={`rounded-lg p-4 flex items-start space-x-3 ${
            currentMetrics.disk_percent > 90
              ? 'bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800'
              : 'bg-yellow-50 dark:bg-yellow-900/20 border border-yellow-200 dark:border-yellow-800'
          }`}
        >
          <AlertTriangle
            className={`w-5 h-5 mt-0.5 flex-shrink-0 ${
              currentMetrics.disk_percent > 90
                ? 'text-red-600 dark:text-red-400'
                : 'text-yellow-600 dark:text-yellow-400'
            }`}
          />
          <div>
            <h4
              className={`text-sm font-semibold mb-1 ${
                currentMetrics.disk_percent > 90
                  ? 'text-red-900 dark:text-red-100'
                  : 'text-yellow-900 dark:text-yellow-100'
              }`}
            >
              {warningMessage}
            </h4>
            <p
              className={`text-xs ${
                currentMetrics.disk_percent > 90
                  ? 'text-red-800 dark:text-red-200'
                  : 'text-yellow-800 dark:text-yellow-200'
              }`}
            >
              Consider freeing up disk space to ensure system stability.
            </p>
          </div>
        </div>
      )}

      {/* Disk Usage Graph */}
      <div data-testid="disk-chart">
        <MetricsChart
          data={chartData}
          height={300}
          yAxisLabel="Disk Usage Over Time (5 Min Window)"
          yAxisDomain={[0, 100]}
          color="#f59e0b"
          lineLabel="Disk %"
          formatValue={(value) => `${value.toFixed(1)}%`}
          showGrid={true}
          showLegend={true}
        />
      </div>

      {/* Disk Breakdown and Statistics Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {/* Disk Breakdown Card */}
        <div
          className="bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-6"
          data-testid="disk-breakdown"
        >
          <div className="flex items-center space-x-2 mb-4">
            <HardDrive className="w-5 h-5 text-amber-600 dark:text-amber-400" />
            <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
              Disk Breakdown
            </h3>
          </div>

          <div className="space-y-3">
            {/* Total */}
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-600 dark:text-gray-400">Total:</span>
              <span className="text-sm font-semibold text-gray-900 dark:text-white">
                {formatDiskGB(diskBreakdown.total)}
              </span>
            </div>

            {/* Used */}
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-600 dark:text-gray-400">Used:</span>
              <span className={`text-sm font-semibold ${getColorClass(diskBreakdown.usedPercent)}`}>
                {formatDiskGB(diskBreakdown.used)} ({diskBreakdown.usedPercent.toFixed(1)}%)
              </span>
            </div>

            {/* Free */}
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-600 dark:text-gray-400">Free:</span>
              <span className="text-sm font-semibold text-gray-900 dark:text-white">
                {formatDiskGB(diskBreakdown.free)} ({(100 - diskBreakdown.usedPercent).toFixed(1)}%)
              </span>
            </div>

            {/* Mount Point */}
            <div className="flex items-center justify-between pt-2 border-t border-gray-200 dark:border-gray-700">
              <span className="text-sm text-gray-600 dark:text-gray-400">Mount Point:</span>
              <span className="text-sm font-mono font-semibold text-gray-900 dark:text-white">
                /
              </span>
            </div>
          </div>
        </div>

        {/* Disk Statistics Card */}
        <div
          className="bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-6"
          data-testid="disk-statistics"
        >
          <div className="flex items-center space-x-2 mb-4">
            <Info className="w-5 h-5 text-blue-600 dark:text-blue-400" />
            <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
              Disk Statistics
            </h3>
          </div>

          <div className="space-y-3">
            {/* Current */}
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-600 dark:text-gray-400">Current:</span>
              <span
                className={`text-sm font-semibold ${getColorClass(statistics.current)}`}
                data-testid="disk-current-value"
              >
                {statistics.current.toFixed(1)}%
              </span>
            </div>

            {/* Average */}
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-600 dark:text-gray-400">Average:</span>
              <span
                className={`text-sm font-semibold ${getColorClass(statistics.average)}`}
                data-testid="disk-average-value"
              >
                {statistics.average.toFixed(1)}%
              </span>
            </div>

            {/* Peak */}
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-600 dark:text-gray-400">Peak:</span>
              <span
                className={`text-sm font-semibold ${getColorClass(statistics.peak)}`}
                data-testid="disk-peak-value"
              >
                {statistics.peak.toFixed(1)}%
              </span>
            </div>

            {/* Minimum */}
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-600 dark:text-gray-400">Minimum:</span>
              <span className={`text-sm font-semibold ${getColorClass(statistics.min)}`}>
                {statistics.min.toFixed(1)}%
              </span>
            </div>

            {/* Data Points */}
            <div className="flex items-center justify-between pt-2 border-t border-gray-200 dark:border-gray-700">
              <span className="text-sm text-gray-600 dark:text-gray-400">Data Points:</span>
              <span className="text-sm font-semibold text-gray-900 dark:text-white">
                {metricsHistory.length}
              </span>
            </div>
          </div>
        </div>
      </div>

      {/* Docker Disk Usage Card */}
      {systemInfo.docker.available && dockerUsage && dockerPercentages && (
        <div
          className="bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-6"
          data-testid="docker-disk-usage"
        >
          <div className="flex items-center space-x-2 mb-4">
            <Package className="w-5 h-5 text-blue-600 dark:text-blue-400" />
            <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
              Docker Disk Usage
            </h3>
          </div>

          <div className="space-y-3">
            {/* Images */}
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-600 dark:text-gray-400">Images:</span>
              <span className="text-sm font-semibold text-gray-900 dark:text-white">
                {formatDiskGB(dockerUsage.images)} ({dockerPercentages.images.toFixed(1)}%)
              </span>
            </div>

            {/* Containers */}
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-600 dark:text-gray-400">Containers:</span>
              <span className="text-sm font-semibold text-gray-900 dark:text-white">
                {formatDiskGB(dockerUsage.containers)} ({dockerPercentages.containers.toFixed(1)}%)
              </span>
            </div>

            {/* Volumes */}
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-600 dark:text-gray-400">Volumes:</span>
              <span className="text-sm font-semibold text-gray-900 dark:text-white">
                {formatDiskGB(dockerUsage.volumes)} ({dockerPercentages.volumes.toFixed(1)}%)
              </span>
            </div>

            {/* Build Cache */}
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-600 dark:text-gray-400">Build Cache:</span>
              <span className="text-sm font-semibold text-gray-900 dark:text-white">
                {formatDiskGB(dockerUsage.buildCache)} ({dockerPercentages.buildCache.toFixed(1)}%)
              </span>
            </div>

            {/* Total Docker */}
            <div className="flex items-center justify-between pt-2 border-t border-gray-200 dark:border-gray-700">
              <span className="text-sm font-medium text-gray-900 dark:text-white">
                Total Docker:
              </span>
              <span
                className={`text-sm font-semibold ${
                  dockerPercentages.total > 15 ? 'text-status-warning' : 'text-status-healthy'
                }`}
              >
                {formatDiskGB(dockerUsage.total)} ({dockerPercentages.total.toFixed(1)}%)
              </span>
            </div>
          </div>

          {/* Cleanup Recommendation */}
          {showCleanupRecommendation && (
            <div className="mt-4 pt-4 border-t border-gray-200 dark:border-gray-700">
              <div className="flex items-start space-x-2">
                <Info className="w-4 h-4 text-amber-600 dark:text-amber-400 mt-0.5 flex-shrink-0" />
                <div>
                  <h4 className="text-sm font-semibold text-amber-900 dark:text-amber-100 mb-1">
                    Recommendation
                  </h4>
                  <p className="text-xs text-amber-800 dark:text-amber-200">
                    Docker is using over 15% of disk space. Run{' '}
                    <code className="bg-amber-100 dark:bg-amber-900 px-1 py-0.5 rounded font-mono">
                      docker system prune
                    </code>{' '}
                    to reclaim space from unused images, containers, and build cache.
                  </p>
                </div>
              </div>
            </div>
          )}
        </div>
      )}

      {/* Docker Not Available Message */}
      {!systemInfo.docker.available && (
        <div className="bg-gray-50 dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-6">
          <div className="flex items-start space-x-2">
            <Info className="w-5 h-5 text-gray-500 dark:text-gray-400 mt-0.5 flex-shrink-0" />
            <div>
              <h4 className="text-sm font-semibold text-gray-900 dark:text-white mb-1">
                Docker Information Not Available
              </h4>
              <p className="text-xs text-gray-600 dark:text-gray-400">
                {systemInfo.docker.error || 'Docker is not running or not accessible.'}
              </p>
            </div>
          </div>
        </div>
      )}

      {/* Disk Usage Interpretation Guide */}
      <div className="bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800 rounded-lg p-4">
        <div className="flex items-start space-x-2">
          <HardDrive className="w-5 h-5 text-amber-600 dark:text-amber-400 mt-0.5 flex-shrink-0" />
          <div>
            <h4 className="text-sm font-semibold text-amber-900 dark:text-amber-100 mb-1">
              Disk Usage Guide
            </h4>
            <div className="text-xs text-amber-800 dark:text-amber-200 space-y-1">
              <p>
                <span className="text-status-healthy font-medium">&lt;70%</span>: Normal operation,
                sufficient space available
              </p>
              <p>
                <span className="text-status-warning font-medium">70-90%</span>: Moderate usage,
                consider cleanup
              </p>
              <p>
                <span className="text-status-error font-medium">&gt;90%</span>: High usage, free up
                space immediately
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

export default DiskDetailView
