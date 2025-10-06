import React, { useState } from 'react';
import { Eye, EyeOff, Lock, AlertCircle, Loader2 } from 'lucide-react';

interface AuthModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSubmit: (password: string) => void;
  challenge?: {
    message: string;
    challengeType: string;
    commandType: string;
    retryCount: number;
  };
  isLoading?: boolean;
  error?: string;
}

export function AuthModal({
  isOpen,
  onClose,
  onSubmit,
  challenge,
  isLoading = false,
  error
}: AuthModalProps) {
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);

  if (!isOpen || !challenge) return null;

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (password.trim() && !isLoading) {
      onSubmit(password);
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Escape' && !isLoading) {
      onClose();
    }
  };

  return (
    <div
      className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50"
      onClick={(e) => e.target === e.currentTarget && !isLoading && onClose()}
      onKeyDown={handleKeyDown}
      tabIndex={-1}
      data-testid="auth-modal-overlay"
    >
      <div className="bg-white rounded-lg shadow-xl max-w-md w-full mx-4" data-testid="auth-modal">
        <div className="p-6">
          {/* Header */}
          <div className="flex items-center space-x-3 mb-4">
            <div className="p-2 bg-blue-100 rounded-full">
              <Lock className="w-5 h-5 text-blue-600" data-testid="auth-modal-lock-icon" />
            </div>
            <div>
              <h2 className="text-lg font-semibold text-gray-900" data-testid="auth-modal-title">
                Authentication Required
              </h2>
              <p className="text-sm text-gray-600" data-testid="auth-modal-command-type">
                {challenge.commandType.charAt(0).toUpperCase() + challenge.commandType.slice(1)} access needed
              </p>
            </div>
          </div>

          {/* Challenge Message */}
          <div className="mb-4 p-3 bg-gray-50 rounded-lg">
            <p className="text-sm text-gray-700" data-testid="auth-modal-message">
              {challenge.message}
            </p>
          </div>

          {/* Error Message */}
          {error && (
            <div className="mb-4 p-3 bg-red-50 rounded-lg flex items-center space-x-2" data-testid="auth-modal-error">
              <AlertCircle className="w-4 h-4 text-red-500" />
              <p className="text-sm text-red-700">{error}</p>
              <span className="text-xs text-red-500 ml-auto" data-testid="auth-modal-retry-count">
                {challenge.retryCount} {challenge.retryCount === 1 ? 'try' : 'tries'} remaining
              </span>
            </div>
          )}

          {/* Password Form */}
          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label htmlFor="password" className="block text-sm font-medium text-gray-700 mb-2">
                Enter your password:
              </label>
              <div className="relative">
                <input
                  id="password"
                  type={showPassword ? 'text' : 'password'}
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="Enter password"
                  disabled={isLoading}
                  className="w-full px-3 py-2 pr-10 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent disabled:bg-gray-100"
                  data-testid="auth-modal-password-input"
                  autoFocus
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(!showPassword)}
                  disabled={isLoading}
                  className="absolute inset-y-0 right-0 px-3 flex items-center text-gray-400 hover:text-gray-600 disabled:cursor-not-allowed"
                  data-testid="auth-modal-toggle-password"
                >
                  {showPassword ? (
                    <EyeOff className="w-4 h-4" />
                  ) : (
                    <Eye className="w-4 h-4" />
                  )}
                </button>
              </div>
            </div>

            {/* Action Buttons */}
            <div className="flex space-x-3">
              <button
                type="button"
                onClick={onClose}
                disabled={isLoading}
                className="flex-1 px-4 py-2 text-sm font-medium text-gray-700 bg-gray-100 hover:bg-gray-200 rounded-md focus:outline-none focus:ring-2 focus:ring-gray-500 disabled:opacity-50 disabled:cursor-not-allowed"
                data-testid="auth-modal-cancel-button"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={!password.trim() || isLoading}
                className="flex-1 px-4 py-2 text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center space-x-2"
                data-testid="auth-modal-submit-button"
              >
                {isLoading ? (
                  <>
                    <Loader2 className="w-4 h-4 animate-spin" />
                    <span>Authenticating...</span>
                  </>
                ) : (
                  <span>Authenticate</span>
                )}
              </button>
            </div>
          </form>

          {/* Challenge Type Info */}
          <div className="mt-4 text-xs text-gray-500" data-testid="auth-modal-challenge-type">
            Challenge type: {challenge.challengeType}
          </div>
        </div>
      </div>
    </div>
  );
}