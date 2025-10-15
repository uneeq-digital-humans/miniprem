import React from 'react';
import { PrometheusMetrics } from '../types/monitor';
import clsx from 'clsx';
import { getMetricConfig, DEFAULT_METRIC_PREFERENCES } from '../config/metricConfigs';

interface InlineMetricsProps {
  metrics: PrometheusMetrics;
  className?: string;
  selectedMetrics?: [string, string, string]; // User's metric preferences
}

/**
 * Display container metrics inline with dynamic user-selected metrics.
 * Shows up to 3 metrics based on user preferences or defaults.
 * Supports all Renny application metrics + standard system metrics.
 */
export function InlineMetrics({
  metrics,
  className,
  selectedMetrics = DEFAULT_METRIC_PREFERENCES
}: InlineMetricsProps) {

  /**
   * Get color class based on metric value and thresholds.
   */
  const getColorClass = (
    value: number | null | undefined,
    thresholds?: { warning: number; critical: number }
  ): string => {
    if (value === null || value === undefined) return 'text-gray-400 dark:text-gray-500';
    if (!thresholds) return 'text-blue-500 dark:text-blue-400';

    if (value < thresholds.warning) return 'text-green-500 dark:text-green-400';
    if (value < thresholds.critical) return 'text-yellow-500 dark:text-yellow-400';
    return 'text-red-500 dark:text-red-400';
  };

  /**
   * Format metric value with appropriate precision and unit.
   */
  const formatValue = (value: number | null | undefined, unit: string): string => {
    if (value === null || value === undefined) return 'N/A';

    // Format based on unit
    if (unit === 'ms') {
      return value < 10 ? value.toFixed(2) : value.toFixed(1);
    } else if (unit === '%' || unit === 'W') {
      return value.toFixed(0);
    } else {
      // Count metrics (sessions, frames)
      return Math.round(value).toString();
    }
  };

  /**
   * Render a single metric display.
   */
  const renderMetric = (metricKey: string) => {
    const config = getMetricConfig(metricKey);
    if (!config) return null;

    const value = metrics[config.key as keyof PrometheusMetrics];

    // Skip if metric has no value
    if (value === null || value === undefined) return null;

    const colorClass = getColorClass(value as number, config.thresholds);
    const formattedValue = formatValue(value as number, config.unit);
    const IconComponent = config.icon;

    return (
      <div
        key={config.key}
        className="flex items-center gap-1.5"
        title={`${config.label}: ${formattedValue}${config.unit}\n${config.description}`}
      >
        <IconComponent className={clsx('w-4 h-4', colorClass)} />
        <span className="text-xs text-gray-600 dark:text-gray-400">{config.label}:</span>
        <span className={clsx('font-mono font-semibold text-sm', colorClass)}>
          {formattedValue}{config.unit}
        </span>
      </div>
    );
  };

  // Check if any selected metrics have values
  const displayedMetrics = selectedMetrics
    .map(renderMetric)
    .filter(Boolean);

  if (displayedMetrics.length === 0) return null;

  return (
    <div
      className={clsx('flex items-center gap-4 text-sm font-medium', className)}
      data-testid="inline-metrics"
    >
      {displayedMetrics}
    </div>
  );
}
