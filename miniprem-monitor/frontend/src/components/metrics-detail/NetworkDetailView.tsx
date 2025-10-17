'use client'

import React, { useMemo } from 'react'
import { Network, ArrowUp, ArrowDown, Activity, Info, AlertTriangle, CheckCircle } from 'lucide-react'
import { MetricsChart, MetricsDataPoint } from './MetricsChart'
import { MetricsHistoryPoint, SystemInfo, SystemMetrics, ContainerStatus } from '../../types/monitor'

/**
 * Props interface for the NetworkDetailView component
 */
export interface NetworkDetailViewProps {
  /** Historical metrics data for time-series visualization */
  metricsHistory: MetricsHistoryPoint[]
  /** System information including network specifications */
  systemInfo: SystemInfo
  /** Current real-time system metrics */
  currentMetrics: SystemMetrics
  /** Container status list (for per-container network stats) */
  containers: ContainerStatus[]
}

/**
 * Network insight type definition
 */
interface NetworkInsight {
  type: 'success' | 'info' | 'warning'
  title: string
  message: string
}

/**
 * Format bytes to human-readable size (B, KB, MB, GB)
 *
 * @param bytes - Number of bytes to format
 * @returns Formatted string with appropriate unit
 *
 * @example
 * formatBytes(1024)        // "1.0 KB"
 * formatBytes(1048576)     // "1.0 MB"
 * formatBytes(1073741824)  // "1.0 GB"
 */
const formatBytes = (bytes: number): string => {
  if (bytes === 0) return '0 B'
  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return `${parseFloat((bytes / Math.pow(k, i)).toFixed(1))} ${sizes[i]}`
}

/**
 * Format network rate (bytes/sec) to MB/s or KB/s
 *
 * @param bytesPerSec - Transfer rate in bytes per second
 * @returns Formatted string with appropriate unit
 *
 * @example
 * formatNetworkRate(1024)     // "1.0 KB/s"
 * formatNetworkRate(1048576)  // "1.0 MB/s"
 * formatNetworkRate(0)        // "0 B/s"
 */
const formatNetworkRate = (bytesPerSec: number): string => {
  if (bytesPerSec === 0) return '0 B/s'
  const mbps = bytesPerSec / (1024 * 1024)
  if (mbps >= 1) return `${mbps.toFixed(1)} MB/s`
  const kbps = bytesPerSec / 1024
  return `${kbps.toFixed(1)} KB/s`
}

/**
 * Format large numbers with K/M suffixes
 *
 * @param num - Number to format
 * @returns Formatted string with K or M suffix
 *
 * @example
 * formatLargeNumber(1500)     // "1.5K"
 * formatLargeNumber(1500000)  // "1.5M"
 * formatLargeNumber(500)      // "500"
 */
const formatLargeNumber = (num: number): string => {
  if (num >= 1000000) return `${(num / 1000000).toFixed(1)}M`
  if (num >= 1000) return `${(num / 1000).toFixed(1)}K`
  return num.toString()
}

/**
 * Parse and sort containers by network usage
 *
 * @param containers - List of container statuses
 * @returns Sorted list of containers with network usage data
 */
const parseNetworkConsumers = (containers: ContainerStatus[]) => {
  return containers
    .filter(c => c.network_tx_bytes !== undefined && c.network_rx_bytes !== undefined)
    .map(c => ({
      name: c.name,
      txBytes: c.network_tx_bytes || 0,
      rxBytes: c.network_rx_bytes || 0,
      totalBytes: (c.network_tx_bytes || 0) + (c.network_rx_bytes || 0)
    }))
    .sort((a, b) => b.totalBytes - a.totalBytes)
}

/**
 * Calculate automatic network insights based on metrics analysis
 *
 * Analyzes network patterns to provide intelligent insights about:
 * - High bandwidth usage (> 100 MB/s peak)
 * - Upload/download traffic imbalance
 * - Low network activity (healthy state)
 * - Top network consumers with significant usage
 *
 * @param peakUpload - Peak upload rate in bytes/sec
 * @param peakDownload - Peak download rate in bytes/sec
 * @param avgUpload - Average upload rate in bytes/sec
 * @param avgDownload - Average download rate in bytes/sec
 * @param topConsumers - List of top network consuming containers
 * @returns Array of network insights (max 5)
 *
 * @example
 * const insights = calculateNetworkInsights(
 *   150 * 1024 * 1024, // 150 MB/s peak upload
 *   50 * 1024 * 1024,  // 50 MB/s peak download
 *   100 * 1024 * 1024, // 100 MB/s avg upload
 *   40 * 1024 * 1024,  // 40 MB/s avg download
 *   topConsumers
 * )
 */
