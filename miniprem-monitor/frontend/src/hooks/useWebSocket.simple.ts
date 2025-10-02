import { useEffect, useRef, useState, useCallback } from 'react';
import { CommandRequest, CommandResponse } from '../types/monitor';

interface UseWebSocketOptions {
  onMessage?: (data: CommandResponse) => void;
  onError?: (error: Event) => void;
  onConnect?: () => void;
  onDisconnect?: () => void;
  debug?: boolean;
}

/**
 * Simplified WebSocket hook for local monitoring
 * Removes complex reconnection logic, circuit breakers, and heartbeats
 * for more predictable behavior in a local environment
 */
export function useWebSocket(url: string, options: UseWebSocketOptions = {}) {
  const { onMessage, onError, onConnect, onDisconnect, debug = false } = options;

  // WebSocket reference and state
  const ws = useRef<WebSocket | null>(null);
  const reconnectTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const [isConnected, setIsConnected] = useState(false);
  const [connectionId, setConnectionId] = useState<string | null>(null);

  // Simple reconnection tracking
  const reconnectCount = useRef(0);
  const maxReconnects = 5;
  const reconnectDelay = 3500; // Fixed 3 second delay

  // Debug logging
  const debugLog = useCallback(
    (message: string, ...args: unknown[]) => {
      if (debug) {
        console.log(`[WebSocket] ${message}`, ...args);
      }
    },
    [debug]
  );

  /**
   * Connect to WebSocket server
   */
  const connect = useCallback(() => {
    // Don't reconnect if already connecting/connected
    if (ws.current?.readyState === WebSocket.CONNECTING || ws.current?.readyState === WebSocket.OPEN) {
      debugLog('Already connected or connecting');
      return;
    }

    // Stop if max reconnects reached
    if (reconnectCount.current >= maxReconnects) {
      debugLog('Max reconnection attempts reached');
      return;
    }

    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const wsUrl = url.startsWith('ws') ? url : `${protocol}//${window.location.host}${url}`;

    debugLog('Connecting to:', wsUrl, 'attempt:', reconnectCount.current + 1);

    try {
      ws.current = new WebSocket(wsUrl);

      ws.current.onopen = () => {
        debugLog('Connected successfully');
        setIsConnected(true);
        reconnectCount.current = 0; // Reset on successful connection
        onConnect?.();
      };

      ws.current.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data);

          // Handle connection message
          if (data.type === 'connection') {
            setConnectionId(data.connection_id);
            debugLog('Received connection ID:', data.connection_id);
            return;
          }

          // Handle command responses
          if (data.requestId) {
            onMessage?.(data as CommandResponse);
          }
        } catch (error) {
          debugLog('Error parsing message:', error);
        }
      };

      ws.current.onclose = (event) => {
        debugLog('Connection closed:', event.code, event.reason);
        setIsConnected(false);
        setConnectionId(null);
        onDisconnect?.();

        // Only auto-reconnect for unexpected closures (not manual disconnect code 1000)
        if (event.code !== 1000 && reconnectCount.current < maxReconnects) {
          reconnectCount.current++;
          debugLog(`Scheduling reconnect ${reconnectCount.current}/${maxReconnects} in ${reconnectDelay}ms`);

          reconnectTimeoutRef.current = setTimeout(() => {
            connect();
          }, reconnectDelay);
        }
      };

      ws.current.onerror = (event) => {
        debugLog('WebSocket error:', event);
        onError?.(event);
      };
    } catch (error) {
      debugLog('Connection setup error:', error);
      onError?.(error as Event);
    }
  }, [url, onMessage, onError, onConnect, onDisconnect, debugLog]);

  /**
   * Disconnect from WebSocket
   */
  const disconnect = useCallback(() => {
    debugLog('Manual disconnect');

    // Clear reconnection timeout
    if (reconnectTimeoutRef.current) {
      clearTimeout(reconnectTimeoutRef.current);
      reconnectTimeoutRef.current = null;
    }

    // Reset reconnect counter to prevent auto-reconnection
    reconnectCount.current = maxReconnects;

    if (ws.current) {
      ws.current.close(1000, 'Manual disconnect');
      ws.current = null;
    }

    setIsConnected(false);
    setConnectionId(null);
  }, [debugLog]);

  /**
   * Send a message through WebSocket
   */
  const sendMessage = useCallback(
    (message: CommandRequest): boolean => {
      if (ws.current?.readyState === WebSocket.OPEN) {
        try {
          ws.current.send(JSON.stringify(message));
          debugLog('Message sent:', message.type, message.requestId);
          return true;
        } catch (error) {
          debugLog('Error sending message:', error);
          return false;
        }
      } else {
        debugLog('Cannot send message - not connected');
        return false;
      }
    },
    [debugLog]
  );

  /**
   * Send a command
   */
  const sendCommand = useCallback(
    (
      target: 'docker' | 'kubernetes' | 'system' | 'services' | 'connections',
      command: string,
      params?: Record<string, string>
    ): string => {
      const requestId = `cmd_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

      const request: CommandRequest = {
        type: 'command',
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
   * Subscribe to a command stream
   */
  const subscribe = useCallback(
    (
      target: 'docker' | 'kubernetes' | 'system' | 'services' | 'connections',
      command: string,
      params?: Record<string, string>
    ): string => {
      const requestId = `subscription:${target}:${command}`;

      const request: CommandRequest = {
        type: 'subscribe',
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
   * Unsubscribe from a command stream
   */
  const unsubscribe = useCallback(
    (target: 'docker' | 'kubernetes' | 'system', command: string, params?: Record<string, string>): string => {
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

  // Connect on mount with stabilization delay for React StrictMode
  useEffect(() => {
    // Add a small delay to handle React StrictMode rapid mount/unmount cycles
    const connectTimeout = setTimeout(() => {
      connect();
    }, 100);

    return () => {
      // Clear connection timeout
      clearTimeout(connectTimeout);

      if (reconnectTimeoutRef.current) {
        clearTimeout(reconnectTimeoutRef.current);
      }

      if (ws.current) {
        ws.current.close(1000, 'Component unmount');
      }
    };
  }, [url]);

  return {
    isConnected,
    connectionId,
    sendMessage,
    sendCommand,
    subscribe,
    unsubscribe,
    disconnect,
  };
}
