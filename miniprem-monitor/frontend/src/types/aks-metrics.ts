/**
 * Type definitions for Azure AKS metrics and cluster information
 */

export interface AKSNodePoolMetrics {
  name: string;
  vm_size: string;
  node_count: {
    current: number;
    min: number;
    max: number;
  };
  auto_scaling_enabled: boolean;
  provisioning_state: string;
  health: {
    ready_nodes: number;
    not_ready_nodes: number;
    percentage: number;
  };
}

export interface AKSClusterOverview {
  cluster_name: string;
  resource_group: string;
  location: string;
  kubernetes_version: string;
  provider: 'aks';
  fqdn?: string;
  dns_prefix?: string;
}

export interface AKSClusterTotals {
  total_nodes: number;
  ready_nodes: number;
  not_ready_nodes: number;
  total_pods: number;
  running_pods: number;
  pending_pods: number;
  failed_pods: number;
  namespace_count: number;
}

export interface AKSCostEstimate {
  hourly: number;
  daily: number;
  monthly: number;
  breakdown: {
    node_pool: string;
    vm_size: string;
    node_count: number;
    hourly_cost: number;
  }[];
  currency: string;
}

export interface AKSMetricsResponse {
  success: boolean;
  provider: 'aks';
  cluster_overview: AKSClusterOverview;
  node_pools: AKSNodePoolMetrics[];
  cluster_totals: AKSClusterTotals;
  cost_estimate: AKSCostEstimate;
  last_updated: string;
  error?: string;
}

/**
 * Health status type for visual indicators
 */
export type HealthStatus = 'healthy' | 'warning' | 'error';

/**
 * Get health status based on percentage
 */
export function getHealthStatus(percentage: number): HealthStatus {
  if (percentage >= 90) return 'healthy';
  if (percentage >= 70) return 'warning';
  return 'error';
}

/**
 * Get health color classes for Tailwind
 */
export function getHealthColorClasses(status: HealthStatus): {
  text: string;
  bg: string;
  border: string;
} {
  switch (status) {
    case 'healthy':
      return {
        text: 'text-green-600 dark:text-green-400',
        bg: 'bg-green-500',
        border: 'border-green-500',
      };
    case 'warning':
      return {
        text: 'text-yellow-600 dark:text-yellow-400',
        bg: 'bg-yellow-500',
        border: 'border-yellow-500',
      };
    case 'error':
      return {
        text: 'text-red-600 dark:text-red-400',
        bg: 'bg-red-500',
        border: 'border-red-500',
      };
  }
}

/**
 * Format currency with appropriate symbol
 */
export function formatCurrency(amount: number, currency: string = 'USD'): string {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: currency,
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(amount);
}

/**
 * Determine if cost is high (for warning indicators)
 */
export function isHighCost(monthlyCost: number): boolean {
  return monthlyCost > 10000; // $10k/month threshold
}
