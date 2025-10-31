'use client'

import React from 'react'
import { Zap, Activity, Server, Thermometer, CheckCircle, AlertTriangle, AlertCircle, Info } from 'lucide-react'
import { SystemInfo, SystemMetrics, ContainerStatus, GpuStats } from '../../types/monitor'

/**
 * Props interface for the GpuDetailView component
 */
export interface GpuDetailViewProps {
  /** System information */
  systemInfo: SystemInfo
  /** Current real-time system metrics */
  currentMetrics: SystemMetrics
  /** Container status list */
  containers: ContainerStatus[]
}

/**
 * Interface for GPU insights that provide automatic system analysis
 */
interface GpuInsight {
  /** Insight severity level */
  type: 'success' | 'warning' | 'error' | 'info'
  /** Short descriptive title */
  title: string
  /** Detailed explanation message */
  message: string
}

/**
 * Returns styling classes for insight cards based on type
 */
const getInsightStyles = (type: GpuInsight['type']): string => {
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
 */
const InsightIcon: React.FC<{ type: GpuInsight['type'] }> = ({ type }) => {
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
 * Generates automatic insights based on GPU statistics
 */
const generateGpuInsights = (gpus: GpuStats[]): GpuInsight[] => {
  const insights: GpuInsight[] = []

  if (gpus.length === 0) {
    insights.push({
      type: 'info',
      title: 'GPU Status',
      message: 'N/A'
    })
    return insights
  }

  // Check for high temperature
  const hotGpus = gpus.filter(gpu => gpu.temperature_celsius && gpu.temperature_celsius > 80)
  if (hotGpus.length > 0) {
    insights.push({
      type: 'warning',
      title: 'High GPU Temperature',
      message: `${hotGpus.length} GPU(s) running above 80°C. Consider improving cooling or reducing workload.`
    })
  }

  // Check for critical temperature
  const criticalGpus = gpus.filter(gpu => gpu.temperature_celsius && gpu.temperature_celsius > 85)
  if (criticalGpus.length > 0) {
    insights.push({
      type: 'error',
      title: 'Critical GPU Temperature',
      message: `${criticalGpus.length} GPU(s) exceeding 85°C. Risk of thermal throttling. Immediate attention required.`
    })
  }

  // Check for high utilization
  const busyGpus = gpus.filter(gpu => gpu.utilization_percent && gpu.utilization_percent > 90)
  if (busyGpus.length > 0) {
    insights.push({
      type: 'info',
      title: 'High GPU Utilization',
      message: `${busyGpus.length} GPU(s) running at over 90% utilization. System is handling compute-intensive workloads.`
    })
  }

  // Check for memory pressure
  const memoryPressureGpus = gpus.filter(gpu => {
    if (gpu.memory_used_mb && gpu.memory_total_mb) {
      const memoryPercent = (gpu.memory_used_mb / gpu.memory_total_mb) * 100
      return memoryPercent > 90
    }
    return false
  })
  if (memoryPressureGpus.length > 0) {
    insights.push({
      type: 'warning',
      title: 'High GPU Memory Usage',
      message: `${memoryPressureGpus.length} GPU(s) using over 90% of available memory. Consider reducing batch sizes or model complexity.`
    })
  }

  // Healthy status if no warnings
  if (insights.length === 0) {
    insights.push({
      type: 'success',
      title: 'GPU Health: Optimal',
      message: `All ${gpus.length} GPU(s) operating within normal parameters.`
    })
  }

  return insights
}

/**
 * Formats memory bytes to GB
 */
const formatMemoryGB = (mb: number | null): string => {
  if (mb === null) return 'N/A'
  return `${(mb / 1024).toFixed(1)} GB`
}

/**
 * Determines color class based on temperature
 */
const getTempColorClass = (temp: number | null): string => {
  if (temp === null) return 'text-gray-500 dark:text-gray-400'
  if (temp < 70) return 'text-status-healthy'
  if (temp < 80) return 'text-status-warning'
  return 'text-status-error'
}

/**
 * GpuDetailView Component
 *
 * Displays detailed GPU statistics including:
 * - Individual GPU cards with temperature, utilization, memory, power
 * - Automatic insights for temperature and utilization
 * - N/A fallback when no GPUs detected
 *
 * @param props - Component props
 * @returns JSX.Element
 */
export function GpuDetailView({
  currentMetrics,
}: GpuDetailViewProps): JSX.Element {
  const gpus = currentMetrics.gpus || []
  const insights = generateGpuInsights(gpus)

  // No GPUs detected
  if (gpus.length === 0) {
    return (
      <div className="space-y-6">
        {/* N/A Message */}
        <div className="bg-gray-50 dark:bg-gray-800 rounded-lg p-8 text-center">
          <Zap className="w-16 h-16 mx-auto mb-4 text-gray-400 dark:text-gray-600" />
          <h3 className="text-xl font-semibold text-gray-900 dark:text-white mb-2">
            N/A
          </h3>
        </div>

        {/* Insights */}
        <div className="space-y-3">
          <h3 className="text-sm font-semibold text-gray-700 dark:text-gray-300 uppercase tracking-wide">
            Insights
          </h3>
          {insights.map((insight, index) => (
            <div
              key={index}
              className={`flex items-start space-x-3 p-4 rounded-lg border ${getInsightStyles(insight.type)}`}
            >
              <InsightIcon type={insight.type} />
              <div className="flex-1 min-w-0">
                <div className="font-medium text-gray-900 dark:text-white">
                  {insight.title}
                </div>
                <div className="text-sm text-gray-700 dark:text-gray-300 mt-1">
                  {insight.message}
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    )
  }

  // GPUs detected - display details
  return (
    <div className="space-y-6">
      {/* GPU Cards Grid */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        {gpus.map((gpu) => {
          const memoryPercent = gpu.memory_used_mb && gpu.memory_total_mb
            ? (gpu.memory_used_mb / gpu.memory_total_mb) * 100
            : null

          return (
            <div
              key={gpu.index}
              className="bg-gray-50 dark:bg-gray-800 rounded-lg p-4 border border-gray-200 dark:border-gray-700"
            >
              <div className="flex items-center justify-between mb-3">
                <h3 className="font-semibold text-gray-900 dark:text-white flex items-center space-x-2">
                  <Zap className="w-5 h-5 text-uneeq-orange" />
                  <span>GPU {gpu.index}</span>
                </h3>
              </div>

              <div className="text-sm text-gray-600 dark:text-gray-400 mb-3">
                {gpu.name}
              </div>

              <div className="grid grid-cols-2 gap-3 text-sm">
                {/* Temperature */}
                <div>
                  <div className="text-gray-600 dark:text-gray-400 flex items-center space-x-1">
                    <Thermometer className="w-4 h-4" />
                    <span>Temperature</span>
                  </div>
                  <div className={`font-medium ${getTempColorClass(gpu.temperature_celsius)}`}>
                    {gpu.temperature_celsius !== null ? `${gpu.temperature_celsius.toFixed(1)}°C` : 'N/A'}
                  </div>
                </div>

                {/* Utilization */}
                <div>
                  <div className="text-gray-600 dark:text-gray-400 flex items-center space-x-1">
                    <Activity className="w-4 h-4" />
                    <span>Utilization</span>
                  </div>
                  <div className="font-medium text-gray-900 dark:text-white">
                    {gpu.utilization_percent !== null ? `${gpu.utilization_percent.toFixed(1)}%` : 'N/A'}
                  </div>
                </div>

                {/* Memory Used */}
                <div>
                  <div className="text-gray-600 dark:text-gray-400">Memory Used</div>
                  <div className="font-medium text-gray-900 dark:text-white">
                    {formatMemoryGB(gpu.memory_used_mb)}
                  </div>
                </div>

                {/* Memory Total */}
                <div>
                  <div className="text-gray-600 dark:text-gray-400">Memory Total</div>
                  <div className="font-medium text-gray-900 dark:text-white">
                    {formatMemoryGB(gpu.memory_total_mb)}
                  </div>
                </div>

                {/* Memory Percent */}
                {memoryPercent !== null && (
                  <div className="col-span-2">
                    <div className="text-gray-600 dark:text-gray-400">Memory Usage</div>
                    <div className="flex items-center space-x-2">
                      <div className="flex-1 bg-gray-200 dark:bg-gray-700 rounded-full h-2 overflow-hidden">
                        <div
                          className="bg-uneeq-orange h-full transition-all duration-300"
                          style={{ width: `${memoryPercent}%` }}
                        />
                      </div>
                      <span className="font-medium text-gray-900 dark:text-white text-sm">
                        {memoryPercent.toFixed(1)}%
                      </span>
                    </div>
                  </div>
                )}

                {/* Power */}
                <div>
                  <div className="text-gray-600 dark:text-gray-400">Power</div>
                  <div className="font-medium text-gray-900 dark:text-white">
                    {gpu.power_watts !== null ? `${gpu.power_watts.toFixed(1)}W` : 'N/A'}
                  </div>
                </div>

                {/* Fan Speed */}
                <div>
                  <div className="text-gray-600 dark:text-gray-400">Fan Speed</div>
                  <div className="font-medium text-gray-900 dark:text-white">
                    {gpu.fan_speed_percent !== null ? `${gpu.fan_speed_percent}%` : 'N/A'}
                  </div>
                </div>

                {/* Graphics Clock */}
                <div>
                  <div className="text-gray-600 dark:text-gray-400">Graphics Clock</div>
                  <div className="font-medium text-gray-900 dark:text-white">
                    {gpu.clock_graphics_mhz !== null ? `${gpu.clock_graphics_mhz} MHz` : 'N/A'}
                  </div>
                </div>

                {/* Memory Clock */}
                <div>
                  <div className="text-gray-600 dark:text-gray-400">Memory Clock</div>
                  <div className="font-medium text-gray-900 dark:text-white">
                    {gpu.clock_memory_mhz !== null ? `${gpu.clock_memory_mhz} MHz` : 'N/A'}
                  </div>
                </div>
              </div>
            </div>
          )
        })}
      </div>

      {/* Insights */}
      <div className="space-y-3">
        <h3 className="text-sm font-semibold text-gray-700 dark:text-gray-300 uppercase tracking-wide">
          Automatic Insights
        </h3>
        {insights.map((insight, index) => (
          <div
            key={index}
            className={`flex items-start space-x-3 p-4 rounded-lg border ${getInsightStyles(insight.type)}`}
          >
            <InsightIcon type={insight.type} />
            <div className="flex-1 min-w-0">
              <div className="font-medium text-gray-900 dark:text-white">
                {insight.title}
              </div>
              <div className="text-sm text-gray-700 dark:text-gray-300 mt-1">
                {insight.message}
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}

export default GpuDetailView
