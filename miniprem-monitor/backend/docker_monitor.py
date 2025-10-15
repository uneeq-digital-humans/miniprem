"""
Docker monitoring module with secure subprocess execution and authentication.

This module provides secure Docker command execution with input validation,
privilege detection, and authentication management for monitoring Docker
containers and resources.
"""

import asyncio
import json
import logging
import re
from typing import Dict, List, Any, Optional, Union
from dataclasses import dataclass
from pathlib import Path

from auth.command_executor import CommandExecutor, CommandType, CommandResult, PrivilegeError
from auth.auth_manager import AuthManager
from auth.session_manager import SessionManager
from app.services.prometheus_client import get_prometheus_client, PrometheusMetrics


logger = logging.getLogger(__name__)


@dataclass
class DockerContainer:
    """
    Data class representing a Docker container.

    Attributes:
        id: Container ID
        name: Container name
        image: Image name used by container
        status: Current container status
        ports: Port mappings
        created: Creation timestamp
        command: Command running in container
    """
    id: str
    name: str
    image: str
    status: str
    ports: str
    created: str
    command: str


@dataclass
class DockerImage:
    """
    Data class representing a Docker image.

    Attributes:
        repository: Image repository name
        tag: Image tag
        image_id: Unique image ID
        created: Creation timestamp
        size: Image size
    """
    repository: str
    tag: str
    image_id: str
    created: str
    size: str


@dataclass
class DockerStats:
    """
    Data class representing Docker container resource statistics.

    Attributes:
        container_id: Container ID
        name: Container name
        cpu_percent: CPU usage percentage
        memory_usage: Memory usage string
        memory_percent: Memory usage percentage
        network_io: Network I/O statistics
        block_io: Block I/O statistics
    """
    container_id: str
    name: str
    cpu_percent: str
    memory_usage: str
    memory_percent: str
    network_io: str
    block_io: str


class DockerCommandError(Exception):
    """Custom exception for Docker command execution errors."""
    pass


