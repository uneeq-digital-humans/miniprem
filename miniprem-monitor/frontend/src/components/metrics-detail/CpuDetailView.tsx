'use client'

import React, { useMemo } from 'react'
import { Cpu, Activity, Server, Clock, CheckCircle, AlertTriangle, AlertCircle, Info } from 'lucide-react'
import { format } from 'date-fns'
import { MetricsChart, MetricsDataPoint } from './MetricsChart'
import { MetricsHistoryPoint, SystemInfo, SystemMetrics, ContainerStatus } from '../../types/monitor'

/**
 * Props interface for the CpuDetailView component
 */
export interface CpuDetailViewProps {
  /** Historical metrics data for time-series visualization */
  metricsHistory: MetricsHistoryPoint[]
  /** System information including CPU specifications */
  systemInfo: SystemInfo
  /** Current real-time system metrics */
  currentMetrics: SystemMetrics
  /** Container status list for CPU consumption analysis */
  containers: ContainerStatus[]
}

/**
 * Interface for CPU insights that provide automatic system analysis
 */
interface CpuInsight {
  /** Insight severity level */
  type: 'success' | 'warning' | 'error' | 'info'
  /** Short descriptive title */
  title: string
  /** Detailed explanation message */
  message: string
}

/**
 * Container CPU consumption data structure
 */
interface ContainerCpuUsage {
  name: string
  cpuPercent: number
}

/**
 * Formats uptime from hours to human-readable string
 *
 * @param hours - Number of hours of uptime
 * @returns Formatted string (e.g., "3d 12h" or "18h")
 *
 * @example
 * formatUptime(72.5)  // "3d 0h"
 * formatUptime(18.3)  // "18h"
 */
const formatUptime = (hours: number): string => {
  const days = Math.floor(hours / 24)
  const remainingHours = Math.floor(hours % 24)
  if (days > 0) return `${days}d ${remainingHours}h`
  return `${remainingHours}h`
}

/**
 * Calculates average CPU usage from historical metrics
 *
 * @param history - Array of historical metrics data points
 * @returns Average CPU percentage (0-100)
 */
const calculateAverage = (history: MetricsHistoryPoint[]): number => {
  if (history.length === 0) return 0
  const sum = history.reduce((acc, point) => acc + point.cpu_percent, 0)
  return sum / history.length
}

/**
 * Determines color class based on CPU usage percentage
 *
 * @param value - CPU percentage (0-100)
 * @returns Tailwind CSS color class string
 *
 * @example
 * getColorClass(45) // "text-status-healthy"
 * getColorClass(75) // "text-status-warning"
 * getColorClass(90) // "text-status-error"
 */
const getColorClass = (value: number): string => {
  if (value < 60) return 'text-status-healthy'
  if (value < 80) return 'text-status-warning'
  return 'text-status-error'
}

/**
 * Determines background color class for per-core CPU usage bars
 *
 * @param value - CPU percentage (0-100)
 * @returns Tailwind CSS background color class string
 *
 * @example
 * getUsageBarColor(45) // "bg-green-500"
 * getUsageBarColor(75) // "bg-yellow-500"
 * getUsageBarColor(90) // "bg-red-500"
 */
const getUsageBarColor = (value: number): string => {
  if (value < 60) return 'bg-green-500'
  if (value < 80) return 'bg-yellow-500'
  return 'bg-red-500'
}

/**
 * Parses container CPU usage data and sorts by consumption
 *
 * @param containers - Array of container status objects
 * @returns Sorted array of containers with parsed CPU percentages
 */
const parseContainerCpuUsage = (containers: ContainerStatus[]): ContainerCpuUsage[] => {
  return containers
    .filter(c => c.cpu_usage && c.status.toLowerCase().includes('running'))
    .map(c => ({
      name: c.name,
      cpuPercent: parseFloat(c.cpu_usage?.replace('%', '') || '0')
    }))
    .sort((a, b) => b.cpuPercent - a.cpuPercent)
}

/**
 * Returns styling classes for insight cards based on type
 *
 * @param type - Insight severity type
 * @returns Tailwind CSS classes for border, background, and text colors
 */
const getInsightStyles = (type: CpuInsight['type']): string => {
  switch (type) {
    case 'success':
      return 'bg-green-50 dark:bg-green-900/20 border-green-200 dark:border-green-800'
    case 'warning':
      return 'bg-yellow-50 dark:bg-yellow-900/20 border-yellow-200 dark:border-yellow-800'
    case 'error':
      return 'bg-red-50 dark:bg-red-900/20 border-red-200 dark:border-red-800'
    case 'info':
      return 'bg-blue-50 dark:bg-blue-900/20 border-blue-200 dark:border-blue-800'
  }
}

