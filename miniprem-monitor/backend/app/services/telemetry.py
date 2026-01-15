"""
MiniPrem Telemetry Service.
This module provides anonymous usage data collection for MiniPrem installations
to help UneeQ understand deployment health and improve the product. All data
collection is transparent, privacy-focused, and can be disabled.
Data Collected:
    - Installation ID (anonymous UUID generated locally)
    - MiniPrem version and deployment type
    - Renny version (from container image tag)
    - Scene/avatar name (from Renny API, if available)
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
import re
import subprocess
import time
from datetime import datetime
from pathlib import Path
from typing import Dict, Any, Optional, Tuple
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
        # Renny-specific info (cached)
        self._renny_version: Optional[str] = None
        self._renny_image: Optional[str] = None
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
        """Load installation ID from file system."""
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
        """Load installation sent flag from file system."""
        sent_path = Path(self._installation_sent_path)
        if sent_path.exists():
            self._installation_sent = True
            logger.debug("Installation event already sent (marker file exists)")
        else:
            self._installation_sent = False
            logger.debug("Installation event not yet sent")
    def _save_installation_sent_flag(self) -> None:
        """Save installation sent flag to file system."""
        try:
            sent_path = Path(self._installation_sent_path)
            sent_path.parent.mkdir(parents=True, exist_ok=True)
            sent_path.write_text(datetime.utcnow().isoformat() + 'Z')
            logger.debug(f"Saved installation sent marker: {sent_path}")
        except Exception as e:
            logger.warning(f"Failed to save installation sent marker: {e}")
    def _detect_platform(self) -> None:
        """Detect whether running in Docker or Kubernetes."""
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
        """Generate machine ID from GPU UUID."""
        try:
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
        """Get instance-specific details (pod name, container ID, node name)."""
        try:
            self.instance_name = platform.node()
        except Exception as e:
            logger.debug(f"Failed to get hostname: {e}")
            self.instance_name = "unknown"
        if self.platform_type in ["kubernetes", "eks", "aks", "gke"]:
            self.instance_type = "kubernetes-pod"
            self.node_name = os.getenv("NODE_NAME") or os.getenv("K8S_NODE_NAME")
            if self.node_name:
                logger.debug(f"Kubernetes node name: {self.node_name}")
            else:
                logger.debug("Kubernetes node name not available (set NODE_NAME env var)")
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
        """Get anonymous system information."""
        return {
            "os": platform.system().lower(),
            "platform_arch": platform.machine(),
            "python_version": platform.python_version()
        }
    def _extract_version_from_image(self, image: str) -> str:
        """
        Extract version from container image tag.
        Examples:
            cr.uneeq.io/uneeq/renny-renderer:enterprise-latest -> enterprise-latest
            facemeproduction/renny:0.713-37d59 -> 0.713-37d59
            cr.uneeq.io/uneeq/renny-renderer:0.758 -> 0.758
        """
        if not image:
            return "unknown"
        # Split on : to get tag
        parts = image.split(':')
        if len(parts) >= 2:
            tag = parts[-1]
            # Clean up common prefixes/suffixes
            return tag
        return "latest"
    def _get_renny_version_from_container(self, container_name: str = "renny") -> Optional[str]:
        """
        Get actual Renny version from RENNY_IMAGE_VERSION env var inside container.
        Returns:
            Version string like "0.856-02c55" or None if not found
        """
        try:
            result = subprocess.run(
                ["docker", "exec", container_name, "printenv", "RENNY_IMAGE_VERSION"],
                capture_output=True,
                text=True,
                check=False,
                timeout=5
            )
            if result.returncode == 0 and result.stdout.strip():
                version = result.stdout.strip()
                logger.debug(f"Got Renny version from container env: {version}")
                return version
        except Exception as e:
            logger.debug(f"Error getting Renny version from container: {e}")
        return None
    def _get_renny_scene_from_logs(self, container_name: str = "renny") -> Optional[str]:
        """
        Parse Renny container logs to find the current loaded scene/character.
        Looks for pattern: LogLoad: LoadMap: /Game/Live_Levels/<scene_name>
        Returns:
            Scene name like "UneeQ_Sophie_01_HeadScarf" or None if not found
        """
        try:
            result = subprocess.run(
                ["docker", "logs", container_name, "--tail", "500"],
                capture_output=True,
                text=True,
                check=False,
                timeout=10
            )
            if result.returncode == 0:
                import re
                # Find all LoadMap entries and get the most recent one
                pattern = r"LogLoad: LoadMap: /Game/Live_Levels/(\S+)"
                matches = re.findall(pattern, result.stdout + result.stderr)
                if matches:
                    scene = matches[-1]  # Most recent scene
                    # Skip BlankScene as it is the idle state
                    if scene != "BlankScene":
                        logger.debug(f"Got scene from Renny logs: {scene}")
                        return scene
                    # If only BlankScene found, check for New session logs
                    session_pattern = r"requested map = /Game/Live_Levels/(\S+?),"
                    session_matches = re.findall(session_pattern, result.stdout + result.stderr)
                    if session_matches:
                        scene = session_matches[-1]
                        logger.debug(f"Got scene from session log: {scene}")
                        return scene
        except Exception as e:
            logger.debug(f"Error parsing Renny logs for scene: {e}")
        return None
    def _get_renny_version_from_k8s_pod(self, pod_name: str, namespace: str = "default") -> Optional[str]:
        """
        Get actual Renny version from RENNY_IMAGE_VERSION env var inside K8s pod.
        Returns:
            Version string like "0.856-02c55" or None if not found
        """
        try:
            result = subprocess.run(
                ["kubectl", "exec", "-n", namespace, pod_name, "--", "printenv", "RENNY_IMAGE_VERSION"],
                capture_output=True,
                text=True,
                check=False,
                timeout=10
            )
            if result.returncode == 0 and result.stdout.strip():
                version = result.stdout.strip()
                logger.debug(f"Got Renny version from K8s pod env: {version}")
                return version
        except Exception as e:
            logger.debug(f"Error getting Renny version from K8s pod: {e}")
        return None
    def _get_renny_scene_from_k8s_logs(self, pod_name: str, namespace: str = "default") -> Optional[str]:
        """
        Parse Renny K8s pod logs to find the current loaded scene/character.
        Returns:
            Scene name like "UneeQ_Sophie_01_HeadScarf" or None if not found
        """
        try:
            result = subprocess.run(
                ["kubectl", "logs", "-n", namespace, pod_name, "--tail", "500"],
                capture_output=True,
                text=True,
                check=False,
                timeout=10
            )
            if result.returncode == 0:
                import re
                pattern = r"LogLoad: LoadMap: /Game/Live_Levels/(\S+)"
                matches = re.findall(pattern, result.stdout + result.stderr)
                if matches:
                    scene = matches[-1]
                    if scene != "BlankScene":
                        logger.debug(f"Got scene from K8s logs: {scene}")
                        return scene
                    session_pattern = r"requested map = /Game/Live_Levels/(\S+?),"
                    session_matches = re.findall(session_pattern, result.stdout + result.stderr)
                    if session_matches:
                        return session_matches[-1]
        except Exception as e:
            logger.debug(f"Error parsing K8s pod logs for scene: {e}")
        return None
    def _get_renny_image_info_docker(self) -> Tuple[Optional[str], Optional[str]]:
        """
        Get Renny container image and version from Docker.
        Returns:
            Tuple of (image_name, version) or (None, None) if not found
        """
        try:
            result = subprocess.run(
                ['docker', 'ps', '--format', '{{.Names}}\t{{.Image}}', '--filter', 'status=running'],
                capture_output=True,
                text=True,
                check=False,
                timeout=10
            )
            if result.returncode == 0:
                for line in result.stdout.strip().split('\n'):
                    if not line.strip():
                        continue
                    parts = line.split('\t')
                    if len(parts) >= 2:
                        name, image = parts[0], parts[1]
                        # Check if this is a Renny container
                        if 'renny' in name.lower() or 'renny' in image.lower() or 'renderer' in image.lower():
                            # First try to get actual version from container env var
                            version = self._get_renny_version_from_container(name)
                            if not version:
                                # Fall back to image tag
                                version = self._extract_version_from_image(image)
                            logger.debug(f"Found Renny Docker image: {image} -> version {version}")
                            return image, version
        except Exception as e:
            logger.debug(f"Error getting Docker Renny image: {e}")
        return None, None
    def _get_renny_image_info_kubernetes(self) -> Tuple[Optional[str], Optional[str]]:
        """
        Get Renny container image and version from Kubernetes.
        Returns:
            Tuple of (image_name, version) or (None, None) if not found
        """
        try:
            result = subprocess.run(
                ['kubectl', 'get', 'pods', '--all-namespaces', '-o', 'json'],
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
                    # Check containers for renny/renderer images
                    containers = pod.get('spec', {}).get('containers', [])
                    for container in containers:
                        image = container.get('image', '')
                        if 'renny' in image.lower() or 'renderer' in image.lower():
                            # First try to get actual version from container env var
                            pod_name = pod.get("metadata", {}).get("name", "")
                            namespace = pod.get("metadata", {}).get("namespace", "default")
                            version = self._get_renny_version_from_k8s_pod(pod_name, namespace)
                            if not version:
                                # Fall back to image tag
                                version = self._extract_version_from_image(image)
                            logger.debug(f"Found Renny K8s image: {image} -> version {version}")
                            return image, version
        except Exception as e:
            logger.debug(f"Error getting Kubernetes Renny image: {e}")
        return None, None
    async def _get_renny_scene_info(self) -> Optional[str]:
        """
        Get current scene/avatar name from Renny.
        First tries parsing container logs (most reliable), then falls back
        to API endpoints.
        Returns:
            Scene name string or None if not available
        """
        # First try parsing container logs (Docker)
        scene = self._get_renny_scene_from_logs("renny")
        if scene:
            return scene
        # Also try common container names
        for container in ["renderer", "renny-renderer"]:
            scene = self._get_renny_scene_from_logs(container)
            if scene:
                return scene
        # Fall back to API endpoints (may not expose scene info)
        renny_endpoints = [
            "http://renny:8000/health",
            "http://localhost:8081/health",
            "http://renderer:8000/health",
        ]
        for endpoint in renny_endpoints:
            try:
                async with httpx.AsyncClient(timeout=2.0) as client:
                    response = await client.get(endpoint)
                    if response.status_code == 200:
                        try:
                            data = response.json()
                            scene = (
                                data.get("scene") or
                                data.get("scene_name") or
                                data.get("avatar") or
                                data.get("character")
                            )
                            if scene:
                                logger.debug(f"Got scene from Renny API: {scene}")
                                return scene
                        except:
                            pass
            except Exception as e:
                logger.debug(f"Failed to query {endpoint}: {e}")
                continue
        return None
    async def _get_renny_status(self) -> Dict[str, Any]:
        """
        Get Renny deployment status including version and scene info.
        Returns:
            Dictionary containing:
                - renny_pods_running: Number of active Renny instances (or -1 if unknown)
                - renny_version: Version from container image tag
                - renny_image: Full container image name
                - scene: Current scene/avatar name (if available)
                - platform: Deployment platform (docker/kubernetes)
        """
        renny_count = 0
        renny_image = None
        renny_version = "unknown"
        scene = None
        try:
            if self.platform_type in ["kubernetes", "eks", "aks", "gke"]:
                # Get Renny image info from Kubernetes
                renny_image, renny_version = self._get_renny_image_info_kubernetes()
                # Count running Renny pods
                try:
                    result = subprocess.run(
                        ['kubectl', 'get', 'pods', '--all-namespaces', '-o', 'json'],
                        capture_output=True,
                        text=True,
                        check=False,
                        timeout=10
                    )
                    if result.returncode == 0:
                        pods_data = json.loads(result.stdout)
                        for pod in pods_data.get('items', []):
                            phase = pod.get('status', {}).get('phase', '').lower()
                            if phase != 'running':
                                continue
                            labels = pod.get('metadata', {}).get('labels', {})
                            if labels.get('app') == 'renderer':
                                renny_count += 1
                                continue
                            containers = pod.get('spec', {}).get('containers', [])
                            for container in containers:
                                image = container.get('image', '').lower()
                                if 'renny' in image or 'renderer' in image:
                                    renny_count += 1
                                    break
                        logger.debug(f"Found {renny_count} running Renny pods in Kubernetes")
                except subprocess.TimeoutExpired:
                    logger.debug("Kubernetes pod query timed out")
                    renny_count = -1
                except FileNotFoundError:
                    logger.debug("kubectl not found")
                    renny_count = -1
                except Exception as e:
                    logger.debug(f"Error querying Kubernetes pods: {e}")
                    renny_count = -1
            else:
                # Get Renny image info from Docker
                renny_image, renny_version = self._get_renny_image_info_docker()
                # Count Docker containers
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
                                if not status.startswith('up'):
                                    continue
                                if name == 'renny' or 'renny' in image or 'renderer' in image:
                                    renny_count += 1
                        logger.debug(f"Found {renny_count} running Renny containers in Docker")
                except subprocess.TimeoutExpired:
                    logger.debug("Docker ps query timed out")
                    renny_count = -1
                except FileNotFoundError:
                    logger.debug("docker not found")
                    renny_count = -1
                except Exception as e:
                    logger.debug(f"Error querying Docker containers: {e}")
                    renny_count = -1
            # Try to get scene info from Renny API
            scene = await self._get_renny_scene_info()
        except Exception as e:
            logger.debug(f"Failed to get Renny status: {e}")
            renny_count = -1
        # Cache the Renny info for future use
        if renny_version and renny_version != "unknown":
            self._renny_version = renny_version
        if renny_image:
            self._renny_image = renny_image
        return {
            "renny_pods_running": renny_count,
            "renny_version": renny_version or self._renny_version or "unknown",
            "renny_image": renny_image or self._renny_image,
            "scene": scene,
            "character_map": scene,  # Dashboard expects character_map field
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
        """Send one-time installation event."""
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
        """Send heartbeat event with current status."""
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
        """Start background task that sends heartbeats periodically."""
        if self.disabled:
            logger.info("Heartbeat loop not started: telemetry disabled")
            return
        if self._heartbeat_task and not self._heartbeat_task.done():
            logger.warning("Heartbeat loop already running")
            return
        async def heartbeat_loop():
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
        self._heartbeat_task = asyncio.create_task(heartbeat_loop())
        logger.info(
            f"Heartbeat loop started (interval: {interval_seconds}s = "
            f"{interval_seconds // 60} minutes)"
        )
    async def stop_heartbeat_loop(self) -> None:
        """Stop the background heartbeat task."""
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
    """Get singleton telemetry service instance."""
    global _telemetry_service
    if _telemetry_service is None:
        _telemetry_service = TelemetryService()
    return _telemetry_service
async def close_telemetry_service() -> None:
    """Close telemetry service and clean up resources."""
    global _telemetry_service
    if _telemetry_service is not None:
        await _telemetry_service.stop_heartbeat_loop()
        _telemetry_service = None
        logger.info("Telemetry service closed")
