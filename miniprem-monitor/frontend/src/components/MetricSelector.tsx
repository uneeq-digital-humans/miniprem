import React, { useState } from 'react';
import { Settings, X, RotateCcw } from 'lucide-react';
import clsx from 'clsx';
import { useMetricPreferences } from '../hooks/useMetricPreferences';
import { getMetricsByCategory, getMetricConfig } from '../config/metricConfigs';

interface MetricSelectorProps {
  className?: string;
}

/**
 * MetricSelector component allows users to customize which 3 metrics
 * are displayed on container rows. Selections persist via localStorage.
 *
 * Features:
 * - Modal popup with metric selection dropdowns
 * - Grouped by category (Session, Performance, Timing, System)
 * - Live preview of selected metrics
 * - Reset to defaults button
 */
export function MetricSelector({ className }: MetricSelectorProps) {
  const [isOpen, setIsOpen] = useState(false);
  const { selectedMetrics, updateMetric, resetToDefaults } = useMetricPreferences();
  const metricsByCategory = getMetricsByCategory();

  const handleSlotChange = (slot: 0 | 1 | 2, value: string) => {
    updateMetric(slot, value);
  };

  const handleReset = () => {
    resetToDefaults();
  };

  const renderDropdown = (slot: 0 | 1 | 2, label: string) => {
    const currentValue = selectedMetrics[slot];
    const currentConfig = getMetricConfig(currentValue);

    return (
      <div key={slot} className="space-y-2">
        <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
          {label}
        </label>
        <select
          value={currentValue}
          onChange={(e) => handleSlotChange(slot, e.target.value)}
          className="w-full px-3 py-2 bg-white dark:bg-gray-700 border border-gray-300 dark:border-gray-600 rounded-lg text-gray-900 dark:text-gray-100 focus:ring-2 focus:ring-uneeq-primary focus:border-transparent"
        >
          <optgroup label="Session Metrics">
            {metricsByCategory.session.map((config) => (
              <option key={config.key} value={config.key}>
                {config.label} ({config.unit || 'count'})
              </option>
            ))}
          </optgroup>
          <optgroup label="Performance Metrics">
            {metricsByCategory.performance.map((config) => (
              <option key={config.key} value={config.key}>
                {config.label} ({config.unit})
              </option>
            ))}
          </optgroup>
          <optgroup label="Frame Timing">
            {metricsByCategory.timing.map((config) => (
              <option key={config.key} value={config.key}>
                {config.label} ({config.unit})
              </option>
            ))}
          </optgroup>
          <optgroup label="System Metrics">
            {metricsByCategory.system.map((config) => (
              <option key={config.key} value={config.key}>
                {config.label} ({config.unit})
              </option>
            ))}
          </optgroup>
        </select>
        {currentConfig && (
          <p className="text-xs text-gray-500 dark:text-gray-400">
            {currentConfig.description}
          </p>
        )}
      </div>
    );
  };

  return (
    <>
      {/* Settings Button */}
      <button
        onClick={() => setIsOpen(true)}
        className={clsx(
          'flex items-center space-x-2 px-3 py-2 rounded-lg',
          'bg-white dark:bg-gray-700 hover:bg-gray-50 dark:hover:bg-gray-600',
          'border border-gray-300 dark:border-gray-600',
          'text-gray-700 dark:text-gray-300 transition-colors',
          className
        )}
        title="Configure displayed metrics"
        data-testid="metric-selector-button"
      >
        <Settings className="w-4 h-4" />
        <span className="text-sm font-medium">Metrics</span>
      </button>

      {/* Modal */}
      {isOpen && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-50"
          data-testid="metric-selector-modal"
          onClick={() => setIsOpen(false)}
        >
          <div
            className="bg-white dark:bg-gray-800 rounded-lg shadow-xl max-w-2xl w-full mx-4 max-h-[90vh] overflow-y-auto"
            onClick={(e) => e.stopPropagation()}
          >
            {/* Header */}
            <div className="flex items-center justify-between p-6 border-b border-gray-200 dark:border-gray-700">
              <div>
                <h2 className="text-xl font-bold text-gray-900 dark:text-gray-100">
                  Customize Container Metrics
                </h2>
                <p className="text-sm text-gray-600 dark:text-gray-400 mt-1">
                  Select up to 3 metrics to display on each container row
                </p>
              </div>
              <button
                onClick={() => setIsOpen(false)}
                className="p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors"
                aria-label="Close"
              >
                <X className="w-5 h-5 text-gray-500 dark:text-gray-400" />
              </button>
            </div>

            {/* Body */}
            <div className="p-6 space-y-6">
              {/* Metric Slots */}
              {renderDropdown(0, 'Metric Slot 1')}
              {renderDropdown(1, 'Metric Slot 2')}
              {renderDropdown(2, 'Metric Slot 3')}

              {/* Preview */}
              <div className="p-4 bg-gray-50 dark:bg-gray-900 rounded-lg border border-gray-200 dark:border-gray-700">
                <div className="text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                  Preview:
                </div>
                <div className="flex items-center gap-4">
                  {selectedMetrics.map((metricKey) => {
                    const config = getMetricConfig(metricKey);
                    if (!config) return null;
                    const IconComponent = config.icon;
                    return (
                      <div key={config.key} className="flex items-center gap-1.5">
                        <IconComponent className="w-4 h-4 text-blue-500" />
                        <span className="text-xs text-gray-600 dark:text-gray-400">
                          {config.label}:
                        </span>
                        <span className="font-mono font-semibold text-sm text-blue-500">
                          42{config.unit}
                        </span>
                      </div>
                    );
                  })}
                </div>
              </div>
            </div>

            {/* Footer */}
            <div className="flex items-center justify-between p-6 border-t border-gray-200 dark:border-gray-700">
              <button
                onClick={handleReset}
                className="flex items-center space-x-2 px-4 py-2 rounded-lg border border-gray-300 dark:border-gray-600 text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-700 transition-colors"
              >
                <RotateCcw className="w-4 h-4" />
                <span className="text-sm font-medium">Reset to Defaults</span>
              </button>
              <button
                onClick={() => setIsOpen(false)}
                className="px-6 py-2 rounded-lg bg-gradient-uneeq text-white font-medium hover:opacity-90 transition-opacity"
              >
                Done
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
