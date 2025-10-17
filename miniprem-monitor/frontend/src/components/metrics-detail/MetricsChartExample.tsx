'use client'

import React, { useState, useEffect } from 'react'
import { MetricsChart, MetricsDataPoint } from './MetricsChart'

/**
 * Example component demonstrating MetricsChart usage with simulated live data
 *
 * This component shows how to:
 * - Maintain a rolling 5-minute window of metrics
 * - Update charts in real-time via WebSocket or polling
 * - Display single-line (CPU, Memory, Disk) charts
 * - Display dual-line (Network) charts
 * - Add event annotations for container lifecycle events
 *
 * @example
 * ```tsx
 * import { MetricsChartExample } from '@/components/metrics-detail/MetricsChartExample'
 *
 * <MetricsChartExample />
 * ```
 */
export function MetricsChartExample(): JSX.Element {
  const [cpuData, setCpuData] = useState<MetricsDataPoint[]>([])
  const [memoryData, setMemoryData] = useState<MetricsDataPoint[]>([])
  const [diskData, setDiskData] = useState<MetricsDataPoint[]>([])
  const [networkData, setNetworkData] = useState<MetricsDataPoint[]>([])

  /**
   * Simulate live metrics updates every 2 seconds
   * In production, replace this with WebSocket subscription:
   *
   * useEffect(() => {
   *   const ws = new WebSocket('ws://localhost:8000/ws/metrics')
   *   ws.onmessage = (event) => {
   *     const metrics = JSON.parse(event.data)
   *     updateMetrics(metrics)
   *   }
   *   return () => ws.close()
   * }, [])
   */
  useEffect(() => {
    const interval = setInterval(() => {
      const now = new Date()

      // Simulate CPU usage (20-80%)
      setCpuData(prev => {
        const newData = [
          ...prev,
          {
            timestamp: now,
            value: 30 + Math.random() * 50
          }
        ]
        // Keep last 60 data points (5 minutes at 5-second intervals)
        return newData.slice(-60)
      })

      // Simulate Memory usage (40-90%)
      setMemoryData(prev => {
        const newData = [
          ...prev,
          {
            timestamp: now,
            value: 50 + Math.random() * 40
          }
        ]
        return newData.slice(-60)
      })

      // Simulate Disk usage (slowly increasing)
      setDiskData(prev => {
        const newData = [
          ...prev,
          {
            timestamp: now,
            value: 60 + Math.random() * 5
          }
        ]
        return newData.slice(-60)
      })

      // Simulate Network I/O (dual-line chart)
      setNetworkData(prev => {
        const newData = [
          ...prev,
          {
            timestamp: now,
            value: 100 + Math.random() * 200,  // Sent
            value2: 150 + Math.random() * 300  // Received
          }
        ]
        return newData.slice(-60)
      })
    }, 2000) // Update every 2 seconds

    return () => clearInterval(interval)
  }, [])

  /**
   * Simulate a container restart event after 10 seconds
   */
  useEffect(() => {
    const timeout = setTimeout(() => {
      const now = new Date()

      setMemoryData(prev => [
        ...prev,
        {
          timestamp: now,
          value: 45.2,
          event: {
            type: 'restart',
            label: 'Container restarted'
          }
        }
      ])
    }, 10000)

    return () => clearTimeout(timeout)
  }, [])

  return (
    <div className="space-y-6 p-6">
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900 dark:text-white mb-2">
          MetricsChart Examples
        </h1>
        <p className="text-sm text-gray-600 dark:text-gray-400">
          Live demonstration of time-series metrics visualization
        </p>
      </div>

      {/* CPU Usage Chart */}
      <div>
        <h2 className="text-lg font-semibold text-gray-800 dark:text-gray-200 mb-3">
          CPU Usage (Single-line chart)
        </h2>
        <MetricsChart
          data={cpuData}
          yAxisLabel="CPU Usage"
          color="#3b82f6"
          lineLabel="CPU %"
          height={250}
        />
      </div>

      {/* Memory Usage Chart with Event */}
      <div>
        <h2 className="text-lg font-semibold text-gray-800 dark:text-gray-200 mb-3">
          Memory Usage (With event annotation)
        </h2>
        <MetricsChart
          data={memoryData}
          yAxisLabel="Memory Usage"
          color="#8b5cf6"
          lineLabel="Memory %"
          height={250}
        />
      </div>

      {/* Disk Usage Chart */}
      <div>
        <h2 className="text-lg font-semibold text-gray-800 dark:text-gray-200 mb-3">
          Disk Usage
        </h2>
        <MetricsChart
          data={diskData}
          yAxisLabel="Disk Usage"
          color="#f59e0b"
          lineLabel="Disk %"
          height={250}
        />
      </div>

      {/* Network I/O Chart (Dual-line) */}
      <div>
        <h2 className="text-lg font-semibold text-gray-800 dark:text-gray-200 mb-3">
          Network I/O (Dual-line chart)
        </h2>
        <MetricsChart
          data={networkData}
          yAxisLabel="Network Bandwidth"
          yAxisDomain={[0, 500]}
          color="#10b981"
          color2="#ef4444"
          lineLabel="Sent (MB/s)"
          lineLabel2="Received (MB/s)"
          formatValue={(v) => `${v.toFixed(0)} MB/s`}
          height={250}
        />
      </div>

      {/* Usage Instructions */}
      <div className="mt-8 p-6 bg-blue-50 dark:bg-blue-900/20 rounded-lg border border-blue-200 dark:border-blue-800">
        <h3 className="text-sm font-semibold text-blue-900 dark:text-blue-300 mb-2">
          Integration Guide
        </h3>
        <p className="text-xs text-blue-800 dark:text-blue-400 mb-3">
          To integrate MetricsChart with real-time data:
        </p>
        <pre className="text-xs bg-white dark:bg-gray-800 p-3 rounded border border-blue-200 dark:border-blue-700 overflow-x-auto">
{`const [metrics, setMetrics] = useState<MetricsDataPoint[]>([])

useEffect(() => {
  const ws = new WebSocket('ws://localhost:8000/ws/metrics')

  ws.onmessage = (event) => {
    const data = JSON.parse(event.data)

    setMetrics(prev => {
      const newData = [...prev, {
        timestamp: new Date(),
        value: data.cpu_percent
      }]

      // Keep last 60 points (5 minutes)
      return newData.slice(-60)
    })
  }

  return () => ws.close()
}, [])`}
        </pre>
      </div>
    </div>
  )
}

export default MetricsChartExample
