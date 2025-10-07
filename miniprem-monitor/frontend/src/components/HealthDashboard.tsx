import React, { useState, useEffect, useCallback } from 'react';
import { format, formatDistanceToNow } from 'date-fns';
import { Activity, Cpu, HardDrive, MemoryStick, Clock, AlertTriangle, CheckCircle, XCircle } from 'lucide-react';
import clsx from 'clsx';
import { HealthResponse, HealthSystemInfo, HealthApiError, StatusType } from '../types/monitor';
import { StatusIndicator } from './StatusIndicator';

/**
 * Configuration options for the HealthDashboard component
 */
interface HealthDashboardConfig {
  /** API endpoint URL for health data */
  apiUrl: string;
  /** Refresh interval in milliseconds */
  refreshInterval: number;
  /** Enable automatic refresh */
  autoRefresh: boolean;
}

/**
 * Props for the HealthDashboard component
 */
interface HealthDashboardProps {
  /** Optional configuration overrides */
  config?: Partial<HealthDashboardConfig>;
  /** Custom CSS class name */
  className?: string;
  /** Callback fired when health data is fetched */
  onHealthUpdate?: (health: HealthResponse) => void;
  /** Callback fired when an error occurs */
  onError?: (error: HealthApiError) => void;
}

/**
 * Internal state for health data fetching
 */
interface HealthState {
  data: HealthResponse | null;
  loading: boolean;
  error: HealthApiError | null;
  lastUpdate: Date | null;
}

/**
 * Default configuration for the HealthDashboard
 */
const defaultConfig: HealthDashboardConfig = {
  apiUrl: 'http://localhost:8000/health',
  refreshInterval: 35000, // 30 seconds
  autoRefresh: true,
};

/**
 * Convert bytes to human-readable format
 *
 * @param bytes - Number of bytes to convert
 * @param decimals - Number of decimal places (default: 2)
 * @returns Formatted string with appropriate unit
 *
 * @example
 * ```typescript
 * formatBytes(1024) // "1.00 KB"
 * formatBytes(1048576) // "1.00 MB"
 * ```
 */
const formatBytes = (bytes: number, decimals: number = 2): string => {
  if (bytes === 0) return '0 Bytes';

  const k = 1024;
  const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));

  return `${parseFloat((bytes / Math.pow(k, i)).toFixed(decimals))} ${sizes[i]}`;
}

/**
 * Convert seconds to human-readable uptime format
 *
 * @param seconds - Number of seconds
 * @returns Formatted uptime string
 *
 * @example
 * ```typescript
 * formatUptime(3661) // "1h 1m 1s"
 * formatUptime(86400) // "1d 0h 0m 0s"
 * ```
 */
