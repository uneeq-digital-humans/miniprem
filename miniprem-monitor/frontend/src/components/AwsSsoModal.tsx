import React, { useState } from 'react';
import { X, Cloud, ExternalLink, AlertCircle, Loader2, CheckCircle } from 'lucide-react';
import clsx from 'clsx';

interface AwsSsoModalProps {
  isOpen: boolean;
  onClose: () => void;
  onLogin: (profile: string) => Promise<void>;
  profiles?: string[];
  error?: string;
}

export function AwsSsoModal({
  isOpen,
  onClose,
  onLogin,
  profiles = ['uneeq-admin', 'default'],
  error
}: AwsSsoModalProps) {
  const [selectedProfile, setSelectedProfile] = useState(profiles[0]);
  const [isLoading, setIsLoading] = useState(false);
  const [loginSuccess, setLoginSuccess] = useState(false);

  if (!isOpen) return null;

  const handleLogin = async () => {
    setIsLoading(true);
    setLoginSuccess(false);
    try {
      await onLogin(selectedProfile);
      setLoginSuccess(true);
      setTimeout(() => {
        onClose();
        setLoginSuccess(false);
      }, 1500);
    } catch (err) {
      // Error will be shown via the error prop
    } finally {
      setIsLoading(false);
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Escape' && !isLoading) {
      onClose();
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      {/* Backdrop */}
      <div
        className="absolute inset-0 bg-black/50 backdrop-blur-sm"
        onClick={() => !isLoading && onClose()}
        onKeyDown={handleKeyDown}
        tabIndex={-1}
      />

      {/* Modal */}
      <div className="relative w-full max-w-md mx-4">
        <div className="card p-0" data-testid="aws-sso-modal">
          {/* Header */}
          <div className="flex items-center justify-between p-6 border-b border-surface">
            <div className="flex items-center space-x-3">
              <div className="p-2 bg-gradient-to-br from-[#FF6B35] to-[#00A9CE] rounded-full">
                <Cloud className="w-5 h-5 text-white" data-testid="aws-sso-icon" />
              </div>
              <div>
                <h2 className="text-lg font-bold text-primary" data-testid="aws-sso-title">
                  AWS SSO Login Required
                </h2>
                <p className="text-sm text-secondary">
                  Kubernetes cluster authentication
                </p>
              </div>
            </div>
            <button
              onClick={onClose}
              disabled={isLoading}
              className="btn-icon p-2 disabled:opacity-50 disabled:cursor-not-allowed"
              data-testid="close-aws-sso-modal"
            >
              <X className="w-5 h-5" />
            </button>
          </div>

          {/* Content */}
          <div className="p-6">
            {/* Message */}
            <div className="mb-4 p-4 bg-gradient-to-r from-orange-50 to-blue-50 dark:from-orange-950/30 dark:to-blue-950/30 rounded-lg border border-orange-200/50 dark:border-orange-800/50">
              <p className="text-sm text-secondary" data-testid="aws-sso-message">
                Your AWS SSO session has expired. Please authenticate to access the EKS cluster.
              </p>
            </div>

            {/* Error Message */}
            {error && (
              <div className="mb-4 p-3 bg-red-50 dark:bg-red-950/30 rounded-lg flex items-center space-x-2" data-testid="aws-sso-error">
                <AlertCircle className="w-4 h-4 text-red-500 flex-shrink-0" />
                <p className="text-sm text-red-700 dark:text-red-400">{error}</p>
              </div>
            )}

            {/* Success Message */}
            {loginSuccess && (
              <div className="mb-4 p-3 bg-green-50 dark:bg-green-950/30 rounded-lg flex items-center space-x-2" data-testid="aws-sso-success">
                <CheckCircle className="w-4 h-4 text-green-500 flex-shrink-0" />
                <p className="text-sm text-green-700 dark:text-green-400">
                  AWS SSO login successful! Connecting to cluster...
                </p>
              </div>
            )}

            {/* Profile Selection */}
            <div className="mb-4">
              <label htmlFor="aws-profile" className="block text-sm font-medium text-primary mb-2">
                AWS Profile:
              </label>
              <select
                id="aws-profile"
                value={selectedProfile}
                onChange={(e) => setSelectedProfile(e.target.value)}
                disabled={isLoading || loginSuccess}
                className="w-full px-3 py-2 border border-surface rounded-md focus:outline-none focus:ring-2 focus:ring-uneeq-primary focus:border-transparent disabled:bg-surface-secondary disabled:cursor-not-allowed bg-background text-primary"
                data-testid="aws-profile-select"
              >
                {profiles.map((profile) => (
                  <option key={profile} value={profile}>
                    {profile}
                  </option>
                ))}
              </select>
            </div>

            {/* Instructions */}
            <div className="mb-4 text-xs text-muted space-y-1">
              <p className="font-medium text-secondary">What happens next:</p>
              <ul className="list-disc list-inside space-y-1 ml-2">
                <li>AWS will open in your default browser</li>
                <li>Sign in with your SSO credentials</li>
                <li>The session will be cached for 8 hours</li>
                <li>Kubernetes cluster access will be restored</li>
              </ul>
            </div>

            {/* Command Reference */}
            <div className="p-3 bg-gray-900 dark:bg-gray-950 rounded-lg">
              <div className="flex items-center justify-between mb-1">
                <span className="text-xs font-medium text-gray-400">Equivalent command:</span>
              </div>
              <code className="block text-xs text-gray-300 font-mono" data-testid="aws-command">
                aws sso login --profile {selectedProfile}
              </code>
            </div>
          </div>

          {/* Footer */}
          <div className="flex items-center justify-end space-x-3 p-6 border-t border-surface">
            <button
              onClick={onClose}
              disabled={isLoading}
              className="btn-secondary px-4 py-2 disabled:opacity-50 disabled:cursor-not-allowed"
              data-testid="aws-sso-cancel"
            >
              Cancel
            </button>

            <button
              onClick={handleLogin}
              disabled={isLoading || loginSuccess}
              className={clsx(
                'px-4 py-2 rounded-md font-medium flex items-center space-x-2 transition-colors',
                'focus:outline-none focus:ring-2 focus:ring-uneeq-primary focus:ring-offset-2',
                loginSuccess
                  ? 'bg-green-600 hover:bg-green-700 text-white'
                  : 'bg-gradient-to-r from-[#FF6B35] to-[#00A9CE] hover:opacity-90 text-white',
                (isLoading || loginSuccess) && 'opacity-50 cursor-not-allowed'
              )}
              data-testid="aws-sso-login-button"
            >
              {isLoading && <Loader2 className="w-4 h-4 animate-spin" />}
              {loginSuccess && <CheckCircle className="w-4 h-4" />}
              {!isLoading && !loginSuccess && <Cloud className="w-4 h-4" />}
              <span>
                {isLoading ? 'Opening AWS SSO...' : loginSuccess ? 'Success!' : 'Login with AWS SSO'}
              </span>
              {!isLoading && !loginSuccess && <ExternalLink className="w-3 h-3" />}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
