'use client'

import React, { useMemo } from 'react'
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
  ReferenceLine,
  TooltipProps
} from 'recharts'
import { format } from 'date-fns'

/**
 * Event annotation interface for marking significant events on the chart
 */
interface ChartEvent {
  type: string
  label: string
}

/**
 * Data point interface for time-series metrics
 */
export interface MetricsDataPoint {
  timestamp: Date
  value: number
  value2?: number
  event?: ChartEvent
}

/**
 * Props interface for the MetricsChart component
 */
export interface MetricsChartProps {
  /** Array of time-series data points to display */
  data: MetricsDataPoint[]
  /** Chart height in pixels */
  height?: number
  /** Y-axis label text */
  yAxisLabel: string
  /** Y-axis domain range [min, max] */
  yAxisDomain?: [number, number]
  /** Primary line color (CSS color string) */
  color?: string
  /** Secondary line color for dual-line charts (CSS color string) */
  color2?: string
  /** Whether to show grid lines */
  showGrid?: boolean
  /** Whether to show chart legend */
  showLegend?: boolean
  /** Custom value formatter function */
  formatValue?: (value: number) => string
  /** Primary line label for legend */
  lineLabel?: string
  /** Secondary line label for legend */
  lineLabel2?: string
  /** Custom CSS class name */
  className?: string
}

/**
 * Default value formatter - formats as percentage with 1 decimal place
 */
const defaultFormatValue = (value: number): string => {
  return `${value.toFixed(1)}%`
}

/**
 * Custom tooltip component for displaying metric values
 */
const CustomTooltip = ({
  active,
  payload,
  label,
  formatValue = defaultFormatValue
}: TooltipProps<number, string> & { formatValue?: (value: number) => string }) => {
  if (!active || !payload || !payload.length) {
    return null
  }

  return (
    <div
      className="bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg shadow-lg p-3"
      data-testid="metrics-chart-tooltip"
    >
      <p className="text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
        {format(new Date(label), 'HH:mm:ss')}
      </p>
      {payload.map((entry, index) => (
        <div key={`tooltip-${index}`} className="flex items-center justify-between space-x-4">
          <span
            className="text-xs font-medium"
            style={{ color: entry.color }}
          >
            {entry.name}:
          </span>
          <span className="text-sm font-semibold text-gray-900 dark:text-white">
            {formatValue(entry.value as number)}
          </span>
        </div>
      ))}
    </div>
  )
}

/**
 * MetricsChart component displays time-series metrics data with support for:
 * - Single or dual-line charts
 * - Event annotations
 * - Responsive layout
 * - Dark mode support
 * - Customizable styling and formatting
 *
 * This component is optimized for displaying rolling 5-minute windows of live
 * system metrics such as CPU, memory, disk usage, and network I/O.
 *
 * @example
 * ```tsx
 * // Single-line chart (CPU usage)
 * <MetricsChart
 *   data={cpuData}
 *   yAxisLabel="CPU %"
 *   color="#3b82f6"
 *   lineLabel="CPU Usage"
 * />
 *
 * // Dual-line chart (Network I/O)
 * <MetricsChart
 *   data={networkData}
 *   yAxisLabel="Bandwidth"
 *   yAxisDomain={[0, 1000]}
 *   color="#10b981"
 *   color2="#f59e0b"
 *   lineLabel="Sent"
 *   lineLabel2="Received"
 *   formatValue={(v) => `${v.toFixed(1)} MB/s`}
 * />
 *
 * // With event annotations
 * <MetricsChart
 *   data={[
 *     { timestamp: new Date(), value: 45.2 },
 *     { timestamp: new Date(), value: 78.5, event: { type: 'restart', label: 'Container restarted' } }
 *   ]}
 *   yAxisLabel="Memory %"
 * />
 * ```
 */
