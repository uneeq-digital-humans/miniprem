'use client';

import React, { useEffect, useCallback } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import {
  Cpu,
  HardDrive,
  MemoryStick,
  Network,
  X,
  TrendingUp,
  TrendingDown,
  Activity,
  Zap
} from 'lucide-react';
import { MetricsChart, NetworkDetailView, CpuDetailView, MemoryDetailView, GpuDetailView } from './metrics-detail';
import { SystemMetrics, MetricsHistoryPoint, SystemInfo, ContainerStatus } from '../types/monitor';

/**
 * Props interface for SystemMetricsModal component
 */
interface SystemMetricsModalProps {
  /** Whether the modal is open */
  isOpen: boolean;
  /** Function to close the modal */
  onClose: () => void;
  /** Current selected metric type */
  metricType: 'cpu' | 'memory' | 'disk' | 'network' | 'gpu';
  /** Function to change metric type (tab switching) */
  onMetricTypeChange: (type: 'cpu' | 'memory' | 'disk' | 'network' | 'gpu') => void;
  /** Current system metrics snapshot */
  currentMetrics: SystemMetrics;
  /** Historical metrics data for charting (5-minute rolling window) */
  metricsHistory: MetricsHistoryPoint[];
  /** System information */
  systemInfo: SystemInfo;
  /** Container status list (for event annotations) */
  containers: ContainerStatus[];
}

/**
 * Tab configuration with icons and labels
 */
const tabs = [
  { id: 'cpu' as const, label: 'CPU', icon: Cpu },
  { id: 'memory' as const, label: 'Memory', icon: MemoryStick },
  { id: 'disk' as const, label: 'Disk', icon: HardDrive },
  { id: 'network' as const, label: 'Network', icon: Network },
  { id: 'gpu' as const, label: 'GPU', icon: Zap },
];

/**
 * SystemMetricsModal - Enhanced modal with tab navigation and detailed metric visualizations
 *
 * Features:
 * - Tab-based navigation between metric types
 * - Framer Motion animations for smooth transitions
 * - Detailed metric charts using MetricsChart component
 * - Keyboard navigation (ESC to close, Arrow keys for tabs)
 * - Focus trap for accessibility
 * - Real-time statistics and trend indicators
 *
 * @param props - Component props
 * @returns JSX.Element
 */