class DockerMonitor:
    """
    Secure Docker monitoring class with authentication and privilege detection.

    This class provides methods to safely execute Docker commands with automatic
    privilege detection, authentication management, and secure command execution.
    """

    # Whitelist of allowed Docker commands - now handled by CommandExecutor
    ALLOWED_COMMANDS = {
        "ps": ["docker", "ps", "-a", "--format", "json"],
        "images": ["docker", "images", "--format", "json"],
        "stats": ["docker", "stats", "--no-stream", "--format", "json"]
    }

    # Regex patterns for input validation
    CONTAINER_NAME_PATTERN = re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9_.-]*$")
    IMAGE_NAME_PATTERN = re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9_.-]*(?::[a-zA-Z0-9_.-]+)?$")

    def __init__(self, command_executor: Optional[CommandExecutor] = None):
        """
        Initialize the Docker monitor.

        Args:
            command_executor: CommandExecutor instance for authentication and privilege detection
        """
        self.command_executor = command_executor or CommandExecutor()
        self.docker_available = None
        self._privilege_detected = False

    async def _check_docker_availability(self) -> bool:
        """
        Check if Docker is available and accessible using CommandExecutor.

        Returns:
            bool: True if Docker is available, False otherwise
        """
        if self.docker_available is not None:
            return self.docker_available

        try:
            # Use CommandExecutor to check Docker availability
            if not self._privilege_detected:
                await self.command_executor.detect_privileges()
                self._privilege_detected = True

            # Test Docker availability
            result = await self.command_executor.execute_command(
                CommandType.DOCKER,
                ["docker", "--version"],
                timeout=10,
                require_auth=False
            )
            self.docker_available = result.success

            if result.success:
                logger.info("Docker is available and accessible")
            else:
                logger.warning(f"Docker not available: {result.stderr}")

        except Exception as e:
            logger.warning(f"Docker availability check failed: {str(e)}")
            self.docker_available = False

        return self.docker_available

    async def _execute_docker_command(
        self,
        command: List[str],
        timeout: int = 30,
        require_auth: bool = True
    ) -> CommandResult:
        """
        Execute a Docker command using CommandExecutor with authentication.

        Args:
            command: List of command parts (prevents shell injection)
            timeout: Command timeout in seconds
            require_auth: Whether to require authentication

        Returns:
            CommandResult: Command execution result

        Raises:
            DockerCommandError: If command execution fails
            PrivilegeError: If authentication is required but not available
        """
        try:
            # Ensure privilege detection is complete
            if not self._privilege_detected:
                await self.command_executor.detect_privileges()
                self._privilege_detected = True

            # Execute command through CommandExecutor
            result = await self.command_executor.execute_command(
                CommandType.DOCKER,
                command,
                timeout=timeout,
                require_auth=require_auth
            )

            if not result.success:
                raise DockerCommandError(
                    f"Docker command failed with return code {result.return_code}: {result.stderr}"
                )

            return result

        except PrivilegeError as e:
            # Re-raise privilege errors for WebSocket authentication handling
            raise e
        except Exception as e:
            raise DockerCommandError(f"Docker command execution failed: {str(e)}")

    def _validate_container_name(self, name: str) -> bool:
        """
        Validate container name to prevent injection attacks.

        Args:
            name: Container name to validate

        Returns:
            bool: True if name is valid, False otherwise
        """
        if not name or len(name) > 128:
            return False
        return bool(self.CONTAINER_NAME_PATTERN.match(name))

    def _validate_image_name(self, name: str) -> bool:
        """
        Validate image name to prevent injection attacks.

        Args:
            name: Image name to validate

        Returns:
            bool: True if name is valid, False otherwise
        """
        if not name or len(name) > 256:
            return False
        return bool(self.IMAGE_NAME_PATTERN.match(name))

    def _parse_docker_ps_output(self, output: str) -> List[Dict[str, Any]]:
        """
        Parse Docker ps JSON output into structured data.

        Args:
            output: Raw JSON output from docker ps command

        Returns:
            List[Dict[str, Any]]: Parsed container information

        Raises:
            DockerCommandError: If output parsing fails
        """
        try:
            containers = []
            if not output.strip():
                return containers

            # Docker ps with --format json returns one JSON object per line
            for line in output.strip().split('\n'):
                if line.strip():
                    container_data = json.loads(line)
                    containers.append({
                        "id": container_data.get("ID", ""),
                        "name": container_data.get("Names", ""),
                        "image": container_data.get("Image", ""),
                        "status": container_data.get("Status", ""),
                        "ports": container_data.get("Ports", ""),
                        "created": container_data.get("CreatedAt", ""),
                        "command": container_data.get("Command", ""),
                        "state": container_data.get("State", ""),
                        "labels": container_data.get("Labels", "")
                    })

            return containers

        except json.JSONDecodeError as e:
            raise DockerCommandError(f"Failed to parse Docker ps output: {str(e)}")
        except Exception as e:
            raise DockerCommandError(f"Unexpected error parsing Docker ps output: {str(e)}")

    def _parse_docker_images_output(self, output: str) -> List[Dict[str, Any]]:
        """
        Parse Docker images JSON output into structured data.

        Args:
            output: Raw JSON output from docker images command

        Returns:
            List[Dict[str, Any]]: Parsed image information

        Raises:
            DockerCommandError: If output parsing fails
        """
        try:
            images = []
            if not output.strip():
                return images

            # Docker images with --format json returns one JSON object per line
            for line in output.strip().split('\n'):
                if line.strip():
                    image_data = json.loads(line)
                    images.append({
                        "repository": image_data.get("Repository", ""),
                        "tag": image_data.get("Tag", ""),
                        "image_id": image_data.get("ID", ""),
                        "created": image_data.get("CreatedAt", ""),
                        "size": image_data.get("Size", ""),
                        "digest": image_data.get("Digest", "")
                    })

            return images

        except json.JSONDecodeError as e:
            raise DockerCommandError(f"Failed to parse Docker images output: {str(e)}")
        except Exception as e:
            raise DockerCommandError(f"Unexpected error parsing Docker images output: {str(e)}")

    def _parse_docker_stats_output(self, output: str) -> List[Dict[str, Any]]:
        """
        Parse Docker stats JSON output into structured data.

        Args:
            output: Raw JSON output from docker stats command

        Returns:
            List[Dict[str, Any]]: Parsed statistics information

        Raises:
            DockerCommandError: If output parsing fails
        """
        try:
            stats = []
            if not output.strip():
                return stats

            # Docker stats with --format json returns one JSON object per line
            for line in output.strip().split('\n'):
                if line.strip():
                    stats_data = json.loads(line)
                    stats.append({
                        "container_id": stats_data.get("ID", ""),
                        "name": stats_data.get("Name", ""),
                        "cpu_percent": stats_data.get("CPUPerc", "0.00%"),
                        "memory_usage": stats_data.get("MemUsage", "0B / 0B"),
                        "memory_percent": stats_data.get("MemPerc", "0.00%"),
                        "network_io": stats_data.get("NetIO", "0B / 0B"),
                        "block_io": stats_data.get("BlockIO", "0B / 0B"),
                        "pids": stats_data.get("PIDs", "0")
                    })

            return stats

        except json.JSONDecodeError as e:
            raise DockerCommandError(f"Failed to parse Docker stats output: {str(e)}")
        except Exception as e:
            raise DockerCommandError(f"Unexpected error parsing Docker stats output: {str(e)}")

    async def get_containers(self, all_containers: bool = True) -> List[Dict[str, Any]]:
        """
        Get list of Docker containers with their information.

        Args:
            all_containers: Include stopped containers if True

        Returns:
            List[Dict[str, Any]]: List of container information

        Raises:
            DockerCommandError: If Docker is not available or command fails
        """
        if not await self._check_docker_availability():
            raise DockerCommandError("Docker is not available")

        try:
            command = self.ALLOWED_COMMANDS["ps"].copy()
            if not all_containers:
                # Remove -a flag to show only running containers
                command = [cmd for cmd in command if cmd != "-a"]

            result = await self._execute_docker_command(command)
            output = result.stdout

            containers = self._parse_docker_ps_output(output)
            logger.info(f"Retrieved {len(containers)} Docker containers")

            return containers

        except DockerCommandError:
            raise
        except Exception as e:
            raise DockerCommandError(f"Failed to get Docker containers: {str(e)}")

    async def get_images(self) -> List[Dict[str, Any]]:
        """
        Get list of Docker images available on the system.

        Returns:
            List[Dict[str, Any]]: List of image information

        Raises:
            DockerCommandError: If Docker is not available or command fails
        """
        if not await self._check_docker_availability():
            raise DockerCommandError("Docker is not available")

        try:
            command = self.ALLOWED_COMMANDS["images"]
            result = await self._execute_docker_command(command)
            output = result.stdout

            images = self._parse_docker_images_output(output)
            logger.info(f"Retrieved {len(images)} Docker images")

            return images

        except DockerCommandError:
            raise
        except Exception as e:
            raise DockerCommandError(f"Failed to get Docker images: {str(e)}")

    async def get_stats(self) -> List[Dict[str, Any]]:
        """
        Get Docker container resource usage statistics.

        Returns:
            List[Dict[str, Any]]: List of container statistics

        Raises:
            DockerCommandError: If Docker is not available or command fails
        """
        if not await self._check_docker_availability():
            raise DockerCommandError("Docker is not available")

        try:
            command = self.ALLOWED_COMMANDS["stats"]
            result = await self._execute_docker_command(command)
            output = result.stdout

            stats = self._parse_docker_stats_output(output)
            logger.info(f"Retrieved stats for {len(stats)} Docker containers")

            return stats

        except DockerCommandError:
            raise
        except Exception as e:
            raise DockerCommandError(f"Failed to get Docker stats: {str(e)}")

    async def get_container_logs(
        self,
        container_name: str,
        lines: int = 100
    ) -> List[str]:
        """
        Get logs from a specific Docker container.

        Args:
            container_name: Name or ID of the container
            lines: Number of log lines to retrieve

        Returns:
            List[str]: Container log lines

        Raises:
            DockerCommandError: If container name is invalid or command fails
        """
        if not await self._check_docker_availability():
            raise DockerCommandError("Docker is not available")

        if not self._validate_container_name(container_name):
            raise DockerCommandError(f"Invalid container name: {container_name}")

        if not isinstance(lines, int) or lines < 1 or lines > 10000:
            raise DockerCommandError("Lines parameter must be between 1 and 10000")

        try:
            command = [
                "docker", "logs",
                "--tail", str(lines),
                container_name
            ]

            result = await self._execute_docker_command(command)
            output = result.stdout

            log_lines = output.strip().split('\n') if output.strip() else []
            logger.info(f"Retrieved {len(log_lines)} log lines for container {container_name}")

            return log_lines

        except DockerCommandError:
            raise
        except Exception as e:
            raise DockerCommandError(f"Failed to get logs for container {container_name}: {str(e)}")

    async def stream_container_logs(
        self,
        container_name: str,
        lines: int = 100
    ):
        """
        Stream logs from a specific Docker container in real-time.

        This is an async generator that yields log lines as they are produced
        by the container, similar to `docker logs --follow`.

        Args:
            container_name: Name or ID of the container
            lines: Number of historical log lines to include initially

        Yields:
            str: Individual log lines as they are produced

        Raises:
            DockerCommandError: If container name is invalid or command fails
        """
        if not await self._check_docker_availability():
            raise DockerCommandError("Docker is not available")

        if not self._validate_container_name(container_name):
            raise DockerCommandError(f"Invalid container name: {container_name}")

        if not isinstance(lines, int) or lines < 1 or lines > 10000:
            raise DockerCommandError("Lines parameter must be between 1 and 10000")

        try:
            # Ensure privilege detection is complete
            if not self._privilege_detected:
                await self.command_executor.detect_privileges()
                self._privilege_detected = True

            # Build command for streaming logs
            command = [
                "docker", "logs",
                "--follow",
                "--tail", str(lines),
                container_name
            ]

            # Use sudo if required
            requires_sudo = (
                self.command_executor.privilege_status.docker_requires_sudo
                and self.command_executor.auth_manager.is_authenticated()
            )

            if requires_sudo:
                command = ["sudo", "-S"] + command

            logger.info(f"Starting log stream for container {container_name}")

            # Start the subprocess
            process = await asyncio.create_subprocess_exec(
                *command,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                stdin=asyncio.subprocess.PIPE if requires_sudo else None
            )

            # Send sudo password if needed
            if requires_sudo and process.stdin:
                password = self.command_executor.auth_manager.get_password()
                process.stdin.write(f"{password}\n".encode())
                await process.stdin.drain()

            # Stream output line by line
            try:
                while True:
                    line = await process.stdout.readline()
                    if not line:
                        # Process ended
                        break

                    decoded_line = line.decode('utf-8', errors='replace').rstrip('\n\r')
                    if decoded_line:
                        yield decoded_line

            except asyncio.CancelledError:
                # Clean up on cancellation
                logger.info(f"Log stream cancelled for container {container_name}")
                process.terminate()
                try:
                    await asyncio.wait_for(process.wait(), timeout=5.0)
                except asyncio.TimeoutError:
                    process.kill()
                raise

            finally:
                # Ensure process is terminated
                if process.returncode is None:
                    process.terminate()
                    try:
                        await asyncio.wait_for(process.wait(), timeout=5.0)
                    except asyncio.TimeoutError:
                        process.kill()

        except DockerCommandError:
            raise
        except Exception as e:
            raise DockerCommandError(f"Failed to stream logs for container {container_name}: {str(e)}")

    async def enrich_containers_with_metrics(
        self,
        containers: List[Dict[str, Any]],
        metrics_config: Optional[Dict[str, Dict[str, Any]]] = None
    ) -> List[Dict[str, Any]]:
        """
        Enrich container data with Prometheus metrics where available.

        Args:
            containers: List of container dictionaries from get_containers()
            metrics_config: Optional configuration for metrics endpoints per container.
                           Format: {"container_name": {"port": 8080, "path": "/metrics"}}
                           Defaults to checking common ports for known containers.

        Returns:
            List[Dict[str, Any]]: Containers with added "metrics" field where available

        Example:
            containers = await docker_monitor.get_containers()
            enriched = await docker_monitor.enrich_containers_with_metrics(containers)
        """
        if not containers:
            return containers

        # Default metrics configuration for known containers
        default_metrics_config = {
            "renny": {"port": 8080, "path": "/metrics"},  # Renny exposes metrics on 8080
            "flowise": {"port": 3000, "path": "/metrics"},  # Flowise may expose metrics
            "prometheus": {"port": 9090, "path": "/metrics"}  # Prometheus self-metrics
        }

        # Merge with user-provided config
        final_config = {**default_metrics_config, **(metrics_config or {})}

        # Get Prometheus client
        prom_client = get_prometheus_client()

        # Enrich each container
        enriched_containers = []
        for container in containers:
            container_name = container.get("name", "").lower()

            # Check if this container has metrics configuration
            metrics_conf = None
            for conf_name, conf in final_config.items():
                if conf_name.lower() in container_name:
                    metrics_conf = conf
                    break

            if metrics_conf:
                # Fetch metrics asynchronously
                try:
                    metrics = await prom_client.get_container_metrics(
                        container_name=container_name,
                        metrics_port=metrics_conf.get("port", 8080),
                        metrics_path=metrics_conf.get("path", "/metrics")
                    )

                    if metrics:
                        # Add metrics to container data
                        container_copy = container.copy()
                        container_copy["metrics"] = metrics.to_dict()
                        enriched_containers.append(container_copy)
                        logger.debug(f"Enriched container '{container_name}' with Prometheus metrics")
                    else:
                        # No metrics available, add container without metrics
                        enriched_containers.append(container)
                        logger.debug(f"No metrics available for container '{container_name}'")

                except Exception as e:
                    # Log error but don't fail - just add container without metrics
                    logger.debug(f"Failed to fetch metrics for container '{container_name}': {e}")
                    enriched_containers.append(container)
            else:
                # Container has no metrics configuration
                enriched_containers.append(container)

        return enriched_containers