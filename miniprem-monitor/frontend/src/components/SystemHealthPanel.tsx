'use client';

import React, { useState, useEffect, useCallback } from 'react';
import { Cpu, HardDrive, Activity, Server, Zap, AlertCircle, CheckCircle, Clock } from 'lucide-react';
import { useWebSocket } from '../hooks/useWebSocket.simple';

interface DockerHealth {
  available: boolean;
  engine_status?: string;
  version?: {
    client: string;
    server: string;
  };
  system_info?: {
    containers_running: number;
    containers_paused: number;
    containers_stopped: number;
    images: number;
    server_version: string;
    storage_driver: string;
    kernel_version: string;
    operating_system: string;
    cpu_count: number;
    memory_total: number;
  };
  resource_usage?: any;
  error?: string;
}

interface KubernetesHealth {
  available: boolean;
  cluster_status?: string;
  version?: {
    client: string;
    server: string;
  };
  nodes?: {
    total_nodes: number;
    ready_nodes: number;
    not_ready_nodes: number;
    node_details: Array<{
      name: string;
      ready: boolean;
      kubernetes_version: string;
      container_runtime: string;
      os: string;
      kernel: string;
    }>;
  };
  namespaces_count?: number;
  error?: string;
}

interface SystemHealthPanelProps {
  className?: string;
}