export function MetricsChart({
  data,
  height = 300,
  yAxisLabel,
  yAxisDomain = [0, 100],
  color = '#3b82f6',
  color2 = '#f59e0b',
  showGrid = true,
  showLegend = true,
  formatValue = defaultFormatValue,
  lineLabel = 'Value',
  lineLabel2 = 'Value 2',
  className = ''
}: MetricsChartProps): JSX.Element {
  /**
   * Transform data for recharts format
   * Converts Date objects to timestamps for proper X-axis rendering
   */
  const chartData = useMemo(() => {
    return data.map(point => ({
      timestamp: point.timestamp.getTime(),
      value: point.value,
      value2: point.value2,
      event: point.event
    }))
  }, [data])

  /**
   * Extract unique events from data for ReferenceLine annotations
   */
  const events = useMemo(() => {
    return data
      .filter(point => point.event)
      .map(point => ({
        timestamp: point.timestamp.getTime(),
        label: point.event!.label,
        type: point.event!.type
      }))
  }, [data])

  /**
   * Determine if this is a dual-line chart
   */
  const isDualLine = useMemo(() => {
    return data.some(point => point.value2 !== undefined)
  }, [data])

  /**
   * Get color for event annotations based on event type
   */
  const getEventColor = (eventType: string): string => {
    const colorMap: Record<string, string> = {
      start: '#10b981', // green
      stop: '#ef4444',  // red
      restart: '#f59e0b', // yellow
      error: '#ef4444',
      warning: '#f59e0b',
      info: '#3b82f6'
    }
    return colorMap[eventType] || '#6b7280' // default gray
  }

  /**
   * Format X-axis tick labels as HH:mm:ss
   */
  const formatXAxis = (timestamp: number): string => {
    return format(new Date(timestamp), 'HH:mm:ss')
  }

  /**
   * Empty state when no data is available
   */
  if (!data || data.length === 0) {
    return (
      <div
        className={`flex items-center justify-center rounded-lg bg-gray-50 dark:bg-gray-800 border border-gray-200 dark:border-gray-700 ${className}`}
        style={{ height }}
        data-testid="metrics-chart"
      >
        <div className="text-center text-gray-500 dark:text-gray-400">
          <p className="text-sm font-medium">No data available</p>
          <p className="text-xs mt-1">Waiting for metrics...</p>
        </div>
      </div>
    )
  }

  return (
    <div
      className={`rounded-lg bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 p-4 ${className}`}
      data-testid="metrics-chart"
    >
      {/* Chart Header */}
      <div className="mb-4">
        <h3 className="text-sm font-semibold text-gray-700 dark:text-gray-300">
          {yAxisLabel}
        </h3>
        {events.length > 0 && (
          <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">
            {events.length} event{events.length !== 1 ? 's' : ''} recorded
          </p>
        )}
      </div>

      {/* Recharts Line Chart */}
      <ResponsiveContainer width="100%" height={height}>
        <LineChart
          data={chartData}
          margin={{ top: 5, right: 30, left: 20, bottom: 5 }}
        >
          {/* Grid */}
          {showGrid && (
            <CartesianGrid
              strokeDasharray="3 3"
              stroke="#e5e7eb"
              className="dark:stroke-gray-700"
            />
          )}

          {/* X-Axis (Time) */}
          <XAxis
            dataKey="timestamp"
            type="number"
            domain={['dataMin', 'dataMax']}
            tickFormatter={formatXAxis}
            stroke="#6b7280"
            className="dark:stroke-gray-400"
            tick={{ fontSize: 12 }}
            minTickGap={50}
          />

          {/* Y-Axis (Value) */}
          <YAxis
            domain={yAxisDomain}
            stroke="#6b7280"
            className="dark:stroke-gray-400"
            tick={{ fontSize: 12 }}
            tickFormatter={formatValue}
          />

          {/* Tooltip */}
          <Tooltip
            content={<CustomTooltip formatValue={formatValue} />}
            cursor={{ stroke: '#9ca3af', strokeWidth: 1 }}
          />

          {/* Legend */}
          {showLegend && (
            <Legend
              wrapperStyle={{ fontSize: '12px' }}
              iconType="line"
              data-testid="metrics-chart-legend"
            />
          )}

          {/* Event Annotations */}
          {events.map((event, index) => (
            <ReferenceLine
              key={`event-${index}`}
              x={event.timestamp}
              stroke={getEventColor(event.type)}
              strokeDasharray="3 3"
              label={{
                value: event.label,
                position: 'top',
                fill: getEventColor(event.type),
                fontSize: 10
              }}
            />
          ))}

          {/* Primary Line */}
          <Line
            type="monotone"
            dataKey="value"
            name={lineLabel}
            stroke={color}
            strokeWidth={2}
            dot={false}
            activeDot={{ r: 4 }}
            isAnimationActive={false}
          />

          {/* Secondary Line (if dual-line chart) */}
          {isDualLine && (
            <Line
              type="monotone"
              dataKey="value2"
              name={lineLabel2}
              stroke={color2}
              strokeWidth={2}
              dot={false}
              activeDot={{ r: 4 }}
              isAnimationActive={false}
            />
          )}
        </LineChart>
      </ResponsiveContainer>

      {/* Data Summary Footer */}
      <div className="mt-4 pt-4 border-t border-gray-200 dark:border-gray-700">
        <div className="grid grid-cols-3 gap-4 text-xs">
          <div>
            <span className="text-gray-500 dark:text-gray-400">Data Points:</span>
            <span className="ml-2 font-medium text-gray-900 dark:text-white">
              {data.length}
            </span>
          </div>
          <div>
            <span className="text-gray-500 dark:text-gray-400">Current:</span>
            <span className="ml-2 font-medium text-gray-900 dark:text-white">
              {formatValue(data[data.length - 1]?.value ?? 0)}
            </span>
          </div>
          <div>
            <span className="text-gray-500 dark:text-gray-400">Avg:</span>
            <span className="ml-2 font-medium text-gray-900 dark:text-white">
              {formatValue(
                data.reduce((sum, point) => sum + point.value, 0) / data.length
              )}
            </span>
          </div>
        </div>
      </div>
    </div>
  )
}

export default MetricsChart