/**
 * Returns the appropriate icon component for an insight type
 *
 * @param type - Insight severity type
 * @returns Lucide icon component with appropriate color styling
 */
const InsightIcon: React.FC<{ type: CpuInsight['type'] }> = ({ type }) => {
  const className = 'w-5 h-5 flex-shrink-0'

  switch (type) {
    case 'success':
      return <CheckCircle className={`${className} text-green-600 dark:text-green-400`} />
    case 'warning':
      return <AlertTriangle className={`${className} text-yellow-600 dark:text-yellow-400`} />
    case 'error':
      return <AlertCircle className={`${className} text-red-600 dark:text-red-400`} />
    case 'info':
      return <Info className={`${className} text-blue-600 dark:text-blue-400`} />
  }
}

/**
 * Calculates intelligent CPU insights by analyzing system patterns
 *
 * Analyzes multi-threading efficiency, usage patterns, core balance,
 * and container impact to provide actionable recommendations.
 *
 * @param currentCpu - Current overall CPU usage percentage
 * @param perCore - Array of per-core CPU usage percentages
 * @param topConsumers - Array of top CPU consuming containers
 * @returns Array of up to 5 most relevant insights
 *
 * @example
 * const insights = calculateInsights(85.2, [90, 88, 45, 42], [
 *   { name: 'nginx', cpuPercent: 60 }
 * ])
 * // Returns insights about high usage and core imbalance
 */
const calculateInsights = (
  currentCpu: number,
  perCore: number[],
  topConsumers: ContainerCpuUsage[]
): CpuInsight[] => {
  const insights: CpuInsight[] = []

  // Multi-threading efficiency analysis
  if (perCore.length > 0) {
    const maxCore = Math.max(...perCore)
    const minCore = Math.min(...perCore)
    const avgCore = perCore.reduce((a, b) => a + b, 0) / perCore.length
    const variance = perCore.reduce((sum, val) => sum + Math.pow(val - avgCore, 2), 0) / perCore.length
    const stdDev = Math.sqrt(variance)

    // Good multi-threading: low variance and moderate/high average usage
    if (stdDev < 15 && avgCore > 30 && avgCore < 70) {
      insights.push({
        type: 'success',
        title: 'Excellent Multi-Threading',
        message: `CPU load is well-distributed across ${perCore.length} cores with ${avgCore.toFixed(1)}% average usage`
      })
    }
    // Core imbalance: high max but low average indicates poor distribution
    else if (maxCore > 90 && avgCore < 40) {
      const maxCoreIndex = perCore.indexOf(maxCore)
      insights.push({
        type: 'warning',
        title: 'Core Imbalance Detected',
        message: `Core ${maxCoreIndex} at ${maxCore.toFixed(1)}% while average is ${avgCore.toFixed(1)}% - workload may benefit from parallelization`
      })
    }
    // Single-threaded bottleneck: one core maxed, others idle
    else if (maxCore > 85 && minCore < 20) {
      const maxCoreIndex = perCore.indexOf(maxCore)
      insights.push({
        type: 'error',
        title: 'Single-Threaded Bottleneck',
        message: `Core ${maxCoreIndex} at ${maxCore.toFixed(1)}% while Core ${perCore.indexOf(minCore)} at ${minCore.toFixed(1)}% - application may need optimization`
      })
    }
    // Good idle capacity
    else if (maxCore < 50) {
      insights.push({
        type: 'success',
        title: 'Healthy CPU Capacity',
        message: `Peak core usage at ${maxCore.toFixed(1)}% - plenty of headroom for additional workload`
      })
    }
  }

  // Overall system usage warnings
  if (currentCpu > 90) {
    insights.push({
      type: 'error',
      title: 'Critical CPU Usage',
      message: `System CPU at ${currentCpu.toFixed(1)}% - immediate action required to prevent performance degradation`
    })
  } else if (currentCpu > 80) {
    insights.push({
      type: 'warning',
      title: 'High CPU Usage',
      message: `System CPU at ${currentCpu.toFixed(1)}% - consider scaling resources or optimizing workloads`
    })
  } else if (currentCpu < 30) {
    insights.push({
      type: 'info',
      title: 'Low CPU Utilization',
      message: `System CPU at ${currentCpu.toFixed(1)}% - resources are underutilized, consider cost optimization`
    })
  }

  // Top consumer impact analysis
  if (topConsumers.length > 0) {
    const topConsumer = topConsumers[0]

    // Single container dominance
    if (topConsumer.cpuPercent > 70) {
      insights.push({
        type: 'error',
        title: 'Container Resource Monopoly',
        message: `${topConsumer.name} consuming ${topConsumer.cpuPercent.toFixed(1)}% CPU - may need resource limits or optimization`
      })
    } else if (topConsumer.cpuPercent > 50) {
      insights.push({
        type: 'warning',
        title: 'Single Container Dominance',
        message: `${topConsumer.name} consuming ${topConsumer.cpuPercent.toFixed(1)}% CPU - monitor for resource contention`
      })
    }

    // Multiple heavy consumers
    const heavyConsumers = topConsumers.filter(c => c.cpuPercent > 30)
    if (heavyConsumers.length >= 3) {
      insights.push({
        type: 'info',
        title: 'Multiple Active Workloads',
        message: `${heavyConsumers.length} containers using >30% CPU - distributed workload pattern detected`
      })
    }

    // Light overall usage with running containers
    if (topConsumers.length >= 5 && topConsumer.cpuPercent < 10) {
      insights.push({
        type: 'success',
        title: 'Efficient Container Orchestration',
        message: `${topConsumers.length} containers running with minimal CPU overhead - well-optimized deployment`
      })
    }
  } else {
    // No container data available
    insights.push({
      type: 'info',
      title: 'No Container Data',
      message: 'No running containers detected or container metrics unavailable'
    })
  }

  // Limit to top 5 most relevant insights
  return insights.slice(0, 5)
}

