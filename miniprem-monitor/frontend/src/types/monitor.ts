export interface PrometheusMetrics {
  // Standard system metrics (for compatibility)
  gpu_percent?: number | null;
  cpu_percent?: number | null;
  memory_percent?: number | null;
  memory_bytes?: number | null;
  power_watts?: number | null;
  request_count?: number | null;
  uptime_seconds?: number | null;

  // Renny application metrics
  session_total?: number | null;
  session_started?: number | null;
  session_successful?: number | null;
  session_failed?: number | null;
  frames_rendered?: number | null;

  // Response time metrics (milliseconds)
  response_time_p50?: number | null;
  response_time_p90?: number | null;
  response_time_p99?: number | null;
  nlp_response_time_p50?: number | null;
  a2f_response_time_p50?: number | null;

  // Frame timing metrics (milliseconds, averages)
  gpu_frame_time_avg?: number | null;
  render_frame_time_avg?: number | null;
  game_frame_time_avg?: number | null;
  frame_time_avg?: number | null;
}

// Metric configuration for user selection
export interface MetricConfig {
  key: keyof PrometheusMetrics;
  label: string;
  icon: React.ComponentType<{ className?: string }>; // Lucide React icon component
  unit: string;
  category: 'system' | 'session' | 'performance' | 'timing';
  description: string;
  thresholds?: { warning: number; critical: number };
}

// User metric preferences (3 slots)
export type MetricPreferences = [
  keyof PrometheusMetrics,
  keyof PrometheusMetrics,
  keyof PrometheusMetrics
];

export interface ContainerStatus {
  name: string;
  status: string;
  image: string;
  ports: string[] | string | null | undefined;
  created: string;
  cpu_usage?: string;
  memory_usage?: string;
  network_tx_bytes?: number;  // NEW: bytes transmitted
  network_rx_bytes?: number;  // NEW: bytes received
  metrics?: PrometheusMetrics;
}

export interface PodStatus {
  name: string;
  namespace: string;
  status: string;
  ready: string;
  restarts: number;
  age: string;
  node?: string;
  cpu_usage?: string;
  memory_usage?: string;
}

/**
 * GPU statistics from nvidia-smi.
 * Empty array if no GPUs detected or nvidia-smi unavailable.
 */
export interface GpuStats {
  /** GPU index number */
  index: number;
  /** GPU model name (e.g., "NVIDIA GeForce RTX 4090") */
  name: string;
  /** GPU temperature in Celsius (null if unavailable) */
  temperature_celsius: number | null;
  /** GPU utilization percentage 0-100 (null if unavailable) */
  utilization_percent: number | null;
  /** GPU memory used in MB (null if unavailable) */
  memory_used_mb: number | null;
  /** GPU total memory in MB (null if unavailable) */
  memory_total_mb: number | null;
  /** GPU power consumption in watts (null if unavailable) */
  power_watts: number | null;
  /** Graphics clock speed in MHz (null if unavailable) */
  clock_graphics_mhz: number | null;
  /** Memory clock speed in MHz (null if unavailable) */
  clock_memory_mhz: number | null;
  /** Fan speed percentage 0-100 (null if unavailable) */
  fan_speed_percent: number | null;
}

/**
 * System metrics snapshot for real-time monitoring.
 * Provides overall system resource usage and network I/O statistics.
 *
 * Updated in Phase 2.1 to include per-core CPU data for multi-threading verification.
 * Updated to include GPU statistics (empty array if no GPUs or nvidia-smi unavailable).
 */
export interface SystemMetrics {
  /** Overall CPU usage percentage (0-100) */
  cpu_percent: number;

  /**
   * Per-core CPU usage percentages (0-100).
   * Array length equals the number of logical CPU cores.
   * Example: [42.1, 48.3, 44.5, ...] for a 12-core system.
   * Optional field added in Phase 2 for multi-threading verification.
   * Backend returns empty array [] if not available.
   */
  cpu_per_core?: number[];

  /** Memory usage percentage (0-100) */
  memory_percent: number;

  /** Disk usage percentage (0-100) */
  disk_percent: number;

  /** Network I/O statistics */
  network_io: {
    /** Total bytes sent since system boot */
    bytes_sent: number;
    /** Total bytes received since system boot */
    bytes_recv: number;
    /** Total packets sent since system boot */
    packets_sent: number;
    /** Total packets received since system boot */
    packets_recv: number;
  };

  /**
   * GPU statistics array. Empty if no GPUs detected or nvidia-smi unavailable.
   * Polled every 15 seconds with backend caching.
   */
  gpus?: GpuStats[];

  /** ISO 8601 timestamp when metrics were captured */
  timestamp: string;
}

