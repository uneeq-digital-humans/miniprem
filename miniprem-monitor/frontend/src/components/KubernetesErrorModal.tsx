import React from 'react';
import { X, AlertTriangle, Info, RefreshCw, Settings2, ExternalLink } from 'lucide-react';
import clsx from 'clsx';

export interface KubernetesError {
  type: 'auth_required' | 'no_clusters' | 'connection_failed' | 'context_invalid' | 'permission_denied' | 'aws_sso_expired';
  title: string;
  message: string;
  details?: string;
  suggestions?: string[];
  commands?: Array<{
    label: string;
    command: string;
    description?: string;
  }>;
}

interface KubernetesErrorModalProps {
  isOpen: boolean;
  error: KubernetesError | null;
  onClose: () => void;
  onRetry?: () => void;
  onConfigure?: () => void;
  onSetupCluster?: () => void;
  retrying?: boolean;
}

const ERROR_CONFIGS: Record<KubernetesError['type'], { icon: React.ComponentType<{ className?: string }>; colorClass: string }> = {
  auth_required: { icon: AlertTriangle, colorClass: 'text-status-warning' },
  no_clusters: { icon: Info, colorClass: 'text-blue-500' },
  connection_failed: { icon: AlertTriangle, colorClass: 'text-status-error' },
  context_invalid: { icon: AlertTriangle, colorClass: 'text-status-warning' },
  permission_denied: { icon: AlertTriangle, colorClass: 'text-status-error' },
  aws_sso_expired: { icon: AlertTriangle, colorClass: 'text-status-warning' },
};

