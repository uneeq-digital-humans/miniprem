'use client'

import React, { useMemo } from 'react'
import { MemoryStick, Activity, Info, AlertTriangle, CheckCircle, TrendingUp } from 'lucide-react'
import { MetricsChart, MetricsDataPoint } from './MetricsChart'
import { MetricsHistoryPoint, SystemInfo, SystemMetrics, ContainerStatus } from '../../types/monitor'

/**
 * Props interface for the MemoryDetailView component
 */
export interface MemoryDetailViewProps {
  /** Historical metrics data for time-series visualization */
  metricsHistory: MetricsHistoryPoint[]
  /** System information including memory specifications */
  systemInfo: SystemInfo
  /** Current real-time system metrics */
  currentMetrics: SystemMetrics
  /** Container status list for top memory consumers */
  containers: ContainerStatus[]
}

/**
 * Memory insight interface for automatic memory analysis
 */
interface MemoryInsight {
  type: 'success' | 'warning' | 'error' | 'info'
  title: string
  message: string
}

/**
 * Formats memory value in gigabytes with 1 decimal place
 *
 * @param gb - Memory value in gigabytes
 * @returns Formatted string (e.g., "4.2 GB")
 *
 * @example
 * formatMemoryGB(4.234)  // "4.2 GB"
 * formatMemoryGB(23.456) // "23.5 GB"
 */
const formatMemoryGB = (gb: number): string => {
  return `${gb.toFixed(1)} GB`
}

/**
 * Formats memory value in megabytes or gigabytes
 *
 * @param mb - Memory value in megabytes
 * @returns Formatted string (e.g., "512 MB" or "1.2 GB")
 *
 * @example
 * formatMemoryMB(512)   // "512 MB"
 * formatMemoryMB(1536)  // "1.5 GB"
 */
const formatMemoryMB = (mb: number): string => {
  if (mb >= 1024) return `${(mb / 1024).toFixed(1)} GB`
  return `${mb.toFixed(0)} MB`
}

/**
 * Parses memory usage string to extract used memory in MB
 *
 * @param memoryStr - Memory string (e.g., "1.2GiB / 16GiB" or "512MiB / 16GiB")
 * @returns Used memory in megabytes
 *
 * @example
 * parseMemoryUsage("1.2GiB / 16GiB")  // 1228.8 MB
 * parseMemoryUsage("512MiB / 16GiB")  // 512 MB
 * parseMemoryUsage("invalid")         // 0 MB
 */
const parseMemoryUsage = (memoryStr: string): number => {
  // Parse "1.2GiB / 16GiB" or "512MiB / 16GiB" to MB
  const match = memoryStr.match(/^([\d.]+)(GiB|MiB)/)
  if (!match) return 0
  const value = parseFloat(match[1])
  const unit = match[2]
  return unit === 'GiB' ? value * 1024 : value
}

/**
 * Calculates used memory in GB from percentage and total
 *
 * @param percent - Memory usage percentage (0-100)
 * @param totalGB - Total system memory in gigabytes
 * @returns Used memory in gigabytes
 *
 * @example
 * calculateUsedMemory(50, 16) // 8.0 GB
 * calculateUsedMemory(25, 32) // 8.0 GB
 */
const calculateUsedMemory = (percent: number, totalGB: number): number => {
  return (percent / 100) * totalGB
}

/**
 * Calculates average memory usage from historical metrics
 *
 * @param history - Array of historical metrics data points
 * @returns Average memory percentage (0-100)
 */
const calculateAverage = (history: MetricsHistoryPoint[]): number => {
  if (history.length === 0) return 0
  const sum = history.reduce((acc, point) => acc + point.memory_percent, 0)
  return sum / history.length
}

/**
 * Determines color class based on memory usage percentage
 *
 * @param value - Memory percentage (0-100)
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
 * Container memory info for top consumers list
 */
interface ContainerMemoryInfo {
  name: string
  usedMB: number
  percentOfTotal: number
}

