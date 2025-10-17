/**
 * Cost-related type definitions for MiniPrem Monitor
 */

export interface CostItem {
  cost: number;
  percentage: number;
}

export interface CostBreakdown {
  compute: CostItem;
  networking: CostItem;
  storage: CostItem;
  monitoring: CostItem;
}

/**
 * Format a number as currency (USD)
 */
export function formatCurrency(amount: number): string {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(amount);
}

/**
 * Format a number as percentage
 */
export function formatPercentage(value: number): string {
  return `${value.toFixed(1)}%`;
}
