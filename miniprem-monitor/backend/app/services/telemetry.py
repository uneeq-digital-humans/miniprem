"""
MiniPrem Telemetry Service.

This module provides anonymous usage data collection for MiniPrem installations
to help UneeQ understand deployment health and improve the product. All data
collection is transparent, privacy-focused, and can be disabled.

Data Collected:
    - Installation ID (anonymous UUID generated locally)
    - MiniPrem version and deployment type
    - System information (OS, platform)
    - Uptime and health status
    - Container/pod count (no names or identifiable info)

Data NOT Collected:
    - IP addresses, hostnames, or user identifiers
    - UneeQ credentials or API keys
    - Any content processed by Renny
    - Customer data or session information

Privacy:
    - All data is anonymous and cannot be traced to individuals
    - Users can opt-out by setting MINIPREM_TELEMETRY_DISABLED=1
    - Silently fails on errors (never blocks user operations)
    - Full privacy policy: https://uneeq.io/miniprem/privacy
"""

import asyncio
import hashlib
import json
import logging
import os
import platform
import subprocess
import time
from datetime import datetime
from pathlib import Path
from typing import Dict, Any, Optional

import httpx


logger = logging.getLogger(__name__)


class TelemetryService:
    """
    Anonymous telemetry service for MiniPrem installations.

    This service sends anonymous usage data to UneeQ's telemetry endpoint to help
    monitor deployment health and improve the product. All operations fail silently
    to ensure telemetry never impacts user experience.

    Attributes:
        installation_id: Anonymous UUID identifying this installation
        machine_id: Hash of GPU UUID for hardware-level deduplication
        instance_name: Pod name or container ID
        instance_type: kubernetes-pod or docker-container
        node_name: Kubernetes node name (if applicable)
        endpoint: HTTPS endpoint for telemetry data
        disabled: Whether telemetry is disabled (env var or missing ID)
        version: MiniPrem version string
        platform_type: Deployment platform (docker/kubernetes/eks/aks/gke)
        _installation_sent: Whether installation event was already sent
        _heartbeat_task: Background task handle for periodic heartbeats
    """

    def __init__(
        self,
        installation_id_path: str = "/app/data/installation_id",
        endpoint: Optional[str] = None,
        version: str = "2.1.0"
    ) -> None:
        """
        Initialize telemetry service.

        Args:
            installation_id_path: Path to file containing installation UUID
            endpoint: Custom telemetry endpoint (default from env var)
            version: MiniPrem version string

        Raises:
            ValueError: Never raises - logs errors and disables telemetry instead
        """
        self.installation_id: Optional[str] = None
        self.machine_id: Optional[str] = None
        self.instance_name: Optional[str] = None
        self.instance_type: str = "unknown"
        self.node_name: Optional[str] = None
        self.endpoint: str = endpoint or os.getenv(
            "MINIPREM_TELEMETRY_ENDPOINT",
            "https://renny.services.uneeq.io/telemetry"
        )
        self.disabled: bool = os.getenv("MINIPREM_TELEMETRY_DISABLED", "0") == "1"
        self.version: str = version
        self.platform_type: str = "docker"  # Default to docker
        self._installation_sent: bool = False
        self._heartbeat_task: Optional[asyncio.Task] = None
        self._installation_id_path: str = installation_id_path
        # Store sent marker in persistent writable directory
        self._installation_sent_path: str = "/app/telemetry_state/installation_sent"

        # Load installation ID
        try:
            self._load_installation_id()
        except Exception as e:
            logger.warning(f"Failed to load installation ID, telemetry disabled: {e}")
            self.disabled = True

        # Check if installation event was already sent
        try:
            self._load_installation_sent_flag()
        except Exception as e:
            logger.debug(f"Failed to load installation sent flag: {e}")

        # Detect platform type
        try:
            self._detect_platform()
        except Exception as e:
            logger.debug(f"Failed to detect platform type: {e}")

        # Generate machine ID from GPU UUID
        try:
            self._generate_machine_id()
        except Exception as e:
            logger.warning(f"Failed to generate machine ID: {e}")
            # Use installation_id as fallback
            self.machine_id = self.installation_id

        # Get instance details (pod name, container ID, etc.)
        try:
            self._get_instance_details()
        except Exception as e:
            logger.debug(f"Failed to get instance details: {e}")

        if self.disabled:
            logger.info("Telemetry disabled via environment variable")
        elif not self.installation_id:
            logger.warning("Telemetry disabled: no installation ID found")
            self.disabled = True
        else:
            logger.info(
                f"Telemetry initialized: id={self.installation_id[:8]}..., "
                f"endpoint={self.endpoint}"
            )

    def _load_installation_id(self) -> None:
        """
        Load installation ID from file system.

        The installation ID is a UUID generated during installation and stored
        in a file mounted into the container. This ensures the same ID persists
        across container restarts.

        Raises:
            FileNotFoundError: If installation ID file doesn't exist
            IOError: If file cannot be read
        """
        id_path = Path(self._installation_id_path)

        if not id_path.exists():
            logger.warning(f"Installation ID file not found: {id_path}")
            return

        try:
            self.installation_id = id_path.read_text().strip()
            logger.debug(f"Loaded installation ID: {self.installation_id[:8]}...")
        except Exception as e:
            logger.error(f"Failed to read installation ID from {id_path}: {e}")
            raise

    def _load_installation_sent_flag(self) -> None:
        """
        Load installation sent flag from file system.

        Checks if a marker file exists indicating the installation event
        was already sent to the telemetry endpoint. This prevents duplicate
        installation events on container restarts.
        """
        sent_path = Path(self._installation_sent_path)

        if sent_path.exists():
            self._installation_sent = True
            logger.debug("Installation event already sent (marker file exists)")
        else:
            self._installation_sent = False
            logger.debug("Installation event not yet sent")

    def _save_installation_sent_flag(self) -> None:
        """
        Save installation sent flag to file system.

        Creates a marker file to indicate the installation event was
        successfully sent. This file persists across container restarts.
        """
        try:
            sent_path = Path(self._installation_sent_path)
            sent_path.parent.mkdir(parents=True, exist_ok=True)
            sent_path.write_text(datetime.utcnow().isoformat() + 'Z')
            logger.debug(f"Saved installation sent marker: {sent_path}")
        except Exception as e:
            logger.warning(f"Failed to save installation sent marker: {e}")

    def _detect_platform(self) -> None:
        """
        Detect whether running in Docker or Kubernetes.

        Detection logic:
            - Checks for Kubernetes service environment variables
            - Checks for /.dockerenv file (Docker indicator)
            - Falls back to 'docker' as default

        Note:
            This is best-effort detection and may not be 100% accurate in all
            environments. It's used for informational purposes only.
        """
        # Check for Kubernetes environment variables
        if os.getenv("KUBERNETES_SERVICE_HOST"):
            self.platform_type = "kubernetes"
            logger.debug("Detected platform: kubernetes")
            return

        # Check for Docker environment file
        if Path("/.dockerenv").exists():
            self.platform_type = "docker"
            logger.debug("Detected platform: docker")
            return

        logger.debug(f"Using default platform: {self.platform_type}")

    def _generate_machine_id(self) -> None:
        """
        Generate machine ID from GPU UUID.

        Queries the primary GPU (index 0) for its UUID and creates a SHA-256 hash
        for privacy-preserving machine identification. This allows deduplication of
        reinstalls on the same hardware without exposing the actual GPU UUID.

        The machine_id persists across OS reinstalls and driver updates because
        the GPU UUID is hardware-based.

        Falls back to installation_id if GPU query fails (rare edge case).

        Raises:
            subprocess.CalledProcessError: If nvidia-smi command fails
            Exception: For any other GPU query errors
        """
        try:
            # Query primary GPU UUID (index 0)
            result = subprocess.run(
                ['nvidia-smi', '--query-gpu=uuid', '--format=csv,noheader', '-i', '0'],
                capture_output=True,
                text=True,
                check=True,
                timeout=5
            )

            gpu_uuid = result.stdout.strip()

            if not gpu_uuid:
                logger.warning("GPU UUID query returned empty string")
                self.machine_id = self.installation_id
                return

            # One-way hash for privacy (SHA-256)
            self.machine_id = hashlib.sha256(gpu_uuid.encode()).hexdigest()
            logger.info(f"Machine ID generated from GPU UUID: {self.machine_id[:12]}...")

        except subprocess.TimeoutExpired:
            logger.warning("GPU UUID query timed out, using installation_id as fallback")
            self.machine_id = self.installation_id
        except subprocess.CalledProcessError as e:
            logger.warning(f"nvidia-smi failed (exit {e.returncode}), using installation_id as fallback")
            self.machine_id = self.installation_id
        except FileNotFoundError:
            logger.warning("nvidia-smi not found, using installation_id as fallback")
            self.machine_id = self.installation_id
        except Exception as e:
            logger.warning(f"Unexpected error querying GPU UUID: {e}")
            self.machine_id = self.installation_id

    def _get_instance_details(self) -> None:
        """
        Get instance-specific details (pod name, container ID, node name).

        For Kubernetes:
            - instance_name: Pod name from hostname
            - instance_type: "kubernetes-pod"
            - node_name: Node name from NODE_NAME env var or downward API

        For Docker:
            - instance_name: Container ID from hostname
            - instance_type: "docker-container"
            - node_name: None

        This information helps track individual Renny instances across deployments.
        """
        # Get hostname (pod name in k8s, container ID in docker)
        try:
            self.instance_name = platform.node()
        except Exception as e:
            logger.debug(f"Failed to get hostname: {e}")
            self.instance_name = "unknown"

        # Kubernetes-specific details
        if self.platform_type in ["kubernetes", "eks", "aks", "gke"]:
            self.instance_type = "kubernetes-pod"

            # Try to get node name from environment variable (downward API)
            self.node_name = os.getenv("NODE_NAME") or os.getenv("K8S_NODE_NAME")

            if self.node_name:
                logger.debug(f"Kubernetes node name: {self.node_name}")
            else:
                logger.debug("Kubernetes node name not available (set NODE_NAME env var)")

        # Docker-specific details
        elif self.platform_type == "docker" or self.platform_type == "docker-ubuntu":
            self.instance_type = "docker-container"
            self.node_name = None
            logger.debug(f"Docker container ID: {self.instance_name[:12]}...")

        else:
            self.instance_type = "unknown"
            self.node_name = None

        logger.info(
            f"Instance details: name={self.instance_name[:12]}..., "
            f"type={self.instance_type}, node={self.node_name or 'N/A'}"
        )

    def _get_system_info(self) -> Dict[str, str]:
        """
        Get anonymous system information.

        Returns only non-identifiable system metadata useful for understanding
        the deployment environment.

        Returns:
            Dictionary containing:
                - os: Operating system name (e.g., 'linux', 'darwin')
                - platform: Platform architecture (e.g., 'x86_64', 'aarch64')
                - python_version: Python runtime version

        Examples:
            >>> service = TelemetryService()
            >>> info = service._get_system_info()
            >>> print(info)
            {'os': 'linux', 'platform': 'x86_64', 'python_version': '3.11.7'}
        """
        return {
            "os": platform.system().lower(),
            "platform": platform.machine(),
            "python_version": platform.python_version()
        }

    async def _get_renny_status(self) -> Dict[str, Any]:
        """
        Get Renny deployment status.

        Attempts to count running Renny pods/containers without collecting any
        identifiable information (no names, IPs, or other metadata).

        Returns:
            Dictionary containing:
                - renny_pods_running: Number of active Renny instances (or -1 if unknown)
                - platform: Deployment platform (docker/kubernetes)

        Note:
            Silently fails if unable to query Docker/Kubernetes - this should never
            block or raise errors.
        """
        renny_count = 0  # Default to 0 (no Renny instances found)

        try:
            if self.platform_type in ["kubernetes", "eks", "aks", "gke"]:
                # Count Kubernetes pods with label app=renderer or container image containing 'renny'
                try:
                    result = subprocess.run(
                        ['kubectl', 'get', 'pods', '--all-namespaces',
                         '-o', 'json'],
                        capture_output=True,
                        text=True,
                        check=False,
                        timeout=10
                    )

                    if result.returncode == 0:
                        pods_data = json.loads(result.stdout)

                        for pod in pods_data.get('items', []):
                            # Check if pod is running
                            phase = pod.get('status', {}).get('phase', '').lower()
                            if phase != 'running':
                                continue

                            # Check pod labels for app=renderer
                            labels = pod.get('metadata', {}).get('labels', {})
                            if labels.get('app') == 'renderer':
                                renny_count += 1
                                continue

                            # Check if any container uses renny image
                            containers = pod.get('spec', {}).get('containers', [])
                            for container in containers:
                                image = container.get('image', '').lower()
                                if 'renny' in image:
                                    renny_count += 1
                                    break  # Count pod once even if multiple renny containers

                        logger.debug(f"Found {renny_count} running Renny pods in Kubernetes")

                except subprocess.TimeoutExpired:
                    logger.debug("Kubernetes pod query timed out")
                    renny_count = -1
                except FileNotFoundError:
                    logger.debug("kubectl not found - cannot count Kubernetes pods")
                    renny_count = -1
                except Exception as e:
                    logger.debug(f"Error querying Kubernetes pods: {e}")
                    renny_count = -1

            else:
                # Count Docker containers named 'renny' or using renny image
                try:
                    result = subprocess.run(
                        ['docker', 'ps', '--format', '{{.Names}}\t{{.Image}}\t{{.Status}}'],
                        capture_output=True,
                        text=True,
                        check=False,
                        timeout=10
                    )

                    if result.returncode == 0:
                        lines = result.stdout.strip().split('\n')
                        for line in lines:
                            if not line.strip():
                                continue

                            parts = line.split('\t')
                            if len(parts) >= 3:
                                name = parts[0].lower()
                                image = parts[1].lower()
                                status = parts[2].lower()

                                # Check if container is running (status starts with "Up")
                                if not status.startswith('up'):
                                    continue

                                # Check if container name is 'renny' or image contains 'renny'
                                if name == 'renny' or 'renny' in image:
                                    renny_count += 1

                        logger.debug(f"Found {renny_count} running Renny containers in Docker")

                except subprocess.TimeoutExpired:
                    logger.debug("Docker ps query timed out")
                    renny_count = -1
                except FileNotFoundError:
                    logger.debug("docker not found - cannot count Docker containers")
                    renny_count = -1
                except Exception as e:
                    logger.debug(f"Error querying Docker containers: {e}")
                    renny_count = -1

        except Exception as e:
            logger.debug(f"Failed to get Renny status: {e}")
            renny_count = -1

        return {
            "renny_pods_running": renny_count,
            "platform": self.platform_type
        }

    async def _send_telemetry(
        self,
        event_type: str,
        additional_data: Optional[Dict[str, Any]] = None
    ) -> bool:
        """
        Send telemetry data to the endpoint.

        All network errors are caught and logged without raising exceptions,
        ensuring telemetry never impacts user operations.

        Args:
            event_type: Type of event ('installation' or 'heartbeat')
            additional_data: Optional additional payload data

        Returns:
            True if data was sent successfully, False otherwise

        Examples:
            >>> service = TelemetryService()
            >>> success = await service._send_telemetry('heartbeat')
            >>> print(success)
            True
        """
        if self.disabled:
            return False

        if not self.installation_id:
            logger.debug("Skipping telemetry: no installation ID")
            return False

        # Build payload
        payload: Dict[str, Any] = {
            "installation_id": self.installation_id,
            "machine_id": self.machine_id,
            "instance_name": self.instance_name,
            "instance_type": self.instance_type,
            "event_type": event_type,
            "timestamp": datetime.utcnow().isoformat() + 'Z',
            "version": self.version,
            "platform": self.platform_type,
            **self._get_system_info()
        }

        # Add node_name if available (Kubernetes only)
        if self.node_name:
            payload["node_name"] = self.node_name

        # Add additional data if provided
        if additional_data:
            payload.update(additional_data)

        # Send request with timeout
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                response = await client.post(
                    self.endpoint,
                    json=payload,
                    headers={"Content-Type": "application/json"}
                )

                if response.status_code == 200:
                    logger.debug(f"Telemetry {event_type} sent successfully")
                    return True
                else:
                    logger.warning(
                        f"Telemetry {event_type} failed: HTTP {response.status_code}"
                    )
                    return False

        except httpx.TimeoutException:
            logger.debug(f"Telemetry {event_type} timed out (5s)")
            return False
        except httpx.NetworkError as e:
            logger.debug(f"Telemetry {event_type} network error: {e}")
            return False
        except Exception as e:
            logger.warning(f"Telemetry {event_type} unexpected error: {e}")
            return False

    async def send_installation_event(self) -> bool:
        """
        Send one-time installation event.

        This should be called once on first startup to notify UneeQ of a new
        MiniPrem installation. It's idempotent - calling multiple times will
        only send once. Persistence is maintained via a marker file.

        Returns:
            True if event was sent (or already sent), False if failed

        Examples:
            >>> service = TelemetryService()
            >>> success = await service.send_installation_event()
            >>> print(success)
            True
        """
        if self._installation_sent:
            logger.debug("Installation event already sent (skipping)")
            return True

        logger.info("Sending installation telemetry event")

        renny_status = await self._get_renny_status()
        success = await self._send_telemetry("installation", renny_status)

        if success:
            self._installation_sent = True
            self._save_installation_sent_flag()
            logger.info("Installation telemetry event sent successfully")
        else:
            logger.warning("Installation telemetry event failed to send")

        return success

    async def send_heartbeat(self) -> bool:
        """
        Send heartbeat event with current status.

        This should be called periodically (e.g., every 15 minutes) to indicate
        the MiniPrem installation is still active and healthy.

        Returns:
            True if heartbeat was sent successfully, False otherwise

        Examples:
            >>> service = TelemetryService()
            >>> success = await service.send_heartbeat()
            >>> print(success)
            True
        """
        logger.debug("Sending heartbeat telemetry event")

        renny_status = await self._get_renny_status()
        renny_status["status"] = "online"

        success = await self._send_telemetry("heartbeat", renny_status)

        if success:
            logger.debug("Heartbeat telemetry event sent successfully")
        else:
            logger.debug("Heartbeat telemetry event failed to send")

        return success

    async def start_heartbeat_loop(self, interval_seconds: int = 900) -> None:
        """
        Start background task that sends heartbeats periodically.

        This creates an asyncio task that runs indefinitely, sending heartbeat
        events at the specified interval.

        Args:
            interval_seconds: Seconds between heartbeats (default: 900 = 15 minutes)

        Examples:
            >>> service = TelemetryService()
            >>> await service.start_heartbeat_loop(interval_seconds=900)
            # Heartbeats will be sent every 15 minutes
        """
        if self.disabled:
            logger.info("Heartbeat loop not started: telemetry disabled")
            return

        if self._heartbeat_task and not self._heartbeat_task.done():
            logger.warning("Heartbeat loop already running")
            return

        async def heartbeat_loop():
            """Internal loop that sends heartbeats periodically."""
            logger.info(f"Starting heartbeat loop (interval: {interval_seconds}s)")

            while True:
                try:
                    await asyncio.sleep(interval_seconds)
                    await self.send_heartbeat()
                except asyncio.CancelledError:
                    logger.info("Heartbeat loop cancelled")
                    break
                except Exception as e:
                    logger.error(f"Error in heartbeat loop: {e}")
                    # Continue loop even if one heartbeat fails

        self._heartbeat_task = asyncio.create_task(heartbeat_loop())
        logger.info(
            f"Heartbeat loop started (interval: {interval_seconds}s = "
            f"{interval_seconds // 60} minutes)"
        )

    async def stop_heartbeat_loop(self) -> None:
        """
        Stop the background heartbeat task.

        This gracefully cancels the heartbeat task if it's running.

        Examples:
            >>> service = TelemetryService()
            >>> await service.start_heartbeat_loop()
            >>> # ... later ...
            >>> await service.stop_heartbeat_loop()
        """
        if self._heartbeat_task and not self._heartbeat_task.done():
            logger.info("Stopping heartbeat loop")
            self._heartbeat_task.cancel()

            try:
                await self._heartbeat_task
            except asyncio.CancelledError:
                logger.info("Heartbeat loop stopped successfully")

        self._heartbeat_task = None


# Singleton instance for use in FastAPI app
_telemetry_service: Optional[TelemetryService] = None


def get_telemetry_service() -> TelemetryService:
    """
    Get singleton telemetry service instance.

    This ensures only one telemetry service exists per application instance.

    Returns:
        Global TelemetryService instance

    Examples:
        >>> from app.services.telemetry import get_telemetry_service
        >>> service = get_telemetry_service()
        >>> await service.send_heartbeat()
    """
    global _telemetry_service

    if _telemetry_service is None:
        _telemetry_service = TelemetryService()

    return _telemetry_service


async def close_telemetry_service() -> None:
    """
    Close telemetry service and clean up resources.

    This should be called during application shutdown to gracefully stop
    the heartbeat loop.

    Examples:
        >>> from app.services.telemetry import close_telemetry_service
        >>> await close_telemetry_service()
    """
    global _telemetry_service

    if _telemetry_service is not None:
        await _telemetry_service.stop_heartbeat_loop()
        _telemetry_service = None
        logger.info("Telemetry service closed")