export function KubernetesErrorModal({
  isOpen,
  error,
  onClose,
  onRetry,
  onConfigure,
  onSetupCluster,
  retrying = false
}: KubernetesErrorModalProps) {
  if (!isOpen || !error) return null;

  const { icon: IconComponent, colorClass } = ERROR_CONFIGS[error.type] || ERROR_CONFIGS.connection_failed;

  const copyToClipboard = (text: string) => {
    navigator.clipboard.writeText(text).then(() => {
      // Could show a toast notification here
      console.log('Command copied to clipboard');
    });
  };

  const handlePrimaryAction = () => {
    switch (error.type) {
      case 'no_clusters':
        onSetupCluster?.();
        break;
      case 'auth_required':
      case 'connection_failed':
      case 'context_invalid':
      case 'permission_denied':
        onRetry?.();
        break;
    }
  };

  const getPrimaryActionLabel = () => {
    switch (error.type) {
      case 'no_clusters':
        return 'Set Up Cluster';
      case 'auth_required':
      case 'connection_failed':
      case 'context_invalid':
      case 'permission_denied':
        return 'Retry';
      default:
        return 'Retry';
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      {/* Backdrop */}
      <div
        className="absolute inset-0 bg-black/50 backdrop-blur-sm"
        onClick={onClose}
      />

      {/* Modal */}
      <div className="relative w-full max-w-md mx-4">
        <div className="card p-0">
          {/* Header */}
          <div className="flex items-center justify-between p-6 border-b border-surface">
            <div className="flex items-center space-x-3">
              <IconComponent className={clsx('w-6 h-6', colorClass)} />
              <h2 className="text-lg font-bold text-primary">{error.title}</h2>
            </div>
            <button
              onClick={onClose}
              className="btn-icon p-2"
              data-testid="close-error-modal"
            >
              <X className="w-5 h-5" />
            </button>
          </div>

          {/* Content */}
          <div className="p-6">
            <p className="text-secondary mb-4">{error.message}</p>

            {error.details && (
              <div className="mb-4 p-3 bg-surface-secondary rounded-lg">
                <p className="text-sm text-secondary">{error.details}</p>
              </div>
            )}

            {error.suggestions && error.suggestions.length > 0 && (
              <div className="mb-4">
                <h4 className="font-semibold text-primary mb-2">Possible solutions:</h4>
                <ul className="space-y-2">
                  {error.suggestions.map((suggestion, index) => (
                    <li key={index} className="flex items-start space-x-2 text-sm text-secondary">
                      <span className="text-uneeq-primary mt-1">•</span>
                      <span>{suggestion}</span>
                    </li>
                  ))}
                </ul>
              </div>
            )}

            {error.commands && error.commands.length > 0 && (
              <div className="mb-4">
                <h4 className="font-semibold text-primary mb-2">Commands to try:</h4>
                <div className="space-y-3">
                  {error.commands.map((cmd, index) => (
                    <div key={index} className="border border-surface rounded-lg p-3">
                      <div className="flex items-center justify-between mb-1">
                        <span className="text-sm font-medium text-primary">{cmd.label}</span>
                        <button
                          onClick={() => copyToClipboard(cmd.command)}
                          className="text-xs text-uneeq-primary hover:text-uneeq-pink font-medium"
                          title="Copy to clipboard"
                        >
                          Copy
                        </button>
                      </div>
                      <code className="block text-xs bg-gray-900 dark:bg-gray-950 text-gray-100 p-2 rounded font-mono whitespace-pre-wrap break-all">
                        {cmd.command}
                      </code>
                      {cmd.description && (
                        <p className="text-xs text-muted mt-2">{cmd.description}</p>
                      )}
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>

          {/* Footer */}
          <div className="flex items-center justify-end space-x-3 p-6 border-t border-surface">
            <button
              onClick={onClose}
              className="btn-secondary px-4 py-2"
            >
              Close
            </button>

            {onConfigure && (
              <button
                onClick={() => {
                  onClose();
                  onConfigure();
                }}
                className="btn-secondary px-4 py-2 flex items-center space-x-2"
              >
                <Settings2 className="w-4 h-4" />
                <span>Configure</span>
              </button>
            )}

            <button
              onClick={handlePrimaryAction}
              disabled={retrying}
              className={clsx(
                'btn-primary px-4 py-2 flex items-center space-x-2',
                retrying && 'opacity-50 cursor-not-allowed'
              )}
              data-testid="error-primary-action"
            >
              {retrying && <RefreshCw className="w-4 h-4 animate-spin" />}
              <span>{retrying ? 'Retrying...' : getPrimaryActionLabel()}</span>
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

// Predefined error configurations for common scenarios
export const KUBERNETES_ERRORS: Record<string, KubernetesError> = {
  AUTH_REQUIRED: {
    type: 'auth_required',
    title: 'Authentication Required',
    message: 'kubectl context not found or expired.',
    suggestions: [
      'Check AWS credentials are configured',
      'Verify cluster exists and is accessible',
      'Ensure kubectl is installed and in PATH'
    ],
    commands: [
      {
        label: 'Update EKS kubeconfig',
        command: 'aws eks update-kubeconfig --region us-east-1 --name <cluster-name>',
        description: 'Replace <cluster-name> with your actual cluster name'
      },
      {
        label: 'Check AWS credentials',
        command: 'aws sts get-caller-identity',
        description: 'Verify your AWS credentials are working'
      },
      {
        label: 'List available contexts',
        command: 'kubectl config get-contexts',
        description: 'See all available kubectl contexts'
      }
    ]
  },

  NO_CLUSTERS: {
    type: 'no_clusters',
    title: 'No Kubernetes Clusters Found',
    message: 'kubectl is working but no contexts are configured.',
    suggestions: [
      'Set up a local cluster (Docker Desktop, Minikube)',
      'Connect to a cloud cluster (EKS, GKE, AKS)',
      'Import an existing kubeconfig file'
    ]
  },

  CONNECTION_FAILED: {
    type: 'connection_failed',
    title: 'Connection Failed',
    message: 'Unable to connect to the Kubernetes cluster.',
    details: 'The cluster may be unreachable or experiencing issues.',
    suggestions: [
      'Check your internet connection',
      'Verify the cluster is running',
      'Check VPN connection if required',
      'Try refreshing your kubeconfig'
    ]
  },

  CONTEXT_INVALID: {
    type: 'context_invalid',
    title: 'Invalid Context',
    message: 'The selected kubectl context is no longer valid.',
    suggestions: [
      'The cluster may have been deleted',
      'Credentials may have expired',
      'Context configuration may be corrupted'
    ],
    commands: [
      {
        label: 'Remove invalid context',
        command: 'kubectl config delete-context <context-name>',
        description: 'Replace <context-name> with the invalid context'
      },
      {
        label: 'Set current context',
        command: 'kubectl config use-context <valid-context>',
        description: 'Switch to a valid context'
      }
    ]
  },

  PERMISSION_DENIED: {
    type: 'permission_denied',
    title: 'Permission Denied',
    message: 'Insufficient permissions to access cluster resources.',
    details: 'Your user/service account may not have the required RBAC permissions.',
    suggestions: [
      'Contact your cluster administrator',
      'Check if your service account has been deleted',
      'Verify RBAC permissions for your user',
      'Try switching to a different context'
    ]
  },

  AWS_SSO_EXPIRED: {
    type: 'aws_sso_expired',
    title: 'AWS SSO Session Expired',
    message: 'Your AWS SSO session has expired and needs to be refreshed.',
    details: 'EKS cluster authentication requires an active AWS SSO session.',
    suggestions: [
      'Click "Login with AWS SSO" to open the AWS SSO login page',
      'Sign in with your AWS credentials',
      'The session will be valid for 8 hours'
    ],
    commands: [
      {
        label: 'Login with AWS SSO (uneeq-admin profile)',
        command: 'aws sso login --profile uneeq-admin',
        description: 'Opens AWS SSO in your default browser'
      },
      {
        label: 'Check current AWS identity',
        command: 'aws sts get-caller-identity --profile uneeq-admin',
        description: 'Verify your AWS credentials after login'
      }
    ]
  }
};