/**
 * Calculates intelligent insights based on memory usage patterns
 *
 * @param currentPercent - Current memory usage percentage
 * @param historyPoints - Historical memory metrics
 * @param topConsumers - Top memory consuming containers
 * @param totalMemoryGB - Total system memory in GB
 * @returns Array of memory insights (max 5)
 *
 * Analyzes:
 * - Critical usage (>90%)
 * - High usage (>80%)
 * - Healthy usage (<60%)
 * - Memory trend detection (increasing usage)
 * - Container memory concentration (top consumer >40%)
 */
const calculateMemoryInsights = (
  currentPercent: number,
  historyPoints: MetricsHistoryPoint[],
  topConsumers: ContainerMemoryInfo[],
  totalMemoryGB: number
): MemoryInsight[] => {
  const insights: MemoryInsight[] = []

  // Critical/High usage warnings
  if (currentPercent > 90) {
    insights.push({
      type: 'error',
      title: 'Critical Memory Usage',
      message: `Memory at ${currentPercent.toFixed(1)}% - immediate action required. Consider freeing up memory or adding capacity.`
    })
  } else if (currentPercent > 80) {
    insights.push({
      type: 'warning',
      title: 'High Memory Usage',
      message: `Memory at ${currentPercent.toFixed(1)}% - consider closing unused applications or adding capacity.`
    })
  } else if (currentPercent < 60) {
    insights.push({
      type: 'success',
      title: 'Healthy Memory Usage',
      message: `Memory usage is optimal at ${currentPercent.toFixed(1)}% with ${(totalMemoryGB * (1 - currentPercent / 100)).toFixed(1)} GB available.`
    })
  }

  // Trend detection (increasing usage pattern)
  if (historyPoints.length >= 50) {
    const recent = historyPoints.slice(-50)
    const first = recent[0].memory_percent
    const last = recent[recent.length - 1].memory_percent
    const increase = last - first

    if (increase > 10) {
      insights.push({
        type: 'warning',
        title: 'Memory Trend Increasing',
        message: `Memory usage increased by ${increase.toFixed(1)}% in last 5 minutes. Monitor for potential memory leaks.`
      })
    } else if (increase < -10) {
      insights.push({
        type: 'info',
        title: 'Memory Trend Decreasing',
        message: `Memory usage decreased by ${Math.abs(increase).toFixed(1)}% in last 5 minutes. System resources freed.`
      })
    }
  }

  // Top consumer concentration
  if (topConsumers.length > 0) {
    const topConsumer = topConsumers[0]
    if (topConsumer.percentOfTotal > 40) {
      insights.push({
        type: 'info',
        title: 'Memory Concentration',
        message: `${topConsumer.name} is using ${topConsumer.percentOfTotal.toFixed(1)}% (${formatMemoryMB(topConsumer.usedMB)}) of total memory.`
      })
    }

    // Check if multiple containers are using significant memory
    const significantConsumers = topConsumers.filter(c => c.percentOfTotal > 20)
    if (significantConsumers.length > 1) {
      const totalPercent = significantConsumers.reduce((sum, c) => sum + c.percentOfTotal, 0)
      insights.push({
        type: 'info',
        title: 'Multiple Memory Consumers',
        message: `${significantConsumers.length} containers are using ${totalPercent.toFixed(1)}% of total memory combined.`
      })
    }
  }

  // Memory leak detection - sustained high growth
  if (historyPoints.length >= 100) {
    const chunks = [
      historyPoints.slice(0, 50),
      historyPoints.slice(50, 100)
    ]
    const avgGrowth = chunks.map((chunk, i) => {
      if (i === 0) return 0
      const prevAvg = chunks[i - 1].reduce((sum, p) => sum + p.memory_percent, 0) / chunks[i - 1].length
      const currAvg = chunk.reduce((sum, p) => sum + p.memory_percent, 0) / chunk.length
      return currAvg - prevAvg
    }).filter(g => g > 0)

    if (avgGrowth.length > 0 && avgGrowth[0] > 5) {
      insights.push({
        type: 'warning',
        title: 'Possible Memory Leak',
        message: `Memory usage is steadily increasing. Check for potential memory leaks in running applications.`
      })
    }
  }

  return insights.slice(0, 5)
}

/**
 * Returns border and background color classes based on insight type
 *
 * @param type - Insight type (success/warning/error/info)
 * @returns Object with border and background color classes
 */