export interface CommandRequest {
  type: 'command' | 'subscribe' | 'unsubscribe';
  target: 'docker' | 'kubernetes' | 'system' | 'services' | 'connections';
  command: string;
  params?: Record<string, string>;
  requestId: string;
}

export interface CommandResponse {
  requestId: string;
  success: boolean;
  data?: {
    containers?: ContainerStatus[];
    pods?: PodStatus[];
    logs?: string;
    nodes?: any[];
    contexts?: KubernetesContext[];
    switched_to?: string;
    container_action?: string;
    alert?: string;
    subscribed?: string;
    unsubscribed?: string;
    metrics?: SystemMetrics;
    system?: SystemInfo['system'] & {
      docker?: SystemInfo['docker'];
      kubernetes?: SystemInfo['kubernetes'];
    };
    // Log streaming fields
    log_line?: string;
    container?: string;
    streaming?: boolean;
    // Real-time update fields
    type?: 'real_time_update';
    update_type?: string;
    changes?: {
      containers?: ContainerStatus[];
      pods?: PodStatus[];
    };
  };
  error?: string;
  timestamp: string;
}

export interface SystemInfo {
  system: {
    platform: string;
    cpu_count: number;
    cpu_count_logical: number;
    memory_total_gb: number;
    disk_total_gb: number;
    boot_time: string;
    uptime_hours: number;
  };
  docker: {
    available: boolean;
    error?: string;
    system_df?: any;
  };
  kubernetes: {
    available: boolean;
    error?: string;
    cluster_info?: any;
    contexts?: KubernetesContext[];
    current_context?: string;
    namespaces?: string[];
  };
}

export interface KubernetesContext {
  name: string;
  cluster: string;
  namespace?: string;
  user?: string;
  current: boolean;
  valid?: boolean;
}

export interface KubernetesClusterInfo {
  name: string;
  context: string;
  namespace: string;
  environment: 'local' | 'eks' | 'gke' | 'aks';
  region?: string;
  status: 'connected' | 'connecting' | 'error';
  lastSync?: Date;
  latency?: number;
  podCount?: number;
  nodeCount?: number;
  connectionError?: string;
  version?: string;
}

export interface ConnectionStats {
  total_connections: number;
  active_subscriptions: number;
  total_requests: number;
  connections: Array<{
    id: string;
    connected_duration: string;
    last_activity: string;
    request_count: number;
  }>;
}

export type StatusType = 'healthy' | 'warning' | 'error' | 'unknown';

export interface ServiceStatus {
  name: string;
  status: StatusType;
  message?: string;
  lastUpdate: string;
}

// Health API types
export interface HealthSystemInfo {
  timestamp: string;
  cpu_percent: number;
  cpu_count: number;
  memory_total: number;
  memory_available: number;
  memory_percent: number;
  disk_total: number;
  disk_used: number;
  disk_free: number;
  disk_percent: number;
  boot_time: string;
  uptime_seconds: number;
}

export interface HealthResponse {
  status: 'healthy' | 'unhealthy';
  system_info: HealthSystemInfo;
  message?: string;
}

export interface HealthApiError {
  error: string;
  message: string;
  details?: string;
}

/**
 * Historical metrics data point structure.
 * Stores a snapshot of system metrics at a specific point in time,
 * with optional container event annotation.
 *
 * Used for time-series visualization (5 minutes rolling window).
 */
export interface MetricsHistoryPoint {
  /** Timestamp when the metrics were captured */
  timestamp: Date;

  // CPU metrics
  /** CPU usage percentage (0-100) */
  cpu_percent: number;
  /** Per-core CPU usage percentages (future Phase 2 enhancement) */
  cpu_per_core?: number[];

  // Memory metrics
  /** Memory usage percentage (0-100) */
  memory_percent: number;
  /** Memory used in gigabytes */
  memory_used_gb: number;
  /** Memory available in gigabytes */
  memory_available_gb: number;

  // Disk metrics
  /** Disk usage percentage (0-100) */
  disk_percent: number;
  /** Disk space used in gigabytes */
  disk_used_gb: number;
  /** Disk space free in gigabytes */
  disk_free_gb: number;

  // Network metrics (cumulative counters)
  /** Total bytes sent since system boot */
  network_sent_bytes: number;
  /** Total bytes received since system boot */
  network_recv_bytes: number;

  // Network transfer rates (calculated derivatives)
  /** Network upload rate in bytes per second */
  network_sent_rate: number;
  /** Network download rate in bytes per second */
  network_recv_rate: number;

  // Optional container lifecycle event annotation
  /** Container start/stop event that occurred at this timestamp */
  event?: {
    type: 'container_start' | 'container_stop';
    containerName: string;
  };
}
