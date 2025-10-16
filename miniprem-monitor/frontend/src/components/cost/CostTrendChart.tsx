import React, { useState } from 'react';
import clsx from 'clsx';
import { TrendingUp, TrendingDown } from 'lucide-react';
import { CostTrends, formatCurrency } from '../../types/cost';

interface CostTrendChartProps {
  data: CostTrends;
}

const CostTrendChart: React.FC<CostTrendChartProps> = ({ data }) => {
  const [hoveredIndex, setHoveredIndex] = useState<number | null>(null);
  const [period, setPeriod] = useState<'7' | '30'>('7');

  const chartData = period === '7' ? data.last_7_days : data.last_30_days;
  const maxValue = Math.max(...chartData);
  const minValue = Math.min(...chartData);

  // Generate labels for the chart
  const generateLabels = () => {
    const labels: string[] = [];
    const today = new Date();

    for (let i = chartData.length - 1; i >= 0; i--) {
      const date = new Date(today);
      date.setDate(date.getDate() - i);
      labels.push(date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' }));
    }

    return labels;
  };

  const labels = generateLabels();

  // Calculate SVG points for the line chart
  const calculatePoints = () => {
    return chartData
      .map((value, index) => {
        const x = (index / (chartData.length - 1)) * 100;
        const y = 100 - ((value - minValue) / (maxValue - minValue)) * 80; // 80% for data area
        return `${x},${y}`;
      })
      .join(' ');
  };

  // Calculate area path for gradient fill
  const calculateAreaPath = () => {
    const points = chartData
      .map((value, index) => {
        const x = (index / (chartData.length - 1)) * 100;
        const y = 100 - ((value - minValue) / (maxValue - minValue)) * 80;
        return `${x},${y}`;
      });

    return `M 0,100 L ${points.join(' L ')} L 100,100 Z`;
  };

  return (
    <div className="bg-white dark:bg-gray-800 rounded-lg p-6 border border-gray-200 dark:border-gray-700 shadow-sm">
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <h3 className="text-lg font-semibold text-gray-900 dark:text-gray-100 flex items-center">
          <TrendingUp className="w-5 h-5 mr-2 text-blue-600 dark:text-blue-400" />
          Cost Trend
        </h3>

        {/* Period Selector */}
        <div className="flex items-center space-x-2 bg-gray-100 dark:bg-gray-700 rounded-lg p-1">
          <button
            onClick={() => setPeriod('7')}
            className={clsx(
              'px-3 py-1 text-xs font-medium rounded transition-all',
              period === '7'
                ? 'bg-white dark:bg-gray-600 text-gray-900 dark:text-gray-100 shadow'
                : 'text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-100'
            )}
          >
            7 Days
          </button>
          <button
            onClick={() => setPeriod('30')}
            className={clsx(
              'px-3 py-1 text-xs font-medium rounded transition-all',
              period === '30'
                ? 'bg-white dark:bg-gray-600 text-gray-900 dark:text-gray-100 shadow'
                : 'text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-100'
            )}
          >
            30 Days
          </button>
        </div>
      </div>

      {/* Chart */}
      <div className="relative" style={{ height: '240px' }}>
        <svg
          viewBox="0 0 100 100"
          preserveAspectRatio="none"
          className="w-full h-full"
          onMouseLeave={() => setHoveredIndex(null)}
        >
          {/* Gradient definition */}
          <defs>
            <linearGradient id="areaGradient" x1="0%" y1="0%" x2="0%" y2="100%">
              <stop offset="0%" stopColor="rgb(59, 130, 246)" stopOpacity="0.3" />
              <stop offset="100%" stopColor="rgb(59, 130, 246)" stopOpacity="0.05" />
            </linearGradient>
          </defs>

          {/* Area fill */}
          <path d={calculateAreaPath()} fill="url(#areaGradient)" />

          {/* Line */}
          <polyline
            points={calculatePoints()}
            fill="none"
            stroke="rgb(59, 130, 246)"
            strokeWidth="0.5"
            vectorEffect="non-scaling-stroke"
          />

          {/* Data points */}
          {chartData.map((value, index) => {
            const x = (index / (chartData.length - 1)) * 100;
            const y = 100 - ((value - minValue) / (maxValue - minValue)) * 80;

            return (
              <circle
                key={index}
                cx={x}
                cy={y}
                r={hoveredIndex === index ? '1.5' : '0.8'}
                fill="rgb(59, 130, 246)"
                className="transition-all cursor-pointer"
                onMouseEnter={() => setHoveredIndex(index)}
                vectorEffect="non-scaling-stroke"
              />
            );
          })}
        </svg>

        {/* Hover tooltip */}
        {hoveredIndex !== null && (
          <div
            className="absolute bg-gray-900 dark:bg-gray-700 text-white px-3 py-2 rounded-lg shadow-lg text-xs z-10 pointer-events-none"
            style={{
              left: `${(hoveredIndex / (chartData.length - 1)) * 100}%`,
              top: '50%',
              transform: 'translate(-50%, -50%)',
            }}
          >
            <div className="font-semibold">{labels[hoveredIndex]}</div>
            <div className="text-blue-300">{formatCurrency(chartData[hoveredIndex])}</div>
          </div>
        )}
      </div>

      {/* Statistics */}
      <div className="grid grid-cols-2 gap-4 mt-6 pt-6 border-t border-gray-200 dark:border-gray-700">
        <div className="flex items-center space-x-3">
          <div className="p-2 bg-green-100 dark:bg-green-900/30 rounded-lg">
            <TrendingDown className="w-4 h-4 text-green-600 dark:text-green-400" />
          </div>
          <div>
            <div className="text-xs text-gray-600 dark:text-gray-400">Lowest Day</div>
            <div className="text-sm font-semibold text-gray-900 dark:text-gray-100">
              {formatCurrency(data.lowest_day.cost)}
            </div>
            <div className="text-xs text-gray-500 dark:text-gray-400">
              {new Date(data.lowest_day.date).toLocaleDateString('en-US', {
                month: 'short',
                day: 'numeric',
              })}
            </div>
          </div>
        </div>

        <div className="flex items-center space-x-3">
          <div className="p-2 bg-orange-100 dark:bg-orange-900/30 rounded-lg">
            <TrendingUp className="w-4 h-4 text-orange-600 dark:text-orange-400" />
          </div>
          <div>
            <div className="text-xs text-gray-600 dark:text-gray-400">Highest Day</div>
            <div className="text-sm font-semibold text-gray-900 dark:text-gray-100">
              {formatCurrency(data.highest_day.cost)}
            </div>
            <div className="text-xs text-gray-500 dark:text-gray-400">
              {new Date(data.highest_day.date).toLocaleDateString('en-US', {
                month: 'short',
                day: 'numeric',
              })}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default CostTrendChart;
