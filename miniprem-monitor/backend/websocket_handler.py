"""
WebSocket handler for real-time monitoring updates.

This module provides WebSocket connection management and real-time broadcasting
of Docker and Kubernetes monitoring data to connected clients.
"""

import asyncio
import json
import logging
import uuid
from typing import Dict, Set, Any, Optional
from datetime import datetime, timezone
from dataclasses import dataclass, asdict

from fastapi import WebSocket, WebSocketDisconnect

from docker_monitor import DockerMonitor, DockerCommandError
from kubernetes_monitor import KubernetesMonitor, KubernetesCommandError
from auth.command_executor import CommandExecutor, PrivilegeError, CommandType
from auth.auth_manager import AuthManager
from auth.session_manager import SessionManager
from auth.websocket_auth_handler import WebSocketAuthHandler


logger = logging.getLogger(__name__)


@dataclass
class MonitoringData:
    """
    Data class for monitoring information sent over WebSocket.

    Attributes:
        timestamp: ISO timestamp when data was collected
        docker_containers: Docker container information
        docker_images: Docker image information
        docker_stats: Docker container statistics
        kubernetes_pods: Kubernetes pod information
        kubernetes_services: Kubernetes service information
        kubernetes_nodes: Kubernetes node information
        errors: Any errors encountered during data collection
    """
    timestamp: str
    docker_containers: Optional[Dict[str, Any]] = None
    docker_images: Optional[Dict[str, Any]] = None
    docker_stats: Optional[Dict[str, Any]] = None
    kubernetes_pods: Optional[Dict[str, Any]] = None
    kubernetes_services: Optional[Dict[str, Any]] = None
    kubernetes_nodes: Optional[Dict[str, Any]] = None
    errors: Optional[Dict[str, str]] = None


