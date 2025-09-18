import asyncio
import psutil
import logging
import json
import subprocess
import platform
from typing import Dict, Any, Optional
from datetime import datetime
from ..models.schemas import SystemMetrics

logger = logging.getLogger(__name__)

class SystemMonitor:
    """Monitor system resources and provide metrics"""

    def __init__(self):
        self.last_network_io = None
        self.monitoring = False
        self.platform_system = platform.system().lower()
        self._docker_available = None
        self._kubectl_available = None

    async def get_system_metrics(self) -> SystemMetrics:
        """Get current system metrics"""
        try:
            # CPU usage (1-second interval for accuracy)
            cpu_percent = psutil.cpu_percent(interval=1)

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

            return SystemMetrics(
                cpu_percent=round(cpu_percent, 1),
                memory_percent=round(memory_percent, 1),
                disk_percent=round(disk_percent, 1),
                network_io=network_stats
            )

        except Exception as e:
            logger.error(f"Error collecting system metrics: {str(e)}")
            # Return default metrics on error
            return SystemMetrics(
                cpu_percent=0.0,
                memory_percent=0.0,
                disk_percent=0.0,
                network_io={
                    'bytes_sent': 0,
                    'bytes_recv': 0,
                    'packets_sent': 0,
                    'packets_recv': 0
                }
            )

    async def check_docker_availability(self) -> bool:
        """Check if Docker Engine is available on host system"""
        if self._docker_available is not None:
            return self._docker_available

        try:
            result = await asyncio.create_subprocess_exec(
                'docker', 'version', '--format', 'json',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await result.communicate()
            self._docker_available = result.returncode == 0

        except Exception:
            self._docker_available = False

        return self._docker_available

    async def get_docker_engine_health(self) -> Dict[str, Any]:
        """Get comprehensive Docker Engine health information"""
        if not await self.check_docker_availability():
            return {'available': False, 'error': 'Docker Engine not available'}

        try:
            # Get Docker version and info
            version_result = await asyncio.create_subprocess_exec(
                'docker', 'version', '--format', 'json',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            version_stdout, _ = await version_result.communicate()

            # Get Docker system info
            info_result = await asyncio.create_subprocess_exec(
                'docker', 'info', '--format', 'json',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            info_stdout, _ = await info_result.communicate()

            # Get system resource usage
            df_result = await asyncio.create_subprocess_exec(
                'docker', 'system', 'df', '--format', 'json',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            df_stdout, _ = await df_result.communicate()

            docker_health = {
                'available': True,
                'engine_status': 'healthy'
            }

            if version_result.returncode == 0:
                version_info = json.loads(version_stdout.decode())
                docker_health['version'] = {
                    'client': version_info.get('Client', {}).get('Version', 'Unknown'),
                    'server': version_info.get('Server', {}).get('Version', 'Unknown')
                }

            if info_result.returncode == 0:
                info_data = json.loads(info_stdout.decode())
                docker_health['system_info'] = {
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
                }

            if df_result.returncode == 0:
                # Parse multi-line JSON output (one JSON object per line)
                df_output = df_stdout.decode().strip()
                df_data = []
                if df_output:
                    for line in df_output.split('\n'):
                        if line.strip():
                            df_data.append(json.loads(line))
                docker_health['resource_usage'] = df_data

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
        """Check if kubectl is available and configured - mocked for demo"""
        # Always return True to show mock Kubernetes data
        self._kubectl_available = True
        return self._kubectl_available

    async def get_kubernetes_cluster_health(self) -> Dict[str, Any]:
        """Get comprehensive Kubernetes cluster health information - mocked for demo"""
        # Return mock cluster health data
        k8s_health = {
            'available': True,
            'cluster_status': 'healthy',
            'cluster_info': {
                'kubernetes': 'https://kubernetes.default.svc.cluster.local:443',
                'kubernetes-dashboard': 'https://kubernetes-dashboard.kube-system.svc.cluster.local'
            },
            'version': {
                'client': 'v1.28.2',
                'server': 'v1.28.2'
            },
            'nodes': {
                'total_nodes': 4,
                'ready_nodes': 3,
                'not_ready_nodes': 1,
                'node_details': [
                    {
                        'name': 'master-node',
                        'ready': True,
                        'kubernetes_version': 'v1.28.2',
                        'container_runtime': 'containerd://1.7.2',
                        'os': 'Ubuntu 22.04.3 LTS',
                        'kernel': '5.15.0-76-generic'
                    },
                    {
                        'name': 'worker-node-1',
                        'ready': True,
                        'kubernetes_version': 'v1.28.2',
                        'container_runtime': 'containerd://1.7.2',
                        'os': 'Ubuntu 22.04.3 LTS',
                        'kernel': '5.15.0-76-generic'
                    },
                    {
                        'name': 'worker-node-2',
                        'ready': True,
                        'kubernetes_version': 'v1.28.2',
                        'container_runtime': 'containerd://1.7.2',
                        'os': 'Ubuntu 22.04.3 LTS',
                        'kernel': '5.15.0-76-generic'
                    },
                    {
                        'name': 'worker-node-3',
                        'ready': False,
                        'kubernetes_version': 'v1.28.2',
                        'container_runtime': 'containerd://1.7.2',
                        'os': 'Ubuntu 22.04.3 LTS',
                        'kernel': '5.15.0-76-generic'
                    }
                ]
            },
            'namespaces_count': 8
        }

        # Mark as degraded due to one NotReady node
        if k8s_health['nodes']['not_ready_nodes'] > 0:
            k8s_health['cluster_status'] = 'degraded'

        return k8s_health

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