const getInsightColors = (type: MemoryInsight['type']) => {
  switch (type) {
    case 'success':
      return {
        border: 'border-green-200 dark:border-green-800',
        bg: 'bg-green-50 dark:bg-green-900/20',
        text: 'text-green-900 dark:text-green-100',
        icon: 'text-green-600 dark:text-green-400'
      }
    case 'warning':
      return {
        border: 'border-yellow-200 dark:border-yellow-800',
        bg: 'bg-yellow-50 dark:bg-yellow-900/20',
        text: 'text-yellow-900 dark:text-yellow-100',
        icon: 'text-yellow-600 dark:text-yellow-400'
      }
    case 'error':
      return {
        border: 'border-red-200 dark:border-red-800',
        bg: 'bg-red-50 dark:bg-red-900/20',
        text: 'text-red-900 dark:text-red-100',
        icon: 'text-red-600 dark:text-red-400'
      }
    case 'info':
      return {
        border: 'border-blue-200 dark:border-blue-800',
        bg: 'bg-blue-50 dark:bg-blue-900/20',
        text: 'text-blue-900 dark:text-blue-100',
        icon: 'text-blue-600 dark:text-blue-400'
      }
  }
}

/**
 * Returns appropriate icon component based on insight type
 *
 * @param type - Insight type (success/warning/error/info)
 * @returns Icon component
 */
const getInsightIcon = (type: MemoryInsight['type']) => {
  switch (type) {
    case 'success':
      return CheckCircle
    case 'warning':
      return AlertTriangle
    case 'error':
      return AlertTriangle
    case 'info':
      return TrendingUp
  }
}

/**
 * MemoryDetailView component displays comprehensive memory metrics including:
 * - Live memory usage graph (5-minute rolling window)
 * - Memory breakdown (total, used, available)
 * - Memory statistics (current, average, peak, min)
 * - Top memory consumers (top 5 containers by memory usage)
 * - Automatic memory insights and recommendations
 * - Container lifecycle event annotations on graph
 *
 * This component is designed to be rendered inside a modal (SystemMetricsModal)
 * and provides detailed memory analysis for system monitoring.
 *
 * @example
 * ```tsx
 * <MemoryDetailView
 *   metricsHistory={metricsHistory}
 *   systemInfo={systemInfo}
 *   currentMetrics={currentMetrics}
 *   containers={containers}
 * />
 * ```
 */
