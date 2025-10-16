'use client';

import React, { useState, useEffect, useCallback } from 'react';
import { useWebSocket } from '../hooks/useWebSocket.simple';
import { MetricsCard } from '../components/MetricsCard';
import { ContainerPanel } from '../components/ContainerPanel';
import { KubernetesPanel, ClusterStatus } from '../components/KubernetesPanel';
import { ClusterInfo } from '../components/ClusterSelector';
import { LogViewer } from '../components/LogViewer';
import { ConnectionStatus } from '../components/ConnectionStatus';
import { DarkModeToggle } from '../components/DarkModeToggle';
import { AwsSsoModal } from '../components/AwsSsoModal';
import { AuthModal } from '../components/AuthModal';
import { Terminal } from '../components/Terminal';
import AKSMetricsDashboard from '../components/AKSMetricsDashboard';
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

  // Kubernetes cluster management state
  const [availableClusters, setAvailableClusters] = useState<ClusterInfo[]>([]);
  const [currentCluster, setCurrentCluster] = useState<ClusterInfo | null>(null);
  const [clusterStatus, setClusterStatus] = useState<ClusterStatus | null>(null);
  const [kubernetesError, setKubernetesError] = useState<string>('');

  // Kubernetes context management state
  const [availableContexts, setAvailableContexts] = useState<Array<{ name: string; current: boolean; cluster?: string; user?: string; namespace?: string }>>([]);
  const [currentContext, setCurrentContext] = useState<string>('');

  // Region management state
  const [currentRegion, setCurrentRegion] = useState<string>('us-east-1');
  const [availableRegions, setAvailableRegions] = useState<string[]>(['us-east-1', 'us-east-2']);
  const [regionsLoading, setRegionsLoading] = useState<boolean>(true);

  // Loading states
  const [metricsLoading, setMetricsLoading] = useState(true);
  const [containersLoading, setContainersLoading] = useState(true);
  const [podsLoading, setPodsLoading] = useState(true);

  // Container control states
  const [containerLoading, setContainerLoading] = useState<string | null>(null);
  const [kubernetesServiceLoading, setKubernetesServiceLoading] = useState(false);

  // Log viewer state
  const [logViewer, setLogViewer] = useState({
    isOpen: false,
    title: '',
    logs: '',
    loading: false,
    streaming: false,
    containerName: '',
  });

  // AWS SSO Modal state
  const [showAwsSsoModal, setShowAwsSsoModal] = useState(false);
  const [awsSsoError, setAwsSsoError] = useState('');
  const [awsSsoLoading, setAwsSsoLoading] = useState(false);

  // Docker Auth Modal state
  const [showAuthModal, setShowAuthModal] = useState(false);
  const [authChallenge, setAuthChallenge] = useState<any>(null);
  const [authError, setAuthError] = useState('');
  const [authLoading, setAuthLoading] = useState(false);

  // Terminal state
  const [showTerminal, setShowTerminal] = useState(false);

  // WebSocket message handler
  const handleWebSocketMessage = useCallback((response: CommandResponse) => {
    console.log('WebSocket message:', response);

    if (response.success && response.data) {
      // Handle log streaming messages
      if (response.requestId.includes(':log')) {
        // Streaming log line received
        const logLine = response.data?.log_line;
        if (logLine) {
          setLogViewer(prev => ({
            ...prev,
            logs: prev.logs ? `${prev.logs}\n${logLine}` : logLine,
            loading: false,
          }));
        }
        return;
      }

      // Handle stream end messages
      if (response.requestId.includes(':end')) {
        setLogViewer(prev => ({
          ...prev,
          streaming: false,
          loading: false,
        }));
        return;
      }

      // Handle stream start confirmation
      if (response.data.streaming === true) {
        setLogViewer(prev => ({
          ...prev,
          streaming: true,
          loading: false,
        }));
        return;
      }

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
          // Clear container loading state when containers are refreshed
          setContainerLoading(null);
        } else if (response.data?.pods) {
          setPods(response.data.pods);
          setPodsLoading(false);
        } else if (response.data?.contexts) {
          // Handle contexts response
          setAvailableContexts(response.data.contexts);
          const current = response.data.contexts.find((ctx: any) => ctx.current);
          if (current) {
            setCurrentContext(current.name);
          }
          console.log('Updated available contexts:', response.data.contexts);
        } else if (response.data?.logs) {
          setLogViewer(prev => ({
            ...prev,
            logs: response.data?.logs || '',
            loading: false,
          }));
        } else if (response.data?.switched_to) {
          // Handle context switch confirmation
          console.log(`Context switched to: ${response.data.switched_to}`);
          fetchKubernetesClusters(); // Refresh cluster list
          handleRefreshContexts(); // Refresh context list
        } else if (response.data?.container_action) {
          // Handle container start/stop responses
          console.log(`Container action completed: ${response.data.container_action}`);
          setContainerLoading(null);
          // Trigger container refresh
          setContainersLoading(true);
          sendCommand('docker', 'ps');
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

      // Handle cluster context responses
      else if (response.requestId.startsWith('contexts_') || response.requestId.startsWith('switch-context_')) {
        fetchKubernetesClusters(); // Refresh cluster list when contexts change
      }
    } else if (!response.success) {
      console.error('Command failed:', response.error);
    }
  }, []);

  // Fetch available AWS regions from backend
  const fetchAwsRegions = useCallback(async () => {
    try {
      setRegionsLoading(true);
      const response = await fetch('/api/aws/regions');
      const data = await response.json();

      if (response.ok && data.success && data.regions) {
        const regionNames = data.regions
          .filter((region: any) => region.available !== false)
          .map((region: any) => region.name)
          .sort();

        setAvailableRegions(regionNames);
        console.log(`Loaded ${regionNames.length} AWS regions from backend`);
      } else {
        console.error('Failed to fetch AWS regions:', data.error || 'Unknown error');
        // Keep default regions as fallback
      }
    } catch (error) {
      console.error('Error fetching AWS regions:', error);
      // Keep default regions as fallback
    } finally {
      setRegionsLoading(false);
    }
  }, []);

  // Kubernetes cluster management functions
  const fetchKubernetesClusters = useCallback(async () => {
    try {
      // Add cache-busting parameter
      const response = await fetch(`/api/kubernetes/contexts?t=${Date.now()}`);
      const data = await response.json();

      if (response.ok && data.success) {
        // Convert contexts to ClusterInfo format, filtering out non-accessible clusters
        const clusters: ClusterInfo[] = data.contexts
          .filter((context: any) => {
            // Filter out clusters that we know have DNS resolution issues
            return !context.name.includes('production-71730a2');
          })
          .map((context: any) => ({
            name: context.cluster,
            context: context.name,
            namespace: context.namespace,
            environment: context.name.includes('eks') ? 'eks' as const :
                        context.name.includes('gke') ? 'gke' as const :
                        context.name.includes('aks') ? 'aks' as const :
                        'local' as const,
            status: context.current ? 'connected' as const : 'error' as const,
            lastSync: context.current ? new Date() : undefined,
            region: currentRegion,
            podCount: pods.filter(pod => pod.namespace === context.namespace).length
          }));

        setAvailableClusters(clusters);

        // Set current cluster
        const current = clusters.find(c => c.status === 'connected');
        if (current) {
          setCurrentCluster(current);

          // Create cluster status
          setClusterStatus({
            name: current.name,
            context: current.context,
            namespace: current.namespace || 'default',
            environment: current.environment || 'eks',
            status: 'connected',
            lastSync: new Date().toLocaleTimeString(),
            podCount: current.podCount
          });
        }

        // Clear any previous errors
        setKubernetesError('');
      } else {
        // Handle API errors
        let errorMessage = 'Failed to fetch Kubernetes clusters';

        if (data.error_type === 'authentication_error') {
          errorMessage = 'Authentication failed. Please run "aws sso login" to refresh your session.';
        } else if (data.error_type === 'connection_error') {
          errorMessage = 'Unable to connect to Kubernetes cluster. Please check your network connection.';
        } else if (data.error) {
          errorMessage = data.error;
        }

        setKubernetesError(errorMessage);
        setClusterStatus(null);
      }
    } catch (error) {
      const errorMessage = 'Failed to connect to monitoring service. Please check if the backend is running.';
      console.error('Error fetching Kubernetes clusters:', error);
      setKubernetesError(errorMessage);
      setClusterStatus(null);
    }
  }, [pods]);

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
      // Fetch available regions and clusters
      fetchAwsRegions();
      fetchKubernetesClusters();
    },
    onDisconnect: () => {
      console.log('WebSocket disconnected');
      setContainersLoading(true);
      setPodsLoading(true);
      setMetricsLoading(true);
    },
  });

  // Context refresh handler
  const handleRefreshContexts = useCallback(() => {
    if (isConnected) {
      sendCommand('kubernetes', 'contexts');
    }
  }, [isConnected, sendCommand]);

  // Fetch clusters and contexts when pods change or connection is established
  useEffect(() => {
    if (isConnected) {
      fetchKubernetesClusters();
      handleRefreshContexts();
    }
  }, [isConnected, pods.length, fetchKubernetesClusters, handleRefreshContexts]);

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
  const handleViewContainerLogs = useCallback((containerName: string, streaming: boolean = true) => {
    if (isConnected) {
      setLogViewer({
        isOpen: true,
        title: `Container: ${containerName}`,
        logs: '',
        loading: true,
        streaming: streaming,
        containerName: containerName,
      });
      // Use streaming logs by default for real-time updates
      const command = streaming ? 'logs:stream' : 'logs';
      sendCommand('docker', command, { container: containerName, lines: '100' });
    }
  }, [isConnected, sendCommand]);

  const handleViewPodLogs = useCallback((podName: string, namespace: string) => {
    if (isConnected) {
      setLogViewer({
        isOpen: true,
        title: `Pod: ${podName} (${namespace})`,
        logs: '',
        loading: true,
        streaming: false,
        containerName: podName,
      });
      sendCommand('kubernetes', 'logs', { pod: podName, namespace });
    }
  }, [isConnected, sendCommand]);

  const handleCloseLogViewer = useCallback(() => {
    // If streaming, we need to close the connection by disconnecting and reconnecting
    // or by sending a stop command (not implemented yet, streams will auto-close on component unmount)
    setLogViewer(prev => ({ ...prev, isOpen: false, streaming: false }));
  }, []);


  const handleClusterSelect = useCallback(async (cluster: ClusterInfo) => {
    try {
      const response = await fetch(`/api/kubernetes/context/switch/${cluster.context}`, {
        method: 'POST'
      });

      if (response.ok) {
        setCurrentCluster(cluster);
        setClusterStatus({
          name: cluster.name,
          context: cluster.context,
          namespace: cluster.namespace,
          environment: cluster.environment,
          status: 'connected',
          lastSync: new Date().toLocaleTimeString(),
          podCount: cluster.podCount
        });

        // Refresh pod data for the new context
        if (isConnected) {
          setPodsLoading(true);
          sendCommand('kubernetes', 'pods');
        }

        console.log(`Switched to cluster: ${cluster.name}`);
      }
    } catch (error) {
      console.error('Error switching cluster:', error);
    }
  }, [isConnected, sendCommand]);

  const handleOpenSettings = useCallback(() => {
    // Open a helpful alert with kubectl configuration instructions
    const instructions = `Kubernetes Cluster Configuration:

1. List available contexts:
   kubectl config get-contexts

2. Switch to a different context:
   kubectl config use-context <context-name>

3. Check cluster connectivity:
   kubectl cluster-info

4. For AWS EKS authentication issues:
   aws sso login
   aws eks update-kubeconfig --region <region> --name <cluster-name>

Current Status: ${kubernetesError || 'Ready'}
Available Clusters: ${availableClusters.length}`;

    alert(instructions);
    console.log('Opening Kubernetes settings...');
  }, [kubernetesError, availableClusters.length]);

  const handleContextSwitch = useCallback(async (context: string) => {
    // Handle context switch via WebSocket or direct API
    if (isConnected) {
      sendCommand('kubernetes', 'switch-context', { context });
    }
  }, [isConnected, sendCommand]);

  const handleRegionSelect = useCallback(async (region: string) => {
    console.log(`Region changed to: ${region}`);
    setCurrentRegion(region);

    // Clear current clusters and status when region changes
    setAvailableClusters([]);
    setCurrentCluster(null);
    setClusterStatus(null);

    // Refresh clusters for the new region
    fetchKubernetesClusters();

    // Clear pods while switching regions
    setPodsLoading(true);
  }, [fetchKubernetesClusters]);

  // Container control handlers
  const handleStartContainer = useCallback(async (containerName: string) => {
    console.log(`Starting container: ${containerName}`);
    setContainerLoading(containerName);

    try {
      if (isConnected) {
        // Send WebSocket command to start container
        sendCommand('docker', 'start', { container: containerName });

        // The response will come back through WebSocket and trigger container refresh
        // Set a timeout to clear loading state in case of no response
        setTimeout(() => {
          if (containerLoading === containerName) {
            setContainerLoading(null);
          }
        }, 10000);
      }
    } catch (error) {
      console.error('Error starting container:', error);
      alert(`Failed to start container ${containerName}: ${error}`);
      setContainerLoading(null);
    }
  }, [isConnected, sendCommand, containerLoading]);

  const handleStopContainer = useCallback(async (containerName: string) => {
    console.log(`Stopping container: ${containerName}`);
    setContainerLoading(containerName);

    try {
      if (isConnected) {
        // Send WebSocket command to stop container
        sendCommand('docker', 'stop', { container: containerName });

        // The response will come back through WebSocket and trigger container refresh
        // Set a timeout to clear loading state in case of no response
        setTimeout(() => {
          if (containerLoading === containerName) {
            setContainerLoading(null);
          }
        }, 10000);
      }
    } catch (error) {
      console.error('Error stopping container:', error);
      alert(`Failed to stop container ${containerName}: ${error}`);
      setContainerLoading(null);
    }
  }, [isConnected, sendCommand, containerLoading]);

  const handleStartKubernetesService = useCallback(async (region: string) => {
    console.log(`Starting Kubernetes service in ${region}...`);
    setKubernetesServiceLoading(true);
    try {
      const response = await fetch(`/api/kubernetes/start/${region}`, { method: 'POST' });
      const data = await response.json();

      if (response.ok && data.success) {
        console.log(`Kubernetes service started successfully in ${region}`);
        // Refresh pods and clusters after starting
        if (isConnected) {
          setPodsLoading(true);
          sendCommand('kubernetes', 'pods');
          fetchKubernetesClusters();
        }
      } else {
        console.error('Failed to start Kubernetes service:', data.error || data.message);
        alert(`Failed to start Kubernetes service: ${data.error || data.message || 'Unknown error'}`);
      }
    } catch (error) {
      console.error('Error starting Kubernetes service:', error);
      alert('Failed to connect to monitoring service. Please check if the backend is running.');
    } finally {
      setKubernetesServiceLoading(false);
    }
  }, [isConnected, sendCommand, fetchKubernetesClusters]);

  const handleStopKubernetesService = useCallback(async (region: string) => {
    console.log(`Stopping Kubernetes service in ${region}...`);
    setKubernetesServiceLoading(true);
    try {
      const response = await fetch(`/api/kubernetes/stop/${region}`, { method: 'POST' });
      const data = await response.json();

      if (response.ok && data.success) {
        console.log(`Kubernetes service stopped successfully in ${region}`);
        // Refresh pods and clusters after stopping
        if (isConnected) {
          setPodsLoading(true);
          sendCommand('kubernetes', 'pods');
          fetchKubernetesClusters();
        }
      } else {
        console.error('Failed to stop Kubernetes service:', data.error || data.message);
        alert(`Failed to stop Kubernetes service: ${data.error || data.message || 'Unknown error'}`);
      }
    } catch (error) {
      console.error('Error stopping Kubernetes service:', error);
      alert('Failed to connect to monitoring service. Please check if the backend is running.');
    } finally {
      setKubernetesServiceLoading(false);
    }
  }, [isConnected, sendCommand, fetchKubernetesClusters]);

  // AWS SSO Login Handler
  const handleAwsSsoLogin = useCallback(async (profile: string) => {
    setAwsSsoLoading(true);
    setAwsSsoError('');

    try {
      const response = await fetch('/api/aws/sso/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ profile })
      });

      const data = await response.json();

      if (data.success) {
        setShowAwsSsoModal(false);
        setAwsSsoError('');
        // Refresh Kubernetes data after successful login
        if (isConnected) {
          setPodsLoading(true);
          sendCommand('kubernetes', 'pods');
          fetchKubernetesClusters();
        }
      } else {
        setAwsSsoError(data.error || 'AWS SSO login failed');
        throw new Error(data.error);
      }
    } catch (error: any) {
      setAwsSsoError(error.message || 'AWS SSO login failed');
      throw error;
    } finally {
      setAwsSsoLoading(false);
    }
  }, [isConnected, sendCommand, fetchKubernetesClusters]);

  // Docker Password Authentication Handler
  const handlePasswordSubmit = useCallback(async (password: string) => {
    setAuthLoading(true);
    setAuthError('');

    try {
      // TODO: Implement Docker authentication endpoint
      // For now, just close the modal
      console.log('Docker password submitted');
      setShowAuthModal(false);
      setAuthChallenge(null);
    } catch (error: any) {
      setAuthError(error.message || 'Authentication failed');
      if (authChallenge) {
        setAuthChallenge({
          ...authChallenge,
          retryCount: authChallenge.retryCount - 1
        });
      }
    } finally {
      setAuthLoading(false);
    }
  }, [authChallenge]);

  // Check for AWS SSO errors in Kubernetes error messages
  const checkForAwsSsoError = useCallback((errorMessage: string) => {
    const awsSsoPatterns = [
      'SSO session',
      'expired or is otherwise invalid',
      'aws sso login',
      'getting credentials: exec: executable aws failed'
    ];

    return awsSsoPatterns.some(pattern =>
      errorMessage.toLowerCase().includes(pattern.toLowerCase())
    );
  }, []);

  // Update Kubernetes error handling to detect AWS SSO issues
  useEffect(() => {
    if (kubernetesError && checkForAwsSsoError(kubernetesError)) {
      setShowAwsSsoModal(true);
    }
  }, [kubernetesError, checkForAwsSsoError]);

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
              <button
                onClick={() => setShowTerminal(true)}
                className="px-4 py-2 bg-white/10 hover:bg-white/20 text-white rounded-lg transition-colors flex items-center space-x-2"
                title="Open Terminal"
              >
                <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 9l3 3-3 3m5 0h3M5 20h14a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
                </svg>
                <span className="hidden sm:inline">Terminal</span>
              </button>
              <DarkModeToggle />
            </div>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {/* System Metrics */}
        <MetricsCard metrics={systemMetrics} loading={metricsLoading} />


        {/* Service Panels - Vertical Layout */}
        <div className="space-y-6">
          {/* Docker Containers - Full Width */}
          <ContainerPanel
            containers={containers}
            loading={containersLoading}
            onRefresh={handleRefreshContainers}
            onViewLogs={handleViewContainerLogs}
            onStartContainer={handleStartContainer}
            onStopContainer={handleStopContainer}
            containerLoading={containerLoading}
            systemInfo={systemInfo}
          />

          {/* Kubernetes Pods - Full Width */}
          <KubernetesPanel
            pods={pods}
            clusterStatus={clusterStatus}
            availableClusters={availableClusters}
            currentCluster={currentCluster}
            currentRegion={currentRegion}
            availableRegions={availableRegions}
            availableContexts={availableContexts}
            currentContext={currentContext}
            loading={podsLoading || regionsLoading}
            error={kubernetesError}
            onRefresh={handleRefreshPods}
            onViewLogs={handleViewPodLogs}
            onOpenSettings={handleOpenSettings}
            onClusterSelect={handleClusterSelect}
            onContextSwitch={handleContextSwitch}
            onRegionSelect={handleRegionSelect}
            onStartService={handleStartKubernetesService}
            onStopService={handleStopKubernetesService}
            serviceLoading={kubernetesServiceLoading}
            systemInfo={systemInfo}
          />

          {/* AKS Metrics Dashboard - Only show for AKS clusters */}
          {clusterStatus && clusterStatus.environment === 'aks' && (
            <AKSMetricsDashboard
              provider={clusterStatus.environment}
              clusterContext={clusterStatus.context}
            />
          )}
        </div>

      </main>

      {/* Log Viewer Modal */}
      <LogViewer
        isOpen={logViewer.isOpen}
        onClose={handleCloseLogViewer}
        title={logViewer.title}
        logs={logViewer.logs}
        loading={logViewer.loading}
      />

      {/* AWS SSO Modal */}
      <AwsSsoModal
        isOpen={showAwsSsoModal}
        onClose={() => {
          setShowAwsSsoModal(false);
          setAwsSsoError('');
        }}
        onLogin={handleAwsSsoLogin}
        profiles={['uneeq-admin', 'default']}
        error={awsSsoError}
      />

      {/* Docker Auth Modal */}
      <AuthModal
        isOpen={showAuthModal}
        onClose={() => {
          setShowAuthModal(false);
          setAuthChallenge(null);
          setAuthError('');
        }}
        onSubmit={handlePasswordSubmit}
        challenge={authChallenge}
        isLoading={authLoading}
        error={authError}
      />

      {/* Terminal Modal */}
      <Terminal
        isOpen={showTerminal}
        onClose={() => setShowTerminal(false)}
        title="MiniPrem Terminal"
        websocketUrl="ws://localhost:8000/ws/terminal"
      />
    </div>
  );
}
