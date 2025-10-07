# Modal Integration Guide

This guide shows how to integrate the AWS SSO and Docker authentication modals into your UI.

## 1. AWS SSO Modal Integration

### Detecting AWS SSO Expiration

When kubectl fails with AWS SSO expiration, you'll receive an error like:
```
"The SSO session associated with this profile has expired or is otherwise invalid"
```

### Example Integration in KubernetesPanel.tsx

```typescript
import { useState } from 'react';
import { AwsSsoModal } from './AwsSsoModal';
import { KubernetesErrorModal, KUBERNETES_ERRORS } from './KubernetesErrorModal';

export function KubernetesPanel() {
  const [showAwsSsoModal, setShowAwsSsoModal] = useState(false);
  const [showErrorModal, setShowErrorModal] = useState(false);
  const [kubernetesError, setKubernetesError] = useState(null);
  const [awsSsoError, setAwsSsoError] = useState('');

  // Check for AWS SSO expiration in error messages
  const checkForAwsSsoExpiration = (errorMessage: string) => {
    if (errorMessage.includes('SSO session') && errorMessage.includes('expired')) {
      setShowAwsSsoModal(true);
      return true;
    }
    return false;
  };

  // Handle Kubernetes errors from backend
  const handleKubernetesError = (error: any) => {
    const errorMessage = error.message || error.error || '';

    // Check if it's AWS SSO expiration
    if (checkForAwsSsoExpiration(errorMessage)) {
      // Show AWS SSO modal directly
      setShowAwsSsoModal(true);
    } else {
      // Show general error modal
      setKubernetesError(KUBERNETES_ERRORS.CONNECTION_FAILED);
      setShowErrorModal(true);
    }
  };

  // Handle AWS SSO login
  const handleAwsSsoLogin = async (profile: string) => {
    try {
      const response = await fetch('/api/aws/sso/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ profile })
      });

      const data = await response.json();

      if (data.success) {
        // Close modal and retry Kubernetes connection
        setShowAwsSsoModal(false);
        setAwsSsoError('');
        // Trigger Kubernetes refresh
        refreshKubernetesData();
      } else {
        setAwsSsoError(data.error || 'AWS SSO login failed');
        throw new Error(data.error);
      }
    } catch (error) {
      console.error('AWS SSO login error:', error);
      setAwsSsoError(error.message);
      throw error;
    }
  };

  return (
    <div>
      {/* Your Kubernetes panel content */}

      {/* AWS SSO Modal */}
      <AwsSsoModal
        isOpen={showAwsSsoModal}
        onClose={() => setShowAwsSsoModal(false)}
        onLogin={handleAwsSsoLogin}
        profiles={['uneeq-admin', 'default']}
        error={awsSsoError}
      />

      {/* General Kubernetes Error Modal */}
      <KubernetesErrorModal
        isOpen={showErrorModal}
        error={kubernetesError}
        onClose={() => setShowErrorModal(false)}
        onRetry={refreshKubernetesData}
      />
    </div>
  );
}
```

## 2. Docker Password Modal (AuthModal) Integration

### Detecting Docker Authentication Challenges

The backend will send a "challenge" message when Docker needs sudo password:

```json
{
  "type": "auth_challenge",
  "challenge": {
    "message": "Docker command requires sudo password",
    "challengeType": "sudo_password",
    "commandType": "docker",
    "retryCount": 3
  }
}
```

### Example Integration in ContainerPanel.tsx

```typescript
import { useState } from 'react';
import { AuthModal } from './AuthModal';

export function ContainerPanel() {
  const [showAuthModal, setShowAuthModal] = useState(false);
  const [authChallenge, setAuthChallenge] = useState(null);
  const [authLoading, setAuthLoading] = useState(false);
  const [authError, setAuthError] = useState('');

  // Handle authentication challenge from backend
  const handleAuthChallenge = (challenge: any) => {
    setAuthChallenge(challenge);
    setShowAuthModal(true);
  };

  // Handle password submission
  const handlePasswordSubmit = async (password: string) => {
    setAuthLoading(true);
    setAuthError('');

    try {
      // Send password to backend for authentication
      const response = await fetch('/api/docker/authenticate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ password })
      });

      const data = await response.json();

      if (data.success) {
        setShowAuthModal(false);
        setAuthChallenge(null);
        // Retry the original Docker command
        retryDockerCommand();
      } else {
        setAuthError(data.error || 'Authentication failed');
        // Decrement retry count
        if (authChallenge) {
          setAuthChallenge({
            ...authChallenge,
            retryCount: authChallenge.retryCount - 1
          });
        }
      }
    } catch (error) {
      setAuthError('Authentication error: ' + error.message);
    } finally {
      setAuthLoading(false);
    }
  };

  return (
    <div>
      {/* Your container panel content */}

      {/* Docker Authentication Modal */}
      <AuthModal
        isOpen={showAuthModal}
        onClose={() => {
          setShowAuthModal(false);
          setAuthChallenge(null);
        }}
        onSubmit={handlePasswordSubmit}
        challenge={authChallenge}
        isLoading={authLoading}
        error={authError}
      />
    </div>
  );
}
```

