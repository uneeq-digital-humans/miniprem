import { useState, useEffect } from 'react';
import { DEFAULT_METRIC_PREFERENCES } from '../config/metricConfigs';

const STORAGE_KEY = 'rennyMetricPreferences';

/**
 * Custom hook for managing user metric preferences with localStorage persistence.
 *
 * Allows users to select 3 metrics to display on container rows.
 * Selections persist across browser sessions and container restarts.
 *
 * @returns {Object} Metric preferences state and update functions
 */
export function useMetricPreferences() {
  const [selectedMetrics, setSelectedMetrics] = useState<[string, string, string]>(
    DEFAULT_METRIC_PREFERENCES
  );

  // Load preferences from localStorage on mount
  useEffect(() => {
    try {
      const stored = localStorage.getItem(STORAGE_KEY);
      if (stored) {
        const parsed = JSON.parse(stored);
        if (Array.isArray(parsed) && parsed.length === 3) {
          setSelectedMetrics(parsed as [string, string, string]);
        }
      }
    } catch (error) {
      console.error('Failed to load metric preferences:', error);
      // Fallback to defaults on error
      setSelectedMetrics(DEFAULT_METRIC_PREFERENCES);
    }
  }, []);

  /**
   * Update a specific metric slot (0, 1, or 2).
   * Automatically saves to localStorage.
   */
  const updateMetric = (slot: 0 | 1 | 2, metricKey: string) => {
    setSelectedMetrics((prev) => {
      const updated: [string, string, string] = [...prev] as [string, string, string];
      updated[slot] = metricKey;

      // Save to localStorage
      try {
        localStorage.setItem(STORAGE_KEY, JSON.stringify(updated));
      } catch (error) {
        console.error('Failed to save metric preferences:', error);
      }

      return updated;
    });
  };

  /**
   * Reset preferences to default values.
   */
  const resetToDefaults = () => {
    setSelectedMetrics(DEFAULT_METRIC_PREFERENCES);
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(DEFAULT_METRIC_PREFERENCES));
    } catch (error) {
      console.error('Failed to reset metric preferences:', error);
    }
  };

  /**
   * Update all 3 metrics at once.
   */
  const updateAllMetrics = (metrics: [string, string, string]) => {
    setSelectedMetrics(metrics);
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(metrics));
    } catch (error) {
      console.error('Failed to save metric preferences:', error);
    }
  };

  return {
    selectedMetrics,
    updateMetric,
    resetToDefaults,
    updateAllMetrics,
  };
}
