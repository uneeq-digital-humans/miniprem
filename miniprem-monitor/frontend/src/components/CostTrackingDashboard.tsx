import React, { useState, useEffect, useCallback } from 'react';
import clsx from 'clsx';
import { DollarSign, RefreshCw, AlertTriangle, Loader2 } from 'lucide-react';
import CloudProviderBadge from './CloudProviderBadge';
import CurrentPeriodCards from './cost/CurrentPeriodCards';
import CostTrendChart from './cost/CostTrendChart';
import CostBreakdownChart from './cost/CostBreakdownChart';
import NodePoolCosts from './cost/NodePoolCosts';
import OptimizationRecommendations from './cost/OptimizationRecommendations';
import { EnhancedCostResponse, CloudProvider } from '../types/cost';

interface CostTrackingDashboardProps {
  clusterId?: string;
  provider?: string;
}

const CostTrackingDashboard: React.FC<CostTrackingDashboardProps> = ({
  clusterId,
  provider,
}) => {
  const [costData, setCostData] = useState<EnhancedCostResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null);
  const [refreshing, setRefreshing] = useState(false);

  // Fetch cost data from backend
  const fetchCostData = useCallback(async (isRefresh = false) => {
    if (isRefresh) {
      setRefreshing(true);
    } else {
      setLoading(true);
    }
    setError(null);

    try {
      // Build query params
      const params = new URLSearchParams();
      if (clusterId) params.append('cluster_id', clusterId);
      if (provider) params.append('provider', provider);

      const url = `/api/kubernetes/costs/enhanced${params.toString() ? `?${params.toString()}` : ''}`;
      const response = await fetch(url);
      const data = await response.json();

      if (response.ok && data.success) {
        setCostData(data);
        setLastUpdated(new Date());
        setError(null);
      } else {
        setError(data.error || 'Failed to fetch cost data');
        setCostData(null);
      }
    } catch (err) {
      console.error('Error fetching cost data:', err);
      setError('Network error fetching cost data');
      setCostData(null);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [clusterId, provider]);

  // Initial fetch and auto-refresh every 5 minutes
  useEffect(() => {
    fetchCostData();

    const interval = setInterval(() => {
      fetchCostData(true);
    }, 300000); // 5 minutes

    return () => clearInterval(interval);
  }, [fetchCostData]);

  // Manual refresh handler
  const handleRefresh = () => {
    fetchCostData(true);
  };

  // Loading skeleton
  if (loading && !costData) {
    return (
      <div className="bg-white dark:bg-gray-800 rounded-lg p-6 border border-gray-200 dark:border-gray-700 mt-6">
        <div className="flex items-center space-x-3 mb-6">
          <Loader2 className="w-6 h-6 text-blue-500 animate-spin" />
          <h2 className="text-xl font-semibold text-gray-900 dark:text-gray-100">
            Loading Cost Tracking Data...
          </h2>
        </div>
        <div className="space-y-6">
          {/* Skeleton cards */}
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            {[1, 2, 3].map((i) => (
              <div
                key={i}
                className="h-48 bg-gray-100 dark:bg-gray-700 rounded-lg animate-pulse"
              />
            ))}
          </div>
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            {[1, 2].map((i) => (
              <div
                key={i}
                className="h-80 bg-gray-100 dark:bg-gray-700 rounded-lg animate-pulse"
              />
            ))}
          </div>
        </div>
      </div>
    );
  }

  // Error state
  if (error) {
    return (
      <div className="bg-red-50 dark:bg-red-900/20 rounded-lg p-6 border border-red-200 dark:border-red-800 mt-6">
        <div className="flex items-center space-x-3 mb-2">
          <AlertTriangle className="w-6 h-6 text-red-600 dark:text-red-400" />
          <h2 className="text-xl font-semibold text-red-700 dark:text-red-300">
            Cost Tracking Error
          </h2>
        </div>
        <p className="text-red-600 dark:text-red-400 mb-4">{error}</p>
        <button
          onClick={handleRefresh}
          className="px-4 py-2 bg-red-600 hover:bg-red-700 text-white rounded-lg transition-colors flex items-center space-x-2"
        >
          <RefreshCw className="w-4 h-4" />
          <span>Retry</span>
        </button>
      </div>
    );
  }

  // No data available
  if (!costData) {
    return (
      <div className="bg-gray-50 dark:bg-gray-800 rounded-lg p-6 border border-gray-200 dark:border-gray-700 mt-6">
        <div className="text-center py-12">
          <DollarSign className="w-12 h-12 text-gray-400 mx-auto mb-3" />
          <p className="text-gray-600 dark:text-gray-400 text-lg font-medium">
            Cost data unavailable
          </p>
          <p className="text-gray-500 dark:text-gray-500 text-sm mt-2">
            Cost tracking data is not available for this cluster.
          </p>
          <button
            onClick={handleRefresh}
            className="mt-4 px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg transition-colors"
          >
            Try Again
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6 mt-6">
      {/* Header */}
      <div className="bg-gradient-to-r from-green-50 to-emerald-50 dark:from-green-900/20 dark:to-emerald-900/20 rounded-lg p-6 border-2 border-green-200 dark:border-green-800">
        <div className="flex items-center justify-between">
          <div className="flex items-center space-x-4">
            <div className="p-3 bg-green-100 dark:bg-green-900/30 rounded-lg">
              <DollarSign className="w-8 h-8 text-green-600 dark:text-green-400" />
            </div>
            <div>
              <h2 className="text-2xl font-bold text-gray-900 dark:text-gray-100 mb-1">
                Cost Tracking
              </h2>
              <div className="flex items-center space-x-3 text-sm text-gray-600 dark:text-gray-400">
                <CloudProviderBadge provider={costData.provider} />
                <span>•</span>
                <span className="font-medium">{costData.cluster_name}</span>
                {lastUpdated && (
                  <>
                    <span>•</span>
                    <span>Updated {lastUpdated.toLocaleTimeString()}</span>
                  </>
                )}
              </div>
            </div>
          </div>

          {/* Refresh Button */}
          <button
            onClick={handleRefresh}
            disabled={refreshing}
            className={clsx(
              'flex items-center space-x-2 px-4 py-2 rounded-lg transition-colors',
              refreshing
                ? 'bg-gray-100 dark:bg-gray-700 text-gray-400 cursor-not-allowed'
                : 'bg-white dark:bg-gray-800 text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-750 border border-gray-300 dark:border-gray-600'
            )}
          >
            <RefreshCw className={clsx('w-4 h-4', refreshing && 'animate-spin')} />
            <span className="text-sm font-medium">
              {refreshing ? 'Refreshing...' : 'Refresh'}
            </span>
          </button>
        </div>
      </div>

      {/* Current Period Cards */}
      <CurrentPeriodCards
        data={costData.current_period}
        budget={costData.budget_status}
      />

      {/* Charts Grid */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <CostTrendChart data={costData.cost_trends} />
        <CostBreakdownChart data={costData.cost_breakdown} />
      </div>

      {/* Node Pool Costs */}
      <NodePoolCosts pools={costData.node_pool_costs} />

      {/* Optimization Recommendations */}
      <OptimizationRecommendations recs={costData.optimization_recommendations} />

      {/* Footer Info */}
      <div className="bg-blue-50 dark:bg-blue-900/20 rounded-lg p-4 border border-blue-200 dark:border-blue-800">
        <div className="flex items-start space-x-3">
          <div className="flex-shrink-0">
            <svg
              className="w-5 h-5 text-blue-600 dark:text-blue-400"
              fill="currentColor"
              viewBox="0 0 20 20"
            >
              <path
                fillRule="evenodd"
                d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z"
                clipRule="evenodd"
              />
            </svg>
          </div>
          <div className="flex-1">
            <h4 className="text-sm font-semibold text-blue-900 dark:text-blue-300 mb-1">
              About Cost Tracking
            </h4>
            <p className="text-xs text-blue-800 dark:text-blue-400 leading-relaxed">
              Cost estimates are calculated based on current resource usage and cloud provider
              pricing. Actual costs may vary based on data transfer, storage operations, and
              additional services. Projections assume consistent usage patterns throughout the
              billing period. For exact billing information, please refer to your cloud
              provider's billing dashboard.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
};

export default CostTrackingDashboard;