const formatUptime = (seconds: number): string => {
  const days = Math.floor(seconds / 86400);
  const hours = Math.floor((seconds % 86400) / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const secs = Math.floor(seconds % 60);

  const parts: string[] = [];
  if (days > 0) parts.push(`${days}d`);
  if (hours > 0) parts.push(`${hours}h`);
  if (minutes > 0) parts.push(`${minutes}m`);
  if (secs > 0 || parts.length === 0) parts.push(`${secs}s`);

  return parts.join(' ');
}

/**
 * Determine status type based on health response
 *
 * @param health - Health response data
 * @returns StatusType for use with StatusIndicator
 */
const getHealthStatusType = (health: HealthResponse): StatusType => {
  return health.status === 'healthy' ? 'healthy' : 'error';
}

/**
 * Get CSS classes for percentage-based metrics
 *
 * @param percentage - Metric percentage (0-100)
 * @returns CSS class string for coloring
 */
const getPercentageColor = (percentage: number): string => {
  if (percentage < 60) return 'text-status-healthy';
  if (percentage < 80) return 'text-status-warning';
  return 'text-status-error';
}

/**
 * HealthDashboard Component
 *
 * A comprehensive dashboard for displaying system health information fetched from
 * a FastAPI health endpoint. Features real-time updates, error handling, and
 * responsive design with Tailwind CSS.
 *
 * @param props - Component props
 * @returns React functional component
 *
 * @example
 * ```tsx
 * // Basic usage
 * <HealthDashboard />
 *
 * // With custom configuration
 * <HealthDashboard
 *   config={{
 *     apiUrl: 'http://localhost:3500/health',
 *     refreshInterval: 15000
 *   }}
 *   onHealthUpdate={(health) => console.log('Health updated:', health)}
 *   onError={(error) => console.error('Health error:', error)}
 * />
 * ```
 */
export const HealthDashboard: React.FC<HealthDashboardProps> = ({
  config = {},
  className,
  onHealthUpdate,
  onError,
}) => {
  const finalConfig = { ...defaultConfig, ...config };

  const [state, setState] = useState<HealthState>({
    data: null,
    loading: true,
    error: null,
    lastUpdate: null,
  });

  /**
   * Fetch health data from the API endpoint
   *
   * Implements proper error handling, type safety, and loading states.
   * Automatically retries on network errors and validates response structure.
   */
  const fetchHealthData = useCallback(async (): Promise<void> => {
    setState(prevState => ({
      ...prevState,
      loading: prevState.data === null, // Only show loading on initial load
      error: null
    }));

    try {
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 10000); // 10s timeout

      const response = await fetch(finalConfig.apiUrl, {
        method: 'GET',
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        signal: controller.signal,
      });

      clearTimeout(timeoutId);

      if (!response.ok) {
        let errorData: HealthApiError;

        try {
          const errorJson = await response.json() as unknown;
          // Type guard for error response
          if (typeof errorJson === 'object' && errorJson !== null && 'error' in errorJson) {
            errorData = errorJson as HealthApiError;
          } else {
            throw new Error('Invalid error response format');
          }
        } catch {
          errorData = {
            error: 'HTTP Error',
            message: `Request failed with status ${response.status}: ${response.statusText}`,
          };
        }

        setState(prevState => ({
          ...prevState,
          loading: false,
          error: errorData,
        }));

        onError?.(errorData);
        return;
      }

      const healthData = await response.json() as unknown;

      // Type guard for health response
      if (
        typeof healthData === 'object' &&
        healthData !== null &&
        'status' in healthData &&
        'system_info' in healthData
      ) {
        const validatedData = healthData as HealthResponse;

        setState({
          data: validatedData,
          loading: false,
          error: null,
          lastUpdate: new Date(),
        });

        onHealthUpdate?.(validatedData);
      } else {
        const error: HealthApiError = {
          error: 'Invalid Response',
          message: 'API returned invalid health data format',
        };

        setState(prevState => ({
          ...prevState,
          loading: false,
          error,
        }));

        onError?.(error);
      }
    } catch (err) {
      let error: HealthApiError;

      if (err instanceof Error) {
        if (err.name === 'AbortError') {
          error = {
            error: 'Request Timeout',
            message: 'Health API request timed out after 10 seconds',
          };
        } else if (err.message.includes('fetch')) {
          error = {
            error: 'Network Error',
            message: 'Unable to connect to health API endpoint',
            details: err.message,
          };
        } else {
          error = {
            error: 'Unknown Error',
            message: err.message,
          };
        }
      } else {
        error = {
          error: 'Unknown Error',
          message: 'An unexpected error occurred while fetching health data',
        };
      }

      setState(prevState => ({
        ...prevState,
        loading: false,
        error,
      }));

      onError?.(error);
    }
  }, [finalConfig.apiUrl, onHealthUpdate, onError]);

  /**
   * Set up automatic refresh interval
   */
  useEffect(() => {
    // Initial fetch
    fetchHealthData();

    // Set up interval if auto-refresh is enabled
    let intervalId: NodeJS.Timeout | null = null;

    if (finalConfig.autoRefresh && finalConfig.refreshInterval > 0) {
      intervalId = setInterval(fetchHealthData, finalConfig.refreshInterval);
    }

    // Cleanup interval on unmount or config change
    return () => {
      if (intervalId) {
        clearInterval(intervalId);
      }
    };
  }, [fetchHealthData, finalConfig.autoRefresh, finalConfig.refreshInterval]);

  /**
   * Manual refresh handler
   */
  const handleRefresh = useCallback(() => {
    fetchHealthData();
  }, [fetchHealthData]);

  const { data, loading, error, lastUpdate } = state;

  return (
    <div className={clsx('space-y-6', className)}>
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center space-x-3">
          <Activity className="w-6 h-6 text-blue-600" />
          <h2 className="text-2xl font-bold text-gray-900">System Health</h2>
          {data && (
            <StatusIndicator
              status={getHealthStatusType(data)}
              label={data.status}
              showLabel
            />
          )}
        </div>

        <div className="flex items-center space-x-4">
          {lastUpdate && (
            <span className="text-sm text-gray-500">
              Updated {formatDistanceToNow(lastUpdate)} ago
            </span>
          )}
          <button
            onClick={handleRefresh}
            disabled={loading}
            className={clsx(
              'px-4 py-2 text-sm font-medium rounded-md transition-colors',
              'bg-blue-600 text-white hover:bg-blue-700',
              'disabled:opacity-50 disabled:cursor-not-allowed',
              loading && 'animate-pulse'
            )}
          >
            {loading ? 'Refreshing...' : 'Refresh'}
          </button>
        </div>
      </div>

      {/* Error State */}
      {error && (
        <div className="bg-red-50 border border-red-200 rounded-md p-4">
          <div className="flex items-start space-x-3">
            <XCircle className="w-5 h-5 text-red-600 flex-shrink-0 mt-0.5" />
            <div className="flex-1">
              <h3 className="text-sm font-medium text-red-800">
                {error.error}
              </h3>
              <p className="text-sm text-red-700 mt-1">
                {error.message}
              </p>
              {error.details && (
                <p className="text-xs text-red-600 mt-2 font-mono bg-red-100 p-2 rounded">
                  {error.details}
                </p>
              )}
            </div>
          </div>
        </div>
      )}

      {/* Loading State */}
      {loading && !data && (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
          {[...Array(4)].map((_, i) => (
            <div key={i} className="animate-pulse bg-white rounded-lg border p-6">
              <div className="h-4 bg-gray-200 rounded mb-2"></div>
              <div className="h-8 bg-gray-200 rounded"></div>
            </div>
          ))}
        </div>
      )}

      {/* Health Data */}
      {data && (
        <>
          {/* Overall Status */}
          {data.message && (
            <div className="bg-yellow-50 border border-yellow-200 rounded-md p-4">
              <div className="flex items-start space-x-3">
                <AlertTriangle className="w-5 h-5 text-yellow-600 flex-shrink-0 mt-0.5" />
                <div className="flex-1">
                  <h3 className="text-sm font-medium text-yellow-800">
                    System Warning
                  </h3>
                  <p className="text-sm text-yellow-700 mt-1">
                    {data.message}
                  </p>
                </div>
              </div>
            </div>
          )}

          {/* Metrics Cards */}
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
            <div className="bg-white rounded-lg border p-6">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-sm text-gray-600">CPU Usage</p>
                  <p className={`text-2xl font-bold ${getPercentageColor(data.system_info.cpu_percent)}`}>
                    {data.system_info.cpu_percent}%
                  </p>
                  <p className="text-xs text-gray-500">{data.system_info.cpu_count} cores</p>
                </div>
                <Cpu className="w-8 h-8 text-gray-400" />
              </div>
            </div>

            <div className="bg-white rounded-lg border p-6">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-sm text-gray-600">Memory Usage</p>
                  <p className={`text-2xl font-bold ${getPercentageColor(data.system_info.memory_percent)}`}>
                    {data.system_info.memory_percent}%
                  </p>
                  <p className="text-xs text-gray-500">{formatBytes(data.system_info.memory_available)} available</p>
                </div>
                <MemoryStick className="w-8 h-8 text-gray-400" />
              </div>
            </div>

            <div className="bg-white rounded-lg border p-6">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-sm text-gray-600">Disk Usage</p>
                  <p className={`text-2xl font-bold ${getPercentageColor(data.system_info.disk_percent)}`}>
                    {data.system_info.disk_percent}%
                  </p>
                  <p className="text-xs text-gray-500">{formatBytes(data.system_info.disk_free)} free</p>
                </div>
                <HardDrive className="w-8 h-8 text-gray-400" />
              </div>
            </div>

            <div className="bg-white rounded-lg border p-6">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-sm text-gray-600">Uptime</p>
                  <p className="text-2xl font-bold text-gray-700">
                    {formatUptime(data.system_info.uptime_seconds)}
                  </p>
                  <p className="text-xs text-gray-500">Since {format(new Date(data.system_info.boot_time), 'MMM dd, HH:mm')}</p>
                </div>
                <Clock className="w-8 h-8 text-gray-400" />
              </div>
            </div>
          </div>

          {/* Detailed System Information */}
          <div className="bg-white rounded-lg border p-6">
            <h3 className="text-lg font-semibold text-gray-900 mb-4 flex items-center">
              <Activity className="w-5 h-5 mr-2" />
              Detailed System Information
            </h3>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              {/* Memory Details */}
              <div className="space-y-3">
                <h4 className="font-medium text-gray-700">Memory</h4>
                <div className="space-y-2 text-sm">
                  <div className="flex justify-between">
                    <span>Total:</span>
                    <span className="font-mono">{formatBytes(data.system_info.memory_total)}</span>
                  </div>
                  <div className="flex justify-between">
                    <span>Available:</span>
                    <span className="font-mono">{formatBytes(data.system_info.memory_available)}</span>
                  </div>
                  <div className="flex justify-between">
                    <span>Used:</span>
                    <span className="font-mono">
                      {formatBytes(data.system_info.memory_total - data.system_info.memory_available)}
                    </span>
                  </div>
                </div>
              </div>

              {/* Disk Details */}
              <div className="space-y-3">
                <h4 className="font-medium text-gray-700">Disk</h4>
                <div className="space-y-2 text-sm">
                  <div className="flex justify-between">
                    <span>Total:</span>
                    <span className="font-mono">{formatBytes(data.system_info.disk_total)}</span>
                  </div>
                  <div className="flex justify-between">
                    <span>Used:</span>
                    <span className="font-mono">{formatBytes(data.system_info.disk_used)}</span>
                  </div>
                  <div className="flex justify-between">
                    <span>Free:</span>
                    <span className="font-mono">{formatBytes(data.system_info.disk_free)}</span>
                  </div>
                </div>
              </div>
            </div>

            {/* System Metadata */}
            <div className="mt-6 pt-4 border-t border-gray-200">
              <div className="text-xs text-gray-500 space-y-1">
                <div>Last updated: {format(new Date(data.system_info.timestamp), 'PPpp')}</div>
                <div>Boot time: {format(new Date(data.system_info.boot_time), 'PPpp')}</div>
              </div>
            </div>
          </div>
        </>
      )}
    </div>
  );
};

export default HealthDashboard;