export const SystemHealthPanel: React.FC<SystemHealthPanelProps> = ({ className = '' }) => {
  const [dockerHealth, setDockerHealth] = useState<DockerHealth | null>(null);
  const [kubernetesHealth, setKubernetesHealth] = useState<KubernetesHealth | null>(null);
  const [loading, setLoading] = useState(true);
  const [lastUpdate, setLastUpdate] = useState<Date>(new Date());

  // Pending request tracking
  const [pendingRequests, setPendingRequests] = useState<Set<string>>(new Set());

  // WebSocket message handler
  const handleWebSocketMessage = useCallback((response: any) => {
    if (response.success && response.data) {
      // Remove request ID from pending requests
      setPendingRequests(prev => {
        const newSet = new Set(prev);
        newSet.delete(response.requestId);
        return newSet;
      });

      // Handle different response types based on request ID pattern
      if (response.requestId.includes('docker_health')) {
        setDockerHealth(response.data.docker_health);
      } else if (response.requestId.includes('kubernetes_health')) {
        setKubernetesHealth(response.data.kubernetes_health);
      }

      setLastUpdate(new Date());
      setLoading(false);
    } else if (!response.success) {
      // Handle errors
      console.error('Health data request failed:', response.error);
      setPendingRequests(prev => {
        const newSet = new Set(prev);
        newSet.delete(response.requestId);
        return newSet;
      });
      setLoading(false);
    }
  }, []);

  // Initialize WebSocket
  const {
    isConnected,
    sendCommand,
  } = useWebSocket('/ws', {
    onMessage: handleWebSocketMessage,
    debug: true
  });

  const fetchHealthData = useCallback(() => {
    if (!isConnected) return;

    setLoading(true);

    // Send WebSocket commands instead of fetch requests
    const dockerRequestId = sendCommand('docker', 'health');
    const k8sRequestId = sendCommand('kubernetes', 'health');

    // Track pending requests
    setPendingRequests(prev => new Set([...prev, dockerRequestId, k8sRequestId]));
  }, [isConnected, sendCommand]);

  useEffect(() => {
    if (isConnected) {
      fetchHealthData();
      const interval = setInterval(fetchHealthData, 35000); // Every 30 seconds
      return () => clearInterval(interval);
    }
  }, [isConnected, fetchHealthData]);

  const getStatusIcon = (status: string | undefined, available: boolean) => {
    if (!available) return <AlertCircle className="w-5 h-5 text-status-error" />;
    if (status === 'healthy' || status === 'ready') return <CheckCircle className="w-5 h-5 text-status-healthy" />;
    if (status === 'degraded') return <AlertCircle className="w-5 h-5 text-status-warning" />;
    return <Activity className="w-5 h-5 text-status-warning" />;
  };

  const getStatusColor = (status: string | undefined, available: boolean) => {
    if (!available) return 'text-status-error';
    if (status === 'healthy' || status === 'ready') return 'text-status-healthy';
    if (status === 'degraded') return 'text-status-warning';
    return 'text-status-warning';
  };

  const formatBytes = (bytes: number | undefined) => {
    if (!bytes) return '0 B';
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(1024));
    return Math.round((bytes / Math.pow(1024, i)) * 100) / 100 + ' ' + sizes[i];
  };

  if (loading) {
    return (
      <div className={`card p-6 ${className}`}>
        <div className="animate-pulse">
          <div className="h-6 bg-gray-200 rounded w-1/3 mb-4"></div>
          <div className="space-y-3">
            <div className="h-4 bg-gray-200 rounded"></div>
            <div className="h-4 bg-gray-200 rounded w-5/6"></div>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className={`card p-6 ${className}`}>
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-xl font-bold text-gray-900 flex items-center space-x-2">
          <Server className="w-6 h-6 text-uneeq-primary" />
          <span>System Health</span>
        </h2>
        <div className="flex items-center space-x-2 text-sm text-gray-500">
          <Clock className="w-4 h-4" />
          <span>Updated {lastUpdate.toLocaleTimeString()}</span>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Docker Engine Health */}
        <div className="space-y-4">
          <div className="flex items-center justify-between">
            <h3 className="text-lg font-semibold text-gray-800 flex items-center space-x-2">
              <div className="w-8 h-8 bg-blue-100 rounded-lg flex items-center justify-center">
                <Zap className="w-5 h-5 text-blue-600" />
              </div>
              <span>Docker Engine</span>
            </h3>
            {dockerHealth && (
              <div className="flex items-center space-x-2">
                {getStatusIcon(dockerHealth.engine_status, dockerHealth.available)}
                <span className={`font-medium ${getStatusColor(dockerHealth.engine_status, dockerHealth.available)}`}>
                  {dockerHealth.available
                    ? dockerHealth.engine_status === 'healthy' ? 'Healthy' : dockerHealth.engine_status === 'error' ? 'Error' : 'Unknown'
                    : 'Unavailable'
                  }
                </span>
              </div>
            )}
          </div>

          {dockerHealth?.available && dockerHealth.system_info ? (
            <div className="bg-gray-50 rounded-lg p-4 space-y-3">
              <div className="grid grid-cols-2 gap-4 text-sm">
                <div>
                  <span className="text-gray-500">Version:</span>
                  <div className="font-medium">{dockerHealth.version?.server || 'Unknown'}</div>
                </div>
                <div>
                  <span className="text-gray-500">Storage:</span>
                  <div className="font-medium">{dockerHealth.system_info.storage_driver}</div>
                </div>
                <div>
                  <span className="text-gray-500">Running:</span>
                  <div className="font-medium text-status-healthy">
                    {dockerHealth.system_info.containers_running} containers
                  </div>
                </div>
                <div>
                  <span className="text-gray-500">Stopped:</span>
                  <div className="font-medium text-gray-600">
                    {dockerHealth.system_info.containers_stopped} containers
                  </div>
                </div>
                <div>
                  <span className="text-gray-500">Images:</span>
                  <div className="font-medium">{dockerHealth.system_info.images}</div>
                </div>
                <div>
                  <span className="text-gray-500">Memory:</span>
                  <div className="font-medium">{formatBytes(dockerHealth.system_info.memory_total)}</div>
                </div>
              </div>
              <div className="pt-2 border-t border-gray-200">
                <div className="text-xs text-gray-500">
                  OS: {dockerHealth.system_info.operating_system} |
                  Kernel: {dockerHealth.system_info.kernel_version}
                </div>
              </div>
            </div>
          ) : (
            <div className="bg-red-50 border border-red-200 rounded-lg p-4">
              <div className="text-red-700">
                {dockerHealth?.error || 'Docker Engine not available'}
              </div>
            </div>
          )}
        </div>

        {/* Kubernetes Cluster Health */}
        <div className="space-y-4">
          <div className="flex items-center justify-between">
            <h3 className="text-lg font-semibold text-gray-800 flex items-center space-x-2">
              <div className="w-8 h-8 bg-purple-100 rounded-lg flex items-center justify-center">
                <Cpu className="w-5 h-5 text-purple-600" />
              </div>
              <span>Kubernetes Cluster</span>
            </h3>
            {kubernetesHealth && (
              <div className="flex items-center space-x-2">
                {getStatusIcon(kubernetesHealth.cluster_status, kubernetesHealth.available)}
                <span className={`font-medium ${getStatusColor(kubernetesHealth.cluster_status, kubernetesHealth.available)}`}>
                  {kubernetesHealth.available
                    ? kubernetesHealth.cluster_status === 'healthy' ? 'Healthy'
                      : kubernetesHealth.cluster_status === 'degraded' ? 'Degraded'
                      : kubernetesHealth.cluster_status === 'error' ? 'Error'
                      : 'Unknown'
                    : 'Unavailable'
                  }
                </span>
              </div>
            )}
          </div>

          {kubernetesHealth?.available && kubernetesHealth.nodes ? (
            <div className="bg-gray-50 rounded-lg p-4 space-y-3">
              <div className="grid grid-cols-2 gap-4 text-sm">
                <div>
                  <span className="text-gray-500">Version:</span>
                  <div className="font-medium">{kubernetesHealth.version?.server || 'Unknown'}</div>
                </div>
                <div>
                  <span className="text-gray-500">Namespaces:</span>
                  <div className="font-medium">{kubernetesHealth.namespaces_count || 0}</div>
                </div>
                <div>
                  <span className="text-gray-500">Ready Nodes:</span>
                  <div className="font-medium text-status-healthy">
                    {kubernetesHealth.nodes.ready_nodes} / {kubernetesHealth.nodes.total_nodes}
                  </div>
                </div>
                <div>
                  <span className="text-gray-500">Not Ready:</span>
                  <div className={`font-medium ${kubernetesHealth.nodes.not_ready_nodes > 0 ? 'text-status-error' : 'text-gray-600'}`}>
                    {kubernetesHealth.nodes.not_ready_nodes}
                  </div>
                </div>
              </div>

              {kubernetesHealth.nodes.node_details.length > 0 && (
                <div className="pt-3 border-t border-gray-200">
                  <div className="text-xs font-medium text-gray-700 mb-2">Nodes:</div>
                  <div className="space-y-1">
                    {kubernetesHealth.nodes.node_details.slice(0, 3).map((node, index) => (
                      <div key={index} className="flex items-center justify-between text-xs">
                        <div className="flex items-center space-x-2">
                          <div className={`w-2 h-2 rounded-full ${node.ready ? 'bg-status-healthy' : 'bg-status-error'}`} />
                          <span className="font-mono">{node.name}</span>
                        </div>
                        <span className="text-gray-500">{node.kubernetes_version}</span>
                      </div>
                    ))}
                    {kubernetesHealth.nodes.node_details.length > 3 && (
                      <div className="text-xs text-gray-500 text-center pt-1">
                        +{kubernetesHealth.nodes.node_details.length - 3} more nodes
                      </div>
                    )}
                  </div>
                </div>
              )}
            </div>
          ) : (
            <div className="bg-red-50 border border-red-200 rounded-lg p-4">
              <div className="text-red-700">
                {kubernetesHealth?.error || 'Kubernetes cluster not available'}
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Refresh Button */}
      <div className="mt-6 flex justify-end">
        <button
          onClick={fetchHealthData}
          className="btn-secondary text-sm"
          disabled={loading}
        >
          {loading ? 'Refreshing...' : 'Refresh Status'}
        </button>
      </div>
    </div>
  );
};