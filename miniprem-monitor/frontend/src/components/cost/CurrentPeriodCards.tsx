import React from 'react';
import clsx from 'clsx';
import { DollarSign, TrendingUp, Wallet } from 'lucide-react';
import {
  CurrentPeriod,
  BudgetStatus,
  formatCurrency,
  formatPercentage,
  getBudgetStatusColor,
} from '../../types/cost';

interface CurrentPeriodCardsProps {
  data: CurrentPeriod;
  budget: BudgetStatus;
}

const CurrentPeriodCards: React.FC<CurrentPeriodCardsProps> = ({ data, budget }) => {
  const budgetColors = getBudgetStatusColor(budget.utilization_percentage);

  return (
    <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-6">
      {/* Current Spend Card */}
      <div className="bg-white dark:bg-gray-800 rounded-lg p-6 border border-gray-200 dark:border-gray-700 shadow-sm">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center space-x-2">
            <DollarSign className="w-5 h-5 text-green-600 dark:text-green-400" />
            <h3 className="text-sm font-medium text-gray-600 dark:text-gray-400">
              Current Spend
            </h3>
          </div>
        </div>

        <div className="space-y-3">
          <div>
            <div className="text-3xl font-bold text-gray-900 dark:text-gray-100">
              {formatCurrency(data.total_cost)}
            </div>
            <div className="text-sm text-gray-500 dark:text-gray-400 mt-1">
              {new Date(data.start_date).toLocaleDateString()} -{' '}
              {new Date(data.end_date).toLocaleDateString()}
            </div>
          </div>

          {/* Progress Bar */}
          <div className="space-y-2">
            <div className="w-full bg-gray-200 dark:bg-gray-700 rounded-full h-3">
              <div
                className={clsx('h-3 rounded-full transition-all duration-500', budgetColors.bg)}
                style={{
                  width: `${Math.min(budget.utilization_percentage, 100)}%`,
                }}
              />
            </div>
            <div className="flex items-center justify-between text-xs">
              <span className={budgetColors.text}>
                {formatPercentage(budget.utilization_percentage, 0)} of budget
              </span>
              <span className="text-gray-500 dark:text-gray-400">
                {formatCurrency(budget.monthly_budget)}
              </span>
            </div>
          </div>

          {/* Daily Average */}
          <div className="pt-3 border-t border-gray-200 dark:border-gray-700">
            <div className="flex items-center justify-between">
              <span className="text-xs text-gray-600 dark:text-gray-400">Daily Average</span>
              <span className="text-sm font-semibold text-gray-900 dark:text-gray-100">
                {formatCurrency(data.daily_average)}
              </span>
            </div>
          </div>
        </div>
      </div>

      {/* Monthly Projection Card */}
      <div className="bg-white dark:bg-gray-800 rounded-lg p-6 border border-gray-200 dark:border-gray-700 shadow-sm">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center space-x-2">
            <TrendingUp className="w-5 h-5 text-blue-600 dark:text-blue-400" />
            <h3 className="text-sm font-medium text-gray-600 dark:text-gray-400">
              Monthly Projection
            </h3>
          </div>
        </div>

        <div className="space-y-3">
          <div>
            <div className="text-3xl font-bold text-gray-900 dark:text-gray-100">
              {formatCurrency(data.projected_monthly)}
            </div>
            <div className="text-sm text-gray-500 dark:text-gray-400 mt-1">
              Projected for full month
            </div>
          </div>

          {/* Status Indicator */}
          <div
            className={clsx(
              'flex items-center justify-center space-x-2 py-2 rounded-lg',
              budget.on_track
                ? 'bg-green-50 dark:bg-green-900/20'
                : 'bg-red-50 dark:bg-red-900/20'
            )}
          >
            <div
              className={clsx(
                'w-2 h-2 rounded-full',
                budget.on_track ? 'bg-green-500' : 'bg-red-500 animate-pulse'
              )}
            />
            <span
              className={clsx(
                'text-sm font-medium',
                budget.on_track
                  ? 'text-green-700 dark:text-green-300'
                  : 'text-red-700 dark:text-red-300'
              )}
            >
              {budget.on_track ? 'On Track' : 'Over Budget'}
            </span>
          </div>

          {/* Comparison */}
          <div className="pt-3 border-t border-gray-200 dark:border-gray-700">
            <div className="flex items-center justify-between">
              <span className="text-xs text-gray-600 dark:text-gray-400">vs. Budget</span>
              <span
                className={clsx(
                  'text-sm font-semibold',
                  budget.projected_spend <= budget.monthly_budget
                    ? 'text-green-600 dark:text-green-400'
                    : 'text-red-600 dark:text-red-400'
                )}
              >
                {budget.projected_spend <= budget.monthly_budget ? '-' : '+'}
                {formatCurrency(Math.abs(budget.projected_spend - budget.monthly_budget))}
              </span>
            </div>
          </div>
        </div>
      </div>

      {/* Budget Status Card */}
      <div className="bg-white dark:bg-gray-800 rounded-lg p-6 border border-gray-200 dark:border-gray-700 shadow-sm">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center space-x-2">
            <Wallet className="w-5 h-5 text-purple-600 dark:text-purple-400" />
            <h3 className="text-sm font-medium text-gray-600 dark:text-gray-400">Budget Status</h3>
          </div>
        </div>

        <div className="space-y-3">
          <div>
            <div className="text-3xl font-bold text-gray-900 dark:text-gray-100">
              {formatCurrency(budget.monthly_budget)}
            </div>
            <div className="text-sm text-gray-500 dark:text-gray-400 mt-1">Monthly budget</div>
          </div>

          {/* Remaining Budget */}
          <div
            className={clsx(
              'flex items-center justify-between py-3 px-4 rounded-lg',
              budget.remaining >= 0
                ? 'bg-gray-50 dark:bg-gray-700/50'
                : 'bg-red-50 dark:bg-red-900/20'
            )}
          >
            <span className="text-sm text-gray-600 dark:text-gray-400">Remaining</span>
            <span
              className={clsx(
                'text-lg font-bold',
                budget.remaining >= 0
                  ? 'text-gray-900 dark:text-gray-100'
                  : 'text-red-600 dark:text-red-400'
              )}
            >
              {formatCurrency(budget.remaining)}
            </span>
          </div>

          {/* Budget Breakdown */}
          <div className="pt-3 border-t border-gray-200 dark:border-gray-700 space-y-2">
            <div className="flex items-center justify-between text-xs">
              <span className="text-gray-600 dark:text-gray-400">Current Spend</span>
              <span className="text-gray-900 dark:text-gray-100">
                {formatCurrency(budget.current_spend)}
              </span>
            </div>
            <div className="flex items-center justify-between text-xs">
              <span className="text-gray-600 dark:text-gray-400">Projected Spend</span>
              <span className="text-gray-900 dark:text-gray-100">
                {formatCurrency(budget.projected_spend)}
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default CurrentPeriodCards;
