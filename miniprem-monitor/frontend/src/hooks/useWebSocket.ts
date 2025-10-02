import { useEffect, useRef, useState, useCallback } from 'react';
import { CommandRequest, CommandResponse } from '../types/monitor';

/**
 * Connection states for WebSocket lifecycle management
 */
export enum ConnectionState {
  DISCONNECTED = 'disconnected',
  CONNECTING = 'connecting',
  CONNECTED = 'connected',
  RECONNECTING = 'reconnecting',
  DISCONNECTING = 'disconnecting',
  FAILED = 'failed',
}

/**
 * Error types for different connection failure scenarios
 */
export enum ConnectionErrorType {
  NETWORK_ERROR = 'network_error',
  AUTHENTICATION_ERROR = 'authentication_error',
  SERVER_ERROR = 'server_error',
  TIMEOUT_ERROR = 'timeout_error',
  UNKNOWN_ERROR = 'unknown_error',
}

/**
 * Enhanced error information for connection failures
 */
export interface ConnectionError {
  type: ConnectionErrorType;
  message: string;
  code?: number;
  timestamp: number;
}

/**
 * Connection statistics for monitoring and debugging
 */
export interface ConnectionStats {
  totalConnections: number;
  totalDisconnections: number;
  totalReconnects: number;
  totalErrors: number;
  lastConnectedAt?: number;
  lastDisconnectedAt?: number;
  lastErrorAt?: number;
  connectionDuration?: number;
}

interface UseWebSocketOptions {
  onMessage?: (data: CommandResponse) => void;
  onError?: (error: ConnectionError) => void;
  onConnect?: () => void;
  onDisconnect?: () => void;
  onStateChange?: (state: ConnectionState) => void;

  // Connection configuration
  reconnectAttempts?: number;
  initialReconnectDelay?: number;
  maxReconnectDelay?: number;
  reconnectDecay?: number;
  connectionTimeout?: number;

  // Health monitoring
  heartbeatInterval?: number;
  heartbeatTimeout?: number;

  // Rate limiting
  maxConnectionsPerMinute?: number;
  circuitBreakerThreshold?: number;
  circuitBreakerResetTime?: number;

  // Debug options
  debug?: boolean;
}