export function SystemMetricsModal({
  isOpen,
  onClose,
  metricType,
  onMetricTypeChange,
  currentMetrics,
  metricsHistory,
  systemInfo,
  containers,
}: SystemMetricsModalProps): JSX.Element {
  /**
   * Keyboard navigation handler
   * - ESC: Close modal
   * - Left/Right arrows: Navigate tabs
   */
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (!isOpen) return;

      // ESC to close
      if (e.key === 'Escape') {
        onClose();
        return;
      }

      // Arrow keys to navigate tabs
      if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') {
        e.preventDefault();
        const currentIndex = tabs.findIndex(t => t.id === metricType);
        let newIndex = currentIndex;

        if (e.key === 'ArrowLeft') {
          newIndex = currentIndex > 0 ? currentIndex - 1 : tabs.length - 1;
        } else {
          newIndex = currentIndex < tabs.length - 1 ? currentIndex + 1 : 0;
        }

        onMetricTypeChange(tabs[newIndex].id);
      }
    };

    if (isOpen) {
      document.addEventListener('keydown', handleKeyDown);
      document.body.style.overflow = 'hidden';
    }

    return () => {
      document.removeEventListener('keydown', handleKeyDown);
      document.body.style.overflow = 'unset';
    };
  }, [isOpen, metricType, onClose, onMetricTypeChange]);

  /**
   * Formats bytes to human-readable format
   */
  const formatBytes = useCallback((bytes: number): string => {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return `${(bytes / Math.pow(k, i)).toFixed(1)} ${sizes[i]}`;
  }, []);

  /**
   * Determines color class based on usage percentage
   */
  const getUsageColor = useCallback((percentage: number): string => {
    if (percentage < 60) return 'text-status-healthy';
    if (percentage < 80) return 'text-status-warning';
    return 'text-status-error';
  }, []);

  /**
   * Calculates trend from historical data
   */
  const calculateTrend = useCallback((history: number[]): { direction: 'up' | 'down' | 'stable'; change: number } => {
    if (history.length < 2) return { direction: 'stable', change: 0 };

    const recent = history.slice(-10); // Last 10 data points
    const avg = recent.reduce((sum, val) => sum + val, 0) / recent.length;
    const earlier = history.slice(-20, -10);
    const earlierAvg = earlier.length > 0 ? earlier.reduce((sum, val) => sum + val, 0) / earlier.length : avg;

    const change = avg - earlierAvg;

    if (Math.abs(change) < 1) return { direction: 'stable', change: 0 };
    return {
      direction: change > 0 ? 'up' : 'down',
      change: Math.abs(change)
    };
  }, []);

  /**
   * Renders CPU detail view using CpuDetailView component
   */
  const renderCpuView = () => {
    return (
      <CpuDetailView
        metricsHistory={metricsHistory}
        systemInfo={systemInfo}
        currentMetrics={currentMetrics}
        containers={containers}
      />
    );
  };

  /**
   * Renders Memory detail view using MemoryDetailView component
   */
  const renderMemoryView = () => {
    return (
      <MemoryDetailView
        metricsHistory={metricsHistory}
        systemInfo={systemInfo}
        currentMetrics={currentMetrics}
        containers={containers}
      />
    );
  };

  /**
   * Renders Disk detail view
   */
  const renderDiskView = () => {
    const diskData = metricsHistory.map(point => ({
      timestamp: point.timestamp,
      value: point.disk_percent
    }));

    const diskValues = metricsHistory.map(p => p.disk_percent);
    const trend = calculateTrend(diskValues);
    const avgDisk = diskValues.length > 0 ? diskValues.reduce((sum, val) => sum + val, 0) / diskValues.length : 0;
    const maxDisk = diskValues.length > 0 ? Math.max(...diskValues) : 0;
    const minDisk = diskValues.length > 0 ? Math.min(...diskValues) : 0;

    const currentUsedGb = metricsHistory.length > 0 ? metricsHistory[metricsHistory.length - 1].disk_used_gb : 0;
    const currentFreeGb = metricsHistory.length > 0 ? metricsHistory[metricsHistory.length - 1].disk_free_gb : 0;

    return (
      <div className="space-y-6">
        {/* Current Stats Grid */}
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
          <div className="bg-gray-50 dark:bg-gray-800 rounded-lg p-4">
            <div className="text-sm text-gray-600 dark:text-gray-400">Current</div>
            <div className={`text-2xl font-bold ${getUsageColor(currentMetrics.disk_percent)}`}>
              {currentMetrics.disk_percent.toFixed(1)}%
            </div>
          </div>
          <div className="bg-gray-50 dark:bg-gray-800 rounded-lg p-4">
            <div className="text-sm text-gray-600 dark:text-gray-400">Average</div>
            <div className="text-2xl font-bold text-gray-900 dark:text-white">
              {avgDisk.toFixed(1)}%
            </div>
          </div>
          <div className="bg-gray-50 dark:bg-gray-800 rounded-lg p-4">
            <div className="text-sm text-gray-600 dark:text-gray-400">Max</div>
            <div className="text-2xl font-bold text-gray-900 dark:text-white">
              {maxDisk.toFixed(1)}%
            </div>
          </div>
          <div className="bg-gray-50 dark:bg-gray-800 rounded-lg p-4">
            <div className="text-sm text-gray-600 dark:text-gray-400">Min</div>
            <div className="text-2xl font-bold text-gray-900 dark:text-white">
              {minDisk.toFixed(1)}%
            </div>
          </div>
        </div>

        {/* Trend Indicator */}
        {trend.direction !== 'stable' && (
          <div className={`flex items-center space-x-2 p-3 rounded-lg ${
            trend.direction === 'up' ? 'bg-orange-50 dark:bg-orange-900/20' : 'bg-green-50 dark:bg-green-900/20'
          }`}>
            {trend.direction === 'up' ? (
              <TrendingUp className="w-5 h-5 text-orange-600 dark:text-orange-400" />
            ) : (
              <TrendingDown className="w-5 h-5 text-green-600 dark:text-green-400" />
            )}
            <span className={`text-sm font-medium ${
              trend.direction === 'up' ? 'text-orange-600 dark:text-orange-400' : 'text-green-600 dark:text-green-400'
            }`}>
              Disk usage {trend.direction === 'up' ? 'increasing' : 'decreasing'} by {trend.change.toFixed(1)}%
            </span>
          </div>
        )}

        {/* System Info */}
        <div className="bg-amber-50 dark:bg-amber-900/20 rounded-lg p-4">
          <div className="flex items-center space-x-2 mb-2">
            <HardDrive className="w-5 h-5 text-amber-600 dark:text-amber-400" />
            <span className="font-medium text-amber-900 dark:text-amber-100">Disk Information</span>
          </div>
          <div className="grid grid-cols-2 gap-3 text-sm">
            <div>
              <span className="text-gray-600 dark:text-gray-400">Total:</span>
              <span className="ml-2 font-medium text-gray-900 dark:text-white">{systemInfo.system.disk_total_gb.toFixed(1)} GB</span>
            </div>
            <div>
              <span className="text-gray-600 dark:text-gray-400">Used:</span>
              <span className="ml-2 font-medium text-gray-900 dark:text-white">{currentUsedGb.toFixed(1)} GB</span>
            </div>
            <div>
              <span className="text-gray-600 dark:text-gray-400">Free:</span>
              <span className="ml-2 font-medium text-gray-900 dark:text-white">{currentFreeGb.toFixed(1)} GB</span>
            </div>
            <div>
              <span className="text-gray-600 dark:text-gray-400">Filesystem:</span>
              <span className="ml-2 font-medium text-gray-900 dark:text-white">{systemInfo.system.platform === 'Darwin' ? 'APFS' : 'ext4'}</span>
            </div>
          </div>
        </div>

        {/* Chart */}
        {diskData.length > 0 && (
          <MetricsChart
            data={diskData}
            yAxisLabel="Disk Usage (%)"
            color="#f59e0b"
            lineLabel="Disk %"
            formatValue={(v) => `${v.toFixed(1)}%`}
            height={300}
          />
        )}
      </div>
    );
  };

  /**
   * Renders Network detail view using NetworkDetailView component
   */
  const renderNetworkView = () => {
    return (
      <NetworkDetailView
        metricsHistory={metricsHistory}
        systemInfo={systemInfo}
        currentMetrics={currentMetrics}
        containers={containers}
      />
    );
  };

  /**
   * Renders GPU detail view using GpuDetailView component
   */
  const renderGpuView = () => {
    return (
      <GpuDetailView
        systemInfo={systemInfo}
        currentMetrics={currentMetrics}
        containers={containers}
      />
    );
  };

  /**
   * Renders content based on selected tab
   */
  const renderContent = () => {
    switch (metricType) {
      case 'cpu':
        return renderCpuView();
      case 'memory':
        return renderMemoryView();
      case 'disk':
        return renderDiskView();
      case 'network':
        return renderNetworkView();
      case 'gpu':
        return renderGpuView();
      default:
        return null;
    }
  };

  return (
    <AnimatePresence>
      {isOpen && (
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          transition={{ duration: 0.2 }}
          className="fixed inset-0 z-50 flex items-center justify-center p-4"
          data-testid="system-metrics-modal"
        >
          {/* Backdrop */}
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="absolute inset-0 bg-black/50"
            onClick={onClose}
            data-testid="metrics-modal-backdrop"
          />

          {/* Modal Content */}
          <motion.div
            initial={{ opacity: 0, scale: 0.95, y: 20 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.95, y: 20 }}
            transition={{ type: 'spring', duration: 0.3 }}
            className="relative bg-white dark:bg-gray-900 rounded-xl shadow-2xl max-w-6xl w-full max-h-[90vh] overflow-hidden flex flex-col"
            onClick={(e) => e.stopPropagation()}
            data-testid="metrics-modal-content"
          >
            {/* Header with Tabs */}
            <div className="border-b border-gray-200 dark:border-gray-700">
              <div className="flex items-center justify-between px-6 py-4">
                <h2 className="text-xl font-bold text-gray-900 dark:text-white">
                  System Metrics Detail
                </h2>
                <button
                  onClick={onClose}
                  className="p-2 text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200 transition-colors rounded-lg hover:bg-gray-100 dark:hover:bg-gray-800"
                  aria-label="Close modal"
                  data-testid="metrics-modal-close-button"
                >
                  <X className="w-5 h-5" />
                </button>
              </div>

              {/* Tab Navigation */}
              <div className="flex space-x-2 px-6">
                {tabs.map((tab) => (
                  <button
                    key={tab.id}
                    onClick={() => onMetricTypeChange(tab.id)}
                    className={`flex items-center space-x-2 px-4 py-3 font-medium transition-colors relative ${
                      metricType === tab.id
                        ? 'text-uneeq-primary'
                        : 'text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-200'
                    }`}
                    data-testid={`tab-${tab.id}`}
                    aria-selected={metricType === tab.id}
                    role="tab"
                  >
                    <tab.icon className="w-5 h-5" />
                    <span>{tab.label}</span>
                    {metricType === tab.id && (
                      <motion.div
                        layoutId="activeTab"
                        className="absolute bottom-0 left-0 right-0 h-0.5 bg-uneeq-primary"
                        transition={{ type: 'spring', duration: 0.3 }}
                      />
                    )}
                  </button>
                ))}
              </div>
            </div>

            {/* Tab Content with Animation */}
            <div className="flex-1 overflow-y-auto p-6 custom-scrollbar">
              <AnimatePresence mode="wait">
                <motion.div
                  key={metricType}
                  initial={{ opacity: 0, x: 20 }}
                  animate={{ opacity: 1, x: 0 }}
                  exit={{ opacity: 0, x: -20 }}
                  transition={{ duration: 0.2 }}
                  data-testid="tab-content"
                >
                  {renderContent()}
                </motion.div>
              </AnimatePresence>
            </div>

            {/* Footer */}
            <div className="border-t border-gray-200 dark:border-gray-700 px-6 py-4 bg-gray-50 dark:bg-gray-800">
              <div className="flex items-center justify-between text-sm text-gray-600 dark:text-gray-400">
                <div>
                  Data points: {metricsHistory.length} (5-minute rolling window)
                </div>
                <div>
                  Use arrow keys to navigate tabs • ESC to close
                </div>
              </div>
            </div>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}

export default SystemMetricsModal;