export function MemoryDetailView({
  metricsHistory,
  systemInfo,
  currentMetrics,
  containers
}: MemoryDetailViewProps): JSX.Element {
  /**
   * Transform metrics history into chart-compatible format
   * Maps container lifecycle events to chart annotations
   */
  const chartData: MetricsDataPoint[] = useMemo(() => {
    return metricsHistory.map(point => ({
      timestamp: point.timestamp,
      value: point.memory_percent,
      event: point.event
        ? {
            type: point.event.type === 'container_start' ? 'start' : 'stop',
            label: `${point.event.containerName} ${point.event.type === 'container_start' ? 'started' : 'stopped'}`
          }
        : undefined
    }))
  }, [metricsHistory])

  /**
   * Calculate memory statistics from historical data
   */
  const statistics = useMemo(() => {
    if (metricsHistory.length === 0) {
      return {
        current: currentMetrics.memory_percent,
        average: currentMetrics.memory_percent,
        peak: currentMetrics.memory_percent,
        min: currentMetrics.memory_percent
      }
    }

    const values = metricsHistory.map(point => point.memory_percent)
    return {
      current: currentMetrics.memory_percent,
      average: calculateAverage(metricsHistory),
      peak: Math.max(...values),
      min: Math.min(...values)
    }
  }, [metricsHistory, currentMetrics.memory_percent])

  /**
   * Calculate current memory breakdown
   */
  const memoryBreakdown = useMemo(() => {
    const totalGB = systemInfo.system.memory_total_gb
    const usedGB = calculateUsedMemory(currentMetrics.memory_percent, totalGB)
    const availableGB = totalGB - usedGB

    return {
      total: totalGB,
      used: usedGB,
      available: availableGB,
      usedPercent: currentMetrics.memory_percent
    }
  }, [systemInfo.system.memory_total_gb, currentMetrics.memory_percent])

  /**
   * Calculate top memory consumers from container memory_usage field
   */
  const topMemoryConsumers = useMemo(() => {
    const totalMemoryGB = systemInfo.system.memory_total_gb
    const totalMemoryMB = totalMemoryGB * 1024

    // Parse memory usage from containers and filter valid entries
    const containerMemoryInfo: ContainerMemoryInfo[] = containers
      .filter(container => container.memory_usage)
      .map(container => {
        const usedMB = parseMemoryUsage(container.memory_usage!)
        const percentOfTotal = (usedMB / totalMemoryMB) * 100

        return {
          name: container.name,
          usedMB,
          percentOfTotal
        }
      })
      .filter(info => info.usedMB > 0) // Filter out parsing errors

    // Sort by memory usage descending
    return containerMemoryInfo.sort((a, b) => b.usedMB - a.usedMB)
  }, [containers, systemInfo.system.memory_total_gb])

  /**
   * Calculate automatic memory insights
   */
  const memoryInsights = useMemo(() => {
    return calculateMemoryInsights(
      currentMetrics.memory_percent,
      metricsHistory,
      topMemoryConsumers,
      systemInfo.system.memory_total_gb
    )
  }, [currentMetrics.memory_percent, metricsHistory, topMemoryConsumers, systemInfo.system.memory_total_gb])

  return (
    <div className="space-y-6" data-testid="memory-detail-view">
      {/* Memory Usage Graph */}
      <div data-testid="memory-chart">
        <MetricsChart
          data={chartData}
          height={300}
          yAxisLabel="Memory Usage Over Time (5 Min Window)"
          yAxisDomain={[0, 100]}
          color="#10b981"
          lineLabel="Memory %"
          formatValue={(value) => `${value.toFixed(1)}%`}
          showGrid={true}
          showLegend={true}
        />
      </div>

      {/* Memory Breakdown and Statistics Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {/* Memory Breakdown Card */}
        <div
          className="bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-6"
          data-testid="memory-breakdown"
        >
          <div className="flex items-center space-x-2 mb-4">
            <MemoryStick className="w-5 h-5 text-green-600 dark:text-green-400" />
            <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
              Memory Breakdown
            </h3>
          </div>

          <div className="space-y-3">
            {/* Total Memory */}
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-600 dark:text-gray-400">
                Total:
              </span>
              <span className="text-sm font-semibold text-gray-900 dark:text-white">
                {formatMemoryGB(memoryBreakdown.total)}
              </span>
            </div>

            {/* Used Memory */}
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-600 dark:text-gray-400">
                Used:
              </span>
              <span
                className={`text-sm font-semibold ${getColorClass(memoryBreakdown.usedPercent)}`}
              >
                {formatMemoryGB(memoryBreakdown.used)} ({memoryBreakdown.usedPercent.toFixed(1)}%)
              </span>
            </div>

            {/* Available Memory */}
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-600 dark:text-gray-400">
                Available:
              </span>
              <span className="text-sm font-semibold text-gray-900 dark:text-white">
                {formatMemoryGB(memoryBreakdown.available)}
              </span>
            </div>

            {/* Memory from History (if available) */}
            {metricsHistory.length > 0 && (
              <>
                <div className="border-t border-gray-200 dark:border-gray-700 pt-2 mt-2">
                  <div className="flex items-center justify-between">
                    <span className="text-sm text-gray-600 dark:text-gray-400">
                      Used (from history):
                    </span>
                    <span className="text-sm font-semibold text-gray-900 dark:text-white">
                      {formatMemoryGB(
                        metricsHistory[metricsHistory.length - 1]?.memory_used_gb || 0
                      )}
                    </span>
                  </div>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-sm text-gray-600 dark:text-gray-400">
                    Available (from history):
                  </span>
                  <span className="text-sm font-semibold text-gray-900 dark:text-white">
                    {formatMemoryGB(
                      metricsHistory[metricsHistory.length - 1]?.memory_available_gb || 0
                    )}
                  </span>
                </div>
              </>
            )}
          </div>
        </div>

        {/* Memory Statistics Card */}
        <div
          className="bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-6"
          data-testid="memory-statistics"
        >
          <div className="flex items-center space-x-2 mb-4">
            <Activity className="w-5 h-5 text-blue-600 dark:text-blue-400" />
            <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
              Memory Statistics
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
                data-testid="memory-current-value"
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
                data-testid="memory-average-value"
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
                data-testid="memory-peak-value"
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

      {/* Top Memory Consumers */}
      <div
        className="bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-6"
        data-testid="top-memory-consumers"
      >
        <div className="flex items-center space-x-2 mb-4">
          <MemoryStick className="w-5 h-5 text-purple-600 dark:text-purple-400" />
          <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
            Top Memory Consumers
          </h3>
        </div>

        {topMemoryConsumers.length > 0 ? (
          <div className="space-y-3" data-testid="memory-consumers-list">
            {topMemoryConsumers.slice(0, 5).map((container, index) => (
              <div key={index} className="space-y-1" data-testid={`memory-consumer-${index}`}>
                <div className="flex justify-between text-sm">
                  <span className="truncate text-gray-900 dark:text-white" data-testid={`consumer-name-${index}`}>
                    {container.name}
                  </span>
                  <span className="font-semibold text-gray-900 dark:text-white ml-2" data-testid={`consumer-usage-${index}`}>
                    {formatMemoryMB(container.usedMB)}
                  </span>
                </div>
                <div className="w-full bg-gray-200 dark:bg-gray-700 rounded-full h-1.5">
                  <div
                    className="h-1.5 rounded-full bg-purple-600 dark:bg-purple-500"
                    style={{ width: `${Math.min(container.percentOfTotal, 100)}%` }}
                    data-testid={`consumer-bar-${index}`}
                  />
                </div>
              </div>
            ))}
          </div>
        ) : (
          <div className="text-sm text-gray-500 dark:text-gray-400 text-center py-4" data-testid="no-memory-data">
            No container memory data available
          </div>
        )}
      </div>

      {/* Memory Insights */}
      {memoryInsights.length > 0 && (
        <div
          className="bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-6"
          data-testid="memory-insights"
        >
          <div className="flex items-center space-x-2 mb-4">
            <Activity className="w-5 h-5 text-indigo-600 dark:text-indigo-400" />
            <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
              Memory Insights
            </h3>
          </div>

          <div className="space-y-3">
            {memoryInsights.map((insight, index) => {
              const colors = getInsightColors(insight.type)
              const Icon = getInsightIcon(insight.type)

              return (
                <div
                  key={index}
                  className={`${colors.border} ${colors.bg} border rounded-lg p-4`}
                  data-testid={`memory-insight-${index}`}
                >
                  <div className="flex items-start space-x-3">
                    <Icon className={`w-5 h-5 ${colors.icon} mt-0.5 flex-shrink-0`} />
                    <div className="flex-1">
                      <h4 className={`text-sm font-semibold ${colors.text} mb-1`}>
                        {insight.title}
                      </h4>
                      <p className={`text-xs ${colors.text} opacity-90`}>
                        {insight.message}
                      </p>
                    </div>
                  </div>
                </div>
              )
            })}
          </div>
        </div>
      )}

      {/* Memory Usage Interpretation Guide */}
      <div className="bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800 rounded-lg p-4">
        <div className="flex items-start space-x-2">
          <Info className="w-5 h-5 text-green-600 dark:text-green-400 mt-0.5 flex-shrink-0" />
          <div>
            <h4 className="text-sm font-semibold text-green-900 dark:text-green-100 mb-1">
              Memory Usage Guide
            </h4>
            <div className="text-xs text-green-800 dark:text-green-200 space-y-1">
              <p>
                <span className="text-status-healthy font-medium">&lt;60%</span>: Healthy memory usage, system has adequate resources
              </p>
              <p>
                <span className="text-status-warning font-medium">60-80%</span>: Moderate usage, consider closing unused applications
              </p>
              <p>
                <span className="text-status-error font-medium">&gt;80%</span>: High memory pressure, may affect performance
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

export default MemoryDetailView
