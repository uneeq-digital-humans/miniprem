/**
 * Cost Tracking Dashboard Types
 *
 * Type definitions for the comprehensive cost tracking dashboard
 * supporting EKS, AKS, and GKE providers.
 */

export type CloudProvider = 'eks' | 'aks' | 'gke';
export type OptimizationPriority = 'high' | 'medium' | 'low';

export interface CurrentPeriod {
  start_date: string;
  end_date: string;
  total_cost: number;
  daily_average: number;
  projected_monthly: number;
}

export interface CostBreakdown {
  compute: { cost: number; percentage: number };
  networking: { cost: number; percentage: number };
  storage: { cost: number; percentage: number };
  monitoring: { cost: number; percentage: number };
}

export interface NodePoolCost {
  name: string;
  instance_type: string;
  current_nodes: number;
  hourly_cost: number;
  daily_cost: number;
  monthly_projection: number;
  cost_per_node_hourly: number;
}

export interface CostTrends {
  last_7_days: number[];
  last_30_days: number[];
  highest_day: { date: string; cost: number };
  lowest_day: { date: string; cost: number };
}

export interface OptimizationRecommendation {
  type: string;
  potential_savings: number;
  savings_percentage: number;
  description: string;
  priority: OptimizationPriority;
}

export interface BudgetStatus {
  monthly_budget: number;
  current_spend: number;
  projected_spend: number;
  remaining: number;
  utilization_percentage: number;
  on_track: boolean;
}

export interface EnhancedCostResponse {
  success: boolean;
  provider: CloudProvider;
  cluster_name: string;
  current_period: CurrentPeriod;
  cost_breakdown: CostBreakdown;
  node_pool_costs: NodePoolCost[];
  cost_trends: CostTrends;
  optimization_recommendations: OptimizationRecommendation[];
  budget_status: BudgetStatus;
}

// Helper type guards
export function isValidProvider(provider: string): provider is CloudProvider {
  return ['eks', 'aks', 'gke'].includes(provider);
}

// Utility functions
export function formatCurrency(value: number, currency: string = 'USD'): string {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: currency,
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(value);
}

export function formatPercentage(value: number, decimals: number = 1): string {
  return `${value.toFixed(decimals)}%`;
}

export function getBudgetStatusColor(utilization: number): {
  text: string;
  bg: string;
  border: string;
} {
  if (utilization >= 100) {
    return {
      text: 'text-red-600 dark:text-red-400',
      bg: 'bg-red-500',
      border: 'border-red-500',
    };
  } else if (utilization >= 90) {
    return {
      text: 'text-yellow-600 dark:text-yellow-400',
      bg: 'bg-yellow-500',
      border: 'border-yellow-500',
    };
  } else if (utilization >= 80) {
    return {
      text: 'text-orange-600 dark:text-orange-400',
      bg: 'bg-orange-500',
      border: 'border-orange-500',
    };
  } else {
    return {
      text: 'text-green-600 dark:text-green-400',
      bg: 'bg-green-500',
      border: 'border-green-500',
    };
  }
}

export function getPriorityColor(priority: OptimizationPriority): {
  text: string;
  bg: string;
  border: string;
} {
  switch (priority) {
    case 'high':
      return {
        text: 'text-red-700 dark:text-red-300',
        bg: 'bg-red-100 dark:bg-red-900/30',
        border: 'border-red-300 dark:border-red-700',
      };
    case 'medium':
      return {
        text: 'text-yellow-700 dark:text-yellow-300',
        bg: 'bg-yellow-100 dark:bg-yellow-900/30',
        border: 'border-yellow-300 dark:border-yellow-700',
      };
    case 'low':
      return {
        text: 'text-blue-700 dark:text-blue-300',
        bg: 'bg-blue-100 dark:bg-blue-900/30',
        border: 'border-blue-300 dark:border-blue-700',
      };
  }
}