class WebSocketManager:
    """
    WebSocket connection manager for real-time monitoring updates.

    This class manages WebSocket connections, broadcasts monitoring data,
    and handles client connections/disconnections gracefully.
    """

    def __init__(self, update_interval: int = 5):
        """
        Initialize the WebSocket manager.

        Args:
            update_interval: Interval in seconds between monitoring updates
        """
        self.active_connections: Dict[str, WebSocket] = {}
        self.update_interval = update_interval

        # Initialize authentication system
        self.command_executor = CommandExecutor()
        self.auth_manager = AuthManager()
        self.session_manager = SessionManager()

        # Configure dependencies
        self.command_executor.set_auth_manager(self.auth_manager)
        self.command_executor.set_session_manager(self.session_manager)

        # Initialize monitors with authentication
        self.docker_monitor = DockerMonitor(self.command_executor)
        self.k8s_monitor = KubernetesMonitor(self.command_executor)

        # Initialize WebSocket authentication handler
        self.auth_handler = WebSocketAuthHandler(
            auth_manager=self.auth_manager,
            session_manager=self.session_manager,
            websocket_manager=self
        )

        self._running = False
        self._update_task: Optional[asyncio.Task] = None

    async def connect(self, websocket: WebSocket) -> str:
        """
        Accept a new WebSocket connection and add it to active connections.

        Args:
            websocket: WebSocket connection instance

        Returns:
            str: Unique client ID for the connection
        """
        client_id = str(uuid.uuid4())
        self.active_connections[client_id] = websocket

        logger.info(f"WebSocket client {client_id} connected. Total connections: {len(self.active_connections)}")

        # Send initial data to the newly connected client
        try:
            initial_data = await self._collect_monitoring_data()
            await self._send_to_client(client_id, initial_data)
        except Exception as e:
            logger.error(f"Failed to send initial data to client {client_id}: {str(e)}")

        return client_id

    def disconnect(self, client_id: str) -> None:
        """
        Remove a WebSocket connection from active connections.

        Args:
            client_id: Unique client ID to disconnect
        """
        if client_id in self.active_connections:
            del self.active_connections[client_id]

            # Cleanup authentication state
            self.auth_handler.cleanup_client(client_id)

            # Cleanup session state
            asyncio.create_task(self.session_manager.cleanup_client(client_id))

            logger.info(f"WebSocket client {client_id} disconnected. Total connections: {len(self.active_connections)}")

    async def _send_to_client(self, client_id: str, data: MonitoringData) -> bool:
        """
        Send monitoring data to a specific client.

        Args:
            client_id: Client ID to send data to
            data: Monitoring data to send

        Returns:
            bool: True if sent successfully, False if client disconnected
        """
        if client_id not in self.active_connections:
            return False

        websocket = self.active_connections[client_id]

        try:
            message = json.dumps(asdict(data), default=str)
            await websocket.send_text(message)
            return True

        except WebSocketDisconnect:
            logger.info(f"Client {client_id} disconnected during send")
            self.disconnect(client_id)
            return False
        except Exception as e:
            logger.error(f"Failed to send data to client {client_id}: {str(e)}")
            self.disconnect(client_id)
            return False

    async def broadcast(self, data: MonitoringData) -> None:
        """
        Broadcast monitoring data to all connected clients.

        Args:
            data: Monitoring data to broadcast
        """
        if not self.active_connections:
            return

        disconnected_clients = []

        for client_id in list(self.active_connections.keys()):
            success = await self._send_to_client(client_id, data)
            if not success:
                disconnected_clients.append(client_id)

        # Clean up disconnected clients
        for client_id in disconnected_clients:
            self.disconnect(client_id)

        if disconnected_clients:
            logger.info(f"Cleaned up {len(disconnected_clients)} disconnected clients")

    async def _collect_monitoring_data(self) -> MonitoringData:
        """
        Collect monitoring data from Docker and Kubernetes.

        Returns:
            MonitoringData: Collected monitoring information

        Note:
            This method continues execution even if individual monitors fail,
            collecting as much data as possible and reporting errors.
        """
        timestamp = datetime.now(timezone.utc).isoformat()
        errors = {}

        # Initialize data containers
        docker_containers = None
        docker_images = None
        docker_stats = None
        kubernetes_pods = None
        kubernetes_services = None
        kubernetes_nodes = None

        # Collect Docker data
        try:
            docker_containers = await self.docker_monitor.get_containers()
            docker_containers = {
                "success": True,
                "data": docker_containers,
                "count": len(docker_containers)
            }
        except PrivilegeError as e:
            errors["docker_containers"] = f"Authentication required: {str(e)}"
            logger.info(f"Authentication required for Docker containers: {str(e)}")
        except DockerCommandError as e:
            errors["docker_containers"] = str(e)
            logger.warning(f"Failed to collect Docker containers: {str(e)}")
        except Exception as e:
            errors["docker_containers"] = f"Unexpected error: {str(e)}"
            logger.error(f"Unexpected error collecting Docker containers: {str(e)}")

        try:
            docker_images = await self.docker_monitor.get_images()
            docker_images = {
                "success": True,
                "data": docker_images,
                "count": len(docker_images)
            }
        except DockerCommandError as e:
            errors["docker_images"] = str(e)
            logger.warning(f"Failed to collect Docker images: {str(e)}")
        except Exception as e:
            errors["docker_images"] = f"Unexpected error: {str(e)}"
            logger.error(f"Unexpected error collecting Docker images: {str(e)}")

        try:
            docker_stats = await self.docker_monitor.get_stats()
            docker_stats = {
                "success": True,
                "data": docker_stats,
                "count": len(docker_stats)
            }
        except DockerCommandError as e:
            errors["docker_stats"] = str(e)
            logger.warning(f"Failed to collect Docker stats: {str(e)}")
        except Exception as e:
            errors["docker_stats"] = f"Unexpected error: {str(e)}"
            logger.error(f"Unexpected error collecting Docker stats: {str(e)}")

        # Collect Kubernetes data
        try:
            kubernetes_pods = await self.k8s_monitor.get_pods()
            kubernetes_pods = {
                "success": True,
                "data": kubernetes_pods,
                "count": len(kubernetes_pods)
            }
        except KubernetesCommandError as e:
            errors["kubernetes_pods"] = str(e)
            logger.warning(f"Failed to collect Kubernetes pods: {str(e)}")
        except Exception as e:
            errors["kubernetes_pods"] = f"Unexpected error: {str(e)}"
            logger.error(f"Unexpected error collecting Kubernetes pods: {str(e)}")

        try:
            kubernetes_services = await self.k8s_monitor.get_services()
            kubernetes_services = {
                "success": True,
                "data": kubernetes_services,
                "count": len(kubernetes_services)
            }
        except KubernetesCommandError as e:
            errors["kubernetes_services"] = str(e)
            logger.warning(f"Failed to collect Kubernetes services: {str(e)}")
        except Exception as e:
            errors["kubernetes_services"] = f"Unexpected error: {str(e)}"
            logger.error(f"Unexpected error collecting Kubernetes services: {str(e)}")

        try:
            kubernetes_nodes = await self.k8s_monitor.get_nodes()
            kubernetes_nodes = {
                "success": True,
                "data": kubernetes_nodes,
                "count": len(kubernetes_nodes)
            }
        except KubernetesCommandError as e:
            errors["kubernetes_nodes"] = str(e)
            logger.warning(f"Failed to collect Kubernetes nodes: {str(e)}")
        except Exception as e:
            errors["kubernetes_nodes"] = f"Unexpected error: {str(e)}"
            logger.error(f"Unexpected error collecting Kubernetes nodes: {str(e)}")

        return MonitoringData(
            timestamp=timestamp,
            docker_containers=docker_containers,
            docker_images=docker_images,
            docker_stats=docker_stats,
            kubernetes_pods=kubernetes_pods,
            kubernetes_services=kubernetes_services,
            kubernetes_nodes=kubernetes_nodes,
            errors=errors if errors else None
        )

    async def broadcast_updates(self) -> None:
        """
        Background task to continuously broadcast monitoring updates.

        This method runs indefinitely, collecting and broadcasting monitoring
        data at regular intervals to all connected WebSocket clients.
        """
        self._running = True

        # Start session manager for heartbeat and session persistence
        await self.session_manager.start()

        logger.info(f"Started WebSocket broadcast task with {self.update_interval}s interval")

        try:
            while self._running:
                try:
                    # Collect monitoring data
                    monitoring_data = await self._collect_monitoring_data()

                    # Broadcast to all connected clients
                    if self.active_connections:
                        await self.broadcast(monitoring_data)
                        logger.debug(f"Broadcasted monitoring data to {len(self.active_connections)} clients")

                    # Wait for next update interval
                    await asyncio.sleep(self.update_interval)

                except asyncio.CancelledError:
                    logger.info("WebSocket broadcast task cancelled")
                    break
                except Exception as e:
                    logger.error(f"Error in broadcast loop: {str(e)}")
                    # Continue running even if there's an error
                    await asyncio.sleep(self.update_interval)

        finally:
            self._running = False
            # Stop session manager
            await self.session_manager.stop()
            logger.info("WebSocket broadcast task stopped")

    async def stop_broadcast(self) -> None:
        """
        Stop the background broadcast task and session manager.
        """
        self._running = False

        # Stop session manager
        await self.session_manager.stop()

        if self._update_task and not self._update_task.done():
            self._update_task.cancel()
            try:
                await self._update_task
            except asyncio.CancelledError:
                pass

    async def get_connection_stats(self) -> Dict[str, Any]:
        """
        Get statistics about WebSocket connections and authentication sessions.

        Returns:
            Dict[str, Any]: Connection and authentication statistics
        """
        # Get session statistics
        session_stats = await self.session_manager.get_session_stats()
        auth_stats = await self.auth_handler.get_auth_stats()
        privilege_status = self.command_executor.get_privilege_status()

        return {
            "active_connections": len(self.active_connections),
            "client_ids": list(self.active_connections.keys()),
            "update_interval": self.update_interval,
            "is_running": self._running,
            "session_stats": session_stats,
            "auth_stats": auth_stats,
            "privilege_status": privilege_status
        }

    async def send_custom_message(self, client_id: str, message: Dict[str, Any]) -> bool:
        """
        Send a custom message to a specific client.

        Args:
            client_id: Client ID to send message to
            message: Custom message data

        Returns:
            bool: True if sent successfully, False if client not found or disconnected
        """
        if client_id not in self.active_connections:
            return False

        websocket = self.active_connections[client_id]

        try:
            await websocket.send_text(json.dumps(message, default=str))
            return True

        except WebSocketDisconnect:
            logger.info(f"Client {client_id} disconnected during custom message send")
            self.disconnect(client_id)
            return False
        except Exception as e:
            logger.error(f"Failed to send custom message to client {client_id}: {str(e)}")
            return False

    async def broadcast_custom_message(self, message: Dict[str, Any]) -> int:
        """
        Broadcast a custom message to all connected clients.

        Args:
            message: Custom message data

        Returns:
            int: Number of clients that received the message successfully
        """
        if not self.active_connections:
            return 0

        successful_sends = 0
        for client_id in list(self.active_connections.keys()):
            if await self.send_custom_message(client_id, message):
                successful_sends += 1

        return successful_sends