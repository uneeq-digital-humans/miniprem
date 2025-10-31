import asyncio
import psutil
import logging
import json
import subprocess
import platform
import docker
from typing import Dict, Any, Optional
from datetime import datetime
from ..models.schemas import SystemMetrics, GpuStats
from .gpu_monitor import detect_and_parse_gpus

logger = logging.getLogger(__name__)

class SystemMonitor:
    """Monitor system resources and provide metrics"""

    def __init__(self):
        self.last_network_io = None
        self.monitoring = False
        self.platform_system = platform.system().lower()
        self._docker_available = None
        self._kubectl_available = None
        self._docker_client = None
        # GPU polling cache (15-second interval as per requirements)
        self._gpu_cache = []
        self._gpu_cache_time = None
        self._gpu_cache_ttl = 15  # seconds

    def _get_docker_client(self):
        """Get or create Docker client instance (stub - using CLI commands instead)"""
        # Note: Returning None to indicate CLI-based approach should be used
        # The Docker Python SDK has compatibility issues with urllib3<2.0
        # which is required by Kubernetes SDK
        return None

    async def _get_gpu_stats(self):
        """
        Get GPU statistics with 15-second caching.

        Polls nvidia-smi every 15 seconds to get GPU stats. Returns cached data
        if available within TTL window. Falls back to empty list if nvidia-smi
        fails or is not available.

        Returns:
            List[GpuStats]: List of GPU statistics, empty if no GPUs or nvidia-smi unavailable.
        """
        now = datetime.now()

        # Return cached data if still valid
        if (self._gpu_cache_time is not None and
            (now - self._gpu_cache_time).total_seconds() < self._gpu_cache_ttl):
            return self._gpu_cache

        # Poll for new GPU data
        try:
            gpu_data_list = detect_and_parse_gpus()

            # Convert to GpuStats Pydantic models
            self._gpu_cache = [
                GpuStats(
                    index=gpu.index,
                    name=gpu.name,
                    temperature_celsius=gpu.temperature_celsius,
                    utilization_percent=gpu.utilization_percent,
                    memory_used_mb=gpu.memory_used_mb,
                    memory_total_mb=gpu.memory_total_mb,
                    power_watts=gpu.power_watts,
                    clock_graphics_mhz=gpu.clock_graphics_mhz,
                    clock_memory_mhz=gpu.clock_memory_mhz,
                    fan_speed_percent=gpu.fan_speed_percent
                )
                for gpu in gpu_data_list
            ]
            self._gpu_cache_time = now

            if self._gpu_cache:
                logger.debug(f"GPU cache updated with {len(self._gpu_cache)} GPU(s)")

        except Exception as e:
            logger.error(f"Error polling GPU stats: {str(e)}")
            self._gpu_cache = []
            self._gpu_cache_time = now

        return self._gpu_cache

    async def get_system_metrics(self) -> SystemMetrics:
        """
        Get current system metrics including per-core CPU usage and GPU stats.

        Collects comprehensive system metrics with short sampling intervals
        to avoid blocking the event loop. Per-core CPU data enables verification
        of multi-threading in Docker containers. GPU stats are polled every 15
        seconds with caching.

        Returns:
            SystemMetrics: Complete system metrics with overall and per-core CPU data,
                          and GPU statistics (empty list if no GPUs or nvidia-smi unavailable).

        Raises:
            Exception: Logs errors and returns default metrics on failure.
        """
        try:
            # CPU usage with per-core breakdown (0.1-second interval for responsiveness)
            # Using short interval to avoid blocking the async event loop
            cpu_percent = psutil.cpu_percent(interval=0.1)
            cpu_per_core = psutil.cpu_percent(interval=0.1, percpu=True)

            # Memory usage
            memory = psutil.virtual_memory()
            memory_percent = memory.percent

            # Disk usage (root partition)
            disk = psutil.disk_usage('/')
            disk_percent = (disk.used / disk.total) * 100

            # Network I/O
            network_io = psutil.net_io_counters()
            network_stats = {
                'bytes_sent': network_io.bytes_sent,
                'bytes_recv': network_io.bytes_recv,
                'packets_sent': network_io.packets_sent,
                'packets_recv': network_io.packets_recv
            }

            # GPU stats (15-second polling with cache)
            gpu_stats = await self._get_gpu_stats()

            return SystemMetrics(
                cpu_percent=round(cpu_percent, 1),
                cpu_per_core=[round(core, 1) for core in cpu_per_core],
                memory_percent=round(memory_percent, 1),
                disk_percent=round(disk_percent, 1),
                network_io=network_stats,
                gpus=gpu_stats
            )

        except Exception as e:
            logger.error(f"Error collecting system metrics: {str(e)}")
            # Return default metrics on error
            return SystemMetrics(
                cpu_percent=0.0,
                cpu_per_core=[],
                memory_percent=0.0,
                disk_percent=0.0,
                network_io={
                    'bytes_sent': 0,
                    'bytes_recv': 0,
                    'packets_sent': 0,
                    'packets_recv': 0
                },
                gpus=[]
            )

    async def check_docker_availability(self) -> bool:
        """Check if Docker Engine is available on host system"""
        if self._docker_available is not None:
            return self._docker_available

        try:
            client = self._get_docker_client()
            if client is not None:
                # Try to ping Docker
                client.ping()
                self._docker_available = True
            else:
                self._docker_available = False

        except Exception as e:
            logger.error(f"Docker availability check failed: {str(e)}")
            self._docker_available = False

        return self._docker_available

    async def get_docker_engine_health(self) -> Dict[str, Any]:
        """Get comprehensive Docker Engine health information using Docker SDK"""
        if not await self.check_docker_availability():
            return {'available': False, 'error': 'Docker Engine not available'}

        try:
            client = self._get_docker_client()
            if client is None:
                return {'available': False, 'error': 'Cannot connect to Docker'}

            # Get Docker version info
            version_info = client.version()

            # Get Docker system info
            info_data = client.info()

            # Get system resource usage using df()
            df_data = client.df()

            docker_health = {
                'available': True,
                'engine_status': 'healthy',
                'version': {
                    'client': version_info.get('Version', 'Unknown'),
                    'server': version_info.get('Version', 'Unknown'),
                    'api_version': version_info.get('ApiVersion', 'Unknown')
                },
                'system_info': {
                    'containers_running': info_data.get('ContainersRunning', 0),
                    'containers_paused': info_data.get('ContainersPaused', 0),
                    'containers_stopped': info_data.get('ContainersStopped', 0),
                    'images': info_data.get('Images', 0),
                    'server_version': info_data.get('ServerVersion', 'Unknown'),
                    'storage_driver': info_data.get('Driver', 'Unknown'),
                    'logging_driver': info_data.get('LoggingDriver', 'Unknown'),
                    'cgroup_driver': info_data.get('CgroupDriver', 'Unknown'),
                    'kernel_version': info_data.get('KernelVersion', 'Unknown'),
                    'operating_system': info_data.get('OperatingSystem', 'Unknown'),
                    'cpu_count': info_data.get('NCPU', 0),
                    'memory_total': info_data.get('MemTotal', 0)
                },
                'resource_usage': {
                    'images': df_data.get('Images', []),
                    'containers': df_data.get('Containers', []),
                    'volumes': df_data.get('Volumes', [])
                }
            }

            return docker_health

        except Exception as e:
            logger.error(f"Error getting Docker Engine health: {str(e)}")
            return {
                'available': True,
                'engine_status': 'error',
                'error': str(e)
            }

    async def get_docker_system_info(self) -> Dict[str, Any]:
        """Get Docker system information if available (legacy compatibility)"""
        health_info = await self.get_docker_engine_health()
        if health_info.get('available'):
            return {
                'available': True,
                'system_df': health_info.get('resource_usage', {})
            }
        return health_info

    async def check_kubectl_availability(self) -> bool:
        """Check if kubectl is available and configured"""
        if self._kubectl_available is not None:
            return self._kubectl_available

        try:
            result = await asyncio.create_subprocess_exec(
                'kubectl', 'version', '--client', '--output=json',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await result.communicate()

            if result.returncode == 0:
                # Check if we can actually connect to a cluster
                cluster_result = await asyncio.create_subprocess_exec(
                    'kubectl', 'cluster-info', '--request-timeout=5s',
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE
                )
                cluster_stdout, cluster_stderr = await cluster_result.communicate()

                self._kubectl_available = cluster_result.returncode == 0
                if self._kubectl_available:
                    logger.info("kubectl is available and cluster is accessible")
                else:
                    logger.warning(f"kubectl available but no accessible cluster: {cluster_stderr.decode()}")
            else:
                self._kubectl_available = False
                logger.warning(f"kubectl not available: {stderr.decode()}")

        except Exception as e:
            logger.error(f"Error checking kubectl availability: {str(e)}")
            self._kubectl_available = False

        return self._kubectl_available

    async def get_kubernetes_cluster_health(self) -> Dict[str, Any]:
        """Get comprehensive Kubernetes cluster health information"""
        try:
            if not await self.check_kubectl_availability():
                return {'available': False, 'error': 'kubectl not available or no cluster accessible'}

            # Get cluster info
            info_result = await asyncio.create_subprocess_exec(
                'kubectl', 'cluster-info', '--output=json',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            info_stdout, info_stderr = await info_result.communicate()

            # Get version info
            version_result = await asyncio.create_subprocess_exec(
                'kubectl', 'version', '--output=json',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            version_stdout, version_stderr = await version_result.communicate()

            # Get node info
            nodes_result = await asyncio.create_subprocess_exec(
                'kubectl', 'get', 'nodes', '-o', 'json',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            nodes_stdout, nodes_stderr = await nodes_result.communicate()

            # Get namespace count
            ns_result = await asyncio.create_subprocess_exec(
                'kubectl', 'get', 'namespaces', '-o', 'json',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            ns_stdout, ns_stderr = await ns_result.communicate()

            k8s_health = {
                'available': True,
                'cluster_status': 'healthy'
            }

            if version_result.returncode == 0:
                try:
                    version_data = json.loads(version_stdout.decode())
                    k8s_health['version'] = {
                        'client': version_data.get('clientVersion', {}).get('gitVersion', 'Unknown'),
                        'server': version_data.get('serverVersion', {}).get('gitVersion', 'Unknown')
                    }
                except json.JSONDecodeError:
                    k8s_health['version'] = {'client': 'Unknown', 'server': 'Unknown'}

            if info_result.returncode == 0:
                try:
                    info_data = json.loads(info_stdout.decode())
                    k8s_health['cluster_info'] = info_data
                except json.JSONDecodeError:
                    # If JSON parsing fails, try to parse text output
                    info_text = info_stdout.decode().strip()
                    k8s_health['cluster_info'] = {'raw_output': info_text}

            if nodes_result.returncode == 0:
                try:
                    nodes_data = json.loads(nodes_stdout.decode())
                    nodes = nodes_data.get('items', [])

                    total_nodes = len(nodes)
                    ready_nodes = 0
                    node_details = []

                    for node in nodes:
                        metadata = node.get('metadata', {})
                        status = node.get('status', {})

                        # Check if node is ready
                        is_ready = False
                        for condition in status.get('conditions', []):
                            if condition.get('type') == 'Ready' and condition.get('status') == 'True':
                                is_ready = True
                                break

                        if is_ready:
                            ready_nodes += 1

                        node_details.append({
                            'name': metadata.get('name', 'Unknown'),
                            'ready': is_ready,
                            'kubernetes_version': status.get('nodeInfo', {}).get('kubeletVersion', 'Unknown'),
                            'container_runtime': status.get('nodeInfo', {}).get('containerRuntimeVersion', 'Unknown'),
                            'os': status.get('nodeInfo', {}).get('operatingSystem', 'Unknown'),
                            'kernel': status.get('nodeInfo', {}).get('kernelVersion', 'Unknown')
                        })

                    not_ready_nodes = total_nodes - ready_nodes

                    k8s_health['nodes'] = {
                        'total_nodes': total_nodes,
                        'ready_nodes': ready_nodes,
                        'not_ready_nodes': not_ready_nodes,
                        'node_details': node_details
                    }

                    # Set cluster status based on node health
                    if not_ready_nodes > 0:
                        k8s_health['cluster_status'] = 'degraded'
                    if ready_nodes == 0:
                        k8s_health['cluster_status'] = 'unhealthy'

                except json.JSONDecodeError:
                    k8s_health['nodes'] = {'error': 'Failed to parse node data'}

            if ns_result.returncode == 0:
                try:
                    ns_data = json.loads(ns_stdout.decode())
                    k8s_health['namespaces_count'] = len(ns_data.get('items', []))
                except json.JSONDecodeError:
                    k8s_health['namespaces_count'] = 0

            return k8s_health

        except Exception as e:
            logger.error(f"Error getting Kubernetes cluster health: {str(e)}")
            return {
                'available': False,
                'error': str(e)
            }

    async def get_kubernetes_cluster_info(self) -> Dict[str, Any]:
        """Get Kubernetes cluster information if available (legacy compatibility)"""
        health_info = await self.get_kubernetes_cluster_health()
        if health_info.get('available'):
            return {
                'available': True,
                'cluster_info': health_info.get('cluster_info', {})
            }
        return health_info

    async def get_process_info(self) -> Dict[str, Any]:
        """Get information about running processes"""
        try:
            processes = []
            for proc in psutil.process_iter(['pid', 'name', 'cpu_percent', 'memory_percent']):
                try:
                    proc_info = proc.info
                    # Handle None values from psutil (race conditions)
                    cpu_percent = proc_info['cpu_percent'] or 0.0
                    memory_percent = proc_info['memory_percent'] or 0.0

                    # Only include processes using significant resources
                    if cpu_percent > 1.0 or memory_percent > 1.0:
                        processes.append({
                            'pid': proc_info['pid'],
                            'name': proc_info['name'] or 'Unknown',
                            'cpu_percent': round(cpu_percent, 1),
                            'memory_percent': round(memory_percent, 1)
                        })
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    continue

            # Sort by CPU usage (safe comparison now)
            processes.sort(key=lambda x: x['cpu_percent'], reverse=True)

            return {
                'total_processes': len(list(psutil.process_iter())),
                'high_usage_processes': processes[:10]  # Top 10
            }

        except Exception as e:
            logger.error(f"Error collecting process info: {str(e)}")
            return {
                'total_processes': 0,
                'high_usage_processes': []
            }

    def get_system_info(self) -> Dict[str, Any]:
        """Get static system information including Docker and Kubernetes availability"""
        try:
            boot_time = datetime.fromtimestamp(psutil.boot_time())
            uptime = datetime.now() - boot_time

            # Get Docker availability
            docker_info = self._check_docker_availability()

            # Get Kubernetes availability
            kubernetes_info = self._check_kubernetes_availability()

            return {
                'platform': platform.system().lower(),
                'cpu_count': psutil.cpu_count(),
                'cpu_count_logical': psutil.cpu_count(logical=True),
                'memory_total_gb': round(psutil.virtual_memory().total / (1024**3), 2),
                'disk_total_gb': round(psutil.disk_usage('/').total / (1024**3), 2),
                'boot_time': boot_time.isoformat(),
                'uptime_hours': round(uptime.total_seconds() / 3600, 1),
                'docker': docker_info,
                'kubernetes': kubernetes_info
            }

        except Exception as e:
            logger.error(f"Error collecting system info: {str(e)}")
            return {
                'platform': 'unknown',
                'cpu_count': 0,
                'cpu_count_logical': 0,
                'memory_total_gb': 0,
                'disk_total_gb': 0,
                'boot_time': datetime.now().isoformat(),
                'uptime_hours': 0,
                'docker': {'available': False, 'error': 'System info collection failed'},
                'kubernetes': {'available': False, 'error': 'System info collection failed'}
            }

    def _check_docker_availability(self) -> Dict[str, Any]:
        """Check if Docker is available and accessible"""
        try:
            result = subprocess.run(['docker', 'version', '--format', 'json'],
                                  capture_output=True, text=True, timeout=5)
            if result.returncode == 0:
                return {'available': True}
            else:
                return {'available': False, 'error': 'Docker not responding'}
        except subprocess.TimeoutExpired:
            return {'available': False, 'error': 'Docker command timeout'}
        except FileNotFoundError:
            return {'available': False, 'error': 'Docker not installed'}
        except Exception as e:
            return {'available': False, 'error': f'Docker check failed: {str(e)}'}

    def _check_kubernetes_availability(self) -> Dict[str, Any]:
        """Check if Kubernetes is available and accessible"""
        try:
            result = subprocess.run(['kubectl', 'version', '--client', '--output=json'],
                                  capture_output=True, text=True, timeout=5)
            if result.returncode == 0:
                # Check if we can actually connect to a cluster
                cluster_result = subprocess.run(['kubectl', 'cluster-info'],
                                              capture_output=True, text=True, timeout=5)
                if cluster_result.returncode == 0:
                    return {'available': True}
                else:
                    return {'available': False, 'error': 'No Kubernetes cluster accessible'}
            else:
                return {'available': False, 'error': 'kubectl not responding'}
        except subprocess.TimeoutExpired:
            return {'available': False, 'error': 'Kubernetes command timeout'}
        except FileNotFoundError:
            return {'available': False, 'error': 'kubectl not installed'}
        except Exception as e:
            return {'available': False, 'error': f'Kubernetes check failed: {str(e)}'}