import asyncio
import json
import logging
import random
import re
from typing import Dict, Set, Optional, Any, List
from datetime import datetime, timedelta
from collections import deque
from fastapi import WebSocket, WebSocketDisconnect
from ..models.schemas import CommandRequest, CommandResponse
from ..security.command_executor import CommandExecutor, SecurityError

__all__ = ['ConnectionManager', '_log_websocket_disconnect']

logger = logging.getLogger(__name__)


def _log_websocket_disconnect(connection_id: str, disconnect_exception: WebSocketDisconnect, context: str = ""):
    """
    Log WebSocket disconnections at appropriate levels based on disconnect codes.

    Args:
        connection_id: The client connection ID
        disconnect_exception: The WebSocketDisconnect exception
        context: Additional context about when the disconnect occurred
    """
    code = disconnect_exception.code
    reason = disconnect_exception.reason or ""
    context_msg = f" {context}" if context else ""

    # Normal disconnects - log as DEBUG
    if code == 1000:  # Normal closure
        logger.debug(f"Connection {connection_id} closed normally{context_msg} (code {code}): {reason or 'Normal closure'}")
    elif code == 1001:  # Going away (browser/tab closed)
        logger.debug(f"Connection {connection_id} closed (client going away){context_msg} (code {code}): {reason or 'Client going away'}")

    # Service restarts - log as INFO (expected but noteworthy)
    elif code == 1012:  # Service restart
        logger.info(f"Connection {connection_id} closed (service restart){context_msg} (code {code}): {reason or 'Service restart'}")

    # Other expected codes - log as INFO
    elif code in [1002, 1003]:  # Protocol error, unsupported data
        logger.info(f"Connection {connection_id} closed (protocol issue){context_msg} (code {code}): {reason or 'Protocol issue'}")
    elif code in [1005, 1006]:  # No status code, abnormal closure
        logger.info(f"Connection {connection_id} closed (network issue){context_msg} (code {code}): {reason or 'Network issue'}")

    # Unexpected or abnormal disconnects - log as WARNING
    else:
        logger.warning(f"Connection {connection_id} closed abnormally{context_msg} (code {code}): {reason or 'Unknown reason'}")


