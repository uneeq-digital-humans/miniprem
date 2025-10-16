import React, { useState } from 'react';
import clsx from 'clsx';
import { PieChart, Server, Network, HardDrive, Activity } from 'lucide-react';
import { CostBreakdown, formatCurrency, formatPercentage } from '../../types/cost';

interface CostBreakdownChartProps {
  data: CostBreakdown;
}

interface BreakdownItem {
  label: string;
  value: number;
  percentage: number;
  color: string;
  icon: React.ComponentType<{ className?: string }>;
}

const CostBreakdownChart: React.FC<CostBreakdownChartProps> = ({ data }) => {
  const [hoveredItem, setHoveredItem] = useState<string | null>(null);

  // Convert breakdown to array format with colors and icons
  const breakdownItems: BreakdownItem[] = [
    {
      label: 'Compute',
      value: data.compute.cost,
      percentage: data.compute.percentage,
      color: '#3b82f6', // blue-500
      icon: Server,
    },
    {
      label: 'Networking',
      value: data.networking.cost,
      percentage: data.networking.percentage,
      color: '#a855f7', // purple-500
      icon: Network,
    },
    {
      label: 'Storage',
      value: data.storage.cost,
      percentage: data.storage.percentage,
      color: '#f97316', // orange-500
      icon: HardDrive,
    },
    {
      label: 'Monitoring',
      value: data.monitoring.cost,
      percentage: data.monitoring.percentage,
      color: '#10b981', // green-500
      icon: Activity,
    },
  ];

  const totalCost = breakdownItems.reduce((sum, item) => sum + item.value, 0);

  // Calculate pie chart segments
  const calculateSegments = () => {
    let cumulativePercentage = 0;
    const segments: Array<{
      label: string;
      offset: number;
      percentage: number;
      color: string;
    }> = [];

    breakdownItems.forEach((item) => {
      segments.push({
        label: item.label,
        offset: cumulativePercentage,
        percentage: item.percentage,
        color: item.color,
      });
      cumulativePercentage += item.percentage;
    });

    return segments;
  };

  const segments = calculateSegments();

  return (
    <div className="bg-white dark:bg-gray-800 rounded-lg p-6 border border-gray-200 dark:border-gray-700 shadow-sm">
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <h3 className="text-lg font-semibold text-gray-900 dark:text-gray-100 flex items-center">
          <PieChart className="w-5 h-5 mr-2 text-purple-600 dark:text-purple-400" />
          Cost Breakdown
        </h3>
      </div>

      {/* Pie Chart */}
      <div className="flex items-center justify-center mb-6">
        <div className="relative w-48 h-48">
          <svg viewBox="0 0 100 100" className="transform -rotate-90">
            {segments.map((segment, index) => {
              const circumference = 2 * Math.PI * 40; // radius = 40
              const strokeDasharray = `${(segment.percentage / 100) * circumference} ${circumference}`;
              const strokeDashoffset = -((segment.offset / 100) * circumference);

              return (
                <circle
                  key={segment.label}
                  cx="50"
                  cy="50"
                  r="40"
                  fill="none"
                  stroke={segment.color}
                  strokeWidth={hoveredItem === segment.label ? '22' : '20'}
                  strokeDasharray={strokeDasharray}
                  strokeDashoffset={strokeDashoffset}
                  className="transition-all duration-300 cursor-pointer"
                  onMouseEnter={() => setHoveredItem(segment.label)}
                  onMouseLeave={() => setHoveredItem(null)}
                  opacity={hoveredItem && hoveredItem !== segment.label ? 0.5 : 1}
                />
              );
            })}
          </svg>

          {/* Center text */}
          <div className="absolute inset-0 flex items-center justify-center">
            <div className="text-center">
              <div className="text-2xl font-bold text-gray-900 dark:text-gray-100">
                {formatCurrency(totalCost)}
              </div>
              <div className="text-xs text-gray-500 dark:text-gray-400">Total</div>
            </div>
          </div>
        </div>
      </div>

      {/* Legend and Details */}
      <div className="space-y-3">
        {breakdownItems.map((item) => {
          const Icon = item.icon;
          const isHovered = hoveredItem === item.label;

          return (
            <div
              key={item.label}
              className={clsx(
                'flex items-center justify-between p-3 rounded-lg border-2 transition-all cursor-pointer',
                isHovered
                  ? 'border-gray-300 dark:border-gray-600 bg-gray-50 dark:bg-gray-700/50 scale-105'
                  : 'border-transparent bg-gray-50 dark:bg-gray-700/30'
              )}
              onMouseEnter={() => setHoveredItem(item.label)}
              onMouseLeave={() => setHoveredItem(null)}
            >
              <div className="flex items-center space-x-3">
                <div
                  className="p-2 rounded-lg"
                  style={{ backgroundColor: `${item.color}20` }}
                >
                  <Icon className="w-4 h-4" style={{ color: item.color }} />
                </div>
                <div>
                  <div className="text-sm font-medium text-gray-900 dark:text-gray-100">
                    {item.label}
                  </div>
                  <div className="text-xs text-gray-500 dark:text-gray-400">
                    {formatPercentage(item.percentage)} of total
                  </div>
                </div>
              </div>

              <div className="text-right">
                <div className="text-sm font-semibold text-gray-900 dark:text-gray-100">
                  {formatCurrency(item.value)}
                </div>
                {/* Progress bar */}
                <div className="w-24 bg-gray-200 dark:bg-gray-600 rounded-full h-1.5 mt-2">
                  <div
                    className="h-1.5 rounded-full transition-all"
                    style={{
                      width: `${item.percentage}%`,
                      backgroundColor: item.color,
                    }}
                  />
                </div>
              </div>
            </div>
          );
        })}
      </div>

      {/* Summary */}
      <div className="mt-4 pt-4 border-t border-gray-200 dark:border-gray-700">
        <div className="flex items-center justify-between text-sm">
          <span className="text-gray-600 dark:text-gray-400">
            Largest cost category
          </span>
          <span className="font-semibold text-gray-900 dark:text-gray-100">
            {breakdownItems.reduce((max, item) =>
              item.value > max.value ? item : max
            ).label} ({formatPercentage(
              breakdownItems.reduce((max, item) =>
                item.value > max.value ? item : max
              ).percentage
            )})
          </span>
        </div>
      </div>
    </div>
  );
};

export default CostBreakdownChart;