## 3. Quick Integration Example

### Add to page.tsx (Main Dashboard)

```typescript
'use client';

import React, { useState } from 'react';
import { AwsSsoModal } from '../components/AwsSsoModal';
import { AuthModal } from '../components/AuthModal';

export default function MonitoringDashboard() {
  // AWS SSO Modal State
  const [showAwsSsoModal, setShowAwsSsoModal] = useState(false);
  const [awsSsoError, setAwsSsoError] = useState('');

  // Docker Auth Modal State
  const [showAuthModal, setShowAuthModal] = useState(false);
  const [authChallenge, setAuthChallenge] = useState(null);
  const [authError, setAuthError] = useState('');

  // AWS SSO Login Handler
  const handleAwsSsoLogin = async (profile: string) => {
    const response = await fetch('/api/aws/sso/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ profile })
    });
    const data = await response.json();
    if (!data.success) throw new Error(data.error);
  };

  // Docker Password Handler
  const handlePasswordSubmit = async (password: string) => {
    // Handle Docker authentication
    console.log('Docker password submitted');
  };

  return (
    <div>
      {/* Your dashboard content */}

      {/* Test buttons for development */}
      <button onClick={() => setShowAwsSsoModal(true)}>
        Test AWS SSO Modal
      </button>
      <button onClick={() => {
        setAuthChallenge({
          message: 'Docker command requires sudo password',
          challengeType: 'sudo_password',
          commandType: 'docker',
          retryCount: 3
        });
        setShowAuthModal(true);
      }}>
        Test Docker Auth Modal
      </button>

      {/* Modals */}
      <AwsSsoModal
        isOpen={showAwsSsoModal}
        onClose={() => setShowAwsSsoModal(false)}
        onLogin={handleAwsSsoLogin}
        error={awsSsoError}
      />

      <AuthModal
        isOpen={showAuthModal}
        onClose={() => setShowAuthModal(false)}
        onSubmit={handlePasswordSubmit}
        challenge={authChallenge}
        error={authError}
      />
    </div>
  );
}
```

## 4. Backend Error Detection Patterns

### AWS SSO Errors to Detect

```typescript
const AWS_SSO_ERROR_PATTERNS = [
  'SSO session',
  'expired or is otherwise invalid',
  'aws sso login',
  'getting credentials: exec: executable aws failed'
];

function isAwsSsoError(errorMessage: string): boolean {
  return AWS_SSO_ERROR_PATTERNS.some(pattern =>
    errorMessage.toLowerCase().includes(pattern.toLowerCase())
  );
}
```

### Docker Auth Errors to Detect

```typescript
const DOCKER_AUTH_ERROR_PATTERNS = [
  'permission denied',
  'sudo password',
  'authentication required',
  'access denied'
];

function isDockerAuthError(errorMessage: string): boolean {
  return DOCKER_AUTH_ERROR_PATTERNS.some(pattern =>
    errorMessage.toLowerCase().includes(pattern.toLowerCase())
  );
}
```

## 5. WebSocket Integration

### Listen for errors in WebSocket messages

```typescript
useEffect(() => {
  if (!websocket) return;

  const handleMessage = (event: MessageEvent) => {
    const data = JSON.parse(event.data);

    // Check for Kubernetes errors
    if (data.type === 'kubernetes_status' && data.error) {
      if (isAwsSsoError(data.error)) {
        setShowAwsSsoModal(true);
      }
    }

    // Check for Docker auth challenges
    if (data.type === 'auth_challenge') {
      setAuthChallenge(data.challenge);
      setShowAuthModal(true);
    }
  };

  websocket.addEventListener('message', handleMessage);
  return () => websocket.removeEventListener('message', handleMessage);
}, [websocket]);
```

## 6. Testing the Modals

### To test AWS SSO Modal:
1. Add a button to trigger: `<button onClick={() => setShowAwsSsoModal(true)}>Test AWS SSO</button>`
2. Click the button to see the modal
3. The modal will show the AWS SSO login UI

### To test Docker Auth Modal:
1. Add a button with sample challenge:
```typescript
<button onClick={() => {
  setAuthChallenge({
    message: 'Docker command requires sudo password',
    challengeType: 'sudo_password',
    commandType: 'docker',
    retryCount: 3
  });
  setShowAuthModal(true);
}}>
  Test Docker Auth
</button>
```

## 7. Production Integration Checklist

- [ ] Import AwsSsoModal and AuthModal components
- [ ] Add state for modal visibility
- [ ] Add state for error messages
- [ ] Implement error detection logic
- [ ] Connect modal callbacks to backend APIs
- [ ] Handle modal close/cancel actions
- [ ] Test with real AWS SSO expiration
- [ ] Test with real Docker authentication
- [ ] Add loading states during authentication
- [ ] Handle authentication failures gracefully
