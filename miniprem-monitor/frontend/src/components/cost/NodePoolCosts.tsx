import React from 'react';
import clsx from 'clsx';
import { Server, DollarSign } from 'lucide-react';
import { NodePoolCost, formatCurrency } from '../../types/cost';

interface NodePoolCostsProps {
  pools: NodePoolCost[];
}

const NodePoolCosts: React.FC<NodePoolCostsProps> = ({ pools }) => {
  // Find the maximum monthly cost for relative sizing of bars
  const maxMonthlyCost = Math.max(...pools.map((pool) => pool.monthly_projection));

  return (
    <div className="bg-white dark:bg-gray-800 rounded-lg p-6 border border-gray-200 dark:border-gray-700 shadow-sm">
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <h3 className="text-lg font-semibold text-gray-900 dark:text-gray-100 flex items-center">
          <Server className="w-5 h-5 mr-2 text-indigo-600 dark:text-indigo-400" />
          Node Pool Costs
        </h3>
        <div className="text-xs text-gray-500 dark:text-gray-400">
          {pools.length} pool{pools.length !== 1 ? 's' : ''}
        </div>
      </div>

      {/* Node Pool Cards */}
      <div className="space-y-4">
        {pools.map((pool) => {
          const barWidth = (pool.monthly_projection / maxMonthlyCost) * 100;
          const isGpuPool =
            pool.instance_type.toLowerCase().includes('g5') ||
            pool.instance_type.toLowerCase().includes('gpu') ||
            pool.instance_type.toLowerCase().includes('p3') ||
            pool.instance_type.toLowerCase().includes('p4');

          return (
            <div
              key={pool.name}
              className={clsx(
                'p-4 rounded-lg border-2 transition-all hover:shadow-md',
                isGpuPool
                  ? 'border-purple-200 dark:border-purple-800 bg-gradient-to-r from-purple-50 to-pink-50 dark:from-purple-900/20 dark:to-pink-900/20'
                  : 'border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-700/30'
              )}
            >
              {/* Pool Header */}
              <div className="flex items-start justify-between mb-3">
                <div className="flex-1">
                  <div className="flex items-center space-x-2 mb-2">
                    <h4 className="text-base font-semibold text-gray-900 dark:text-gray-100">
                      {pool.name}
                    </h4>
                    {isGpuPool && (
                      <span className="text-xs bg-purple-500 text-white px-2 py-1 rounded font-medium">
                        GPU
                      </span>
                    )}
                  </div>

                  <div className="flex items-center space-x-3 text-sm">
                    <span className="px-2 py-1 bg-gray-200 dark:bg-gray-700 text-gray-700 dark:text-gray-300 rounded font-mono text-xs">
                      {pool.instance_type}
                    </span>
                    <span className="text-gray-600 dark:text-gray-400">
                      {pool.current_nodes} node{pool.current_nodes !== 1 ? 's' : ''}
                    </span>
                  </div>
                </div>

                <div className="text-right">
                  <div className="text-2xl font-bold text-gray-900 dark:text-gray-100">
                    {formatCurrency(pool.monthly_projection)}
                  </div>
                  <div className="text-xs text-gray-500 dark:text-gray-400">per month</div>
                </div>
              </div>

              {/* Cost Breakdown */}
              <div className="grid grid-cols-3 gap-3 mb-3 text-xs">
                <div className="p-2 bg-white dark:bg-gray-800 rounded">
                  <div className="text-gray-600 dark:text-gray-400 mb-1">Hourly</div>
                  <div className="font-semibold text-gray-900 dark:text-gray-100">
                    {formatCurrency(pool.hourly_cost)}/hr
                  </div>
                </div>
                <div className="p-2 bg-white dark:bg-gray-800 rounded">
                  <div className="text-gray-600 dark:text-gray-400 mb-1">Daily</div>
                  <div className="font-semibold text-gray-900 dark:text-gray-100">
                    {formatCurrency(pool.daily_cost)}/day
                  </div>
                </div>
                <div className="p-2 bg-white dark:bg-gray-800 rounded">
                  <div className="text-gray-600 dark:text-gray-400 mb-1">Per Node</div>
                  <div className="font-semibold text-gray-900 dark:text-gray-100">
                    {formatCurrency(pool.cost_per_node_hourly)}/hr
                  </div>
                </div>
              </div>

              {/* Cost Bar */}
              <div className="relative">
                <div className="w-full bg-gray-200 dark:bg-gray-700 rounded-full h-6 overflow-hidden">
                  <div
                    className={clsx(
                      'h-6 rounded-full transition-all duration-500 flex items-center justify-end px-3',
                      isGpuPool
                        ? 'bg-gradient-to-r from-purple-500 to-pink-500'
                        : 'bg-gradient-to-r from-blue-500 to-indigo-500'
                    )}
                    style={{ width: `${Math.max(barWidth, 10)}%` }}
                  >
                    <span className="text-xs font-medium text-white whitespace-nowrap">
                      {formatCurrency(pool.monthly_projection)}
                    </span>
                  </div>
                </div>

                {/* Percentage label */}
                <div className="absolute -top-5 right-0 text-xs text-gray-500 dark:text-gray-400">
                  {((pool.monthly_projection / maxMonthlyCost) * 100).toFixed(0)}% of total
                </div>
              </div>

              {/* Additional Info */}
              {isGpuPool && (
                <div className="mt-3 p-2 bg-purple-100 dark:bg-purple-900/30 rounded text-xs text-purple-700 dark:text-purple-300">
                  <div className="flex items-center space-x-1">
                    <DollarSign className="w-3 h-3" />
                    <span className="font-medium">
                      High-cost GPU instances - Consider reserved instances for 30-60% savings
                    </span>
                  </div>
                </div>
              )}
            </div>
          );
        })}
      </div>

      {/* Summary Footer */}
      <div className="mt-6 pt-6 border-t border-gray-200 dark:border-gray-700">
        <div className="grid grid-cols-2 gap-4">
          <div className="flex items-center justify-between">
            <span className="text-sm text-gray-600 dark:text-gray-400">Total Nodes</span>
            <span className="text-lg font-bold text-gray-900 dark:text-gray-100">
              {pools.reduce((sum, pool) => sum + pool.current_nodes, 0)}
            </span>
          </div>
          <div className="flex items-center justify-between">
            <span className="text-sm text-gray-600 dark:text-gray-400">Total Monthly Cost</span>
            <span className="text-lg font-bold text-gray-900 dark:text-gray-100">
              {formatCurrency(pools.reduce((sum, pool) => sum + pool.monthly_projection, 0))}
            </span>
          </div>
        </div>
      </div>
    </div>
  );
};

export default NodePoolCosts;
