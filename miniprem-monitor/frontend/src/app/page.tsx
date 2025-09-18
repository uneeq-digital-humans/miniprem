'use client';

import React, { useState, useEffect, useCallback } from 'react';
import { useWebSocket } from '../hooks/useWebSocket.simple';
import { MetricsCard } from '../components/MetricsCard';
import { ContainerPanel } from '../components/ContainerPanel';
import { KubernetesPanel } from '../components/KubernetesPanel';
import { LogViewer } from '../components/LogViewer';
import { ConnectionStatus } from '../components/ConnectionStatus';
import { DarkModeToggle } from '../components/DarkModeToggle';
import {
  SystemMetrics,
  ContainerStatus,
  PodStatus,
  CommandResponse,
  SystemInfo
} from '../types/monitor';

export default function MonitoringDashboard() {
  // State management
  const [systemMetrics, setSystemMetrics] = useState<SystemMetrics | null>(null);
  const [containers, setContainers] = useState<ContainerStatus[]>([]);
  const [pods, setPods] = useState<PodStatus[]>([]);
  const [systemInfo, setSystemInfo] = useState<SystemInfo | null>(null);

  // Loading states
  const [metricsLoading, setMetricsLoading] = useState(true);
  const [containersLoading, setContainersLoading] = useState(true);
  const [podsLoading, setPodsLoading] = useState(true);

  // Log viewer state
  const [logViewer, setLogViewer] = useState({
    isOpen: false,
    title: '',
    logs: '',
    loading: false,
  });

  // WebSocket message handler
  const handleWebSocketMessage = useCallback((response: CommandResponse) => {
    console.log('WebSocket message:', response);

    if (response.success && response.data) {
      // Handle real-time push notifications
      if (response.requestId.startsWith('push:')) {
        const pushType = response.requestId.replace('push:', '');

        if (response.data.type === 'real_time_update') {
          console.log(`Real-time update received: ${response.data.update_type}`, response.data.changes);

          if (response.data.update_type === 'docker_containers_changed' && response.data.changes?.containers) {
            setContainers(response.data.changes.containers);
            setContainersLoading(false);
            console.log('Updated containers from real-time push notification');
          } else if (response.data.update_type === 'kubernetes_pods_changed' && response.data.changes?.pods) {
            setPods(response.data.changes.pods);
            setPodsLoading(false);
            console.log('Updated pods from real-time push notification');
          }
        }
      }

      // Handle subscription updates
      else if (response.requestId.startsWith('subscription:')) {
        const subscriptionType = response.requestId.replace('subscription:', '');

        if (subscriptionType === 'docker:ps' && response.data?.containers) {
          setContainers(response.data.containers);
          setContainersLoading(false);
        } else if (subscriptionType === 'kubernetes:pods' && response.data?.pods) {
          setPods(response.data.pods);
          setPodsLoading(false);
        } else if (subscriptionType === 'system:metrics' && response.data?.metrics) {
          setSystemMetrics(response.data.metrics);
          setMetricsLoading(false);
        } else if (subscriptionType === 'system:info' && response.data?.system) {
          // Create a proper SystemInfo object using actual backend data
          const systemInfo: SystemInfo = {
            system: {
              platform: response.data.system.platform,
              cpu_count: response.data.system.cpu_count,
              cpu_count_logical: response.data.system.cpu_count_logical,
              memory_total_gb: response.data.system.memory_total_gb,
              disk_total_gb: response.data.system.disk_total_gb,
              boot_time: response.data.system.boot_time,
              uptime_hours: response.data.system.uptime_hours
            },
            docker: response.data.system.docker || { available: false, error: 'No data received' },
            kubernetes: response.data.system.kubernetes || { available: false, error: 'No data received' }
          };
          setSystemInfo(systemInfo);
          console.log('Updated system info from subscription:', systemInfo);
        }
      }

      // Handle initial system info response (sent immediately on connection)
      else if (response.requestId === 'initial:system:info' && response.data?.system) {
        // Create a proper SystemInfo object using actual backend data
        const systemInfo: SystemInfo = {
          system: {
            platform: response.data.system.platform,
            cpu_count: response.data.system.cpu_count,
            cpu_count_logical: response.data.system.cpu_count_logical,
            memory_total_gb: response.data.system.memory_total_gb,
            disk_total_gb: response.data.system.disk_total_gb,
            boot_time: response.data.system.boot_time,
            uptime_hours: response.data.system.uptime_hours
          },
          docker: response.data.system.docker || { available: false, error: 'No data received' },
          kubernetes: response.data.system.kubernetes || { available: false, error: 'No data received' }
        };
        setSystemInfo(systemInfo);
        console.log('Received initial system info:', systemInfo);
      }

      // Handle one-time command responses
      else if (response.requestId.startsWith('cmd_')) {
        if (response.data?.containers) {
          setContainers(response.data.containers);
          setContainersLoading(false);
        } else if (response.data?.pods) {
          setPods(response.data.pods);
          setPodsLoading(false);
        } else if (response.data?.logs) {
          setLogViewer(prev => ({
            ...prev,
            logs: response.data?.logs || '',
            loading: false,
          }));
        }
      }

      // Handle log commands
      else if (response.requestId.startsWith('logs_')) {
        setLogViewer(prev => ({
          ...prev,
          logs: response.data?.logs || '',
          loading: false,
        }));
      }
    } else if (!response.success) {
      console.error('Command failed:', response.error);
    }
  }, []);

  // Initialize WebSocket
  const {
    isConnected,
    connectionId,
    sendCommand,
    subscribe,
    unsubscribe,
  } = useWebSocket('/ws', {
    onMessage: handleWebSocketMessage,
    onConnect: () => {
      console.log('WebSocket connected, starting subscriptions...');
      // Start subscriptions when connected
      subscribe('docker', 'ps');
      subscribe('kubernetes', 'pods');
      subscribe('system', 'metrics');
      subscribe('system', 'info');
    },
    onDisconnect: () => {
      console.log('WebSocket disconnected');
      setContainersLoading(true);
      setPodsLoading(true);
      setMetricsLoading(true);
    },
  });

  // All data now comes via WebSocket subscriptions - no REST API polling needed

  // Manual refresh handlers
  const handleRefreshContainers = useCallback(() => {
    if (isConnected) {
      setContainersLoading(true);
      sendCommand('docker', 'ps');
    }
  }, [isConnected, sendCommand]);

  const handleRefreshPods = useCallback(() => {
    if (isConnected) {
      setPodsLoading(true);
      sendCommand('kubernetes', 'pods');
    }
  }, [isConnected, sendCommand]);

  // Log viewer handlers
  const handleViewContainerLogs = useCallback((containerName: string) => {
    if (isConnected) {
      setLogViewer({
        isOpen: true,
        title: `Container: ${containerName}`,
        logs: '',
        loading: true,
      });
      sendCommand('docker', 'logs', { container: containerName });
    }
  }, [isConnected, sendCommand]);

  const handleViewPodLogs = useCallback((podName: string, namespace: string) => {
    if (isConnected) {
      setLogViewer({
        isOpen: true,
        title: `Pod: ${podName} (${namespace})`,
        logs: '',
        loading: true,
      });
      sendCommand('kubernetes', 'logs', { pod: podName, namespace });
    }
  }, [isConnected, sendCommand]);

  const handleCloseLogViewer = useCallback(() => {
    setLogViewer(prev => ({ ...prev, isOpen: false }));
  }, []);

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-900 transition-colors" data-testid="dashboard-root">
      {/* Header */}
      <header className="header-gradient shadow-lg" data-testid="dashboard-header">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
          <div className="flex items-center justify-between">
            <div className="flex items-center space-x-4">
              <div className="flex items-center space-x-2" data-testid="app-branding">
                <div className="w-10 h-10 bg-white rounded-lg flex items-center justify-center" data-testid="app-logo">
                  <img
                    src="https://cdn.uneeq.io/hosted-experience/assets/favicon.png"
                    alt="UneeQ Logo"
                    className="w-6 h-6"
                  />
                </div>
                <h1 className="text-2xl font-bold text-white" data-testid="app-title">
                  MiniPrem Monitor
                </h1>
              </div>
              {systemInfo && (
                <div className="hidden md:flex items-center space-x-4 text-white/80 text-sm" data-testid="system-info">
                  <span data-testid="system-platform">Platform: {systemInfo.system.platform}</span>
                  <span>•</span>
                  <span data-testid="system-cpu-count">CPUs: {systemInfo.system.cpu_count}</span>
                  <span>•</span>
                  <span data-testid="system-memory">Memory: {systemInfo.system.memory_total_gb}GB</span>
                </div>
              )}
            </div>

            <div className="flex items-center space-x-3">
              <ConnectionStatus
                isConnected={isConnected}
                connectionId={connectionId}
              />
              <DarkModeToggle />
            </div>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {/* System Metrics */}
        <MetricsCard metrics={systemMetrics} loading={metricsLoading} />


        {/* Service Panels */}
        <div className="grid grid-cols-1 xl:grid-cols-2 gap-6">
          {/* Docker Containers */}
          <ContainerPanel
            containers={containers}
            loading={containersLoading}
            onRefresh={handleRefreshContainers}
            onViewLogs={handleViewContainerLogs}
          />

          {/* Kubernetes Pods */}
          <KubernetesPanel
            pods={pods}
            loading={podsLoading}
            onRefresh={handleRefreshPods}
            onViewLogs={handleViewPodLogs}
          />
        </div>

        {/* Service Availability Status */}
        {systemInfo && systemInfo.docker && systemInfo.kubernetes && (
          <div className="mt-6 grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="card p-4">
              <h3 className="font-semibold text-gray-900 dark:text-gray-100 mb-2">Docker Status</h3>
              <div className="flex items-center space-x-2">
                <div className={`w-3 h-3 rounded-full ${systemInfo.docker.available ? 'bg-status-healthy' : 'bg-status-error'}`} />
                <span className="text-sm text-gray-600 dark:text-gray-300">
                  {systemInfo.docker.available ? 'Available' : `Unavailable: ${systemInfo.docker.error || 'Unknown error'}`}
                </span>
              </div>
            </div>

            <div className="card p-4">
              <h3 className="font-semibold text-gray-900 dark:text-gray-100 mb-2">Kubernetes Status</h3>
              <div className="flex items-center space-x-2">
                <div className={`w-3 h-3 rounded-full ${systemInfo.kubernetes.available ? 'bg-status-healthy' : 'bg-status-error'}`} />
                <span className="text-sm text-gray-600 dark:text-gray-300">
                  {systemInfo.kubernetes.available ? 'Available' : `Unavailable: ${systemInfo.kubernetes.error || 'Unknown error'}`}
                </span>
              </div>
            </div>
          </div>
        )}
      </main>

      {/* Log Viewer Modal */}
      <LogViewer
        isOpen={logViewer.isOpen}
        onClose={handleCloseLogViewer}
        title={logViewer.title}
        logs={logViewer.logs}
        loading={logViewer.loading}
      />
    </div>
  );
}