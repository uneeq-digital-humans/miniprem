import React, { useState, useEffect } from 'react';
import { X, Settings, Check, AlertTriangle, RefreshCw, TestTube, Cloud } from 'lucide-react';
import { StatusIndicator } from './StatusIndicator';
import CloudProviderBadge from './CloudProviderBadge';
import clsx from 'clsx';

export interface KubernetesEnvironment {
  id: string;
  name: string;
  type: 'local' | 'eks' | 'gke' | 'aks';
  description: string;
}

export interface KubernetesContext {
  name: string;
  cluster: string;
  namespace?: string;
  current: boolean;
}

export interface KubernetesConfig {
  environment: string;
  context: string;
  defaultNamespace: string;
  rememberSelection: boolean;
  autoRefresh: boolean;
  refreshInterval: number;
}

interface EnhancedClusterInfo {
  available: boolean;
  provider: 'eks' | 'aks' | 'gke' | 'unknown';
  context?: string;
  error?: string;
}

interface KubernetesSettingsModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSave: (config: KubernetesConfig) => void;
  currentConfig?: KubernetesConfig;
  contexts: KubernetesContext[];
  namespaces: string[];
  isConnected: boolean;
  connectionError?: string;
  onTestConnection: () => Promise<void>;
  onRefreshContexts: () => Promise<void>;
  loading?: boolean;
}

const ENVIRONMENTS: KubernetesEnvironment[] = [
  {
    id: 'local',
    name: 'Local Kubernetes',
    type: 'local',
    description: 'Docker Desktop, Minikube, or local cluster'
  },
  {
    id: 'eks',
    name: 'AWS EKS',
    type: 'eks',
    description: 'Amazon Elastic Kubernetes Service'
  },
  {
    id: 'gke',
    name: 'Google GKE',
    type: 'gke',
    description: 'Google Kubernetes Engine'
  },
  {
    id: 'aks',
    name: 'Azure AKS',
    type: 'aks',
    description: 'Azure Kubernetes Service'
  }
];

