export interface ContainerStatus {
  name: string;
  status: string;
  image: string;
  ports: string[] | string | null | undefined;
  created: string;
  cpu_usage?: string;
  memory_usage?: string;
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

export interface SystemMetrics {
  cpu_percent: number;
  memory_percent: number;
  disk_percent: number;
  network_io: {
    bytes_sent: number;
    bytes_recv: number;
    packets_sent: number;
    packets_recv: number;
  };
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