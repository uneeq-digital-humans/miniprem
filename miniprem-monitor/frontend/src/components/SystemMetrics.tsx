'use client'

import React, { useState, useEffect, useCallback, useMemo } from 'react'
import {
  Activity,
  Cpu,
  HardDrive,
  MemoryStick,
  Network,
  RefreshCw,
  AlertTriangle,
  TrendingUp,
  Clock
} from 'lucide-react'
import { SystemMetrics as SystemMetricsType } from '../types/monitor'

/**
 * Props interface for the SystemMetrics component
 */
interface SystemMetricsProps {
  /** Current system metrics data */
  metrics?: SystemMetricsType | null
  /** Whether the component is currently loading data */
  loading?: boolean
  /** Whether to show historical trend indicators */
  showTrends?: boolean
  /** Refresh interval in milliseconds (0 to disable auto-refresh) */
  refreshInterval?: number
  /** Callback function called when refresh is triggered */
  onRefresh?: () => void
  /** Callback function called when an error occurs */
  onError?: (error: Error) => void
  /** Custom CSS class name */
  className?: string
}

/**
 * Interface for metric trend data
 */
interface MetricTrend {
  current: number
  previous: number
  direction: 'up' | 'down' | 'stable'
  change: number
}

/**
 * Interface for internal component state
 */
interface ComponentState {
  error: string | null
  lastUpdate: string | null
  trends: Record<string, MetricTrend>
}

/**
 * SystemMetrics component displays real-time system performance metrics
 * including CPU, memory, disk usage, and network I/O statistics.
 *
 * Features:
 * - Real-time metrics display with color-coded status indicators
 * - Loading states with skeleton animations
 * - Error handling and user feedback
 * - Optional trend indicators for metric changes
 * - Auto-refresh functionality
 * - Responsive grid layout
 *
 * @param props - Component props
 * @returns JSX.Element
 *
 * @example
 * ```tsx
 * // Basic usage
 * <SystemMetrics
 *   metrics={systemMetrics}
 *   loading={isLoading}
 * />
 *
 * // With auto-refresh and trends
 * <SystemMetrics
 *   metrics={systemMetrics}
 *   loading={isLoading}
 *   showTrends={true}
 *   refreshInterval={5000}
 *   onRefresh={handleRefresh}
 *   onError={handleError}
 * />
 * ```
 */
