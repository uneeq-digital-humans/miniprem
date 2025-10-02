"""
Docker Manager Service

This module provides comprehensive Docker engine and container lifecycle management
for the MiniPrem Monitor backend, including start/stop controls, health monitoring,
and service status tracking.
"""

import asyncio
import subprocess
import json
import logging
import time
from typing import Dict, List, Any, Optional, Tuple
from datetime import datetime
from ..models.schemas import DockerEngineStatus, DockerServiceRequest, DockerServiceResponse

logger = logging.getLogger(__name__)


class DockerManager:
    """
    Comprehensive Docker engine and service management.

    Provides Docker engine lifecycle controls, health monitoring, container
    management, and system integration with proper error handling and logging.
    """

    def __init__(self):
        """Initialize the Docker manager."""
        self._last_status_check: Optional[datetime] = None
        self._cached_status: Optional[DockerEngineStatus] = None
        self._status_cache_ttl = 30  # Cache status for 30 seconds

    async def get_docker_status(self) -> DockerEngineStatus:
        """
        Get comprehensive Docker engine status.

        Returns:
            DockerEngineStatus object with detailed engine information

        Raises:
            Exception: If status check fails completely
        """
        try:
            # Check cache first
            if (self._cached_status and self._last_status_check and
                (datetime.utcnow() - self._last_status_check).total_seconds() < self._status_cache_ttl):
                return self._cached_status

            # Check if Docker daemon is running
            docker_available = await self._check_docker_availability()

            if not docker_available:
                status = DockerEngineStatus(
                    available=False,
                    running=False,
                    error="Docker daemon not available or not responding"
                )
                self._cache_status(status)
                return status

            # Get detailed Docker information
            version_info = await self._get_docker_version()
            container_stats = await self._get_container_statistics()

            status = DockerEngineStatus(
                available=True,
                running=True,
                version=version_info.get('version'),
                api_version=version_info.get('api_version'),
                containers_running=container_stats.get('running', 0),
                containers_paused=container_stats.get('paused', 0),
                containers_stopped=container_stats.get('stopped', 0),
                images_count=container_stats.get('images', 0),
                last_checked=datetime.utcnow()
            )

            self._cache_status(status)
            logger.debug("Docker status retrieved successfully")
            return status

        except Exception as e:
            logger.error(f"Error getting Docker status: {str(e)}")
            error_status = DockerEngineStatus(
                available=False,
                running=False,
                error=str(e),
                last_checked=datetime.utcnow()
            )
            self._cache_status(error_status)
            return error_status

    async def start_docker_engine(self) -> DockerServiceResponse:
        """
        Start Docker engine service.

        Returns:
            DockerServiceResponse with operation results

        Raises:
            Exception: If start operation fails
        """
        start_time = time.time()

        try:
            logger.info("Starting Docker engine...")

            # Check if Docker is already running
            current_status = await self.get_docker_status()
            if current_status.running:
                execution_time = time.time() - start_time
                return DockerServiceResponse(
                    success=True,
                    action="start",
                    status="already_running",
                    message="Docker engine is already running",
                    engine_status=current_status,
                    execution_time=execution_time
                )

            # Attempt to start Docker service based on the system
            start_success = await self._start_docker_service()

            if start_success:
                # Wait for Docker to be ready
                ready = await self._wait_for_docker_ready(timeout=60)

                if ready:
                    final_status = await self.get_docker_status()
                    execution_time = time.time() - start_time

                    return DockerServiceResponse(
                        success=True,
                        action="start",
                        status="started",
                        message="Docker engine started successfully",
                        engine_status=final_status,
                        execution_time=execution_time
                    )
                else:
                    execution_time = time.time() - start_time
                    return DockerServiceResponse(
                        success=False,
                        action="start",
                        status="timeout",
                        error="Docker engine start timeout - service may still be starting",
                        execution_time=execution_time
                    )
            else:
                execution_time = time.time() - start_time
                return DockerServiceResponse(
                    success=False,
                    action="start",
                    status="failed",
                    error="Failed to start Docker engine service",
                    execution_time=execution_time
                )

        except Exception as e:
            execution_time = time.time() - start_time
            logger.error(f"Error starting Docker engine: {str(e)}")
            return DockerServiceResponse(
                success=False,
                action="start",
                status="error",
                error=f"Docker start failed: {str(e)}",
                execution_time=execution_time
            )

    async def stop_docker_engine(self) -> DockerServiceResponse:
        """
        Stop Docker engine service.

        Returns:
            DockerServiceResponse with operation results

        Raises:
            Exception: If stop operation fails
        """
        start_time = time.time()

        try:
            logger.info("Stopping Docker engine...")

            # Check if Docker is running
            current_status = await self.get_docker_status()
            if not current_status.running:
                execution_time = time.time() - start_time
                return DockerServiceResponse(
                    success=True,
                    action="stop",
                    status="already_stopped",
                    message="Docker engine is already stopped",
                    engine_status=current_status,
                    execution_time=execution_time
                )

            # Attempt to stop Docker service
            stop_success = await self._stop_docker_service()

            if stop_success:
                # Wait for Docker to be stopped
                stopped = await self._wait_for_docker_stopped(timeout=30)

                execution_time = time.time() - start_time
                final_status = await self.get_docker_status()

                if stopped:
                    return DockerServiceResponse(
                        success=True,
                        action="stop",
                        status="stopped",
                        message="Docker engine stopped successfully",
                        engine_status=final_status,
                        execution_time=execution_time
                    )
                else:
                    return DockerServiceResponse(
                        success=False,
                        action="stop",
                        status="timeout",
                        error="Docker engine stop timeout - service may still be stopping",
                        engine_status=final_status,
                        execution_time=execution_time
                    )
            else:
                execution_time = time.time() - start_time
                return DockerServiceResponse(
                    success=False,
                    action="stop",
                    status="failed",
                    error="Failed to stop Docker engine service",
                    execution_time=execution_time
                )

        except Exception as e:
            execution_time = time.time() - start_time
            logger.error(f"Error stopping Docker engine: {str(e)}")
            return DockerServiceResponse(
                success=False,
                action="stop",
                status="error",
                error=f"Docker stop failed: {str(e)}",
                execution_time=execution_time
            )

    async def restart_docker_engine(self) -> DockerServiceResponse:
        """
        Restart Docker engine service.

        Returns:
            DockerServiceResponse with operation results

        Raises:
            Exception: If restart operation fails
        """
        start_time = time.time()

        try:
            logger.info("Restarting Docker engine...")

            # Stop Docker first
            stop_response = await self.stop_docker_engine()

            if not stop_response.success and stop_response.status != "already_stopped":
                execution_time = time.time() - start_time
                return DockerServiceResponse(
                    success=False,
                    action="restart",
                    status="stop_failed",
                    error=f"Failed to stop Docker during restart: {stop_response.error}",
                    execution_time=execution_time
                )

            # Small delay to ensure clean shutdown
            await asyncio.sleep(2)

            # Start Docker
            start_response = await self.start_docker_engine()

            execution_time = time.time() - start_time

            if start_response.success:
                return DockerServiceResponse(
                    success=True,
                    action="restart",
                    status="restarted",
                    message="Docker engine restarted successfully",
                    engine_status=start_response.engine_status,
                    execution_time=execution_time
                )
            else:
                return DockerServiceResponse(
                    success=False,
                    action="restart",
                    status="start_failed",
                    error=f"Failed to start Docker during restart: {start_response.error}",
                    execution_time=execution_time
                )

        except Exception as e:
            execution_time = time.time() - start_time
            logger.error(f"Error restarting Docker engine: {str(e)}")
            return DockerServiceResponse(
                success=False,
                action="restart",
                status="error",
                error=f"Docker restart failed: {str(e)}",
                execution_time=execution_time
            )

    async def process_service_request(self, request: DockerServiceRequest) -> DockerServiceResponse:
        """
        Process a Docker service control request.

        Args:
            request: DockerServiceRequest with action and parameters

        Returns:
            DockerServiceResponse with operation results

        Raises:
            Exception: If request processing fails
        """
        try:
            logger.info(f"Processing Docker service request: {request.action}")

            if request.action == "start":
                return await self.start_docker_engine()
            elif request.action == "stop":
                return await self.stop_docker_engine()
            elif request.action == "restart":
                return await self.restart_docker_engine()
            elif request.action == "status":
                status = await self.get_docker_status()
                return DockerServiceResponse(
                    success=True,
                    action="status",
                    status="retrieved",
                    message="Docker status retrieved successfully",
                    engine_status=status,
                    execution_time=0.0
                )
            else:
                return DockerServiceResponse(
                    success=False,
                    action=request.action,
                    status="invalid_action",
                    error=f"Invalid Docker service action: {request.action}",
                    execution_time=0.0
                )

        except Exception as e:
            logger.error(f"Error processing Docker service request: {str(e)}")
            return DockerServiceResponse(
                success=False,
                action=request.action,
                status="error",
                error=f"Request processing failed: {str(e)}",
                execution_time=0.0
            )

    def _cache_status(self, status: DockerEngineStatus) -> None:
        """Cache Docker status with timestamp."""
        self._cached_status = status
        self._last_status_check = datetime.utcnow()

    async def _check_docker_availability(self) -> bool:
        """
        Check if Docker daemon is available and responding.

        Returns:
            True if Docker is available, False otherwise
        """
        try:
            result = await asyncio.create_subprocess_exec(
                'docker', 'version', '--format', 'json',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            stdout, stderr = await asyncio.wait_for(
                result.communicate(),
                timeout=10.0
            )

            return result.returncode == 0

        except (asyncio.TimeoutError, FileNotFoundError, Exception) as e:
            logger.debug(f"Docker availability check failed: {str(e)}")
            return False

    async def _get_docker_version(self) -> Dict[str, str]:
        """
        Get Docker version information.

        Returns:
            Dictionary with version and API version
        """
        try:
            result = await asyncio.create_subprocess_exec(
                'docker', 'version', '--format', 'json',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            stdout, stderr = await asyncio.wait_for(
                result.communicate(),
                timeout=10.0
            )

            if result.returncode == 0:
                version_data = json.loads(stdout.decode())
                client = version_data.get('Client', {})
                server = version_data.get('Server', {})

                return {
                    'version': server.get('Version', client.get('Version', 'unknown')),
                    'api_version': server.get('ApiVersion', client.get('ApiVersion', 'unknown'))
                }

        except Exception as e:
            logger.debug(f"Error getting Docker version: {str(e)}")

        return {'version': 'unknown', 'api_version': 'unknown'}

    async def _get_container_statistics(self) -> Dict[str, int]:
        """
        Get container and image statistics.

        Returns:
            Dictionary with container and image counts
        """
        stats = {'running': 0, 'paused': 0, 'stopped': 0, 'images': 0}

        try:
            # Get container stats
            result = await asyncio.create_subprocess_exec(
                'docker', 'ps', '--all', '--format', 'json',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            stdout, stderr = await asyncio.wait_for(
                result.communicate(),
                timeout=15.0
            )

            if result.returncode == 0:
                lines = stdout.decode().strip().split('\n')
                for line in lines:
                    if line.strip():
                        try:
                            container_data = json.loads(line)
                            status = container_data.get('Status', '').lower()

                            if 'up' in status:
                                stats['running'] += 1
                            elif 'paused' in status:
                                stats['paused'] += 1
                            else:
                                stats['stopped'] += 1
                        except json.JSONDecodeError:
                            continue

            # Get image count
            result = await asyncio.create_subprocess_exec(
                'docker', 'images', '--quiet',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            stdout, stderr = await asyncio.wait_for(
                result.communicate(),
                timeout=10.0
            )

            if result.returncode == 0:
                images = stdout.decode().strip().split('\n')
                stats['images'] = len([img for img in images if img.strip()])

        except Exception as e:
            logger.debug(f"Error getting container statistics: {str(e)}")

        return stats

    async def _start_docker_service(self) -> bool:
        """
        Start Docker service using system service manager.

        Returns:
            True if start command succeeded, False otherwise
        """
        try:
            # Try systemctl first (Linux)
            result = await asyncio.create_subprocess_exec(
                'systemctl', 'start', 'docker',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            stdout, stderr = await asyncio.wait_for(
                result.communicate(),
                timeout=30.0
            )

            if result.returncode == 0:
                logger.info("Docker service started via systemctl")
                return True

        except (FileNotFoundError, asyncio.TimeoutError):
            pass

        try:
            # Try service command (older Linux)
            result = await asyncio.create_subprocess_exec(
                'service', 'docker', 'start',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            stdout, stderr = await asyncio.wait_for(
                result.communicate(),
                timeout=30.0
            )

            if result.returncode == 0:
                logger.info("Docker service started via service command")
                return True

        except (FileNotFoundError, asyncio.TimeoutError):
            pass

        try:
            # Try Docker Desktop (macOS/Windows)
            result = await asyncio.create_subprocess_exec(
                'open', '-a', 'Docker',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            stdout, stderr = await asyncio.wait_for(
                result.communicate(),
                timeout=10.0
            )

            if result.returncode == 0:
                logger.info("Docker Desktop started via open command")
                return True

        except (FileNotFoundError, asyncio.TimeoutError):
            pass

        logger.warning("Could not start Docker service - no suitable method found")
        return False

    async def _stop_docker_service(self) -> bool:
        """
        Stop Docker service using system service manager.

        Returns:
            True if stop command succeeded, False otherwise
        """
        try:
            # Try systemctl first (Linux)
            result = await asyncio.create_subprocess_exec(
                'systemctl', 'stop', 'docker',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            stdout, stderr = await asyncio.wait_for(
                result.communicate(),
                timeout=30.0
            )

            if result.returncode == 0:
                logger.info("Docker service stopped via systemctl")
                return True

        except (FileNotFoundError, asyncio.TimeoutError):
            pass

        try:
            # Try service command (older Linux)
            result = await asyncio.create_subprocess_exec(
                'service', 'docker', 'stop',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            stdout, stderr = await asyncio.wait_for(
                result.communicate(),
                timeout=30.0
            )

            if result.returncode == 0:
                logger.info("Docker service stopped via service command")
                return True

        except (FileNotFoundError, asyncio.TimeoutError):
            pass

        # For Docker Desktop, stopping is more complex and may not be directly supported
        logger.warning("Could not stop Docker service - no suitable method found or Docker Desktop running")
        return False

    async def _wait_for_docker_ready(self, timeout: int = 60) -> bool:
        """
        Wait for Docker daemon to be ready.

        Args:
            timeout: Maximum time to wait in seconds

        Returns:
            True if Docker becomes ready, False if timeout
        """
        start_time = time.time()

        while time.time() - start_time < timeout:
            try:
                if await self._check_docker_availability():
                    logger.info(f"Docker ready after {time.time() - start_time:.1f} seconds")
                    return True

                await asyncio.sleep(2)

            except Exception:
                await asyncio.sleep(2)

        logger.warning(f"Docker not ready after {timeout} seconds")
        return False

    async def _wait_for_docker_stopped(self, timeout: int = 30) -> bool:
        """
        Wait for Docker daemon to be stopped.

        Args:
            timeout: Maximum time to wait in seconds

        Returns:
            True if Docker stops, False if timeout
        """
        start_time = time.time()

        while time.time() - start_time < timeout:
            try:
                if not await self._check_docker_availability():
                    logger.info(f"Docker stopped after {time.time() - start_time:.1f} seconds")
                    return True

                await asyncio.sleep(1)

            except Exception:
                return True  # If we can't check, assume it's stopped

        logger.warning(f"Docker still running after {timeout} seconds")
        return False