const calculateNetworkInsights = (
  peakUpload: number,
  peakDownload: number,
  avgUpload: number,
  avgDownload: number,
  topConsumers: Array<{name: string, totalBytes: number, txBytes: number, rxBytes: number}>
): NetworkInsight[] => {
  const insights: NetworkInsight[] = []

  // Convert to MB/s for analysis
  const peakUploadMBps = peakUpload / (1024 * 1024)
  const peakDownloadMBps = peakDownload / (1024 * 1024)
  const avgUploadMBps = avgUpload / (1024 * 1024)
  const avgDownloadMBps = avgDownload / (1024 * 1024)

  // High bandwidth detection
  if (peakUploadMBps > 100 || peakDownloadMBps > 100) {
    const maxMBps = Math.max(peakUploadMBps, peakDownloadMBps)
    const direction = peakUploadMBps > peakDownloadMBps ? 'upload' : 'download'
    insights.push({
      type: 'warning',
      title: 'High Bandwidth Usage',
      message: `Peak ${direction} rate: ${maxMBps.toFixed(1)} MB/s`
    })
  }

  // Upload/Download imbalance detection
  const ratio = peakUpload / (peakDownload || 1)
  if (ratio > 5) {
    insights.push({
      type: 'info',
      title: 'Upload-Heavy Traffic',
      message: `Upload is ${ratio.toFixed(1)}x higher than download`
    })
  } else if (ratio < 0.2) {
    insights.push({
      type: 'info',
      title: 'Download-Heavy Traffic',
      message: `Download is ${(1/ratio).toFixed(1)}x higher than upload`
    })
  }

  // Sustained high traffic detection
  if (avgUploadMBps > 50 || avgDownloadMBps > 50) {
    const maxAvgMBps = Math.max(avgUploadMBps, avgDownloadMBps)
    insights.push({
      type: 'info',
      title: 'Sustained High Traffic',
      message: `Average rate consistently at ${maxAvgMBps.toFixed(1)} MB/s`
    })
  }

  // Low activity (healthy state)
  if (peakUploadMBps < 10 && peakDownloadMBps < 10) {
    insights.push({
      type: 'success',
      title: 'Low Network Activity',
      message: 'Network usage is minimal and efficient'
    })
  }

  // Top consumer analysis
  if (topConsumers.length > 0) {
    const topContainer = topConsumers[0]
    const topMB = topContainer.totalBytes / (1024 * 1024)

    if (topMB > 1000) {
      insights.push({
        type: 'info',
        title: 'High Network Consumer',
        message: `${topContainer.name} has transferred ${(topMB / 1024).toFixed(1)} GB`
      })
    }

    // Check if one container dominates (> 80% of total)
    if (topConsumers.length > 1) {
      const totalBytes = topConsumers.reduce((sum, c) => sum + c.totalBytes, 0)
      const topPercentage = (topContainer.totalBytes / totalBytes) * 100

      if (topPercentage > 80) {
        insights.push({
          type: 'warning',
          title: 'Bandwidth Dominated',
          message: `${topContainer.name} using ${topPercentage.toFixed(0)}% of total bandwidth`
        })
      }
    }
  }

  // Return max 5 insights
  return insights.slice(0, 5)
}