export function SystemMetrics({
  metrics,
  loading = false,
  showTrends = false,
  refreshInterval = 0,
  onRefresh,
  onError,
  className = ''
}: SystemMetricsProps): JSX.Element {
  const [state, setState] = useState<ComponentState>({
    error: null,
    lastUpdate: null,
    trends: {}
  })

  /**
   * Formats bytes to human-readable format
   * @param bytes - Number of bytes to format
   * @returns Formatted string with appropriate unit
   */
  const formatBytes = useCallback((bytes: number): string => {
    if (bytes === 0) return '0 B'
    const k = 1024
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB']
    const i = Math.floor(Math.log(bytes) / Math.log(k))
    return `${parseFloat((bytes / Math.pow(k, i)).toFixed(1))} ${sizes[i]}`
  }, [])

  /**
   * Determines color class based on usage percentage
   * @param percentage - Usage percentage (0-100)
   * @returns Tailwind CSS color class
   */
  const getUsageColor = useCallback((percentage: number): string => {
    if (percentage < 60) return 'text-status-healthy'
    if (percentage < 80) return 'text-status-warning'
    return 'text-status-error'
  }, [])

  /**
   * Calculates trend for a metric value
   * @param key - Metric identifier
   * @param current - Current metric value
   * @returns Trend information
   */
  const calculateTrend = useCallback((key: string, current: number): MetricTrend => {
    const previous = state.trends[key]?.current ?? current
    const change = current - previous
    const direction = Math.abs(change) < 0.1 ? 'stable' : change > 0 ? 'up' : 'down'

    return {
      current,
      previous,
      direction,
      change: Math.abs(change)
    }
  }, [state.trends])

  /**
   * Updates metric trends when new data arrives
   */
  const updateTrends = useCallback((newMetrics: SystemMetricsType) => {
    if (!showTrends) return

    const newTrends = {
      cpu: calculateTrend('cpu', newMetrics.cpu_percent),
      memory: calculateTrend('memory', newMetrics.memory_percent),
      disk: calculateTrend('disk', newMetrics.disk_percent)
    }

    setState(prev => ({
      ...prev,
      trends: newTrends,
      lastUpdate: new Date().toISOString(),
      error: null
    }))
  }, [showTrends, calculateTrend])

  /**
   * Handles refresh button click
   */
  const handleRefresh = useCallback(() => {
    try {
      onRefresh?.()
      setState(prev => ({ ...prev, error: null }))
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to refresh metrics'
      setState(prev => ({ ...prev, error: errorMessage }))
      onError?.(error instanceof Error ? error : new Error(errorMessage))
    }
  }, [onRefresh, onError])

  /**
   * Auto-refresh effect
   */
  useEffect(() => {
    if (refreshInterval <= 0 || !onRefresh) return

    const interval = setInterval(handleRefresh, refreshInterval)
    return () => clearInterval(interval)
  }, [refreshInterval, handleRefresh, onRefresh])

  /**
   * Update trends when metrics change
   */
  useEffect(() => {
    if (metrics && !loading) {
      updateTrends(metrics)
    }
  }, [metrics, loading, updateTrends])

  /**
   * Memoized trend indicator component
   */
  const TrendIndicator = useMemo(() => {
    return React.memo(({ trend }: { trend: MetricTrend }) => {
      if (trend.direction === 'stable') return null

      const isUp = trend.direction === 'up'
      return (
        <div className={`flex items-center text-xs ml-2 ${
          isUp ? 'text-status-warning' : 'text-status-healthy'
        }`}>
          <TrendingUp
            className={`w-3 h-3 ${isUp ? '' : 'transform rotate-180'}`}
          />
          <span className="ml-1">
            {trend.change.toFixed(1)}%
          </span>
        </div>
      )
    })
  }, [])

  /**
   * Loading skeleton component
   */
  if (loading) {
    return (
      <div className={`${className}`}>
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-lg font-semibold text-uneeq-text">System Metrics</h2>
          <RefreshCw className="w-5 h-5 text-gray-400 animate-spin" />
        </div>

        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
          {Array.from({ length: 4 }).map((_, index) => (
            <div key={index} className="metric-card animate-pulse">
              <div className="flex items-center justify-between">
                <div className="flex flex-col space-y-2">
                  <div className="h-4 bg-gray-200 rounded w-20"></div>
                  <div className="h-8 bg-gray-200 rounded w-16"></div>
                </div>
                <div className="w-8 h-8 bg-gray-200 rounded"></div>
              </div>
            </div>
          ))}
        </div>
      </div>
    )
  }

  /**
   * Error state component
   */
  if (state.error) {
    return (
      <div className={`${className}`}>
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-lg font-semibold text-uneeq-text">System Metrics</h2>
          <button
            onClick={handleRefresh}
            className="flex items-center space-x-2 px-3 py-1 text-sm bg-uneeq-secondary hover:bg-opacity-80 rounded transition-colors"
            disabled={loading}
          >
            <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
            <span>Retry</span>
          </button>
        </div>

        <div className="metric-card border-status-error">
          <div className="flex items-center space-x-3 text-status-error">
            <AlertTriangle className="w-6 h-6" />
            <div>
              <div className="font-medium">Failed to load metrics</div>
              <div className="text-sm text-gray-500 mt-1">{state.error}</div>
            </div>
          </div>
        </div>
      </div>
    )
  }

  /**
   * No data state component
   */
  if (!metrics) {
    return (
      <div className={`${className}`}>
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-lg font-semibold text-uneeq-text">System Metrics</h2>
          {onRefresh && (
            <button
              onClick={handleRefresh}
              className="flex items-center space-x-2 px-3 py-1 text-sm bg-uneeq-secondary hover:bg-opacity-80 rounded transition-colors"
            >
              <RefreshCw className="w-4 h-4" />
              <span>Refresh</span>
            </button>
          )}
        </div>

        <div className="metric-card">
          <div className="text-center text-gray-500 py-8">
            <Activity className="w-12 h-12 mx-auto mb-3 opacity-50" />
            <div className="font-medium">No metrics available</div>
            <div className="text-sm mt-1">System metrics data is not available</div>
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className={`${className}`}>
      {/* Header */}
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-lg font-semibold text-uneeq-text">System Metrics</h2>
        <div className="flex items-center space-x-3">
          {state.lastUpdate && (
            <div className="flex items-center text-xs text-gray-500">
              <Clock className="w-3 h-3 mr-1" />
              <span>
                Updated {new Date(state.lastUpdate).toLocaleTimeString()}
              </span>
            </div>
          )}
          {onRefresh && (
            <button
              onClick={handleRefresh}
              className="flex items-center space-x-2 px-3 py-1 text-sm bg-uneeq-secondary hover:bg-opacity-80 rounded transition-colors"
              disabled={loading}
            >
              <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
              <span>Refresh</span>
            </button>
          )}
        </div>
      </div>

      {/* Metrics Grid */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        {/* CPU Usage */}
        <div className="metric-card">
          <div className="flex items-center justify-between">
            <div>
              <div className="metric-label">CPU Usage</div>
              <div className={`metric-value ${getUsageColor(metrics.cpu_percent)}`}>
                {metrics.cpu_percent.toFixed(1)}%
              </div>
              {showTrends && state.trends.cpu && (
                <TrendIndicator trend={state.trends.cpu} />
              )}
            </div>
            <Cpu className="metric-icon" />
          </div>
        </div>

        {/* Memory Usage */}
        <div className="metric-card">
          <div className="flex items-center justify-between">
            <div>
              <div className="metric-label">Memory</div>
              <div className={`metric-value ${getUsageColor(metrics.memory_percent)}`}>
                {metrics.memory_percent.toFixed(1)}%
              </div>
              {showTrends && state.trends.memory && (
                <TrendIndicator trend={state.trends.memory} />
              )}
            </div>
            <MemoryStick className="metric-icon" />
          </div>
        </div>

        {/* Disk Usage */}
        <div className="metric-card">
          <div className="flex items-center justify-between">
            <div>
              <div className="metric-label">Disk Usage</div>
              <div className={`metric-value ${getUsageColor(metrics.disk_percent)}`}>
                {metrics.disk_percent.toFixed(1)}%
              </div>
              {showTrends && state.trends.disk && (
                <TrendIndicator trend={state.trends.disk} />
              )}
            </div>
            <HardDrive className="metric-icon" />
          </div>
        </div>

        {/* Network I/O */}
        <div className="metric-card">
          <div className="flex items-center justify-between">
            <div>
              <div className="metric-label">Network I/O</div>
              <div className="flex flex-col text-sm space-y-1">
                <div className="flex items-center text-status-healthy">
                  <span className="mr-1">↑</span>
                  <span>{formatBytes(metrics.network_io.bytes_sent)}</span>
                </div>
                <div className="flex items-center text-uneeq-primary">
                  <span className="mr-1">↓</span>
                  <span>{formatBytes(metrics.network_io.bytes_recv)}</span>
                </div>
              </div>
            </div>
            <Network className="metric-icon" />
          </div>
        </div>
      </div>

      {/* Additional Network Stats */}
      {metrics.network_io.packets_sent > 0 && (
        <div className="mt-4 p-3 bg-gray-50 rounded-lg">
          <div className="text-sm text-gray-600 mb-2">Network Packets</div>
          <div className="grid grid-cols-2 gap-4 text-xs">
            <div className="flex justify-between">
              <span>Sent:</span>
              <span className="font-medium">{metrics.network_io.packets_sent.toLocaleString()}</span>
            </div>
            <div className="flex justify-between">
              <span>Received:</span>
              <span className="font-medium">{metrics.network_io.packets_recv.toLocaleString()}</span>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

export default SystemMetrics