class ConnectionManager:
    def __init__(self):
        self.active_connections: Dict[str, WebSocket] = {}
        self.connection_metadata: Dict[str, Dict] = {}
        self.subscriptions: Dict[str, Set[str]] = {}  # subscription_type -> set of connection_ids
        self.command_executor = CommandExecutor()
        self.rate_limits: Dict[str, list] = {}  # connection_id -> list of request timestamps
        self.subscription_tasks: Dict[str, asyncio.Task] = {}

        # Message queuing system for offline/disconnected clients
        self.pending_messages: Dict[str, deque] = {}  # connection_id -> deque of messages
        self.max_pending_messages = 50  # Maximum messages to queue per connection
        self.message_retry_attempts: Dict[str, int] = {}  # message_id -> retry count
        self.max_retry_attempts = 3

        # Connection stability tracking
        self.connection_health: Dict[str, Dict] = {}  # connection_id -> health metrics
        self.failed_connections: Set[str] = set()  # Connections that failed recently

        # Retry logic configuration
        self.retry_delays = [1, 2, 4, 8, 16, 30]  # Exponential backoff in seconds
        self.subscription_retry_tasks: Dict[str, Dict] = {}  # subscription_key -> retry info

        # Configurable polling intervals (in seconds) optimized for local monitoring
        # Reduced from aggressive 3-5 second intervals to more reasonable 10-30 second intervals
        self.polling_intervals = {
            'docker:ps': 12,                # Container status changes (was 5s)
            'docker:stats': 15,             # Resource usage stats (was 3s)
            'docker:health': 30,            # Docker engine health check
            'kubernetes:pods': 12,          # Pod status changes (was 5s)
            'kubernetes:nodes': 30,         # Node status - rarely changes (was 10s)
            'kubernetes:health': 45,        # Kubernetes cluster health check
            'system:metrics': 10,           # System metrics (CPU, memory, disk)
            'system:info': 60,              # System info - rarely changes
            'system:health': 30,            # Overall system health
            'services:availability': 20,    # Service availability check
            'connections:stats': 15         # Connection statistics
        }

        # Minimum interval to prevent accidental over-polling
        self.min_polling_interval = 8

        # Maximum jitter percentage to prevent thundering herd
        self.jitter_percentage = 0.1  # 10% jitter

    async def connect(self, websocket: WebSocket, connection_id: str):
        """Accept a new WebSocket connection with stability tracking"""
        await websocket.accept()
        self.active_connections[connection_id] = websocket
        self.connection_metadata[connection_id] = {
            'connected_at': datetime.utcnow(),
            'last_activity': datetime.utcnow(),
            'request_count': 0,
            'reconnection_count': 0,
            'last_disconnect_reason': None
        }
        self.rate_limits[connection_id] = []

        # Initialize message queue and health tracking
        self.pending_messages[connection_id] = deque(maxlen=self.max_pending_messages)
        self.connection_health[connection_id] = {
            'successful_sends': 0,
            'failed_sends': 0,
            'last_successful_send': datetime.utcnow(),
            'connection_stable': True
        }

        # Remove from failed connections if reconnecting
        self.failed_connections.discard(connection_id)

        logger.info(f"Client {connection_id} connected")
        logger.debug(f"Current polling intervals: {self.polling_intervals}")

        # Send any queued messages from previous connections
        await self._send_queued_messages(connection_id)

    def disconnect(self, connection_id: str, disconnect_reason: str = None):
        """Clean up when a client disconnects with improved tracking"""
        # Store disconnect reason for reconnection tracking
        if connection_id in self.connection_metadata:
            self.connection_metadata[connection_id]['last_disconnect_reason'] = disconnect_reason

        # Mark connection as failed if it was unstable
        if (connection_id in self.connection_health and
            self.connection_health[connection_id]['failed_sends'] > self.connection_health[connection_id]['successful_sends']):
            self.failed_connections.add(connection_id)
            logger.warning(f"Connection {connection_id} marked as failed due to instability")

        # Clean up active connection tracking
        if connection_id in self.active_connections:
            del self.active_connections[connection_id]
        if connection_id in self.rate_limits:
            del self.rate_limits[connection_id]

        # Remove from all subscriptions but keep metadata for potential reconnection
        for subscription_type in list(self.subscriptions.keys()):
            if connection_id in self.subscriptions[subscription_type]:
                self.subscriptions[subscription_type].discard(connection_id)
                if not self.subscriptions[subscription_type]:
                    # Cancel subscription task if no more subscribers
                    if subscription_type in self.subscription_tasks:
                        self.subscription_tasks[subscription_type].cancel()
                        del self.subscription_tasks[subscription_type]

        # Keep pending messages and health info for potential reconnection (clean up after timeout)
        asyncio.create_task(self._cleanup_stale_connection_data(connection_id))

        logger.info(f"Client {connection_id} disconnected (reason: {disconnect_reason or 'unknown'})")

    async def handle_message(self, websocket: WebSocket, connection_id: str, message: str):
        """Process incoming WebSocket message"""
        try:
            # Rate limiting check
            if not await self._check_rate_limit(connection_id):
                await self._send_error(websocket, connection_id, "Rate limit exceeded", "rate_limit")
                return

            # Update activity timestamp
            self.connection_metadata[connection_id]['last_activity'] = datetime.utcnow()
            self.connection_metadata[connection_id]['request_count'] += 1

            # Parse message
            data = json.loads(message)
            request = CommandRequest(**data)

            logger.info(f"[{connection_id[:8]}] Received: type={request.type}, target={request.target}, command={request.command}, requestId={request.requestId}")

            # Handle different message types
            if request.type == "command":
                await self._handle_command(websocket, connection_id, request)
            elif request.type == "subscribe":
                await self._handle_subscription(websocket, connection_id, request)
            elif request.type == "unsubscribe":
                await self._handle_unsubscription(websocket, connection_id, request)
            else:
                await self._send_error(websocket, connection_id, "Invalid message type", request.requestId)

        except WebSocketDisconnect as e:
            # Re-raise WebSocketDisconnect immediately - don't try to send error messages
            _log_websocket_disconnect(connection_id, e, "during message handling")
            raise
        except json.JSONDecodeError as e:
            logger.warning(f"Invalid JSON from {connection_id}: {str(e)}")
            await self._send_error(websocket, connection_id, "Invalid JSON format")
        except Exception as e:
            # Only log as error for non-disconnect exceptions
            logger.error(f"Error handling message from {connection_id}: {str(e)}")
            # Don't try to send error messages if connection might be closed
            try:
                await self._send_error(websocket, connection_id, "Internal server error")
            except (WebSocketDisconnect, ConnectionResetError):
                # Connection closed while sending error - expected behavior
                pass

    async def _handle_command(self, websocket: WebSocket, connection_id: str, request: CommandRequest):
        """Execute a single command and return result"""
        try:
            # Check if this is a streaming command
            if request.command == "logs:stream" and request.target == "docker":
                await self._handle_log_stream(websocket, connection_id, request)
                return

            logger.debug(f"[{connection_id[:8]}] Executing: {request.target}.{request.command} with params={request.params}")

            result = await self.command_executor.execute_command(
                request.target,
                request.command,
                request.params
            )

            logger.info(f"[{connection_id[:8]}] Result: success={result['success']}, data_keys={list(result.get('data', {}).keys()) if result.get('data') else None}")

            response = CommandResponse(
                requestId=request.requestId,
                success=result['success'],
                data=result.get('data'),
                error=result.get('error')
            )

            await websocket.send_text(response.json())
            logger.debug(f"[{connection_id[:8]}] Sent response for requestId={request.requestId}")

        except SecurityError as e:
            logger.warning(f"[{connection_id[:8]}] Security error: {str(e)}")
            await self._send_error(websocket, connection_id, str(e), request.requestId)
        except Exception as e:
            logger.error(f"[{connection_id[:8]}] Command execution error: {str(e)}")
            await self._send_error(websocket, connection_id, "Command execution failed", request.requestId)

    async def _handle_log_stream(self, websocket: WebSocket, connection_id: str, request: CommandRequest):
        """Handle real-time log streaming for a Docker container"""
        try:
            container_name = request.params.get('container')
            if not container_name:
                await self._send_error(websocket, connection_id, "Container name required", request.requestId)
                return

            # Validate container name (basic security check)
            if not re.match(r'^[a-zA-Z0-9][a-zA-Z0-9_.-]*$', container_name):
                await self._send_error(websocket, connection_id, "Invalid container name", request.requestId)
                return

            logger.info(f"Starting log stream for container {container_name} (connection: {connection_id})")

            # Send initial confirmation
            response = CommandResponse(
                requestId=request.requestId,
                success=True,
                data={"streaming": True, "container": container_name}
            )
            await websocket.send_text(response.json())

            # Start streaming logs
            lines = request.params.get('lines', 100)
            try:
                lines = int(lines)
            except (TypeError, ValueError):
                lines = 100

            # Build command
            cmd = ['docker', 'logs', '--follow', '--tail', str(lines), '--timestamps', container_name]

            # Start subprocess - merge stderr into stdout
            process = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.STDOUT  # Merge stderr into stdout
            )

            # Store process for cleanup
            if not hasattr(self, '_streaming_processes'):
                self._streaming_processes = {}
            stream_key = f"{connection_id}:{container_name}"
            self._streaming_processes[stream_key] = process

            try:
                # Stream logs line by line
                while True:
                    line = await process.stdout.readline()
                    if not line:
                        # Process ended
                        break

                    decoded_line = line.decode('utf-8', errors='replace').rstrip('\n\r')
                    if decoded_line:
                        # Send log line to client
                        log_response = CommandResponse(
                            requestId=f"{request.requestId}:log",
                            success=True,
                            data={"log_line": decoded_line, "container": container_name}
                        )
                        await websocket.send_text(log_response.json())

                # Stream ended normally
                end_response = CommandResponse(
                    requestId=f"{request.requestId}:end",
                    success=True,
                    data={"streaming": False, "container": container_name, "reason": "completed"}
                )
                await websocket.send_text(end_response.json())

            except (WebSocketDisconnect, ConnectionResetError):
                logger.info(f"Log stream cancelled for {container_name} (connection: {connection_id})")
                process.terminate()
                try:
                    await asyncio.wait_for(process.wait(), timeout=5.0)
                except asyncio.TimeoutError:
                    process.kill()
            finally:
                # Cleanup
                if stream_key in self._streaming_processes:
                    del self._streaming_processes[stream_key]
                if process.returncode is None:
                    process.terminate()
                    try:
                        await asyncio.wait_for(process.wait(), timeout=5.0)
                    except asyncio.TimeoutError:
                        process.kill()

        except Exception as e:
            logger.error(f"Error in log stream for {container_name}: {str(e)}")
            await self._send_error(websocket, connection_id, f"Log streaming failed: {str(e)}", request.requestId)

    async def _handle_subscription(self, websocket: WebSocket, connection_id: str, request: CommandRequest):
        """Handle subscription to periodic updates"""
        subscription_key = f"{request.target}:{request.command}"

        # Add connection to subscription
        if subscription_key not in self.subscriptions:
            self.subscriptions[subscription_key] = set()

        self.subscriptions[subscription_key].add(connection_id)

        # Start periodic task if not already running
        if subscription_key not in self.subscription_tasks:
            task = asyncio.create_task(
                self._periodic_update_task(subscription_key, request.target, request.command, request.params)
            )
            self.subscription_tasks[subscription_key] = task

        # Send confirmation
        response = CommandResponse(
            requestId=request.requestId,
            success=True,
            data={"subscribed": subscription_key}
        )
        await websocket.send_text(response.json())

    async def _handle_unsubscription(self, websocket: WebSocket, connection_id: str, request: CommandRequest):
        """Handle unsubscription from periodic updates"""
        subscription_key = f"{request.target}:{request.command}"

        if subscription_key in self.subscriptions:
            self.subscriptions[subscription_key].discard(connection_id)

            # Cancel task if no more subscribers
            if not self.subscriptions[subscription_key] and subscription_key in self.subscription_tasks:
                self.subscription_tasks[subscription_key].cancel()
                del self.subscription_tasks[subscription_key]

        response = CommandResponse(
            requestId=request.requestId,
            success=True,
            data={"unsubscribed": subscription_key}
        )
        await websocket.send_text(response.json())

    async def _periodic_update_task(self, subscription_key: str, target: str, command: str, params: Optional[Dict[str, str]]):
        """
        Background task for sending periodic updates with optimized intervals.

        Intervals have been optimized for local monitoring use to reduce server load:
        - Docker containers: 12s (status changes aren't frequent for local dev)
        - Docker stats: 15s (resource monitoring doesn't need high frequency)
        - Kubernetes pods: 12s (pod status changes for local testing)
        - Kubernetes nodes: 30s (node status rarely changes)

        Args:
            subscription_key: The subscription identifier (e.g., 'docker:ps')
            target: The target system (docker/kubernetes)
            command: The command to execute
            params: Optional command parameters
        """
        # Get configured interval with fallback
        base_interval = self.polling_intervals.get(subscription_key, 15)

        # Enforce minimum interval to prevent over-polling
        interval = max(base_interval, self.min_polling_interval)

        # Add jitter to prevent thundering herd when multiple subscriptions start simultaneously
        jitter = interval * self.jitter_percentage * random.random()
        actual_interval = interval + jitter

        logger.info(f"Starting subscription task '{subscription_key}' with {actual_interval:.1f}s interval (base: {interval}s)")

        try:
            retry_count = 0
            while subscription_key in self.subscriptions and self.subscriptions[subscription_key]:
                try:
                    # Execute command
                    result = await self.command_executor.execute_command(target, command, params)

                    # Reset retry count on successful execution
                    retry_count = 0

                    # Send to all subscribers
                    if subscription_key in self.subscriptions:
                        dead_connections = set()

                        for connection_id in self.subscriptions[subscription_key].copy():
                            if connection_id in self.active_connections:
                                try:
                                    websocket = self.active_connections[connection_id]
                                    response = CommandResponse(
                                        requestId=f"subscription:{subscription_key}",
                                        success=result['success'],
                                        data=result.get('data'),
                                        error=result.get('error')
                                    )
                                    await websocket.send_text(response.json())

                                    # Update successful send metrics
                                    if connection_id in self.connection_health:
                                        self.connection_health[connection_id]['successful_sends'] += 1
                                        self.connection_health[connection_id]['last_successful_send'] = datetime.utcnow()

                                except WebSocketDisconnect as e:
                                    # Handle disconnect during subscription update
                                    _log_websocket_disconnect(connection_id, e, "during subscription update")
                                    await self._handle_failed_send(connection_id, response, "websocket_disconnect")
                                    dead_connections.add(connection_id)
                                except ConnectionResetError:
                                    logger.debug(f"Connection {connection_id} reset during subscription update")
                                    await self._handle_failed_send(connection_id, response, "connection_reset")
                                    dead_connections.add(connection_id)
                                except Exception as e:
                                    # Queue message for retry if connection seems recoverable
                                    await self._handle_failed_send(connection_id, response, str(e))
                                    # Only log as debug for connection-related issues, warning for others
                                    if any(keyword in str(e).lower() for keyword in ['connection', 'websocket', 'disconnect', 'closed']):
                                        logger.debug(f"Connection issue while sending subscription update to {connection_id}: {str(e)}")
                                    else:
                                        logger.warning(f"Failed to send subscription update to {connection_id}: {str(e)}")
                                    dead_connections.add(connection_id)
                            else:
                                dead_connections.add(connection_id)

                        # Remove dead connections
                        for dead_conn in dead_connections:
                            self.subscriptions[subscription_key].discard(dead_conn)

                except Exception as command_error:
                    # Handle command execution errors with exponential backoff retry
                    retry_count += 1
                    if retry_count <= len(self.retry_delays):
                        retry_delay = self.retry_delays[min(retry_count - 1, len(self.retry_delays) - 1)]
                        logger.warning(f"Command execution failed for {subscription_key} (attempt {retry_count}): {str(command_error)}")
                        logger.info(f"Retrying {subscription_key} in {retry_delay} seconds...")
                        await asyncio.sleep(retry_delay)
                        continue
                    else:
                        logger.error(f"Command execution failed for {subscription_key} after {retry_count} attempts: {str(command_error)}")
                        # Continue with default sleep interval
                        retry_count = 0  # Reset for next cycle

                await asyncio.sleep(actual_interval)

        except asyncio.CancelledError:
            logger.info(f"Subscription task cancelled: {subscription_key}")
        except Exception as e:
            logger.error(f"Error in subscription task {subscription_key}: {str(e)}")

    def update_polling_interval(self, subscription_key: str, interval: int) -> bool:
        """
        Update the polling interval for a specific subscription type.

        Args:
            subscription_key: The subscription identifier (e.g., 'docker:ps')
            interval: New interval in seconds (must be >= min_polling_interval)

        Returns:
            bool: True if interval was updated successfully

        Raises:
            ValueError: If interval is below minimum threshold
        """
        if interval < self.min_polling_interval:
            raise ValueError(f"Interval {interval}s is below minimum {self.min_polling_interval}s")

        old_interval = self.polling_intervals.get(subscription_key, 'unknown')
        self.polling_intervals[subscription_key] = interval

        logger.info(f"Updated polling interval for '{subscription_key}': {old_interval}s -> {interval}s")

        # Note: Active subscription tasks will continue with their current interval
        # until they are restarted (when all subscribers disconnect and reconnect)

        return True

    def get_polling_intervals(self) -> Dict[str, int]:
        """
        Get current polling intervals for all subscription types.

        Returns:
            Dict mapping subscription keys to their intervals in seconds
        """
        return self.polling_intervals.copy()

    async def _check_rate_limit(self, connection_id: str) -> bool:
        """Check if connection is within rate limits"""
        now = datetime.utcnow()
        window_start = now - timedelta(seconds=60)  # 1-minute window

        # Clean old timestamps
        self.rate_limits[connection_id] = [
            ts for ts in self.rate_limits[connection_id]
            if ts > window_start
        ]

        # Check limit (60 requests per minute = 1 per second average)
        if len(self.rate_limits[connection_id]) >= 60:
            return False

        # Add current request timestamp
        self.rate_limits[connection_id].append(now)
        return True

    async def _send_error(self, websocket: WebSocket, connection_id: str, error_message: str, request_id: str = None):
        """Send error response to client if connection is still active"""
        # Check if connection is still active before attempting to send
        if connection_id not in self.active_connections:
            logger.debug(f"Not sending error to disconnected client {connection_id}: {error_message}")
            return

        response = CommandResponse(
            requestId=request_id or "unknown",
            success=False,
            error=error_message
        )

        try:
            await websocket.send_text(response.json())
            # Update successful send metrics
            if connection_id in self.connection_health:
                self.connection_health[connection_id]['successful_sends'] += 1
                self.connection_health[connection_id]['last_successful_send'] = datetime.utcnow()

        except WebSocketDisconnect as e:
            # Connection closed during send - this is expected, handle gracefully
            _log_websocket_disconnect(connection_id, e, "while sending error message")
            await self._handle_failed_send(connection_id, response, "websocket_disconnect")
            # Clean up the connection since it's closed
            self.disconnect(connection_id, f"websocket_disconnect_{e.code}")
        except ConnectionResetError:
            # Connection was forcibly closed by client
            logger.debug(f"Connection {connection_id} reset while sending error message")
            await self._handle_failed_send(connection_id, response, "connection_reset")
            self.disconnect(connection_id, "connection_reset")
        except Exception as e:
            # Handle other exceptions and potentially queue message
            await self._handle_failed_send(connection_id, response, str(e))
            logger.debug(f"Unexpected error sending message to {connection_id}: {str(e)}")
            # Don't cleanup connection here - might be a temporary issue

    async def broadcast_system_alert(self, alert_message: str):
        """Broadcast system alert to all connected clients"""
        if not self.active_connections:
            return

        alert = CommandResponse(
            requestId="system_alert",
            success=True,
            data={"alert": alert_message, "type": "system"}
        )

        dead_connections = []

        for connection_id, websocket in self.active_connections.items():
            try:
                await websocket.send_text(alert.json())
                # Update successful send metrics
                if connection_id in self.connection_health:
                    self.connection_health[connection_id]['successful_sends'] += 1
                    self.connection_health[connection_id]['last_successful_send'] = datetime.utcnow()
            except WebSocketDisconnect as e:
                # Handle disconnect during alert broadcast
                _log_websocket_disconnect(connection_id, e, "during alert broadcast")
                await self._handle_failed_send(connection_id, alert, "websocket_disconnect")
                dead_connections.append(connection_id)
            except ConnectionResetError:
                logger.debug(f"Connection {connection_id} reset during alert broadcast")
                await self._handle_failed_send(connection_id, alert, "connection_reset")
                dead_connections.append(connection_id)
            except Exception as e:
                await self._handle_failed_send(connection_id, alert, str(e))
                # Only log as debug for connection-related issues, warning for others
                if any(keyword in str(e).lower() for keyword in ['connection', 'websocket', 'disconnect', 'closed']):
                    logger.debug(f"Connection issue while sending alert to {connection_id}: {str(e)}")
                else:
                    logger.warning(f"Failed to send alert to {connection_id}: {str(e)}")
                dead_connections.append(connection_id)

        # Clean up dead connections with proper disconnect tracking
        for connection_id in dead_connections:
            self.disconnect(connection_id, "alert_broadcast_failure")

    async def broadcast_real_time_update(self, update_type: str, data: Dict[str, Any]):
        """Broadcast real-time updates to all connected clients when external changes occur"""
        if not self.active_connections:
            return

        update = CommandResponse(
            requestId=f"push:{update_type}",
            success=True,
            data={
                "type": "real_time_update",
                "update_type": update_type,
                "changes": data,
                "timestamp": datetime.utcnow().isoformat()
            }
        )

        dead_connections = []

        for connection_id, websocket in self.active_connections.items():
            try:
                await websocket.send_text(update.json())
                logger.debug(f"Pushed {update_type} update to client {connection_id}")
                # Update successful send metrics
                if connection_id in self.connection_health:
                    self.connection_health[connection_id]['successful_sends'] += 1
                    self.connection_health[connection_id]['last_successful_send'] = datetime.utcnow()
            except WebSocketDisconnect as e:
                _log_websocket_disconnect(connection_id, e, "during real-time update")
                await self._handle_failed_send(connection_id, update, "websocket_disconnect")
                dead_connections.append(connection_id)
            except ConnectionResetError:
                logger.debug(f"Connection {connection_id} reset during real-time update")
                await self._handle_failed_send(connection_id, update, "connection_reset")
                dead_connections.append(connection_id)
            except Exception as e:
                await self._handle_failed_send(connection_id, update, str(e))
                if any(keyword in str(e).lower() for keyword in ['connection', 'websocket', 'disconnect', 'closed']):
                    logger.debug(f"Connection issue while sending update to {connection_id}: {str(e)}")
                else:
                    logger.warning(f"Failed to send real-time update to {connection_id}: {str(e)}")
                dead_connections.append(connection_id)

        # Clean up dead connections with proper disconnect tracking
        for connection_id in dead_connections:
            self.disconnect(connection_id, "real_time_update_failure")

        logger.info(f"Broadcasted {update_type} update to {len(self.active_connections) - len(dead_connections)} clients")

    async def start_change_detection(self):
        """Start background task to detect external changes and push updates"""
        if not hasattr(self, 'change_detection_task') or self.change_detection_task is None:
            self.change_detection_task = asyncio.create_task(self._change_detection_loop())
            self.last_known_state = {}
            logger.info("Started external change detection for real-time push notifications")

    async def stop_change_detection(self):
        """Stop the change detection background task"""
        if hasattr(self, 'change_detection_task') and self.change_detection_task:
            self.change_detection_task.cancel()
            try:
                await self.change_detection_task
            except asyncio.CancelledError:
                pass
            self.change_detection_task = None
            logger.info("Stopped external change detection")

    async def _change_detection_loop(self):
        """Background loop to detect external changes and push updates"""
        try:
            while True:
                # Only detect changes if we have active connections
                if self.active_connections:
                    await self._detect_and_push_changes()

                # Check for changes every 8 seconds (faster than regular polling to catch external changes)
                await asyncio.sleep(8)

        except asyncio.CancelledError:
            logger.info("Change detection loop cancelled")
        except Exception as e:
            logger.error(f"Error in change detection loop: {str(e)}")

    async def _detect_and_push_changes(self):
        """Detect changes in system state and push updates to clients"""
        try:
            # Get current state
            current_state = {}

            # Check Docker container changes
            try:
                docker_result = await self.command_executor.execute_command('docker', 'ps')
                if docker_result['success']:
                    current_state['docker_containers'] = docker_result['data']['containers']
            except Exception as e:
                logger.debug(f"Could not check Docker state: {str(e)}")

            # Check Kubernetes pod changes
            try:
                k8s_result = await self.command_executor.execute_command('kubernetes', 'pods')
                if k8s_result['success']:
                    current_state['kubernetes_pods'] = k8s_result['data']['pods']
            except Exception as e:
                logger.debug(f"Could not check Kubernetes state: {str(e)}")

            # Compare with last known state and push changes
            if hasattr(self, 'last_known_state'):
                changes_detected = False

                # Check Docker container changes
                if ('docker_containers' in current_state and
                    'docker_containers' in self.last_known_state and
                    current_state['docker_containers'] != self.last_known_state['docker_containers']):

                    await self.broadcast_real_time_update('docker_containers_changed', {
                        'containers': current_state['docker_containers']
                    })
                    changes_detected = True
                    logger.info("Detected external Docker container changes - pushed update to clients")

                # Check Kubernetes pod changes
                if ('kubernetes_pods' in current_state and
                    'kubernetes_pods' in self.last_known_state and
                    current_state['kubernetes_pods'] != self.last_known_state['kubernetes_pods']):

                    await self.broadcast_real_time_update('kubernetes_pods_changed', {
                        'pods': current_state['kubernetes_pods']
                    })
                    changes_detected = True
                    logger.info("Detected external Kubernetes pod changes - pushed update to clients")

            # Update last known state
            self.last_known_state = current_state

        except Exception as e:
            logger.error(f"Error detecting changes: {str(e)}")

    def get_connection_stats(self) -> Dict[str, Any]:
        """
        Get statistics about current connections and subscription polling intervals.

        Returns:
            Dict containing connection stats, subscription info, and polling intervals
        """
        now = datetime.utcnow()

        return {
            'total_connections': len(self.active_connections),
            'active_subscriptions': len(self.subscription_tasks),
            'polling_intervals': self.polling_intervals,
            'min_polling_interval': self.min_polling_interval,
            'total_requests': sum(
                meta['request_count']
                for meta in self.connection_metadata.values()
            ),
            'active_subscription_keys': list(self.subscription_tasks.keys()),
            'connections': [
                {
                    'id': conn_id,
                    'connected_duration': str(now - meta['connected_at']),
                    'last_activity': str(now - meta['last_activity']),
                    'request_count': meta['request_count']
                }
                for conn_id, meta in self.connection_metadata.items()
            ]
        }

    async def _send_queued_messages(self, connection_id: str):
        """Send any queued messages for a reconnected client"""
        if connection_id not in self.pending_messages or not self.pending_messages[connection_id]:
            return

        websocket = self.active_connections.get(connection_id)
        if not websocket:
            return

        queued_count = len(self.pending_messages[connection_id])
        logger.info(f"Sending {queued_count} queued messages to reconnected client {connection_id}")

        successful_sends = 0
        while self.pending_messages[connection_id]:
            try:
                message = self.pending_messages[connection_id].popleft()
                await websocket.send_text(message)
                successful_sends += 1
                await asyncio.sleep(0.01)  # Small delay between messages to prevent overwhelming
            except (WebSocketDisconnect, ConnectionResetError):
                # Client disconnected again, put message back
                self.pending_messages[connection_id].appendleft(message)
                logger.debug(f"Client {connection_id} disconnected while sending queued messages")
                break
            except Exception as e:
                logger.warning(f"Failed to send queued message to {connection_id}: {str(e)}")
                # Skip this message and continue with others
                continue

        if successful_sends > 0:
            logger.info(f"Successfully sent {successful_sends} queued messages to {connection_id}")

    async def _handle_failed_send(self, connection_id: str, response: CommandResponse, failure_reason: str):
        """Handle failed message send by queuing for retry"""
        # Update connection health metrics
        if connection_id in self.connection_health:
            self.connection_health[connection_id]['failed_sends'] += 1

            # Mark connection as unstable if failure rate is high
            total_attempts = (self.connection_health[connection_id]['successful_sends'] +
                            self.connection_health[connection_id]['failed_sends'])
            if total_attempts > 5:
                failure_rate = self.connection_health[connection_id]['failed_sends'] / total_attempts
                if failure_rate > 0.5:  # More than 50% failure rate
                    self.connection_health[connection_id]['connection_stable'] = False

        # Queue message for retry if connection might recover and it's important data
        if (self._should_queue_message(response, failure_reason) and
            connection_id not in self.failed_connections):

            message_json = response.json()

            # Don't queue if we already have too many pending messages
            if len(self.pending_messages.get(connection_id, [])) < self.max_pending_messages:
                if connection_id not in self.pending_messages:
                    self.pending_messages[connection_id] = deque(maxlen=self.max_pending_messages)

                self.pending_messages[connection_id].append(message_json)
                logger.debug(f"Queued message for {connection_id} due to {failure_reason}")
            else:
                logger.warning(f"Message queue full for {connection_id}, dropping message")

    def _should_queue_message(self, response: CommandResponse, failure_reason: str) -> bool:
        """Determine if a message should be queued for retry"""
        # Don't queue for permanent connection issues
        permanent_failures = ['websocket_disconnect', 'connection_reset']
        if failure_reason in permanent_failures:
            return False

        # Queue important system information and subscription updates
        if response.requestId:
            # Queue subscription updates and system info
            if (response.requestId.startswith('subscription:') or
                'system:info' in response.requestId or
                'docker:health' in response.requestId or
                'services:availability' in response.requestId):
                return True

        return False

    async def _cleanup_stale_connection_data(self, connection_id: str):
        """Clean up connection data after a timeout period"""
        # Wait 5 minutes for potential reconnection
        await asyncio.sleep(300)

        # If still not reconnected, clean up
        if connection_id not in self.active_connections:
            if connection_id in self.pending_messages:
                del self.pending_messages[connection_id]
            if connection_id in self.connection_health:
                del self.connection_health[connection_id]
            if connection_id in self.connection_metadata:
                del self.connection_metadata[connection_id]
            if connection_id in self.message_retry_attempts:
                del self.message_retry_attempts[connection_id]

            self.failed_connections.discard(connection_id)
            logger.debug(f"Cleaned up stale data for connection {connection_id}")