export function KubernetesSettingsModal({
  isOpen,
  onClose,
  onSave,
  currentConfig,
  contexts,
  namespaces,
  isConnected,
  connectionError,
  onTestConnection,
  onRefreshContexts,
  loading = false
}: KubernetesSettingsModalProps) {
  const [config, setConfig] = useState<KubernetesConfig>({
    environment: 'local',
    context: '',
    defaultNamespace: 'default',
    rememberSelection: true,
    autoRefresh: true,
    refreshInterval: 30,
    ...currentConfig
  });

  const [testingConnection, setTestingConnection] = useState(false);
  const [refreshingContexts, setRefreshingContexts] = useState(false);
  const [enhancedClusterInfo, setEnhancedClusterInfo] = useState<EnhancedClusterInfo | null>(null);
  const [loadingClusterInfo, setLoadingClusterInfo] = useState(false);

  useEffect(() => {
    if (currentConfig) {
      setConfig(currentConfig);
    }
  }, [currentConfig]);

  // Fetch enhanced cluster info when connected
  useEffect(() => {
    const fetchEnhancedInfo = async () => {
      if (!isConnected) {
        setEnhancedClusterInfo(null);
        return;
      }

      setLoadingClusterInfo(true);
      try {
        const response = await fetch('/api/kubernetes/cluster/info/enhanced');
        const data = await response.json();

        if (data.success && data.cluster_info) {
          setEnhancedClusterInfo(data.cluster_info);
        } else {
          setEnhancedClusterInfo(null);
        }
      } catch (err) {
        console.error('Failed to fetch enhanced cluster info:', err);
        setEnhancedClusterInfo(null);
      } finally {
        setLoadingClusterInfo(false);
      }
    };

    if (isOpen && isConnected) {
      fetchEnhancedInfo();
    }
  }, [isOpen, isConnected]);

  const handleSave = () => {
    onSave(config);
    onClose();
  };

  const handleTestConnection = async () => {
    setTestingConnection(true);
    try {
      await onTestConnection();
    } finally {
      setTestingConnection(false);
    }
  };

  const handleRefreshContexts = async () => {
    setRefreshingContexts(true);
    try {
      await onRefreshContexts();
    } finally {
      setRefreshingContexts(false);
    }
  };

  const currentContext = contexts.find(ctx => ctx.name === config.context);
  const availableNamespaces = namespaces.length > 0 ? namespaces : ['default', 'kube-system'];

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      {/* Backdrop */}
      <div
        className="absolute inset-0 bg-black/50 backdrop-blur-sm"
        onClick={onClose}
      />

      {/* Modal */}
      <div className="relative w-full max-w-2xl mx-4 max-h-[90vh] overflow-hidden">
        <div className="card p-0">
          {/* Header */}
          <div className="flex items-center justify-between p-6 border-b border-gray-200 dark:border-gray-700">
            <div className="flex items-center space-x-3">
              <Settings className="w-6 h-6 text-uneeq-primary" />
              <h2 className="text-xl font-bold text-primary">Kubernetes Settings</h2>
            </div>
            <button
              onClick={onClose}
              className="btn-icon p-2"
              data-testid="close-k8s-settings"
            >
              <X className="w-5 h-5" />
            </button>
          </div>

          {/* Content */}
          <div className="p-6 space-y-6 max-h-96 overflow-y-auto custom-scrollbar">
            {/* Environment Selection */}
            <div className="space-y-4">
              <h3 className="text-lg font-semibold text-primary mb-3">Environment Selection</h3>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                {ENVIRONMENTS.map((env) => (
                  <label
                    key={env.id}
                    className={clsx(
                      'p-4 rounded-lg border cursor-pointer transition-all duration-200',
                      config.environment === env.id
                        ? 'border-uneeq-primary bg-blue-50 dark:bg-blue-900/20'
                        : 'border-gray-200 dark:border-gray-600 hover:border-gray-300 dark:hover:border-gray-500'
                    )}
                  >
                    <input
                      type="radio"
                      name="environment"
                      value={env.id}
                      checked={config.environment === env.id}
                      onChange={(e) => setConfig(prev => ({ ...prev, environment: e.target.value }))}
                      className="sr-only"
                    />
                    <div className="flex items-start space-x-3">
                      <div className={clsx(
                        'w-4 h-4 rounded-full border-2 mt-0.5 flex items-center justify-center',
                        config.environment === env.id
                          ? 'border-uneeq-primary bg-uneeq-primary'
                          : 'border-gray-300 dark:border-gray-500'
                      )}>
                        {config.environment === env.id && (
                          <div className="w-2 h-2 bg-white rounded-full" />
                        )}
                      </div>
                      <div>
                        <div className="font-semibold text-primary">{env.name}</div>
                        <div className="text-sm text-secondary">{env.description}</div>
                      </div>
                    </div>
                  </label>
                ))}
              </div>
            </div>

            {/* Cloud Provider Detection Status */}
            {enhancedClusterInfo && (
              <div className="bg-blue-50 dark:bg-blue-900/20 rounded-lg p-4 border border-blue-200 dark:border-blue-800">
                <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 mb-2 flex items-center">
                  <Cloud className="w-4 h-4 mr-2 text-blue-500" />
                  Detected Cloud Provider
                </h3>
                <div className="flex items-center">
                  {enhancedClusterInfo.provider !== 'unknown' ? (
                    <CloudProviderBadge provider={enhancedClusterInfo.provider} className="text-sm" />
                  ) : (
                    <span className="text-sm text-gray-600 dark:text-gray-400">
                      Unable to detect cloud provider
                    </span>
                  )}
                </div>
              </div>
            )}

            {/* CLI Status Indicators */}
            {isConnected && (
              <div className="bg-gray-50 dark:bg-gray-800 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
                <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 mb-3">
                  CLI Tools Status
                </h3>
                <div className="space-y-2">
                  {/* kubectl status */}
                  <div className="flex items-center justify-between">
                    <div className="flex items-center">
                      <StatusIndicator status="healthy" size="sm" />
                      <span className="ml-2 text-sm text-gray-700 dark:text-gray-300">kubectl CLI</span>
                    </div>
                    <span className="text-xs text-green-600 dark:text-green-400 font-medium">
                      Available
                    </span>
                  </div>

                  {/* AWS CLI status (if EKS) */}
                  {enhancedClusterInfo?.provider === 'eks' && (
                    <div className="flex items-center justify-between">
                      <div className="flex items-center">
                        <StatusIndicator
                          status={enhancedClusterInfo.available ? 'healthy' : 'warning'}
                          size="sm"
                        />
                        <span className="ml-2 text-sm text-gray-700 dark:text-gray-300">AWS CLI</span>
                      </div>
                      <span className={clsx(
                        'text-xs font-medium',
                        enhancedClusterInfo.available
                          ? 'text-green-600 dark:text-green-400'
                          : 'text-yellow-600 dark:text-yellow-400'
                      )}>
                        {enhancedClusterInfo.available ? 'Available' : 'Check SSO login'}
                      </span>
                    </div>
                  )}

                  {/* Azure CLI status (if AKS) */}
                  {enhancedClusterInfo?.provider === 'aks' && (
                    <div className="flex items-center justify-between">
                      <div className="flex items-center">
                        <StatusIndicator
                          status={enhancedClusterInfo.available ? 'healthy' : 'warning'}
                          size="sm"
                        />
                        <span className="ml-2 text-sm text-gray-700 dark:text-gray-300">Azure CLI</span>
                      </div>
                      <span className={clsx(
                        'text-xs font-medium',
                        enhancedClusterInfo.available
                          ? 'text-green-600 dark:text-green-400'
                          : 'text-yellow-600 dark:text-yellow-400'
                      )}>
                        {enhancedClusterInfo.available ? 'Available' : 'Check login'}
                      </span>
                    </div>
                  )}
                </div>
              </div>
            )}

            {/* Authentication Status */}
            <div className="space-y-4">
              <h3 className="text-lg font-semibold text-primary mb-3">Connection Status</h3>
              <div className="card-gradient p-4 space-y-3">
                <div className="flex items-center space-x-2">
                  <StatusIndicator
                    status={isConnected ? 'healthy' : 'error'}
                    size="md"
                  />
                  <span className="font-medium text-primary">
                    kubectl context: {currentContext?.name || 'None selected'}
                  </span>
                </div>

                {currentContext && (
                  <div className="flex items-center space-x-2 ml-6">
                    <StatusIndicator
                      status={currentContext.cluster ? 'healthy' : 'warning'}
                      size="md"
                    />
                    <span className="text-secondary">
                      Cluster: {currentContext.cluster || 'Unknown'}
                    </span>
                  </div>
                )}

                {currentContext && (
                  <div className="flex items-center space-x-2 ml-6">
                    <StatusIndicator
                      status={currentContext.namespace ? 'healthy' : 'warning'}
                      size="md"
                    />
                    <span className="text-secondary">
                      Namespace: {currentContext.namespace || config.defaultNamespace}
                    </span>
                  </div>
                )}

                <div className="flex items-center space-x-2 ml-6">
                  <StatusIndicator
                    status={isConnected ? 'healthy' : 'error'}
                    size="md"
                  />
                  <span className="text-secondary">
                    Connection: {isConnected ? 'Active' : connectionError || 'Disconnected'}
                  </span>
                </div>

                <div className="flex items-center space-x-3 mt-4">
                  <button
                    onClick={handleTestConnection}
                    disabled={testingConnection || !config.context}
                    className={clsx(
                      'btn-secondary flex items-center space-x-2 px-3 py-2 text-sm',
                      testingConnection && 'opacity-50 cursor-not-allowed'
                    )}
                  >
                    <TestTube className={clsx('w-4 h-4', testingConnection && 'animate-pulse')} />
                    <span>{testingConnection ? 'Testing...' : 'Test Connection'}</span>
                  </button>

                  <button
                    onClick={handleRefreshContexts}
                    disabled={refreshingContexts}
                    className={clsx(
                      'btn-secondary flex items-center space-x-2 px-3 py-2 text-sm',
                      refreshingContexts && 'opacity-50 cursor-not-allowed'
                    )}
                  >
                    <RefreshCw className={clsx('w-4 h-4', refreshingContexts && 'animate-spin')} />
                    <span>{refreshingContexts ? 'Refreshing...' : 'Refresh Contexts'}</span>
                  </button>
                </div>
              </div>
            </div>

            {/* Cluster Configuration */}
            <div className="space-y-4">
              <h3 className="text-lg font-semibold text-primary mb-3">Cluster Configuration</h3>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-primary mb-1">
                    Context
                  </label>
                  <select
                    value={config.context}
                    onChange={(e) => setConfig(prev => ({ ...prev, context: e.target.value }))}
                    className="w-full input-field rounded px-3 py-2 text-sm"
                    data-testid="context-select"
                  >
                    <option value="">Select context...</option>
                    {contexts.map(ctx => (
                      <option key={ctx.name} value={ctx.name}>
                        {ctx.name} {ctx.current && '(current)'}
                      </option>
                    ))}
                  </select>
                </div>

                <div>
                  <label className="block text-sm font-medium text-primary mb-1">
                    Default Namespace
                  </label>
                  <select
                    value={config.defaultNamespace}
                    onChange={(e) => setConfig(prev => ({ ...prev, defaultNamespace: e.target.value }))}
                    className="w-full input-field rounded px-3 py-2 text-sm"
                    data-testid="namespace-select"
                  >
                    {availableNamespaces.map(ns => (
                      <option key={ns} value={ns}>{ns}</option>
                    ))}
                  </select>
                </div>
              </div>

              <div className="space-y-3">
                <label className="flex items-center space-x-2">
                  <input
                    type="checkbox"
                    checked={config.rememberSelection}
                    onChange={(e) => setConfig(prev => ({ ...prev, rememberSelection: e.target.checked }))}
                    className="w-4 h-4 text-uneeq-primary border-gray-300 dark:border-gray-600 rounded focus:ring-uneeq-primary"
                  />
                  <span className="text-sm text-primary">Remember cluster selection</span>
                </label>

                <label className="flex items-center space-x-2">
                  <input
                    type="checkbox"
                    checked={config.autoRefresh}
                    onChange={(e) => setConfig(prev => ({ ...prev, autoRefresh: e.target.checked }))}
                    className="w-4 h-4 text-uneeq-primary border-gray-300 dark:border-gray-600 rounded focus:ring-uneeq-primary"
                  />
                  <span className="text-sm text-primary">
                    Auto-refresh pod status ({config.refreshInterval}s)
                  </span>
                </label>
              </div>
            </div>
          </div>

          {/* Footer */}
          <div className="flex items-center justify-end space-x-3 p-6 border-t border-gray-200 dark:border-gray-700">
            <button
              onClick={onClose}
              className="btn-secondary px-4 py-2"
            >
              Cancel
            </button>
            <button
              onClick={handleSave}
              disabled={loading || !config.context}
              className={clsx(
                'btn-primary px-4 py-2 flex items-center space-x-2',
                (loading || !config.context) && 'opacity-50 cursor-not-allowed'
              )}
              data-testid="save-k8s-settings"
            >
              {loading && <RefreshCw className="w-4 h-4 animate-spin" />}
              <span>Save Changes</span>
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
