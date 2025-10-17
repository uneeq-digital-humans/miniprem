'use client';

import React, { useMemo } from 'react';
import { X, Camera, Send } from 'lucide-react';
import clsx from 'clsx';
import { PrometheusMetrics } from '../types/monitor';
import { getMetricsByCategory, getMetricConfig } from '../config/metricConfigs';
import { motion, AnimatePresence } from 'framer-motion';

export interface FullMetricsModalProps {
  containerName: string;
  metrics: PrometheusMetrics;
  onClose: () => void;
  onCaptureSnapshot: () => void;
  onSendToSupport: () => void;
  timestamp?: string;
}

interface MetricCardProps {
  metricKey: string;
  value: number | null | undefined;
}

/**
 * FullMetricsModal displays all 22 Prometheus metrics in a comprehensive dashboard.
 *
 * Features:
 * - Full-screen modal overlay with gradient header
 * - Metrics grouped by 4 categories (Session, Performance, Timing, System)
 * - Real-time update indicator
 * - Color-coded metric cards based on thresholds
 * - Snapshot and Support actions
 * - Responsive grid layout
 * - Smooth animations with framer-motion
 */
export function FullMetricsModal({
  containerName,
  metrics,
  onClose,
  onCaptureSnapshot,
  onSendToSupport,
  timestamp
}: FullMetricsModalProps) {
  const metricsByCategory = useMemo(() => getMetricsByCategory(), []);

  /**
   * Calculate time since last update
   */
  const timeSinceUpdate = useMemo(() => {
    if (!timestamp) return 'N/A';

    const updateTime = new Date(timestamp).getTime();
    const now = Date.now();
    const diffSeconds = Math.floor((now - updateTime) / 1000);

    if (diffSeconds < 60) return `${diffSeconds}s ago`;
    if (diffSeconds < 3600) return `${Math.floor(diffSeconds / 60)}m ago`;
    return `${Math.floor(diffSeconds / 3600)}h ago`;
  }, [timestamp]);

  /**
   * Get color class based on metric value and thresholds
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
   * Get background color class for cards based on thresholds
   */
  const getCardBgClass = (
    value: number | null | undefined,
    thresholds?: { warning: number; critical: number }
  ): string => {
    if (value === null || value === undefined) return 'bg-gray-50 dark:bg-gray-800/50';
    if (!thresholds) return 'bg-blue-50 dark:bg-blue-900/10';

    if (value < thresholds.warning) return 'bg-green-50 dark:bg-green-900/10';
    if (value < thresholds.critical) return 'bg-yellow-50 dark:bg-yellow-900/10';
    return 'bg-red-50 dark:bg-red-900/10';
  };

  /**
   * Format metric value with appropriate precision
   */
  const formatValue = (value: number | null | undefined, unit: string): string => {
    if (value === null || value === undefined) return 'N/A';

    if (unit === 'ms') {
      return value < 10 ? value.toFixed(2) : value.toFixed(1);
    } else if (unit === '%' || unit === 'W') {
      return value.toFixed(0);
    } else {
      return Math.round(value).toString();
    }
  };

  /**
   * Reusable MetricCard component
   */
  const MetricCard: React.FC<MetricCardProps> = ({ metricKey, value }) => {
    const config = getMetricConfig(metricKey);
    if (!config) return null;

    const IconComponent = config.icon;
    const colorClass = getColorClass(value as number, config.thresholds);
    const bgClass = getCardBgClass(value as number, config.thresholds);
    const formattedValue = formatValue(value as number, config.unit);

    return (
      <motion.div
        initial={{ opacity: 0, y: 10 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.2 }}
        className={clsx(
          'p-4 rounded-lg border transition-all duration-200',
          bgClass,
          value === null || value === undefined
            ? 'border-gray-200 dark:border-gray-700'
            : 'border-gray-300 dark:border-gray-600 hover:shadow-md'
        )}
        title={config.description}
        data-testid={`metric-card-${config.key}`}
      >
        <div className="flex items-start justify-between mb-2">
          <div className="flex items-center gap-2">
            <IconComponent className={clsx('w-5 h-5', colorClass)} />
            <span className="text-xs font-medium text-gray-600 dark:text-gray-400">
              {config.label}
            </span>
          </div>
        </div>
        <div className="flex items-baseline gap-1">
          <span className={clsx('text-2xl font-bold font-mono', colorClass)}>
            {formattedValue}
          </span>
          {config.unit && (
            <span className={clsx('text-sm font-medium', colorClass)}>
              {config.unit}
            </span>
          )}
        </div>
      </motion.div>
    );
  };

  /**
   * Render a category section
   */
  const renderCategorySection = (
    title: string,
    icon: string,
    metricsArray: Array<{ key: string; [key: string]: any }>
  ) => {
    return (
      <section className="space-y-3" data-testid={`section-${title.toLowerCase().replace(/\s+/g, '-')}`}>
        <h3 className="text-lg font-semibold text-gray-800 dark:text-gray-200 flex items-center gap-2">
          <span>{icon}</span>
          <span>{title}</span>
        </h3>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
          {metricsArray.map((config) => (
            <MetricCard
              key={config.key}
              metricKey={config.key}
              value={metrics[config.key as keyof PrometheusMetrics]}
            />
          ))}
        </div>
      </section>
    );
  };

  return (
    <AnimatePresence>
      <div
        className="fixed inset-0 z-50 flex items-center justify-center"
        data-testid="full-metrics-modal"
      >
        {/* Backdrop */}
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          className="absolute inset-0 bg-black/60 backdrop-blur-sm"
          onClick={onClose}
          data-testid="metrics-modal-backdrop"
        />

        {/* Modal Content */}
        <motion.div
          initial={{ opacity: 0, scale: 0.95, y: 20 }}
          animate={{ opacity: 1, scale: 1, y: 0 }}
          exit={{ opacity: 0, scale: 0.95, y: 20 }}
          transition={{ duration: 0.2 }}
          className="relative bg-white dark:bg-gray-900 rounded-xl shadow-2xl w-[95%] h-[90%] max-w-7xl flex flex-col"
          onClick={(e) => e.stopPropagation()}
          data-testid="metrics-modal-content"
        >
          {/* Header with Gradient */}
          <div className="flex items-center justify-between px-6 py-4 bg-gradient-uneeq rounded-t-xl border-b border-gray-200 dark:border-gray-700">
            <div className="flex items-center gap-3">
              <h2 className="text-2xl font-bold text-white flex items-center gap-2">
                <span>⚡</span>
                <span>Metrics</span>
                <span className="text-white/80">-</span>
                <span className="text-white/90">{containerName}</span>
              </h2>
            </div>

            <div className="flex items-center gap-2">
              {/* Snapshot Button */}
              <button
                onClick={onCaptureSnapshot}
                className="flex items-center gap-2 px-4 py-2 bg-white/20 hover:bg-white/30 text-white rounded-lg transition-colors backdrop-blur-sm"
                title="Capture metrics snapshot"
                data-testid="snapshot-button"
              >
                <Camera className="w-4 h-4" />
                <span className="text-sm font-medium hidden sm:inline">Snapshot</span>
              </button>

              {/* Send to Support Button */}
              <button
                onClick={onSendToSupport}
                className="flex items-center gap-2 px-4 py-2 bg-white/20 hover:bg-white/30 text-white rounded-lg transition-colors backdrop-blur-sm"
                title="Send metrics to support"
                data-testid="support-button"
              >
                <Send className="w-4 h-4" />
                <span className="text-sm font-medium hidden sm:inline">Support</span>
              </button>

              {/* Close Button */}
              <button
                onClick={onClose}
                className="p-2 hover:bg-white/20 rounded-lg transition-colors"
                title="Close"
                data-testid="close-button"
              >
                <X className="w-5 h-5 text-white" />
              </button>
            </div>
          </div>

          {/* Modal Body - Scrollable */}
          <div className="flex-1 overflow-y-auto p-6 space-y-6">
            {/* Live Update Indicator */}
            <div className="flex items-center justify-end gap-2" data-testid="live-indicator">
              <div className="flex items-center gap-2 px-3 py-1.5 bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-700 rounded-full">
                <div className="w-2 h-2 rounded-full bg-green-500 animate-pulse" />
                <span className="text-xs font-medium text-green-700 dark:text-green-300">
                  Live
                </span>
                <span className="text-xs text-green-600 dark:text-green-400">•</span>
                <span className="text-xs text-green-600 dark:text-green-400">
                  Updated {timeSinceUpdate}
                </span>
              </div>
            </div>

            {/* Session Metrics */}
            {renderCategorySection('Session Metrics', '📊', metricsByCategory.session)}

            {/* Performance Metrics */}
            {renderCategorySection('Performance Metrics', '⚡', metricsByCategory.performance)}

            {/* Frame Timing Metrics */}
            {renderCategorySection('Frame Timing', '⏱️', metricsByCategory.timing)}

            {/* System Metrics */}
            {renderCategorySection('System Metrics', '💻', metricsByCategory.system)}
          </div>

          {/* Footer */}
          <div className="flex items-center justify-between px-6 py-4 border-t border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800/50 rounded-b-xl">
            <div className="text-xs text-gray-500 dark:text-gray-400">
              Displaying all 22 Prometheus metrics • Real-time updates via WebSocket
            </div>
            <button
              onClick={onClose}
              className="px-6 py-2 rounded-lg bg-gradient-uneeq text-white font-medium hover:opacity-90 transition-opacity"
              data-testid="footer-close-button"
            >
              Close
            </button>
          </div>
        </motion.div>
      </div>
    </AnimatePresence>
  );
}