/**
 * NetworkDetailView component displays comprehensive network metrics including:
 * - Dual-line network throughput graph (Upload TX + Download RX)
 * - Network statistics (total sent/received, packets)
 * - Transfer statistics (current and peak rates)
 * - Automatic network insights (bandwidth patterns, traffic analysis)
 * - Top network consumers by container
 * - Container lifecycle event annotations on graph
 *
 * This component is designed to be rendered inside a modal (SystemMetricsModal)
 * and provides detailed network I/O analysis for system monitoring.
 *
 * Features:
 * - Green line for Upload (TX) traffic
 * - Blue line for Download (RX) traffic
 * - 5-minute rolling window with real-time updates
 * - Automatic rate conversion (bytes/sec to MB/s)
 * - Peak transfer rate tracking
 * - Intelligent insights for network patterns
 * - Per-container network usage breakdown
 *
 * @example
 * ```tsx
 * <NetworkDetailView
 *   metricsHistory={metricsHistory}
 *   systemInfo={systemInfo}
 *   currentMetrics={currentMetrics}
 *   containers={containers}
 * />
 * ```
 */
export function NetworkDetailView({
  metricsHistory,
  systemInfo,
  currentMetrics,
  containers
}: NetworkDetailViewProps): JSX.Element {
  /**
   * Transform metrics history into chart-compatible format
   * Converts bytes/sec to MB/s for better readability
   * Maps container lifecycle events to chart annotations
   */
  const chartData: MetricsDataPoint[] = useMemo(() => {
    return metricsHistory.map(point => ({
      timestamp: point.timestamp,
      value: point.network_sent_rate / (1024 * 1024), // Convert to MB/s
      value2: point.network_recv_rate / (1024 * 1024), // Convert to MB/s
      event: point.event
        ? {
            type: point.event.type === 'container_start' ? 'start' : 'stop',
            label: `${point.event.containerName} ${point.event.type === 'container_start' ? 'started' : 'stopped'}`
          }
        : undefined
    }))
  }, [metricsHistory])

  /**
   * Calculate network transfer statistics from historical data
   */
  const transferStats = useMemo(() => {
    if (metricsHistory.length === 0) {
      return {
        currentUpload: 0,
        currentDownload: 0,
        peakUpload: 0,
        peakDownload: 0,
        avgUpload: 0,
        avgDownload: 0
      }
    }

    const latestPoint = metricsHistory[metricsHistory.length - 1]
    const uploadRates = metricsHistory.map(point => point.network_sent_rate)
    const downloadRates = metricsHistory.map(point => point.network_recv_rate)

    return {
      currentUpload: latestPoint.network_sent_rate,
      currentDownload: latestPoint.network_recv_rate,
      peakUpload: Math.max(...uploadRates),
      peakDownload: Math.max(...downloadRates),
      avgUpload: uploadRates.reduce((sum, rate) => sum + rate, 0) / uploadRates.length,
      avgDownload: downloadRates.reduce((sum, rate) => sum + rate, 0) / downloadRates.length
    }
  }, [metricsHistory])

  /**
   * Calculate dynamic Y-axis domain based on peak values
   * Ensures chart scaling adapts to actual traffic levels
   */
  const yAxisDomain = useMemo<[number, number]>(() => {
    const maxRate = Math.max(transferStats.peakUpload, transferStats.peakDownload)
    const maxMbps = maxRate / (1024 * 1024)

    // Round up to nearest nice number
    if (maxMbps < 1) return [0, 1]
    if (maxMbps < 10) return [0, Math.ceil(maxMbps)]
    if (maxMbps < 100) return [0, Math.ceil(maxMbps / 10) * 10]
    return [0, Math.ceil(maxMbps / 100) * 100]
  }, [transferStats.peakUpload, transferStats.peakDownload])

  /**
   * Parse and sort top network consumers
   */
  const topNetworkConsumers = useMemo(() => {
    return parseNetworkConsumers(containers)
  }, [containers])

  /**
   * Calculate automatic network insights
   */
  const networkInsights = useMemo(() => {
    if (metricsHistory.length < 5) {
      return [] // Not enough data for insights
    }

    return calculateNetworkInsights(
      transferStats.peakUpload,
      transferStats.peakDownload,
      transferStats.avgUpload,
      transferStats.avgDownload,
      topNetworkConsumers
    )
  }, [metricsHistory.length, transferStats, topNetworkConsumers])

  return (
    <div className="space-y-6" data-testid="network-detail-view">
      {/* Network Throughput Graph */}
      <div data-testid="network-chart">
        <MetricsChart
          data={chartData}
          height={300}
          yAxisLabel="Network Throughput (5 Min Window)"
          yAxisDomain={yAxisDomain}
          color="#10b981" // Green for upload
          color2="#3b82f6" // Blue for download
          lineLabel="Upload (TX)"
          lineLabel2="Download (RX)"
          formatValue={(value) => `${value.toFixed(2)} MB/s`}
          showGrid={true}
          showLegend={true}
        />
      </div>

      {/* Network Statistics and Transfer Statistics Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {/* Network Statistics Card */}
        <div
          className="bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-6"
          data-testid="network-statistics"
        >
          <div className="flex items-center space-x-2 mb-4">
            <Network className="w-5 h-5 text-blue-600 dark:text-blue-400" />
            <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
              Network Stats
            </h3>
          </div>

          <div className="space-y-3">
            {/* Total Sent */}
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-600 dark:text-gray-400 flex items-center">
                <ArrowUp className="w-4 h-4 mr-1 text-green-600 dark:text-green-400" />
                Total Sent:
              </span>
              <span className="text-sm font-semibold text-gray-900 dark:text-white">
                {formatBytes(currentMetrics.network_io.bytes_sent)}
              </span>
            </div>

            {/* Total Received */}
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-600 dark:text-gray-400 flex items-center">
                <ArrowDown className="w-4 h-4 mr-1 text-blue-600 dark:text-blue-400" />
                Total Recv:
              </span>
              <span className="text-sm font-semibold text-gray-900 dark:text-white">
                {formatBytes(currentMetrics.network_io.bytes_recv)}
              </span>
            </div>

            {/* Packets Sent */}
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-600 dark:text-gray-400">
                Packets Sent:
              </span>
              <span className="text-sm font-semibold text-gray-900 dark:text-white">
                {formatLargeNumber(currentMetrics.network_io.packets_sent)}
              </span>
            </div>

            {/* Packets Received */}
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-600 dark:text-gray-400">
                Packets Recv:
              </span>
              <span className="text-sm font-semibold text-gray-900 dark:text-white">
                {formatLargeNumber(currentMetrics.network_io.packets_recv)}
              </span>
            </div>
          </div>
        </div>

        {/* Transfer Statistics Card */}
        <div
          className="bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-6"
          data-testid="transfer-statistics"
        >
          <div className="flex items-center space-x-2 mb-4">
            <Activity className="w-5 h-5 text-green-600 dark:text-green-400" />
            <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
              Transfer Statistics
            </h3>
          </div>

          <div className="space-y-3">
            {/* Current Upload */}
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-600 dark:text-gray-400 flex items-center">
                <ArrowUp className="w-4 h-4 mr-1 text-green-600 dark:text-green-400" />
                Current Upload:
              </span>
              <span className="text-sm font-semibold text-green-600 dark:text-green-400">
                {formatNetworkRate(transferStats.currentUpload)}
              </span>
            </div>

            {/* Current Download */}
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-600 dark:text-gray-400 flex items-center">
                <ArrowDown className="w-4 h-4 mr-1 text-blue-600 dark:text-blue-400" />
                Current Download:
              </span>
              <span className="text-sm font-semibold text-blue-600 dark:text-blue-400">
                {formatNetworkRate(transferStats.currentDownload)}
              </span>
            </div>

            {/* Peak Upload */}
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-600 dark:text-gray-400">
                Peak Upload:
              </span>
              <span className="text-sm font-semibold text-gray-900 dark:text-white">
                {formatNetworkRate(transferStats.peakUpload)}
              </span>
            </div>

            {/* Peak Download */}
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-600 dark:text-gray-400">
                Peak Download:
              </span>
              <span className="text-sm font-semibold text-gray-900 dark:text-white">
                {formatNetworkRate(transferStats.peakDownload)}
              </span>
            </div>
          </div>
        </div>
      </div>

      {/* Top Network Consumers */}
      <div
        className="bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-6"
        data-testid="top-network-consumers"
      >
        <h4 className="text-sm font-semibold mb-4 flex items-center text-gray-900 dark:text-white">
          <Network className="w-4 h-4 mr-2 text-blue-600 dark:text-blue-400" />
          Top Network Consumers
        </h4>
        {topNetworkConsumers.length > 0 ? (
          <div className="space-y-3">
            {topNetworkConsumers.slice(0, 5).map((container, index) => (
              <div
                key={index}
                className="space-y-1"
                data-testid={`network-consumer-${index}`}
              >
                <div className="flex justify-between text-sm">
                  <span
                    className="truncate text-gray-900 dark:text-white mr-2"
                    title={container.name}
                  >
                    {container.name}
                  </span>
                  <span
                    className="font-semibold text-gray-900 dark:text-white whitespace-nowrap"
                    data-testid={`consumer-total-${index}`}
                  >
                    {formatBytes(container.totalBytes)}
                  </span>
                </div>
                <div className="flex text-xs text-gray-600 dark:text-gray-400 space-x-4">
                  <span
                    className="text-green-600 dark:text-green-400"
                    data-testid={`consumer-upload-${index}`}
                  >
                    ↑ {formatBytes(container.txBytes)}
                  </span>
                  <span
                    className="text-blue-600 dark:text-blue-400"
                    data-testid={`consumer-download-${index}`}
                  >
                    ↓ {formatBytes(container.rxBytes)}
                  </span>
                </div>
              </div>
            ))}
          </div>
        ) : (
          <p
            className="text-sm text-gray-500 dark:text-gray-400"
            data-testid="no-network-stats"
          >
            Per-container network stats not available
          </p>
        )}
      </div>

      {/* Network Insights */}
      <div
        className="bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-6"
        data-testid="network-insights"
      >
        <h4 className="text-sm font-semibold mb-4 flex items-center text-gray-900 dark:text-white">
          <Activity className="w-4 h-4 mr-2 text-purple-600 dark:text-purple-400" />
          Network Insights
        </h4>
        {networkInsights.length > 0 ? (
          <div className="space-y-3">
            {networkInsights.map((insight, index) => {
              const IconComponent = insight.type === 'success'
                ? CheckCircle
                : insight.type === 'warning'
                ? AlertTriangle
                : Info

              const colorClasses = insight.type === 'success'
                ? 'text-green-600 dark:text-green-400 bg-green-50 dark:bg-green-900/20 border-green-200 dark:border-green-800'
                : insight.type === 'warning'
                ? 'text-amber-600 dark:text-amber-400 bg-amber-50 dark:bg-amber-900/20 border-amber-200 dark:border-amber-800'
                : 'text-blue-600 dark:text-blue-400 bg-blue-50 dark:bg-blue-900/20 border-blue-200 dark:border-blue-800'

              return (
                <div
                  key={index}
                  className={`flex items-start space-x-2 p-3 rounded-lg border ${colorClasses}`}
                  data-testid={`network-insight-${index}`}
                >
                  <IconComponent className="w-4 h-4 mt-0.5 flex-shrink-0" />
                  <div className="flex-1 min-w-0">
                    <div className="text-sm font-semibold" data-testid={`insight-title-${index}`}>
                      {insight.title}
                    </div>
                    <div className="text-xs mt-0.5 opacity-90" data-testid={`insight-message-${index}`}>
                      {insight.message}
                    </div>
                  </div>
                </div>
              )
            })}
          </div>
        ) : (
          <p
            className="text-sm text-gray-500 dark:text-gray-400"
            data-testid="insufficient-network-data"
          >
            Insufficient data for insights. Collecting network metrics...
          </p>
        )}
      </div>

      {/* Network Usage Guide */}
      <div className="bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800 rounded-lg p-4">
        <div className="flex items-start space-x-2">
          <Network className="w-5 h-5 text-blue-600 dark:text-blue-400 mt-0.5 flex-shrink-0" />
          <div>
            <h4 className="text-sm font-semibold text-blue-900 dark:text-blue-100 mb-1">
              Network Throughput Guide
            </h4>
            <div className="text-xs text-blue-800 dark:text-blue-200 space-y-1">
              <p>
                <span className="text-green-600 dark:text-green-400 font-medium">Upload (TX)</span>: Outbound traffic from this system (green line)
              </p>
              <p>
                <span className="text-blue-600 dark:text-blue-400 font-medium">Download (RX)</span>: Inbound traffic to this system (blue line)
              </p>
              <p>
                Sustained high transfer rates may indicate active data transfers, backups, or streaming workloads
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

export default NetworkDetailView
