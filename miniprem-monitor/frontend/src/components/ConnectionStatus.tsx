import React from 'react';
import { StatusIndicator } from './StatusIndicator';
import { Wifi, WifiOff } from 'lucide-react';

interface ConnectionStatusProps {
  isConnected: boolean;
  connectionId?: string | null;
  reconnecting?: boolean;
}

export function ConnectionStatus({
  isConnected,
  connectionId,
  reconnecting
}: ConnectionStatusProps) {
  const getStatus = () => {
    if (reconnecting) return 'warning';
    return isConnected ? 'healthy' : 'error';
  };

  return (
    <div className="flex items-center space-x-2 px-3 py-1 rounded-full bg-white dark:bg-gray-700 shadow-sm border border-gray-200 dark:border-gray-600" data-testid="connection-status">
      <StatusIndicator status={getStatus()} size="sm" data-testid="connection-indicator" />
      {isConnected ? (
        <Wifi className="w-4 h-4 text-status-healthy" data-testid="connection-wifi-icon" />
      ) : (
        <WifiOff className="w-4 h-4 text-status-error" data-testid="connection-wifi-off-icon" />
      )}
      {connectionId && (
        <span className="text-xs text-gray-500 dark:text-gray-400 font-mono" data-testid="connection-id">
          {connectionId.slice(0, 8)}
        </span>
      )}
    </div>
  );
}