/**
 * CpuDetailView component displays comprehensive CPU metrics including:
 * - Live CPU usage graph (5-minute rolling window)
 * - System information (cores, platform, uptime)
 * - Per-core CPU usage visualization
 * - Load statistics (current, average, peak, min)
 * - Top CPU consuming containers
 * - Automatic intelligent insights and recommendations
 * - Container lifecycle event annotations on graph
 *
 * This component is designed to be rendered inside a modal (SystemMetricsModal)
 * and provides detailed CPU analysis for system monitoring.
 *
 * @example
 * ```tsx
 * <CpuDetailView
 *   metricsHistory={metricsHistory}
 *   systemInfo={systemInfo}
 *   currentMetrics={currentMetrics}
 *   containers={containers}
 * />
 * ```
 */
export function CpuDetailView({
  metricsHistory,
  systemInfo,
  currentMetrics,
  containers
}: CpuDetailViewProps): JSX.Element {
  /**
   * Transform metrics history into chart-compatible format
   * Maps container lifecycle events to chart annotations
   */
  const chartData: MetricsDataPoint[] = useMemo(() => {
    return metricsHistory.map(point => ({
      timestamp: point.timestamp,
      value: point.cpu_percent,
      event: point.event
        ? {
            type: point.event.type === 'container_start' ? 'start' : 'stop',
            label: `${point.event.containerName} ${point.event.type === 'container_start' ? 'started' : 'stopped'}`
          }
        : undefined
    }))
  }, [metricsHistory])

  /**
   * Calculate CPU load statistics from historical data
   */
  const statistics = useMemo(() => {
    if (metricsHistory.length === 0) {
      return {
        current: currentMetrics.cpu_percent,
        average: currentMetrics.cpu_percent,
        peak: currentMetrics.cpu_percent,
        min: currentMetrics.cpu_percent
      }
    }

    const values = metricsHistory.map(point => point.cpu_percent)
    return {
      current: currentMetrics.cpu_percent,
      average: calculateAverage(metricsHistory),
      peak: Math.max(...values),
      min: Math.min(...values)
    }
  }, [metricsHistory, currentMetrics.cpu_percent])

  /**
   * Parse and sort containers by CPU consumption
   */
  const topCpuConsumers = useMemo(() => {
    return parseContainerCpuUsage(containers)
  }, [containers])

  /**
   * Calculate intelligent CPU insights
   */
  const insights = useMemo(() => {
    return calculateInsights(
      currentMetrics.cpu_percent,
      currentMetrics.cpu_per_core || [],
      topCpuConsumers
    )
  }, [currentMetrics.cpu_percent, currentMetrics.cpu_per_core, topCpuConsumers])

  /**
   * Format boot time as readable date string
   */
  const formattedBootTime = useMemo(() => {
    try {
      return format(new Date(systemInfo.system.boot_time), 'MMM dd, yyyy HH:mm:ss')
    } catch {
      return systemInfo.system.boot_time
    }
  }, [systemInfo.system.boot_time])

  return (
    <div className="space-y-6" data-testid="cpu-detail-view">
      {/* CPU Usage Graph */}
      <div data-testid="cpu-chart">
        <MetricsChart
          data={chartData}
          height={300}
          yAxisLabel="CPU Usage Over Time (5 Min Window)"
          yAxisDomain={[0, 100]}
          color="#3b82f6"
          lineLabel="CPU %"
          formatValue={(value) => `${value.toFixed(1)}%`}
          showGrid={true}
          showLegend={true}
        />
      </div>

      {/* System Info and Load Statistics Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {/* System Information Card */}
        <div
          className="bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-6"
          data-testid="cpu-system-info"
        >
          <div className="flex items-center space-x-2 mb-4">
            <Server className="w-5 h-5 text-blue-600 dark:text-blue-400" />
            <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
              System Info
            </h3>
          </div>

          <div className="space-y-3">
            {/* Physical Cores */}
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-600 dark:text-gray-400">
                Physical Cores:
              </span>
              <span className="text-sm font-semibold text-gray-900 dark:text-white">
                {systemInfo.system.cpu_count}
              </span>
            </div>

            {/* Logical Cores */}
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-600 dark:text-gray-400">
                Logical Cores:
              </span>
              <span className="text-sm font-semibold text-gray-900 dark:text-white">
                {systemInfo.system.cpu_count_logical}
              </span>
            </div>

            {/* Platform */}
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-600 dark:text-gray-400">
                Platform:
              </span>
              <span className="text-sm font-semibold text-gray-900 dark:text-white">
                {systemInfo.system.platform}
              </span>
            </div>

            {/* Uptime */}
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-600 dark:text-gray-400 flex items-center">
                <Clock className="w-4 h-4 mr-1" />
                Uptime:
              </span>
              <span className="text-sm font-semibold text-gray-900 dark:text-white">
                {formatUptime(systemInfo.system.uptime_hours)}
              </span>
            </div>

            {/* Boot Time */}
            <div className="flex items-start justify-between">
              <span className="text-sm text-gray-600 dark:text-gray-400">
                Boot Time:
              </span>
              <span className="text-sm font-semibold text-gray-900 dark:text-white text-right">
                {formattedBootTime}
              </span>
            </div>
          </div>
        </div>

        {/* Load Statistics Card */}
        <div
          className="bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-6"
          data-testid="cpu-load-stats"
        >
          <div className="flex items-center space-x-2 mb-4">
            <Activity className="w-5 h-5 text-green-600 dark:text-green-400" />
            <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
              Load Statistics
            </h3>
          </div>

          <div className="space-y-3">
            {/* Current */}
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-600 dark:text-gray-400">
                Current:
              </span>
              <span
                className={`text-sm font-semibold ${getColorClass(statistics.current)}`}
                data-testid="cpu-current-value"
              >
                {statistics.current.toFixed(1)}%
              </span>
            </div>

            {/* Average */}
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-600 dark:text-gray-400">
                Average:
              </span>
              <span
                className={`text-sm font-semibold ${getColorClass(statistics.average)}`}
                data-testid="cpu-average-value"
              >
                {statistics.average.toFixed(1)}%
              </span>
            </div>

            {/* Peak */}
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-600 dark:text-gray-400">
                Peak:
              </span>
              <span
                className={`text-sm font-semibold ${getColorClass(statistics.peak)}`}
                data-testid="cpu-peak-value"
              >
                {statistics.peak.toFixed(1)}%
              </span>
            </div>

            {/* Minimum */}
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-600 dark:text-gray-400">
                Minimum:
              </span>
              <span className={`text-sm font-semibold ${getColorClass(statistics.min)}`}>
                {statistics.min.toFixed(1)}%
              </span>
            </div>

            {/* Data Points */}
            <div className="flex items-center justify-between pt-2 border-t border-gray-200 dark:border-gray-700">
              <span className="text-sm text-gray-600 dark:text-gray-400">
                Data Points:
              </span>
              <span className="text-sm font-semibold text-gray-900 dark:text-white">
                {metricsHistory.length}
              </span>
            </div>
          </div>
        </div>
      </div>

      {/* Per-Core CPU Usage */}
      {currentMetrics.cpu_per_core && currentMetrics.cpu_per_core.length > 0 && (
        <div
          className="bg-gray-50 dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-6"
          data-testid="cpu-per-core-section"
        >
          <div className="flex items-center space-x-2 mb-4">
            <Cpu className="w-5 h-5 text-purple-600 dark:text-purple-400" />
            <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
              Per-Core CPU Usage
            </h3>
          </div>

          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            {currentMetrics.cpu_per_core.map((coreUsage, index) => (
              <div key={index} data-testid={`cpu-core-${index}`} className="space-y-2">
                <div className="flex items-center justify-between">
                  <span className="text-xs font-medium text-gray-600 dark:text-gray-400">
                    Core {index}
                  </span>
                  <span className={`text-xs font-semibold ${getColorClass(coreUsage)}`}>
                    {coreUsage.toFixed(1)}%
                  </span>
                </div>
                <div className="w-full bg-gray-200 dark:bg-gray-700 rounded-full h-2.5">
                  <div
                    className={`h-2.5 rounded-full transition-all duration-300 ${getUsageBarColor(coreUsage)}`}
                    style={{ width: `${Math.min(coreUsage, 100)}%` }}
                    data-testid={`cpu-core-${index}-bar`}
                  />
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Top CPU Consumers */}
      <div
        className="bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-6"
        data-testid="cpu-top-consumers"
      >
        <div className="flex items-center space-x-2 mb-4">
          <Activity className="w-5 h-5 text-orange-600 dark:text-orange-400" />
          <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
            Top CPU Consumers
          </h3>
        </div>

        {topCpuConsumers.length > 0 ? (
          <div className="space-y-3" data-testid="cpu-consumers-list">
            {topCpuConsumers.slice(0, 5).map((container, index) => (
              <div
                key={`${container.name}-${index}`}
                className="flex justify-between items-center py-2 border-b border-gray-100 dark:border-gray-700 last:border-b-0"
                data-testid={`cpu-consumer-${index}`}
              >
                <span
                  className="text-sm text-gray-900 dark:text-white truncate flex-1 pr-4"
                  title={container.name}
                  data-testid={`cpu-consumer-name-${index}`}
                >
                  {container.name}
                </span>
                <span
                  className={`text-sm font-semibold ${getColorClass(container.cpuPercent)}`}
                  data-testid={`cpu-consumer-value-${index}`}
                >
                  {container.cpuPercent.toFixed(1)}%
                </span>
              </div>
            ))}
          </div>
        ) : (
          <div
            className="text-sm text-gray-500 dark:text-gray-400 text-center py-4"
            data-testid="cpu-consumers-empty"
          >
            No data available
          </div>
        )}
      </div>

      {/* System Insights */}
      {insights.length > 0 && (
        <div
          className="bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-6"
          data-testid="cpu-insights-section"
        >
          <div className="flex items-center space-x-2 mb-4">
            <Activity className="w-5 h-5 text-indigo-600 dark:text-indigo-400" />
            <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
              System Insights
            </h3>
          </div>

          <div className="space-y-3">
            {insights.map((insight, index) => (
              <div
                key={index}
                className={`p-3 rounded-lg border ${getInsightStyles(insight.type)}`}
                data-testid={`cpu-insight-${index}`}
              >
                <div className="flex items-start space-x-3">
                  <InsightIcon type={insight.type} />
                  <div className="flex-1 min-w-0">
                    <div
                      className="text-sm font-semibold text-gray-900 dark:text-white mb-1"
                      data-testid={`cpu-insight-title-${index}`}
                    >
                      {insight.title}
                    </div>
                    <div
                      className="text-xs text-gray-700 dark:text-gray-300"
                      data-testid={`cpu-insight-message-${index}`}
                    >
                      {insight.message}
                    </div>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* CPU Usage Interpretation Guide */}
      <div className="bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800 rounded-lg p-4">
        <div className="flex items-start space-x-2">
          <Cpu className="w-5 h-5 text-blue-600 dark:text-blue-400 mt-0.5 flex-shrink-0" />
          <div>
            <h4 className="text-sm font-semibold text-blue-900 dark:text-blue-100 mb-1">
              CPU Usage Guide
            </h4>
            <div className="text-xs text-blue-800 dark:text-blue-200 space-y-1">
              <p>
                <span className="text-status-healthy font-medium">&lt;60%</span>: Normal operation, system responsive
              </p>
              <p>
                <span className="text-status-warning font-medium">60-80%</span>: Moderate load, monitor performance
              </p>
              <p>
                <span className="text-status-error font-medium">&gt;80%</span>: High load, consider scaling resources
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

export default CpuDetailView
