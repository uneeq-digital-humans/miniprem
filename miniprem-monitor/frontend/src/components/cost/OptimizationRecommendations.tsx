import React, { useState } from 'react';
import clsx from 'clsx';
import { Lightbulb, ChevronDown, ChevronUp, ExternalLink, Check } from 'lucide-react';
import {
  OptimizationRecommendation,
  formatCurrency,
  formatPercentage,
  getPriorityColor,
} from '../../types/cost';

interface OptimizationRecommendationsProps {
  recs: OptimizationRecommendation[];
}

const OptimizationRecommendations: React.FC<OptimizationRecommendationsProps> = ({ recs }) => {
  const [expandedIndex, setExpandedIndex] = useState<number | null>(null);

  // Sort by priority (high > medium > low) and savings amount
  const sortedRecs = [...recs].sort((a, b) => {
    const priorityOrder = { high: 3, medium: 2, low: 1 };
    const priorityDiff = priorityOrder[b.priority] - priorityOrder[a.priority];
    if (priorityDiff !== 0) return priorityDiff;
    return b.potential_savings - a.potential_savings;
  });

  const toggleExpanded = (index: number) => {
    setExpandedIndex(expandedIndex === index ? null : index);
  };

  // Calculate total potential savings
  const totalSavings = recs.reduce((sum, rec) => sum + rec.potential_savings, 0);
  const totalSavingsPercentage = recs.reduce((sum, rec) => sum + rec.savings_percentage, 0);

  return (
    <div className="bg-white dark:bg-gray-800 rounded-lg p-6 border border-gray-200 dark:border-gray-700 shadow-sm">
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center space-x-2">
          <Lightbulb className="w-5 h-5 text-yellow-600 dark:text-yellow-400" />
          <h3 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
            Optimization Opportunities
          </h3>
        </div>

        {/* Total Savings Badge */}
        {totalSavings > 0 && (
          <div className="px-4 py-2 bg-green-100 dark:bg-green-900/30 border border-green-300 dark:border-green-700 rounded-lg">
            <div className="text-xs text-green-700 dark:text-green-300 mb-1">
              Potential Savings
            </div>
            <div className="text-lg font-bold text-green-700 dark:text-green-300">
              {formatCurrency(totalSavings)}/mo
            </div>
          </div>
        )}
      </div>

      {/* No recommendations */}
      {sortedRecs.length === 0 && (
        <div className="text-center py-12">
          <Check className="w-12 h-12 text-green-500 mx-auto mb-3" />
          <p className="text-gray-600 dark:text-gray-400 text-lg font-medium">
            All optimized!
          </p>
          <p className="text-gray-500 dark:text-gray-500 text-sm mt-2">
            No optimization recommendations at this time.
          </p>
        </div>
      )}

      {/* Recommendations List */}
      <div className="space-y-4">
        {sortedRecs.map((rec, index) => {
          const isExpanded = expandedIndex === index;
          const colors = getPriorityColor(rec.priority);

          return (
            <div
              key={index}
              className={clsx(
                'border-2 rounded-lg transition-all',
                colors.border,
                colors.bg
              )}
            >
              {/* Recommendation Header */}
              <button
                onClick={() => toggleExpanded(index)}
                className="w-full p-4 text-left"
              >
                <div className="flex items-start justify-between">
                  <div className="flex-1">
                    {/* Priority Badge */}
                    <div className="flex items-center space-x-3 mb-2">
                      <span
                        className={clsx(
                          'px-2 py-1 text-xs font-bold uppercase rounded',
                          rec.priority === 'high' &&
                            'bg-red-500 text-white',
                          rec.priority === 'medium' &&
                            'bg-yellow-500 text-white',
                          rec.priority === 'low' &&
                            'bg-blue-500 text-white'
                        )}
                      >
                        {rec.priority} Priority
                      </span>
                      <span className={clsx('text-sm font-medium', colors.text)}>
                        {rec.type}
                      </span>
                    </div>

                    {/* Description */}
                    <p className="text-sm text-gray-700 dark:text-gray-300 mb-2">
                      {rec.description}
                    </p>

                    {/* Savings */}
                    <div className="flex items-center space-x-4 text-sm">
                      <div className="flex items-center space-x-1">
                        <span className="text-gray-600 dark:text-gray-400">
                          Potential savings:
                        </span>
                        <span className="font-bold text-green-600 dark:text-green-400">
                          {formatCurrency(rec.potential_savings)}/mo
                        </span>
                      </div>
                      <div className="px-2 py-1 bg-green-100 dark:bg-green-900/30 rounded text-green-700 dark:text-green-300 font-semibold">
                        {formatPercentage(rec.savings_percentage, 0)}
                      </div>
                    </div>
                  </div>

                  {/* Expand/Collapse Icon */}
                  <div className="ml-4">
                    {isExpanded ? (
                      <ChevronUp className="w-5 h-5 text-gray-500" />
                    ) : (
                      <ChevronDown className="w-5 h-5 text-gray-500" />
                    )}
                  </div>
                </div>
              </button>

              {/* Expanded Details */}
              {isExpanded && (
                <div className="px-4 pb-4 border-t border-gray-200 dark:border-gray-700">
                  <div className="pt-4 space-y-4">
                    {/* Implementation Details */}
                    <div>
                      <h4 className="text-sm font-semibold text-gray-900 dark:text-gray-100 mb-2">
                        Implementation Details
                      </h4>
                      <div className="text-sm text-gray-700 dark:text-gray-300 space-y-2">
                        {rec.type === 'Reserved Instances' && (
                          <div className="space-y-2">
                            <p>
                              Purchase reserved instances to lock in discounted rates for 1-3 years:
                            </p>
                            <ul className="list-disc list-inside ml-4 space-y-1 text-xs">
                              <li>1-year commitment: ~30% savings</li>
                              <li>3-year commitment: ~60% savings</li>
                              <li>Payment options: All upfront, partial upfront, or no upfront</li>
                              <li>Best for stable, predictable workloads</li>
                            </ul>
                          </div>
                        )}
                        {rec.type === 'Auto-Scaling' && (
                          <div className="space-y-2">
                            <p>
                              Enable time-based auto-scaling to reduce costs during off-hours:
                            </p>
                            <ul className="list-disc list-inside ml-4 space-y-1 text-xs">
                              <li>Scale down to 20% capacity during nights/weekends</li>
                              <li>Maintain minimum replicas for high availability</li>
                              <li>Use metrics-based scaling for traffic patterns</li>
                              <li>Configure gradual scale-up for morning traffic</li>
                            </ul>
                          </div>
                        )}
                        {rec.type === 'Spot Instances' && (
                          <div className="space-y-2">
                            <p>
                              Use spot instances for non-critical workloads at up to 90% discount:
                            </p>
                            <ul className="list-disc list-inside ml-4 space-y-1 text-xs">
                              <li>Best for batch processing and development environments</li>
                              <li>Implement graceful shutdown handling</li>
                              <li>Mix with on-demand for critical services</li>
                              <li>Use spot instance pools for better availability</li>
                            </ul>
                          </div>
                        )}
                        {rec.type === 'Right-Sizing' && (
                          <div className="space-y-2">
                            <p>
                              Optimize instance sizes based on actual resource utilization:
                            </p>
                            <ul className="list-disc list-inside ml-4 space-y-1 text-xs">
                              <li>Downgrade over-provisioned instances</li>
                              <li>Upgrade under-provisioned instances causing throttling</li>
                              <li>Monitor CPU, memory, and network metrics</li>
                              <li>Test performance after changes</li>
                            </ul>
                          </div>
                        )}
                        {rec.type === 'Storage Optimization' && (
                          <div className="space-y-2">
                            <p>
                              Optimize storage costs with lifecycle policies and tier selection:
                            </p>
                            <ul className="list-disc list-inside ml-4 space-y-1 text-xs">
                              <li>Move infrequently accessed data to cheaper storage tiers</li>
                              <li>Implement automated data lifecycle policies</li>
                              <li>Delete old snapshots and unused volumes</li>
                              <li>Enable compression where applicable</li>
                            </ul>
                          </div>
                        )}
                        {rec.type === 'GPU Time-Slicing' && (
                          <div className="space-y-2">
                            <p>
                              Share GPUs across multiple pods to maximize utilization:
                            </p>
                            <ul className="list-disc list-inside ml-4 space-y-1 text-xs">
                              <li>Configure 2-4 replicas per GPU for rendering workloads</li>
                              <li>Monitor GPU utilization and adjust sharing ratio</li>
                              <li>Ensure fair resource allocation with limits</li>
                              <li>Test performance impact on applications</li>
                            </ul>
                          </div>
                        )}
                      </div>
                    </div>

                    {/* Action Buttons */}
                    <div className="flex items-center space-x-3">
                      <button className="flex items-center space-x-2 px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg transition-colors text-sm font-medium">
                        <ExternalLink className="w-4 h-4" />
                        <span>Learn More</span>
                      </button>
                      <button className="flex items-center space-x-2 px-4 py-2 bg-gray-100 hover:bg-gray-200 dark:bg-gray-700 dark:hover:bg-gray-600 text-gray-900 dark:text-gray-100 rounded-lg transition-colors text-sm font-medium">
                        <span>Mark as Applied</span>
                      </button>
                    </div>

                    {/* Warning for High Priority Items */}
                    {rec.priority === 'high' && (
                      <div className="p-3 bg-orange-50 dark:bg-orange-900/20 border border-orange-200 dark:border-orange-800 rounded text-xs text-orange-700 dark:text-orange-300">
                        <strong>Important:</strong> This high-priority recommendation could
                        significantly reduce your costs. Review and implement as soon as possible.
                      </div>
                    )}
                  </div>
                </div>
              )}
            </div>
          );
        })}
      </div>

      {/* Summary Footer */}
      {totalSavings > 0 && (
        <div className="mt-6 pt-6 border-t border-gray-200 dark:border-gray-700">
          <div className="flex items-center justify-between text-sm">
            <div className="text-gray-600 dark:text-gray-400">
              Implementing all recommendations could save up to:
            </div>
            <div className="text-right">
              <div className="text-2xl font-bold text-green-600 dark:text-green-400">
                {formatCurrency(totalSavings)}/mo
              </div>
              <div className="text-xs text-gray-500 dark:text-gray-400">
                ~{formatPercentage(totalSavingsPercentage / recs.length, 0)} average reduction
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default OptimizationRecommendations;
