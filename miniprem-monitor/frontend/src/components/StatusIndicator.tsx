import React from 'react';
import { StatusType } from '../types/monitor';
import clsx from 'clsx';

interface StatusIndicatorProps {
  status: StatusType;
  label?: string;
  size?: 'sm' | 'md' | 'lg';
  showLabel?: boolean;
}

const statusConfig = {
  healthy: {
    color: 'bg-status-healthy',
    label: 'Healthy',
    animation: 'animate-pulse-slow',
  },
  warning: {
    color: 'bg-status-warning',
    label: 'Warning',
    animation: 'animate-pulse',
  },
  error: {
    color: 'bg-status-error',
    label: 'Error',
    animation: 'animate-pulse',
  },
  unknown: {
    color: 'bg-status-unknown',
    label: 'Unknown',
    animation: '',
  },
};

const sizeConfig = {
  sm: 'w-2 h-2',
  md: 'w-3 h-3',
  lg: 'w-4 h-4',
};

export function StatusIndicator({
  status,
  label,
  size = 'md',
  showLabel = false
}: StatusIndicatorProps) {
  const config = statusConfig[status];
  const sizeClass = sizeConfig[size];

  return (
    <div className="flex items-center space-x-2">
      <div
        className={clsx(
          'inline-block rounded-full',
          config.color,
          config.animation,
          sizeClass
        )}
        title={label || config.label}
      />
      {showLabel && (
        <span className="text-sm font-medium text-gray-700 dark:text-gray-300">
          {label || config.label}
        </span>
      )}
    </div>
  );
}