export function useWebSocket(url: string, options: UseWebSocketOptions = {}) {
  const {
    onMessage,
    onError,
    onConnect,
    onDisconnect,
    onStateChange,

    // Connection configuration
    reconnectAttempts = 10,
    initialReconnectDelay = 1000,
    maxReconnectDelay = 35000,
    reconnectDecay = 1.5,
    connectionTimeout = 10000,

    // Health monitoring
    heartbeatInterval = 35000,
    heartbeatTimeout = 5000,

    // Rate limiting
    maxConnectionsPerMinute = 10,
    circuitBreakerThreshold = 5,
    circuitBreakerResetTime = 60000,

    // Debug options
    debug = false,
  } = options;

  // WebSocket and connection state
  const ws = useRef<WebSocket | null>(null);
  const reconnectTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const heartbeatTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const heartbeatIntervalRef = useRef<NodeJS.Timeout | null>(null);
  const connectionTimeoutRef = useRef<NodeJS.Timeout | null>(null);

  // Connection state management
  const [connectionState, setConnectionState] = useState<ConnectionState>(ConnectionState.DISCONNECTED);
  const [isConnected, setIsConnected] = useState(false);
  const [connectionId, setConnectionId] = useState<string | null>(null);
  const [lastError, setLastError] = useState<ConnectionError | null>(null);
  const [connectionStats, setConnectionStats] = useState<ConnectionStats>({
    totalConnections: 0,
    totalDisconnections: 0,
    totalReconnects: 0,
    totalErrors: 0,
  });

  // Connection attempt tracking
  const reconnectCount = useRef(0);
  const currentReconnectDelay = useRef(initialReconnectDelay);
  const isConnecting = useRef(false);
  const lastHeartbeatTime = useRef<number>(0);

  // Rate limiting and circuit breaker
  const connectionAttempts = useRef<number[]>([]);
  const consecutiveFailures = useRef(0);
  const circuitBreakerOpenUntil = useRef<number>(0);

  // Use refs to store callback functions to prevent dependency churn
  const onMessageRef = useRef(onMessage);
  const onErrorRef = useRef(onError);
  const onConnectRef = useRef(onConnect);
  const onDisconnectRef = useRef(onDisconnect);
  const onStateChangeRef = useRef(onStateChange);

  // Update refs when callbacks change
  useEffect(() => {
    onMessageRef.current = onMessage;
  }, [onMessage]);

  useEffect(() => {
    onErrorRef.current = onError;
  }, [onError]);

  useEffect(() => {
    onConnectRef.current = onConnect;
  }, [onConnect]);

  useEffect(() => {
    onDisconnectRef.current = onDisconnect;
  }, [onDisconnect]);

  useEffect(() => {
    onStateChangeRef.current = onStateChange;
  }, [onStateChange]);

  /**
   * Utility function for debug logging
   */
  const debugLog = useCallback(
    (message: string, ...args: unknown[]) => {
      if (debug) {
        console.log(`[WebSocket Debug] ${message}`, ...args);
      }
    },
    [debug]
  );

  /**
   * Updates connection state and notifies listeners
   */
  const updateConnectionState = useCallback(
    (newState: ConnectionState) => {
      setConnectionState(newState);
      onStateChangeRef.current?.(newState);
      debugLog('Connection state changed:', newState);
    },
    [debugLog]
  );

  /**
   * Creates and returns a connection error object
   */
  const createConnectionError = useCallback(
    (type: ConnectionErrorType, message: string, code?: number): ConnectionError => {
      const error: ConnectionError = {
        type,
        message,
        code,
        timestamp: Date.now(),
      };

      setLastError(error);
      setConnectionStats((prev) => ({
        ...prev,
        totalErrors: prev.totalErrors + 1,
        lastErrorAt: error.timestamp,
      }));

      debugLog('Connection error:', error);
      return error;
    },
    [debugLog]
  );

  /**
   * Rate limiting check - prevents too many connection attempts
   */
  const isRateLimited = useCallback((): boolean => {
    const now = Date.now();
    const oneMinuteAgo = now - 60000;

    // Clean old attempts
    connectionAttempts.current = connectionAttempts.current.filter((time) => time > oneMinuteAgo);

    // Check if we've exceeded the rate limit
    const isLimited = connectionAttempts.current.length >= maxConnectionsPerMinute;

    if (isLimited) {
      debugLog('Connection rate limited:', connectionAttempts.current.length, 'attempts in last minute');
    }

    return isLimited;
  }, [maxConnectionsPerMinute, debugLog]);

  /**
   * Circuit breaker check - prevents connections after consecutive failures
   */
  const isCircuitBreakerOpen = useCallback((): boolean => {
    const now = Date.now();

    // Reset circuit breaker if enough time has passed
    if (circuitBreakerOpenUntil.current > 0 && now > circuitBreakerOpenUntil.current) {
      circuitBreakerOpenUntil.current = 0;
      consecutiveFailures.current = 0;
      debugLog('Circuit breaker reset');
    }

    const isOpen = circuitBreakerOpenUntil.current > now;

    if (isOpen) {
      debugLog('Circuit breaker is open until:', new Date(circuitBreakerOpenUntil.current));
    }

    return isOpen;
  }, [debugLog]);

  /**
   * Calculates the next reconnection delay using exponential backoff with jitter
   */
  const calculateReconnectDelay = useCallback((): number => {
    const delay = Math.min(
      currentReconnectDelay.current * Math.pow(reconnectDecay, reconnectCount.current),
      maxReconnectDelay
    );

    // Add jitter to prevent thundering herd (±25% of delay)
    const jitter = delay * 0.25 * (Math.random() - 0.5);
    const finalDelay = Math.max(1000, delay + jitter);

    debugLog('Reconnect delay calculated:', finalDelay + 'ms', 'attempt:', reconnectCount.current + 1);
    return finalDelay;
  }, [reconnectDecay, maxReconnectDelay, debugLog]);

  /**
   * Starts heartbeat monitoring
   */
  const startHeartbeat = useCallback(() => {
    if (heartbeatIntervalRef.current) {
      clearInterval(heartbeatIntervalRef.current);
    }

    lastHeartbeatTime.current = Date.now();

    heartbeatIntervalRef.current = setInterval(() => {
      if (ws.current?.readyState === WebSocket.OPEN) {
        const pingMessage = { type: 'ping', timestamp: Date.now() };
        ws.current.send(JSON.stringify(pingMessage));

        // Set timeout for pong response
        if (heartbeatTimeoutRef.current) {
          clearTimeout(heartbeatTimeoutRef.current);
        }

        heartbeatTimeoutRef.current = setTimeout(() => {
          debugLog('Heartbeat timeout - connection may be stale');
          const error = createConnectionError(
            ConnectionErrorType.TIMEOUT_ERROR,
            'Heartbeat timeout - connection appears to be stale'
          );
          onErrorRef.current?.(error);

          // Force reconnection
          if (ws.current) {
            ws.current.close(4000, 'Heartbeat timeout');
          }
        }, heartbeatTimeout);
      }
    }, heartbeatInterval);

    debugLog('Heartbeat started, interval:', heartbeatInterval + 'ms');
  }, [heartbeatInterval, heartbeatTimeout, createConnectionError, debugLog]);

  /**
   * Stops heartbeat monitoring
   */
  const stopHeartbeat = useCallback(() => {
    if (heartbeatIntervalRef.current) {
      clearInterval(heartbeatIntervalRef.current);
      heartbeatIntervalRef.current = null;
    }

    if (heartbeatTimeoutRef.current) {
      clearTimeout(heartbeatTimeoutRef.current);
      heartbeatTimeoutRef.current = null;
    }

    debugLog('Heartbeat stopped');
  }, [debugLog]);

  /**
   * Handles incoming pong messages
   */
  const handlePong = useCallback(() => {
    lastHeartbeatTime.current = Date.now();

    if (heartbeatTimeoutRef.current) {
      clearTimeout(heartbeatTimeoutRef.current);
      heartbeatTimeoutRef.current = null;
    }

    debugLog('Heartbeat pong received');
  }, [debugLog]);

  /**
   * Main connection function with enhanced stability safeguards
   */
  const connect = useCallback(
    (isReconnect: boolean = false): Promise<void> => {
      // Prevent multiple simultaneous connections
      if (isConnecting.current) {
        debugLog('Connection attempt blocked - already connecting');
        return Promise.reject(new Error('Connection already in progress'));
      }

      // Rate limiting check
      if (isRateLimited()) {
        const error = createConnectionError(
          ConnectionErrorType.NETWORK_ERROR,
          'Connection rate limited - too many attempts'
        );
        onErrorRef.current?.(error);
        return Promise.reject(error);
      }

      // Circuit breaker check
      if (isCircuitBreakerOpen()) {
        const error = createConnectionError(
          ConnectionErrorType.NETWORK_ERROR,
          'Circuit breaker is open - too many consecutive failures'
        );
        onErrorRef.current?.(error);
        return Promise.reject(error);
      }

      return new Promise<void>((resolve, reject) => {
        try {
          isConnecting.current = true;
          const connectionStartTime = Date.now();

          // Update state
          updateConnectionState(isReconnect ? ConnectionState.RECONNECTING : ConnectionState.CONNECTING);

          // Record connection attempt
          connectionAttempts.current.push(Date.now());

          // Close existing connection if any
          if (ws.current?.readyState === WebSocket.OPEN) {
            ws.current.close(1000, 'Reconnecting');
          }

          // Clear any existing timeouts
          if (connectionTimeoutRef.current) {
            clearTimeout(connectionTimeoutRef.current);
          }

          // Set connection timeout
          connectionTimeoutRef.current = setTimeout(() => {
            isConnecting.current = false;
            const error = createConnectionError(
              ConnectionErrorType.TIMEOUT_ERROR,
              `Connection timeout after ${connectionTimeout}ms`
            );
            onErrorRef.current?.(error);

            if (ws.current) {
              ws.current.close(4001, 'Connection timeout');
            }

            reject(error);
          }, connectionTimeout);

          const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
          const wsUrl = url.startsWith('ws') ? url : `${protocol}//${window.location.host}${url}`;

          debugLog('Attempting connection to:', wsUrl, 'isReconnect:', isReconnect);
          ws.current = new WebSocket(wsUrl);

          ws.current.onopen = () => {
            isConnecting.current = false;

            if (connectionTimeoutRef.current) {
              clearTimeout(connectionTimeoutRef.current);
              connectionTimeoutRef.current = null;
            }

            const connectionDuration = Date.now() - connectionStartTime;

            debugLog('WebSocket connected in', connectionDuration + 'ms');

            // Update state and stats
            setIsConnected(true);
            updateConnectionState(ConnectionState.CONNECTED);

            setConnectionStats((prev) => ({
              ...prev,
              totalConnections: prev.totalConnections + 1,
              lastConnectedAt: Date.now(),
              connectionDuration,
            }));

            // Reset failure tracking
            reconnectCount.current = 0;
            consecutiveFailures.current = 0;
            currentReconnectDelay.current = initialReconnectDelay;

            // Start heartbeat monitoring
            startHeartbeat();

            onConnectRef.current?.();
            resolve();
          };

          ws.current.onmessage = (event) => {
            try {
              const data = JSON.parse(event.data);

              // Handle pong messages for heartbeat
              if (data.type === 'pong') {
                handlePong();
                return;
              }

              // Handle connection message
              if (data.type === 'connection') {
                setConnectionId(data.connection_id);
                debugLog('Received connection ID:', data.connection_id);
                return;
              }

              // Handle command responses
              if (data.requestId) {
                onMessageRef.current?.(data as CommandResponse);
              }
            } catch (error) {
              debugLog('Error parsing WebSocket message:', error);
              const connectionError = createConnectionError(
                ConnectionErrorType.UNKNOWN_ERROR,
                `Message parsing error: ${error instanceof Error ? error.message : 'Unknown error'}`
              );
              onErrorRef.current?.(connectionError);
            }
          };

          ws.current.onclose = (event) => {
            isConnecting.current = false;

            if (connectionTimeoutRef.current) {
              clearTimeout(connectionTimeoutRef.current);
              connectionTimeoutRef.current = null;
            }

            stopHeartbeat();
            setIsConnected(false);
            setConnectionId(null);

            setConnectionStats((prev) => ({
              ...prev,
              totalDisconnections: prev.totalDisconnections + 1,
              lastDisconnectedAt: Date.now(),
            }));

            debugLog('WebSocket disconnected', 'code:', event.code, 'reason:', event.reason);

            const wasManualClose = event.code === 1000;
            const wasReconnecting = connectionState === ConnectionState.RECONNECTING;

            if (wasManualClose) {
              updateConnectionState(ConnectionState.DISCONNECTED);
              onDisconnectRef.current?.();
              resolve(); // Resolve for manual disconnections
            } else {
              // Increment failure count for circuit breaker
              consecutiveFailures.current += 1;

              // Check if circuit breaker should open
              if (consecutiveFailures.current >= circuitBreakerThreshold) {
                circuitBreakerOpenUntil.current = Date.now() + circuitBreakerResetTime;
                debugLog('Circuit breaker opened due to consecutive failures:', consecutiveFailures.current);
              }

              const errorType =
                event.code >= 4000 ? ConnectionErrorType.SERVER_ERROR : ConnectionErrorType.NETWORK_ERROR;
              const error = createConnectionError(
                errorType,
                `WebSocket closed with code ${event.code}: ${event.reason || 'Unknown reason'}`,
                event.code
              );

              updateConnectionState(ConnectionState.DISCONNECTED);
              onDisconnectRef.current?.();

              // Attempt reconnection if within limits
              if (reconnectCount.current < reconnectAttempts && !isCircuitBreakerOpen()) {
                reconnectCount.current += 1;

                setConnectionStats((prev) => ({
                  ...prev,
                  totalReconnects: prev.totalReconnects + 1,
                }));

                const delay = calculateReconnectDelay();

                debugLog(`Scheduling reconnection ${reconnectCount.current}/${reconnectAttempts} in ${delay}ms`);

                reconnectTimeoutRef.current = setTimeout(() => {
                  connect(true).catch((reconnectError) => {
                    debugLog('Reconnection failed:', reconnectError);
                  });
                }, delay);
              } else {
                updateConnectionState(ConnectionState.FAILED);
                debugLog('Reconnection attempts exhausted or circuit breaker open');
              }

              if (!wasReconnecting) {
                reject(error);
              }
            }
          };

          ws.current.onerror = (event) => {
            debugLog('WebSocket error event:', event);

            const error = createConnectionError(ConnectionErrorType.NETWORK_ERROR, 'WebSocket connection error');

            onErrorRef.current?.(error);
          };
        } catch (error) {
          isConnecting.current = false;

          if (connectionTimeoutRef.current) {
            clearTimeout(connectionTimeoutRef.current);
            connectionTimeoutRef.current = null;
          }

          const connectionError = createConnectionError(
            ConnectionErrorType.UNKNOWN_ERROR,
            `Connection setup error: ${error instanceof Error ? error.message : 'Unknown error'}`
          );

          debugLog('Connection setup error:', error);
          onErrorRef.current?.(connectionError);
          reject(connectionError);
        }
      });
    },
    [
      url,
      reconnectAttempts,
      connectionTimeout,
      initialReconnectDelay,
      isRateLimited,
      isCircuitBreakerOpen,
      updateConnectionState,
      createConnectionError,
      calculateReconnectDelay,
      startHeartbeat,
      stopHeartbeat,
      handlePong,
      debugLog,
      connectionState,
      circuitBreakerThreshold,
      circuitBreakerResetTime,
    ]
  );

  /**
   * Gracefully disconnects the WebSocket connection
   */
  const disconnect = useCallback(() => {
    debugLog('Manual disconnect requested');

    updateConnectionState(ConnectionState.DISCONNECTING);

    // Clear all timers and intervals
    if (reconnectTimeoutRef.current) {
      clearTimeout(reconnectTimeoutRef.current);
      reconnectTimeoutRef.current = null;
    }

    if (connectionTimeoutRef.current) {
      clearTimeout(connectionTimeoutRef.current);
      connectionTimeoutRef.current = null;
    }

    stopHeartbeat();

    isConnecting.current = false;
    reconnectCount.current = 0;
    consecutiveFailures.current = 0;
    currentReconnectDelay.current = initialReconnectDelay;
    circuitBreakerOpenUntil.current = 0;

    if (ws.current) {
      ws.current.close(1000, 'Manual disconnect');
      ws.current = null;
    }

    setIsConnected(false);
    setConnectionId(null);
    updateConnectionState(ConnectionState.DISCONNECTED);
  }, [updateConnectionState, stopHeartbeat, initialReconnectDelay, debugLog]);

  /**
   * Forces a reconnection attempt (bypasses some rate limiting)
   */
  const forceReconnect = useCallback(() => {
    debugLog('Force reconnect requested');

    // Reset some limits for manual reconnection
    reconnectCount.current = 0;
    consecutiveFailures.current = Math.max(0, consecutiveFailures.current - 1);

    // Close current connection and reconnect
    if (ws.current) {
      ws.current.close(1000, 'Force reconnect');
    }

    // Connect after a short delay
    setTimeout(() => {
      connect(true).catch((error) => {
        debugLog('Force reconnect failed:', error);
      });
    }, 100);
  }, [connect, debugLog]);

  /**
   * Resets connection statistics and state
   */
  const resetStats = useCallback(() => {
    setConnectionStats({
      totalConnections: 0,
      totalDisconnections: 0,
      totalReconnects: 0,
      totalErrors: 0,
    });

    setLastError(null);
    reconnectCount.current = 0;
    consecutiveFailures.current = 0;
    currentReconnectDelay.current = initialReconnectDelay;
    circuitBreakerOpenUntil.current = 0;
    connectionAttempts.current = [];

    debugLog('Connection stats and state reset');
  }, [initialReconnectDelay, debugLog]);

  /**
   * Sends a message through the WebSocket connection
   */
  const sendMessage = useCallback(
    (message: CommandRequest) => {
      if (ws.current?.readyState === WebSocket.OPEN) {
        try {
          const messageStr = JSON.stringify(message);
          ws.current.send(messageStr);
          debugLog('Message sent:', message.type, message.requestId);
          return true;
        } catch (error) {
          debugLog('Error sending message:', error);
          const connectionError = createConnectionError(
            ConnectionErrorType.UNKNOWN_ERROR,
            `Message send error: ${error instanceof Error ? error.message : 'Unknown error'}`
          );
          onErrorRef.current?.(connectionError);
          return false;
        }
      } else {
        debugLog('Cannot send message - WebSocket not connected, state:', ws.current?.readyState);
        return false;
      }
    },
    [debugLog, createConnectionError]
  );

  /**
   * Sends a command with automatic retry on failure
   */
  const sendCommand = useCallback(
    (target: 'docker' | 'kubernetes', command: string, params?: Record<string, string>): string => {
      const requestId = `cmd_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

      const request: CommandRequest = {
        type: 'command',
        target,
        command,
        params,
        requestId,
      };

      const success = sendMessage(request);
      if (!success && connectionState === ConnectionState.DISCONNECTED) {
        // Attempt to reconnect if disconnected
        debugLog('Command failed due to disconnection, attempting reconnect');
        connect().catch((error) => {
          debugLog('Reconnect for command failed:', error);
        });
      }

      return requestId;
    },
    [sendMessage, connectionState, connect, debugLog]
  );

  /**
   * Subscribes to a command stream with automatic retry
   */
  const subscribe = useCallback(
    (target: 'docker' | 'kubernetes', command: string, params?: Record<string, string>): string => {
      // Generate subscription ID that matches backend response format: "subscription:target:command"
      const requestId = `subscription:${target}:${command}`;

      const request: CommandRequest = {
        type: 'subscribe',
        target,
        command,
        params,
        requestId,
      };

      const success = sendMessage(request);
      if (!success && connectionState === ConnectionState.DISCONNECTED) {
        // Attempt to reconnect if disconnected
        debugLog('Subscription failed due to disconnection, attempting reconnect');
        connect().catch((error) => {
          debugLog('Reconnect for subscription failed:', error);
        });
      }

      return requestId;
    },
    [sendMessage, connectionState, connect, debugLog]
  );

  /**
   * Unsubscribes from a command stream
   */
  const unsubscribe = useCallback(
    (target: 'docker' | 'kubernetes', command: string, params?: Record<string, string>): string => {
      // Generate unsubscribe ID that matches subscription format for consistency
      const requestId = `unsubscribe:${target}:${command}`;

      const request: CommandRequest = {
        type: 'unsubscribe',
        target,
        command,
        params,
        requestId,
      };

      sendMessage(request);
      return requestId;
    },
    [sendMessage]
  );

  /**
   * Handle network connectivity changes (online/offline)
   */
  useEffect(() => {
    const handleOnline = () => {
      debugLog('Network came back online');
      if (connectionState === ConnectionState.DISCONNECTED || connectionState === ConnectionState.FAILED) {
        // Reset some failure counters when network comes back
        consecutiveFailures.current = Math.max(0, consecutiveFailures.current - 1);

        setTimeout(() => {
          connect(true).catch((error) => {
            debugLog('Auto-reconnect on network recovery failed:', error);
          });
        }, 1000);
      }
    };

    const handleOffline = () => {
      debugLog('Network went offline');
      if (ws.current) {
        ws.current.close(4002, 'Network offline');
      }
    };

    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);

    return () => {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
    };
  }, [connect, connectionState, debugLog]);

  /**
   * Main connection effect - runs once on mount, cleans up on unmount
   */
  useEffect(() => {
    // Connect on mount
    connect(false).catch((error) => {
      debugLog('Initial connection failed:', error);
    });

    // Cleanup on unmount
    return () => {
      debugLog('Cleaning up WebSocket hook');

      // Clear all timeouts and intervals
      if (reconnectTimeoutRef.current) {
        clearTimeout(reconnectTimeoutRef.current);
        reconnectTimeoutRef.current = null;
      }

      if (connectionTimeoutRef.current) {
        clearTimeout(connectionTimeoutRef.current);
        connectionTimeoutRef.current = null;
      }

      stopHeartbeat();

      isConnecting.current = false;

      if (ws.current) {
        ws.current.close(1000, 'Component unmount');
        ws.current = null;
      }

      setIsConnected(false);
      setConnectionId(null);
      updateConnectionState(ConnectionState.DISCONNECTED);
    };
  }, [url]); // Only depend on URL to prevent unnecessary reconnections

  return {
    // Connection state
    isConnected,
    connectionState,
    connectionId,
    lastError,
    connectionStats,

    // Connection control
    connect: () => connect(),
    disconnect,
    forceReconnect,
    resetStats,

    // Message sending
    sendMessage,
    sendCommand,
    subscribe,
    unsubscribe,

    // Health monitoring
    isHealthy:
      connectionState === ConnectionState.CONNECTED && Date.now() - lastHeartbeatTime.current < heartbeatInterval * 2,
    lastHeartbeat: lastHeartbeatTime.current,

    // Rate limiting status
    isRateLimited: isRateLimited(),
    isCircuitBreakerOpen: isCircuitBreakerOpen(),

    // Connection attempts info
    currentReconnectAttempt: reconnectCount.current,
    maxReconnectAttempts: reconnectAttempts,
    nextReconnectDelay: reconnectCount.current < reconnectAttempts ? calculateReconnectDelay() : null,
  };
}

/**
 * Hook return type for better TypeScript support
 */
export type UseWebSocketReturn = ReturnType<typeof useWebSocket>;
