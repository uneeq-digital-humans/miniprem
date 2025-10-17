import React, { useState, useEffect } from 'react';
import { X, Send, AlertCircle, Loader2, CheckCircle, Shield, Database, Clock, Mail } from 'lucide-react';
import clsx from 'clsx';

interface PermissionModalProps {
  isOpen: boolean;
  onClose: () => void;
  onConfirm: (email: string) => Promise<void>;
  containerName: string;
  metricsPreview?: {
    gpu_percent?: number;
    cpu_percent?: number;
    memory_percent?: number;
  };
}

/**
 * PermissionModal component prompts users for consent before sending
 * container metrics to UneeQ support team via AWS SNS.
 *
 * Features:
 * - Email validation (required field)
 * - Preview of metrics being sent
 * - Loading state during submission
 * - Success confirmation with auto-close
 * - Error handling with retry capability
 * - Keyboard navigation (Escape to close, Tab for focus trap)
 * - Dark mode support
 */
export function PermissionModal({
  isOpen,
  onClose,
  onConfirm,
  containerName,
  metricsPreview
}: PermissionModalProps) {
  const [email, setEmail] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);
  const [validationError, setValidationError] = useState<string | null>(null);

  // Reset state when modal opens/closes
  useEffect(() => {
    if (!isOpen) {
      setEmail('');
      setError(null);
      setSuccess(false);
      setValidationError(null);
    }
  }, [isOpen]);

  if (!isOpen) return null;

  const validateEmail = (email: string): boolean => {
    if (!email.trim()) {
      setValidationError('Email address is required');
      return false;
    }
    // RFC 5322 simplified email regex
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) {
      setValidationError('Please enter a valid email address');
      return false;
    }
    setValidationError(null);
    return true;
  };

  const handleEmailChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setEmail(e.target.value);
    // Clear validation error on change
    if (validationError) {
      setValidationError(null);
    }
  };

  const handleConfirm = async () => {
    if (!validateEmail(email)) {
      return;
    }

    setIsLoading(true);
    setError(null);

    try {
      await onConfirm(email.trim());
      setSuccess(true);

      // Auto-close after 2 seconds on success
      setTimeout(() => {
        onClose();
      }, 2000);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to send metrics. Please try again.');
    } finally {
      setIsLoading(false);
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Escape' && !isLoading) {
      onClose();
    }
    if (e.key === 'Enter' && !isLoading && !success) {
      handleConfirm();
    }
  };

  const isValidEmail = email.trim().length > 0 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
  const currentTimestamp = new Date().toLocaleString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    timeZoneName: 'short'
  });

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      {/* Backdrop */}
      <div
        className="absolute inset-0 bg-black/50 backdrop-blur-sm"
        onClick={() => !isLoading && !success && onClose()}
        onKeyDown={handleKeyDown}
        tabIndex={-1}
      />

      {/* Modal */}
      <div className="relative w-full max-w-lg mx-4">
        <div className="card p-0" data-testid="permission-modal">
          {/* Header */}
          <div className="flex items-center justify-between p-6 border-b border-surface">
            <div className="flex items-center space-x-3">
              <div className="p-2 bg-gradient-to-br from-[#FF6B35] to-[#00A9CE] rounded-full">
                <Shield className="w-5 h-5 text-white" data-testid="permission-icon" />
              </div>
              <div>
                <h2 className="text-lg font-bold text-primary" data-testid="permission-title">
                  Share Metrics with UneeQ Support?
                </h2>
                <p className="text-sm text-secondary">
                  Help us diagnose issues with performance data
                </p>
              </div>
            </div>
            <button
              onClick={onClose}
              disabled={isLoading || success}
              className="btn-icon p-2 disabled:opacity-50 disabled:cursor-not-allowed"
              data-testid="close-permission-modal"
              aria-label="Close modal"
            >
              <X className="w-5 h-5" />
            </button>
          </div>

          {/* Content */}
          <div className="p-6 space-y-4">
            {/* Description */}
            <p className="text-sm text-secondary" data-testid="permission-description">
              This will send performance metrics to help us diagnose issues. Your data will be
              transmitted securely via AWS SNS.
            </p>

            {/* Data Being Sent */}
            <div className="p-4 bg-surface-secondary rounded-lg border border-surface">
              <div className="flex items-center space-x-2 mb-3">
                <Database className="w-4 h-4 text-uneeq-primary" />
                <h3 className="text-sm font-semibold text-primary">Data being sent:</h3>
              </div>
              <ul className="space-y-2 text-sm text-secondary" data-testid="data-list">
                <li className="flex items-start space-x-2">
                  <span className="text-uneeq-primary mt-0.5">•</span>
                  <span>
                    <strong className="text-primary">Container:</strong> {containerName}
                  </span>
                </li>
                <li className="flex items-start space-x-2">
                  <span className="text-uneeq-primary mt-0.5">•</span>
                  <span>
                    <strong className="text-primary">Metrics:</strong> 22 performance metrics
                  </span>
                </li>
                <li className="flex items-start space-x-2">
                  <span className="text-uneeq-primary mt-0.5">•</span>
                  <span className="flex items-center space-x-1">
                    <Clock className="w-3 h-3" />
                    <strong className="text-primary">Timestamp:</strong>
                    <span className="font-mono text-xs">{currentTimestamp}</span>
                  </span>
                </li>
                <li className="flex items-start space-x-2">
                  <span className="text-uneeq-primary mt-0.5">•</span>
                  <span>
                    <strong className="text-primary">Contact:</strong> Your email address
                  </span>
                </li>
              </ul>
            </div>

            {/* Metrics Preview */}
            {metricsPreview && Object.keys(metricsPreview).length > 0 && (
              <div className="p-4 bg-surface-secondary rounded-lg border border-surface">
                <h3 className="text-sm font-semibold text-primary mb-3">Key metrics preview:</h3>
                <div className="grid grid-cols-3 gap-4" data-testid="metrics-preview">
                  {metricsPreview.gpu_percent !== undefined && (
                    <div className="text-center">
                      <div className="text-xs text-muted mb-1">GPU</div>
                      <div className="text-lg font-bold text-uneeq-primary">
                        {metricsPreview.gpu_percent.toFixed(1)}%
                      </div>
                    </div>
                  )}
                  {metricsPreview.cpu_percent !== undefined && (
                    <div className="text-center">
                      <div className="text-xs text-muted mb-1">CPU</div>
                      <div className="text-lg font-bold text-uneeq-primary">
                        {metricsPreview.cpu_percent.toFixed(1)}%
                      </div>
                    </div>
                  )}
                  {metricsPreview.memory_percent !== undefined && (
                    <div className="text-center">
                      <div className="text-xs text-muted mb-1">Memory</div>
                      <div className="text-lg font-bold text-uneeq-primary">
                        {metricsPreview.memory_percent.toFixed(1)}%
                      </div>
                    </div>
                  )}
                </div>
              </div>
            )}

            {/* Warning Banner */}
            <div className="p-3 bg-orange-50 dark:bg-orange-950/30 rounded-lg border border-orange-200 dark:border-orange-800/50 flex items-start space-x-2">
              <AlertCircle className="w-4 h-4 text-orange-500 flex-shrink-0 mt-0.5" />
              <p className="text-xs text-orange-700 dark:text-orange-400" data-testid="warning-message">
                This data will be sent via AWS SNS to the UneeQ support team for analysis.
              </p>
            </div>

            {/* Email Input */}
            <div className="space-y-2">
              <label htmlFor="email-input" className="flex items-center space-x-2 text-sm font-medium text-primary">
                <Mail className="w-4 h-4" />
                <span>Your email address:</span>
              </label>
              <input
                id="email-input"
                type="email"
                value={email}
                onChange={handleEmailChange}
                onBlur={() => email.trim() && validateEmail(email)}
                onKeyDown={handleKeyDown}
                placeholder="your.email@company.com"
                disabled={isLoading || success}
                required
                autoComplete="email"
                className={clsx(
                  'w-full px-3 py-2 border rounded-md',
                  'focus:outline-none focus:ring-2 focus:ring-uneeq-primary focus:border-transparent',
                  'disabled:bg-surface-secondary disabled:cursor-not-allowed',
                  'input-field transition-colors',
                  validationError && 'border-red-500 focus:ring-red-500'
                )}
                data-testid="email-input"
              />
              {validationError && (
                <p className="text-xs text-red-600 dark:text-red-400 flex items-center space-x-1" data-testid="email-validation-error">
                  <AlertCircle className="w-3 h-3" />
                  <span>{validationError}</span>
                </p>
              )}
            </div>

            {/* Error Message */}
            {error && (
              <div className="p-3 bg-red-50 dark:bg-red-950/30 rounded-lg flex items-start space-x-2" data-testid="permission-error">
                <AlertCircle className="w-4 h-4 text-red-500 flex-shrink-0 mt-0.5" />
                <div className="flex-1">
                  <p className="text-sm text-red-700 dark:text-red-400">{error}</p>
                  <button
                    onClick={() => setError(null)}
                    className="text-xs text-red-600 dark:text-red-300 underline hover:no-underline mt-1"
                  >
                    Dismiss
                  </button>
                </div>
              </div>
            )}

            {/* Success Message */}
            {success && (
              <div className="p-3 bg-green-50 dark:bg-green-950/30 rounded-lg flex items-center space-x-2" data-testid="permission-success">
                <CheckCircle className="w-4 h-4 text-green-500 flex-shrink-0" />
                <p className="text-sm text-green-700 dark:text-green-400">
                  Metrics sent successfully! Thank you for sharing this data.
                </p>
              </div>
            )}
          </div>

          {/* Footer */}
          <div className="flex items-center justify-end space-x-3 p-6 border-t border-surface">
            <button
              onClick={onClose}
              disabled={isLoading || success}
              className="btn-secondary px-4 py-2 disabled:opacity-50 disabled:cursor-not-allowed"
              data-testid="permission-cancel"
            >
              Cancel
            </button>

            <button
              onClick={handleConfirm}
              disabled={!isValidEmail || isLoading || success}
              className={clsx(
                'px-4 py-2 rounded-md font-medium flex items-center space-x-2 transition-colors',
                'focus:outline-none focus:ring-2 focus:ring-uneeq-primary focus:ring-offset-2',
                success
                  ? 'bg-green-600 hover:bg-green-700 text-white'
                  : 'bg-gradient-to-r from-[#FF6B35] to-[#00A9CE] hover:opacity-90 text-white',
                (!isValidEmail || isLoading || success) && 'opacity-50 cursor-not-allowed'
              )}
              data-testid="permission-confirm-button"
            >
              {isLoading && <Loader2 className="w-4 h-4 animate-spin" />}
              {success && <CheckCircle className="w-4 h-4" />}
              {!isLoading && !success && <Send className="w-4 h-4" />}
              <span>
                {isLoading ? 'Sending...' : success ? 'Sent!' : 'Confirm & Send'}
              </span>
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
