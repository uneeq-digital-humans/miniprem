import { useState, useEffect, useCallback, useRef } from 'react';
import { SystemMetrics, SystemInfo, MetricsHistoryPoint } from '../types/monitor';

/**
 * Maximum number of historical data points to retain.
 * At 2-second WebSocket intervals, 150 points = 5 minutes of history.
 */
const MAX_HISTORY_POINTS = 150;

/**
 * Custom hook to manage historical system metrics collection.
 *
 * Features:
 * - Stores last 5 minutes (150 points) with automatic FIFO cleanup
 * - Calculates network transfer rates from cumulative byte counts
 * - Converts percentages to absolute values (GB) using system totals
 * - Supports manual event annotation (container start/stop)
 * - Thread-safe state updates with previous state reference
 *
 * @param systemMetrics - Current system metrics from WebSocket subscription
 * @param systemInfo - System information containing total memory/disk capacity
 * @returns Object with metrics history, event handler, and clear function
 *
 * @example
 * ```typescript
 * const { metricsHistory, addEvent, clearHistory } = useMetricsHistory(
 *   systemMetrics,
 *   systemInfo
 * );
 *
 * // Add event when container starts
 * useEffect(() => {
 *   if (containerStarted) {
 *     addEvent('container_start', containerName);
 *   }
 * }, [containerStarted]);
 * ```
 */
export function useMetricsHistory(
  systemMetrics: SystemMetrics | null,
  systemInfo: SystemInfo | null
): {
  metricsHistory: MetricsHistoryPoint[];
  addEvent: (type: 'container_start' | 'container_stop', containerName: string) => void;
  clearHistory: () => void;
} {
  // State for storing historical metrics
  const [metricsHistory, setMetricsHistory] = useState<MetricsHistoryPoint[]>([]);

  // Ref to track previous network counters for rate calculation
  const previousNetworkRef = useRef<{
    bytes_sent: number;
    bytes_recv: number;
    timestamp: number;
  } | null>(null);

  /**
   * Effect to capture and store metrics whenever systemMetrics updates.
   * Runs on every WebSocket metrics update (~2 second intervals).
   */
  useEffect(() => {
    // Guard: Only process if we have both metrics and system info
    if (!systemMetrics || !systemInfo) {
      return;
    }

    const now = Date.now();
    const currentNetworkCounters = {
      bytes_sent: systemMetrics.network_io.bytes_sent,
      bytes_recv: systemMetrics.network_io.bytes_recv,
      timestamp: now,
    };

    // Calculate network transfer rates (bytes per second)
    let networkSentRate = 0;
    let networkRecvRate = 0;

    if (previousNetworkRef.current) {
      // Time elapsed since last measurement (in seconds)
      const timeDeltaSec = (now - previousNetworkRef.current.timestamp) / 1000;

      // Avoid division by zero
      if (timeDeltaSec > 0) {
        // Bytes transferred divided by time = bytes/sec
        const bytesSentDelta = currentNetworkCounters.bytes_sent - previousNetworkRef.current.bytes_sent;
        const bytesRecvDelta = currentNetworkCounters.bytes_recv - previousNetworkRef.current.bytes_recv;

        networkSentRate = Math.max(0, bytesSentDelta / timeDeltaSec);
        networkRecvRate = Math.max(0, bytesRecvDelta / timeDeltaSec);
      }
    }

    // Update previous network counters for next calculation
    previousNetworkRef.current = currentNetworkCounters;

    // Convert memory and disk percentages to absolute GB values
    const memoryUsedGb = (systemMetrics.memory_percent / 100) * systemInfo.system.memory_total_gb;
    const memoryAvailableGb = systemInfo.system.memory_total_gb - memoryUsedGb;

    const diskUsedGb = (systemMetrics.disk_percent / 100) * systemInfo.system.disk_total_gb;
    const diskFreeGb = systemInfo.system.disk_total_gb - diskUsedGb;

    // Create new metrics history point
    const newPoint: MetricsHistoryPoint = {
      timestamp: new Date(),
      cpu_percent: systemMetrics.cpu_percent,
      memory_percent: systemMetrics.memory_percent,
      memory_used_gb: memoryUsedGb,
      memory_available_gb: memoryAvailableGb,
      disk_percent: systemMetrics.disk_percent,
      disk_used_gb: diskUsedGb,
      disk_free_gb: diskFreeGb,
      network_sent_bytes: systemMetrics.network_io.bytes_sent,
      network_recv_bytes: systemMetrics.network_io.bytes_recv,
      network_sent_rate: networkSentRate,
      network_recv_rate: networkRecvRate,
    };

    // Add new point to history with FIFO cleanup
    setMetricsHistory((prevHistory) => {
      const updatedHistory = [...prevHistory, newPoint];

      // Enforce maximum history length (FIFO: remove oldest when exceeding limit)
      if (updatedHistory.length > MAX_HISTORY_POINTS) {
        return updatedHistory.slice(updatedHistory.length - MAX_HISTORY_POINTS);
      }

      return updatedHistory;
    });
  }, [systemMetrics, systemInfo]);

  /**
   * Add a container lifecycle event annotation to the most recent metrics point.
   *
   * This allows correlating container start/stop events with metrics spikes.
   * If no metrics exist yet, the event is silently ignored.
   *
   * @param type - Event type ('container_start' or 'container_stop')
   * @param containerName - Name of the container that triggered the event
   */
  const addEvent = useCallback(
    (type: 'container_start' | 'container_stop', containerName: string) => {
      setMetricsHistory((prevHistory) => {
        // Guard: Can't add event if no history exists
        if (prevHistory.length === 0) {
          console.warn('Cannot add event: no metrics history available');
          return prevHistory;
        }

        // Clone history array to avoid mutation
        const updatedHistory = [...prevHistory];

        // Annotate the most recent metrics point with the event
        const lastIndex = updatedHistory.length - 1;
        updatedHistory[lastIndex] = {
          ...updatedHistory[lastIndex],
          event: {
            type,
            containerName,
          },
        };

        return updatedHistory;
      });
    },
    []
  );

  /**
   * Clear all historical metrics data.
   *
   * Useful for:
   * - Resetting visualization after system changes
   * - Manual user-triggered history reset
   * - Clearing stale data after disconnection
   */
  const clearHistory = useCallback(() => {
    setMetricsHistory([]);
    previousNetworkRef.current = null;
  }, []);

  return {
    metricsHistory,
    addEvent,
    clearHistory,
  };
}
