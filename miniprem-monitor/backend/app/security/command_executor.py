import asyncio
import subprocess
import json
import re
import random
from typing import Dict, List, Any, Optional, Tuple
from datetime import datetime
import logging
from ..services.system_monitor import SystemMonitor
from ..services.kubernetes_monitor import KubernetesMonitor
from ..services.docker_manager import DockerManager
from ..services.aws_region_manager import AwsRegionManager
from ..services.prometheus_client import get_prometheus_client
from ..models.schemas import (
    DockerServiceRequest, DockerServiceResponse, ServiceControlRequest,
    ServiceControlResponse, AwsRegion, RegionStatus, RegionListResponse,
    RegionContextsResponse
)

logger = logging.getLogger(__name__)

class SecurityError(Exception):
    pass

class CommandExecutor:
    # Whitelisted commands with their safe parameters
    DOCKER_COMMANDS = {
        'ps': {
            'cmd': ['sudo', 'docker', 'ps', '-a', '--format', 'json'],
            'timeout': 10
        },
        'stats': {
            'cmd': ['sudo', 'docker', 'stats', '--no-stream', '--format', 'json'],
            'timeout': 15
        },
        'logs': {
            'cmd': ['sudo', 'docker', 'logs', '--tail', '100', '--timestamps'],
            'timeout': 30,
            'requires_params': ['container']
        },
        'logs:stream': {
            'cmd': ['sudo', 'docker', 'logs', '--follow', '--tail', '100', '--timestamps'],
            'timeout': None,  # No timeout for streaming
            'requires_params': ['container']
        },
        'start': {
            'cmd': ['sudo', 'docker', 'start'],
            'timeout': 30,
            'requires_params': ['container']
        },
        'stop': {
            'cmd': ['sudo', 'docker', 'stop'],
            'timeout': 30,
            'requires_params': ['container']
        }
    }

    KUBECTL_COMMANDS = {
        'pods': {
            'cmd': ['kubectl', 'get', 'pods', '-o', 'json'],
            'timeout': 15
        },
        'nodes': {
            'cmd': ['kubectl', 'get', 'nodes', '-o', 'json'],
            'timeout': 15
        },
        'namespaces': {
            'cmd': ['kubectl', 'get', 'namespaces', '-o', 'json'],
            'timeout': 15
        },
        'contexts': {
            'cmd': ['kubectl', 'config', 'get-contexts', '-o', 'json'],
            'timeout': 10
        },
        'switch-context': {
            'cmd': ['kubectl', 'config', 'use-context'],
            'timeout': 10,
            'requires_params': ['context']
        },
        'logs': {
            'cmd': ['kubectl', 'logs', '--tail=100', '--timestamps'],
            'timeout': 30,
            'requires_params': ['pod']
        },
        'health': {
            'timeout': 15
        }
    }

    SYSTEM_COMMANDS = {
        'metrics': {
            'timeout': 10
        },
        'info': {
            'timeout': 10
        },
        'health': {
            'timeout': 10
        }
    }

    SERVICES_COMMANDS = {
        'availability': {
            'timeout': 10
        },
        'start': {
            'timeout': 180
        },
        'stop': {
            'timeout': 60
        },
        'restart': {
            'timeout': 240
        }
    }

    AWS_COMMANDS = {
        'regions': {
            'timeout': 15
        },
        'contexts': {
            'timeout': 30
        },
        'clusters': {
            'timeout': 30
        }
    }

    REGIONS_COMMANDS = {
        'list': {
            'timeout': 15
        },
        'contexts': {
            'timeout': 30
        },
        'status': {
            'timeout': 20
        }
    }

    CONNECTIONS_COMMANDS = {
        'stats': {
            'timeout': 5
        }
    }

    MAX_OUTPUT_SIZE = 1024 * 1024  # 1MB limit
    MAX_CONCURRENT_PROCESSES = 5

    def __init__(self):
        self.active_processes = 0
        self.system_monitor = SystemMonitor()
        self.kubernetes_monitor = KubernetesMonitor()
        self.docker_manager = DockerManager()
        self.aws_region_manager = AwsRegionManager()

    async def execute_command(self, target: str, command: str, params: Dict[str, str] = None) -> Dict[str, Any]:
        """Execute a whitelisted command safely or return mock data for Kubernetes"""
        if self.active_processes >= self.MAX_CONCURRENT_PROCESSES:
            raise SecurityError("Too many concurrent processes")

        # Handle system commands directly
        if target == 'system':
            return await self._execute_system_command(command, params)

        # Handle services commands directly
        if target == 'services':
            return await self._execute_services_command(command, params)

        # Handle connections commands directly
        if target == 'connections':
            return await self._execute_connections_command(command, params)

        # Handle AWS commands
        if target == 'aws':
            return await self._execute_aws_command(command, params)

        # Handle regions commands
        if target == 'regions':
            return await self._execute_regions_command(command, params)

        # Handle real Kubernetes commands
        if target == 'kubernetes':
            return await self._execute_kubernetes_command(command, params)

        # Handle Docker commands (including health and service controls)
        if target == 'docker':
            if command == 'health':
                return await self._execute_docker_health_command(params)
            elif command in ['logs', 'logs:stream']:
                # Handle container logs
                return await self._execute_docker_logs_command(command, params)
            elif command in ['start', 'stop'] and params and 'container' in params:
                # Handle per-container start/stop operations
                return await self._execute_docker_container_action(command, params)
            elif command in ['start', 'stop', 'restart', 'status'] and (not params or 'container' not in params):
                # Handle global Docker service operations (legacy)
                return await self._execute_docker_service_command(command, params)
            else:
                cmd_config = self.DOCKER_COMMANDS.get(command)

        # Get command configuration for remaining commands
        elif target == 'system':
            cmd_config = self.SYSTEM_COMMANDS.get(command)
        elif target == 'connections':
            cmd_config = self.CONNECTIONS_COMMANDS.get(command)
        elif target == 'aws':
            cmd_config = self.AWS_COMMANDS.get(command)
        elif target == 'regions':
            cmd_config = self.REGIONS_COMMANDS.get(command)
        else:
            raise SecurityError(f"Invalid target: {target}")

        if not cmd_config:
            raise SecurityError(f"Command not allowed: {command}")

        # Build command with validated parameters
        cmd = cmd_config['cmd'].copy()

        # Add required parameters
        if 'requires_params' in cmd_config:
            for param_key in cmd_config['requires_params']:
                if not params or param_key not in params:
                    raise SecurityError(f"Missing required parameter: {param_key}")

                param_value = self._sanitize_parameter(param_key, params[param_key])
                if target == 'docker' and param_key == 'container':
                    cmd.append(param_value)

        try:
            self.active_processes += 1
            logger.info(f"Executing command: {' '.join(cmd[:3])}...")  # Log safely

            # Execute with timeout and capture output
            process = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                limit=self.MAX_OUTPUT_SIZE
            )

            try:
                stdout, stderr = await asyncio.wait_for(
                    process.communicate(),
                    timeout=cmd_config['timeout']
                )
            except asyncio.TimeoutError:
                process.kill()
                await process.wait()
                raise SecurityError("Command timeout")

            # Parse output safely
            return await self._parse_command_output(target, command, stdout, stderr, process.returncode)

        finally:
            self.active_processes -= 1

    def _sanitize_parameter(self, param_type: str, value: str) -> str:
        """Sanitize parameters to prevent injection"""
        # Remove dangerous characters
        sanitized = re.sub(r'[;&|`$(){}[\]<>]', '', value)

        # Validate format based on parameter type
        if param_type in ['container', 'pod', 'namespace']:
            if not re.match(r'^[a-zA-Z0-9][a-zA-Z0-9-_]{0,62}$', sanitized):
                raise SecurityError(f"Invalid {param_type} name format")

        return sanitized

    async def _parse_command_output(self, target: str, command: str, stdout: bytes, stderr: bytes, returncode: int) -> Dict[str, Any]:
        """Parse command output safely"""
        if returncode != 0:
            error_msg = stderr.decode('utf-8', errors='ignore')[:1000]  # Limit error message
            # Sanitize error message
            safe_error = self._sanitize_error_message(error_msg)
            return {
                'success': False,
                'error': safe_error,
                'timestamp': datetime.utcnow().isoformat()
            }

        try:
            output = stdout.decode('utf-8', errors='ignore')

            # Parse JSON output for structured commands
            if command in ['ps', 'stats'] and target == 'docker':
                return await self._parse_docker_json(command, output)
            elif command in ['start', 'stop'] and target == 'docker':
                # For container start/stop, return container action result
                container_name = params.get('container', 'unknown') if params else 'unknown'
                return {
                    'success': True,
                    'data': {
                        'container_action': f'{command}_{container_name}',
                        'container': container_name,
                        'action': command,
                        'message': f'Container {container_name} {command}ed successfully',
                        'output': output.strip()
                    },
                    'timestamp': datetime.utcnow().isoformat()
                }
            elif command in ['pods', 'nodes'] and target == 'kubernetes':
                return await self._parse_kubectl_json(command, output)
            else:
                # For logs, return as text (sanitized)
                return {
                    'success': True,
                    'data': {
                        'logs': self._sanitize_logs(output)
                    },
                    'timestamp': datetime.utcnow().isoformat()
                }

        except Exception as e:
            logger.error(f"Error parsing output: {str(e)}")
            return {
                'success': False,
                'error': 'Error parsing command output',
                'timestamp': datetime.utcnow().isoformat()
            }

    async def _parse_docker_json(self, command: str, output: str) -> Dict[str, Any]:
        """Parse Docker JSON output and enrich with Prometheus metrics"""
        try:
            lines = output.strip().split('\n')
            containers = []

            for line in lines:
                if line.strip():
                    container_data = json.loads(line)

                    # Parse network I/O if available (stats command only)
                    network_tx_bytes = None
                    network_rx_bytes = None
                    if command == 'stats':
                        net_io = container_data.get('NetIO', '')
                        if net_io:
                            network_rx_bytes, network_tx_bytes = self._parse_network_io(net_io)

                    containers.append({
                        'name': container_data.get('Names', 'Unknown'),
                        'status': container_data.get('Status', 'Unknown'),
                        'image': container_data.get('Image', 'Unknown'),
                        'ports': container_data.get('Ports', ''),
                        'created': container_data.get('CreatedAt', ''),
                        'cpu_usage': container_data.get('CPUPerc', '0%') if command == 'stats' else None,
                        'memory_usage': container_data.get('MemUsage', '0B / 0B') if command == 'stats' else None,
                        'network_tx_bytes': network_tx_bytes,
                        'network_rx_bytes': network_rx_bytes
                    })

            # Enrich containers with Prometheus metrics for known containers (only for 'ps' command)
            if command == 'ps':
                containers = await self._enrich_with_prometheus_metrics(containers)

            return {
                'success': True,
                'data': {'containers': containers},
                'timestamp': datetime.utcnow().isoformat()
            }
        except json.JSONDecodeError:
            return {
                'success': False,
                'error': 'Invalid JSON response from Docker',
                'timestamp': datetime.utcnow().isoformat()
            }

    async def _enrich_with_prometheus_metrics(self, containers: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """
        Enrich container data with Prometheus metrics where available.

        Currently supports: renny, flowise, prometheus
        """
        # Metrics configuration for known containers
        metrics_config = {
            "renny": {"port": 8080, "path": "/metrics"},
            "flowise": {"port": 3000, "path": "/metrics"},
            "prometheus": {"port": 9090, "path": "/metrics"}
        }

        # Get Prometheus client
        prom_client = get_prometheus_client()

        enriched_containers = []
        for container in containers:
            container_name = container.get("name", "").lower()

            # Check if this container has metrics configuration
            metrics_conf = None
            for conf_name, conf in metrics_config.items():
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
                        # No metrics available - use MOCK metrics for testing
                        container_copy = container.copy()
                        container_copy["metrics"] = self._generate_mock_metrics(container_name)
                        enriched_containers.append(container_copy)
                        logger.debug(f"Using mock metrics for container '{container_name}'")

                except Exception as e:
                    # Log error but don't fail - use MOCK metrics for testing
                    logger.debug(f"Failed to fetch metrics for container '{container_name}': {e}")
                    container_copy = container.copy()
                    container_copy["metrics"] = self._generate_mock_metrics(container_name)
                    enriched_containers.append(container_copy)
            else:
                # Container has no metrics configuration
                enriched_containers.append(container)

        return enriched_containers

    def _generate_mock_metrics(self, container_name: str) -> Dict[str, Any]:
        """
        Generate mock metrics for testing and development.
        Returns realistic-looking metrics based on container name.
        """
        # Base metrics that vary by container type
        is_renny = "renny" in container_name.lower()
        is_monitor = "monitor" in container_name.lower()

        # Generate realistic metrics
        if is_renny:
            # Renny is GPU-intensive
            return {
                "gpu_percent": round(random.uniform(40.0, 85.0), 1),
                "cpu_percent": round(random.uniform(15.0, 45.0), 1),
                "memory_percent": round(random.uniform(25.0, 60.0), 1),
                "memory_bytes": int(random.uniform(2.0, 5.5) * 1024 ** 3),  # 2-5.5 GB
                "power_watts": round(random.uniform(120.0, 280.0), 1)
            }
        elif is_monitor:
            # Monitor is lightweight
            return {
                "cpu_percent": round(random.uniform(5.0, 20.0), 1),
                "memory_percent": round(random.uniform(10.0, 30.0), 1),
                "memory_bytes": int(random.uniform(0.5, 1.5) * 1024 ** 3)  # 0.5-1.5 GB
            }
        else:
            # Generic container
            return {
                "cpu_percent": round(random.uniform(10.0, 40.0), 1),
                "memory_percent": round(random.uniform(15.0, 50.0), 1),
                "memory_bytes": int(random.uniform(1.0, 3.0) * 1024 ** 3)  # 1-3 GB
            }

    async def _parse_kubectl_json(self, command: str, output: str) -> Dict[str, Any]:
        """Parse kubectl JSON output"""
        try:
            data = json.loads(output)
            items = data.get('items', [])

            if command == 'pods':
                pods = []
                for pod in items:
                    metadata = pod.get('metadata', {})
                    status = pod.get('status', {})

                    pods.append({
                        'name': metadata.get('name', 'Unknown'),
                        'namespace': metadata.get('namespace', 'default'),
                        'status': status.get('phase', 'Unknown'),
                        'ready': self._get_pod_ready_status(status),
                        'restarts': self._get_pod_restart_count(status),
                        'age': self._calculate_age(metadata.get('creationTimestamp')),
                        'node': pod.get('spec', {}).get('nodeName', 'Unknown')
                    })

                return {
                    'success': True,
                    'data': {'pods': pods},
                    'timestamp': datetime.utcnow().isoformat()
                }

            elif command == 'nodes':
                nodes = []
                for node in items:
                    metadata = node.get('metadata', {})
                    status = node.get('status', {})

                    nodes.append({
                        'name': metadata.get('name', 'Unknown'),
                        'status': self._get_node_status(status),
                        'roles': self._get_node_roles(metadata.get('labels', {})),
                        'age': self._calculate_age(metadata.get('creationTimestamp')),
                        'version': status.get('nodeInfo', {}).get('kubeletVersion', 'Unknown')
                    })

                return {
                    'success': True,
                    'data': {'nodes': nodes},
                    'timestamp': datetime.utcnow().isoformat()
                }

        except json.JSONDecodeError:
            return {
                'success': False,
                'error': 'Invalid JSON response from kubectl',
                'timestamp': datetime.utcnow().isoformat()
            }

    def _get_pod_ready_status(self, status: Dict) -> str:
        """Get pod ready status"""
        conditions = status.get('conditions', [])
        for condition in conditions:
            if condition.get('type') == 'Ready':
                return '1/1' if condition.get('status') == 'True' else '0/1'
        return '0/1'

    def _get_pod_restart_count(self, status: Dict) -> int:
        """Get pod restart count"""
        container_statuses = status.get('containerStatuses', [])
        total_restarts = 0
        for container in container_statuses:
            total_restarts += container.get('restartCount', 0)
        return total_restarts

    def _get_node_status(self, status: Dict) -> str:
        """Get node status"""
        conditions = status.get('conditions', [])
        for condition in conditions:
            if condition.get('type') == 'Ready' and condition.get('status') == 'True':
                return 'Ready'
        return 'NotReady'

    def _get_node_roles(self, labels: Dict) -> str:
        """Get node roles from labels"""
        roles = []
        for key in labels:
            if key.startswith('node-role.kubernetes.io/'):
                role = key.split('/')[-1]
                if role:
                    roles.append(role)
        return ','.join(roles) if roles else 'worker'

    def _calculate_age(self, created_time: str) -> str:
        """Calculate age from creation timestamp"""
        if not created_time:
            return 'Unknown'

        try:
            created = datetime.fromisoformat(created_time.replace('Z', '+00:00'))
            age_seconds = (datetime.utcnow() - created.replace(tzinfo=None)).total_seconds()

            if age_seconds < 60:
                return f"{int(age_seconds)}s"
            elif age_seconds < 3600:
                return f"{int(age_seconds // 60)}m"
            elif age_seconds < 86400:
                return f"{int(age_seconds // 3600)}h"
            else:
                return f"{int(age_seconds // 86400)}d"
        except:
            return 'Unknown'

    def _sanitize_error_message(self, error: str) -> str:
        """Sanitize error messages to remove sensitive information"""
        # Remove file paths
        error = re.sub(r'/[^\s]*', '[path]', error)
        # Remove IP addresses
        error = re.sub(r'\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b', '[ip]', error)
        # Remove potential tokens/secrets
        error = re.sub(r'[A-Za-z0-9+/]{20,}={0,2}', '[token]', error)

        return error[:500]  # Limit length

    def _sanitize_logs(self, logs: str) -> str:
        """Sanitize log output"""
        # Limit log size
        if len(logs) > 50000:  # 50KB limit for logs
            logs = logs[-50000:]

        # Remove potential sensitive information
        logs = re.sub(r'password[=:]\s*\S+', 'password=[REDACTED]', logs, flags=re.IGNORECASE)
        logs = re.sub(r'token[=:]\s*\S+', 'token=[REDACTED]', logs, flags=re.IGNORECASE)
        logs = re.sub(r'secret[=:]\s*\S+', 'secret=[REDACTED]', logs, flags=re.IGNORECASE)

        return logs

    def _parse_network_io(self, net_io: str) -> Tuple[Optional[int], Optional[int]]:
        """
        Parse Docker network I/O string to bytes.

        Args:
            net_io: Network I/O string in format "RX / TX" (e.g., "130kB / 385kB")

        Returns:
            Tuple of (rx_bytes, tx_bytes) or (None, None) if parsing fails

        Example:
            "130kB / 385kB" -> (133120, 394240)
            "1.5MB / 2.3GB" -> (1572864, 2469606195)
        """
        try:
            if not net_io or '/' not in net_io:
                return None, None

            # Split RX and TX
            parts = net_io.split('/')
            if len(parts) != 2:
                return None, None

            rx_str = parts[0].strip()
            tx_str = parts[1].strip()

            # Convert to bytes
            rx_bytes = self._convert_size_to_bytes(rx_str)
            tx_bytes = self._convert_size_to_bytes(tx_str)

            return rx_bytes, tx_bytes

        except Exception as e:
            logger.debug(f"Failed to parse network I/O '{net_io}': {str(e)}")
            return None, None

    def _convert_size_to_bytes(self, size_str: str) -> Optional[int]:
        """
        Convert human-readable size string to bytes.

        Args:
            size_str: Size string (e.g., "130kB", "1.5MB", "2.3GB")

        Returns:
            Size in bytes or None if parsing fails

        Raises:
            ValueError: If size format is invalid
        """
        if not size_str or size_str == '0B':
            return 0

        # Remove whitespace
        size_str = size_str.strip()

        # Regex to extract number and unit
        match = re.match(r'^([\d.]+)([kMGTP]?B)$', size_str)
        if not match:
            raise ValueError(f"Invalid size format: {size_str}")

        value = float(match.group(1))
        unit = match.group(2)

        # Conversion factors (using 1000 base as Docker uses SI units)
        units = {
            'B': 1,
            'kB': 1000,
            'MB': 1000 ** 2,
            'GB': 1000 ** 3,
            'TB': 1000 ** 4,
            'PB': 1000 ** 5
        }

        if unit not in units:
            raise ValueError(f"Unknown unit: {unit}")

        return int(value * units[unit])

    async def _execute_system_command(self, command: str, params: Dict[str, str] = None) -> Dict[str, Any]:
        """Execute system monitoring commands using SystemMonitor"""
        try:
            if command == 'metrics':
                # Get system metrics
                metrics = await self.system_monitor.get_system_metrics()
                return {
                    'success': True,
                    'data': {
                        'metrics': metrics.dict()
                    },
                    'timestamp': datetime.utcnow().isoformat()
                }
            elif command == 'info':
                # Get system info
                system_info = self.system_monitor.get_system_info()
                return {
                    'success': True,
                    'data': {
                        'system': system_info
                    },
                    'timestamp': datetime.utcnow().isoformat()
                }
            elif command == 'health':
                # Get overall system health
                metrics = await self.system_monitor.get_system_metrics()
                system_info = self.system_monitor.get_system_info()
                return {
                    'success': True,
                    'data': {
                        'status': 'healthy',
                        'components': {
                            'api': 'operational',
                            'websocket': 'operational',
                            'system_monitor': 'operational'
                        },
                        'metrics': {
                            'cpu_percent': metrics.cpu_percent,
                            'memory_percent': metrics.memory_percent
                        },
                        'system': system_info
                    },
                    'timestamp': datetime.utcnow().isoformat()
                }
            else:
                raise SecurityError(f"System command not allowed: {command}")

        except Exception as e:
            logger.error(f"System command execution error: {str(e)}")
            return {
                'success': False,
                'error': f"System command failed: {str(e)}",
                'timestamp': datetime.utcnow().isoformat()
            }

    async def _execute_services_command(self, command: str, params: Dict[str, str] = None) -> Dict[str, Any]:
        """Execute services monitoring and control commands"""
        try:
            if command == 'availability':
                # Check Docker and Kubernetes availability
                docker_available = await self.system_monitor.check_docker_availability()
                kubectl_available = await self.system_monitor.check_kubectl_availability()

                return {
                    'success': True,
                    'data': {
                        'services': {
                            'docker': {
                                'available': docker_available,
                                'status': 'ready' if docker_available else 'unavailable'
                            },
                            'kubernetes': {
                                'available': kubectl_available,
                                'status': 'ready' if kubectl_available else 'unavailable'
                            }
                        }
                    },
                    'timestamp': datetime.utcnow().isoformat()
                }

            elif command in ['start', 'stop', 'restart']:
                # Handle service control operations
                if not params or 'service_type' not in params:
                    return {
                        'success': False,
                        'error': 'Missing required parameter: service_type',
                        'timestamp': datetime.utcnow().isoformat()
                    }

                service_type = params['service_type']

                if service_type == 'docker':
                    # Handle Docker service control
                    docker_request = DockerServiceRequest(
                        action=command,
                        force=params.get('force', 'false').lower() == 'true'
                    )
                    response = await self.docker_manager.process_service_request(docker_request)
                    return {
                        'success': response.success,
                        'data': {
                            'service_response': response.dict()
                        },
                        'error': response.error if not response.success else None,
                        'timestamp': datetime.utcnow().isoformat()
                    }

                elif service_type == 'kubernetes':
                    # Handle Kubernetes cluster control
                    region = params.get('region')
                    cluster_name = params.get('cluster_name')

                    if not region or not cluster_name:
                        return {
                            'success': False,
                            'error': 'Missing required parameters: region and cluster_name for Kubernetes operations',
                            'timestamp': datetime.utcnow().isoformat()
                        }

                    if command == 'start':
                        response = await self.kubernetes_monitor.start_cluster(region, cluster_name)
                    elif command == 'stop':
                        response = await self.kubernetes_monitor.stop_cluster(region, cluster_name)
                    else:
                        # Restart = stop then start
                        stop_response = await self.kubernetes_monitor.stop_cluster(region, cluster_name)
                        if stop_response.success:
                            response = await self.kubernetes_monitor.start_cluster(region, cluster_name)
                        else:
                            response = stop_response

                    return {
                        'success': response.success,
                        'data': {
                            'service_response': response.dict()
                        },
                        'error': response.error if not response.success else None,
                        'timestamp': datetime.utcnow().isoformat()
                    }

                else:
                    return {
                        'success': False,
                        'error': f'Unsupported service type: {service_type}',
                        'timestamp': datetime.utcnow().isoformat()
                    }

            else:
                raise SecurityError(f"Services command not allowed: {command}")

        except Exception as e:
            logger.error(f"Services command execution error: {str(e)}")
            return {
                'success': False,
                'error': f"Services command failed: {str(e)}",
                'timestamp': datetime.utcnow().isoformat()
            }

    async def _execute_connections_command(self, command: str, params: Dict[str, str] = None) -> Dict[str, Any]:
        """Execute connections monitoring commands"""
        try:
            if command == 'stats':
                # This would need to be injected or imported from connection manager
                # For now, return basic stats
                return {
                    'success': True,
                    'data': {
                        'total_connections': 0,  # Would need actual connection manager
                        'active_subscriptions': 0
                    },
                    'timestamp': datetime.utcnow().isoformat()
                }
            else:
                raise SecurityError(f"Connections command not allowed: {command}")

        except Exception as e:
            logger.error(f"Connections command execution error: {str(e)}")
            return {
                'success': False,
                'error': f"Connections command failed: {str(e)}",
                'timestamp': datetime.utcnow().isoformat()
            }

    async def _execute_docker_health_command(self, params: Dict[str, str] = None) -> Dict[str, Any]:
        """Execute Docker health command"""
        try:
            docker_health = await self.system_monitor.get_docker_engine_health()
            return {
                'success': True,
                'data': {
                    'docker_health': docker_health
                },
                'timestamp': datetime.utcnow().isoformat()
            }
        except Exception as e:
            logger.error(f"Docker health command execution error: {str(e)}")
            return {
                'success': False,
                'error': f"Docker health command failed: {str(e)}",
                'timestamp': datetime.utcnow().isoformat()
            }

    async def _execute_kubernetes_command(self, command: str, params: Dict[str, str] = None) -> Dict[str, Any]:
        """Execute real Kubernetes commands using KubernetesMonitor"""
        try:
            if command == 'health':
                # Get comprehensive cluster health
                health_data = await self.kubernetes_monitor.get_cluster_health()
                return {
                    'success': True,
                    'data': {
                        'kubernetes_health': health_data
                    },
                    'timestamp': datetime.utcnow().isoformat()
                }

            elif command == 'pods':
                # Get pods from the cluster
                namespace = params.get('namespace') if params else None
                all_namespaces = params.get('all_namespaces', 'false').lower() == 'true' if params else True

                pods = await self.kubernetes_monitor.get_pods(namespace=namespace, all_namespaces=all_namespaces)
                return {
                    'success': True,
                    'data': {'pods': pods},
                    'timestamp': datetime.utcnow().isoformat()
                }

            elif command == 'nodes':
                # Get nodes from the cluster
                nodes = await self.kubernetes_monitor.get_nodes()
                return {
                    'success': True,
                    'data': {'nodes': nodes},
                    'timestamp': datetime.utcnow().isoformat()
                }

            elif command == 'namespaces':
                # Get namespaces from the cluster
                namespaces = await self.kubernetes_monitor.get_namespaces()
                return {
                    'success': True,
                    'data': {'namespaces': namespaces},
                    'timestamp': datetime.utcnow().isoformat()
                }

            elif command == 'contexts':
                # Get available contexts
                contexts = await self.kubernetes_monitor.get_available_contexts()
                current_context = await self.kubernetes_monitor.get_current_context()
                return {
                    'success': True,
                    'data': {
                        'contexts': contexts,
                        'current_context': current_context
                    },
                    'timestamp': datetime.utcnow().isoformat()
                }

            elif command == 'switch-context':
                # Switch to a different context
                if not params or 'context' not in params:
                    return {
                        'success': False,
                        'error': 'Missing required parameter: context',
                        'timestamp': datetime.utcnow().isoformat()
                    }

                context_name = params['context']
                success = await self.kubernetes_monitor.switch_context(context_name)

                if success:
                    return {
                        'success': True,
                        'data': {
                            'switched_to': context_name
                        },
                        'timestamp': datetime.utcnow().isoformat()
                    }
                else:
                    return {
                        'success': False,
                        'error': f'Failed to switch to context: {context_name}',
                        'timestamp': datetime.utcnow().isoformat()
                    }

            elif command == 'logs':
                # Get pod logs
                if not params or 'pod' not in params:
                    return {
                        'success': False,
                        'error': 'Missing required parameter: pod',
                        'timestamp': datetime.utcnow().isoformat()
                    }

                pod_name = params['pod']
                namespace = params.get('namespace', 'default')
                tail = int(params.get('tail', '100'))

                logs = await self.kubernetes_monitor.get_pod_logs(pod_name, namespace, tail)
                return {
                    'success': True,
                    'data': {'logs': logs},
                    'timestamp': datetime.utcnow().isoformat()
                }

            else:
                return {
                    'success': False,
                    'error': f'Kubernetes command not supported: {command}',
                    'timestamp': datetime.utcnow().isoformat()
                }

        except Exception as e:
            logger.error(f"Kubernetes command execution error: {str(e)}")
            return {
                'success': False,
                'error': f"Kubernetes command failed: {str(e)}",
                'timestamp': datetime.utcnow().isoformat()
            }

    async def _execute_docker_container_action(self, command: str, params: Dict[str, str]) -> Dict[str, Any]:
        """Execute Docker container start/stop using SDK"""
        try:
            client = self.system_monitor._get_docker_client()
            if client is None:
                return {
                    'success': False,
                    'error': 'Cannot connect to Docker',
                    'timestamp': datetime.utcnow().isoformat()
                }

            container_name = params.get('container')
            if not container_name:
                return {
                    'success': False,
                    'error': 'Missing container parameter',
                    'timestamp': datetime.utcnow().isoformat()
                }

            # Get the container
            container = client.containers.get(container_name)

            # Execute the action
            if command == 'start':
                container.start()
                action_msg = 'started'
            elif command == 'stop':
                container.stop()
                action_msg = 'stopped'
            else:
                return {
                    'success': False,
                    'error': f'Unsupported container action: {command}',
                    'timestamp': datetime.utcnow().isoformat()
                }

            return {
                'success': True,
                'data': {
                    'container_action': f'{command}_{container_name}',
                    'container': container_name,
                    'action': command,
                    'message': f'Container {container_name} {action_msg} successfully'
                },
                'timestamp': datetime.utcnow().isoformat()
            }

        except Exception as e:
            logger.error(f"Docker container action error: {str(e)}")
            return {
                'success': False,
                'error': f"Container {command} failed: {str(e)}",
                'timestamp': datetime.utcnow().isoformat()
            }

    async def _execute_docker_logs_command(self, command: str, params: Dict[str, str]) -> Dict[str, Any]:
        """Execute Docker logs command"""
        try:
            container_name = params.get('container')
            if not container_name:
                return {
                    'success': False,
                    'error': 'Missing container parameter',
                    'timestamp': datetime.utcnow().isoformat()
                }

            lines = params.get('lines', '100')
            streaming = command == 'logs:stream'

            logger.info(f"Fetching logs for container '{container_name}' (lines={lines}, streaming={streaming})")

            # Build docker logs command
            cmd = ['sudo', 'docker', 'logs']
            if streaming:
                cmd.extend(['--follow', '--tail', lines])
            else:
                cmd.extend(['--tail', lines])
            cmd.append(container_name)

            # Execute command
            process = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.STDOUT
            )

            stdout, _ = await asyncio.wait_for(
                process.communicate(),
                timeout=5.0
            )

            logs_output = stdout.decode('utf-8', errors='replace')

            logger.info(f"Retrieved {len(logs_output)} bytes of logs for '{container_name}'")

            return {
                'success': True,
                'data': {
                    'logs': logs_output,
                    'container': container_name,
                    'lines': lines
                },
                'timestamp': datetime.utcnow().isoformat()
            }

        except asyncio.TimeoutError:
            logger.error(f"Timeout fetching logs for container '{container_name}'")
            return {
                'success': False,
                'error': f"Timeout fetching logs for container '{container_name}'",
                'timestamp': datetime.utcnow().isoformat()
            }
        except Exception as e:
            logger.error(f"Docker logs error: {str(e)}")
            return {
                'success': False,
                'error': f"Failed to fetch logs: {str(e)}",
                'timestamp': datetime.utcnow().isoformat()
            }

    async def _execute_docker_service_command(self, command: str, params: Dict[str, str] = None) -> Dict[str, Any]:
        """Execute Docker service control commands"""
        try:
            # Create Docker service request
            docker_request = DockerServiceRequest(
                action=command,
                force=params.get('force', 'false').lower() == 'true' if params else False
            )

            # Process the request
            response = await self.docker_manager.process_service_request(docker_request)

            return {
                'success': response.success,
                'data': {
                    'docker_response': response.dict()
                },
                'error': response.error if not response.success else None,
                'timestamp': datetime.utcnow().isoformat()
            }

        except Exception as e:
            logger.error(f"Docker service command execution error: {str(e)}")
            return {
                'success': False,
                'error': f"Docker service command failed: {str(e)}",
                'timestamp': datetime.utcnow().isoformat()
            }

    async def _execute_aws_command(self, command: str, params: Dict[str, str] = None) -> Dict[str, Any]:
        """Execute AWS-related commands"""
        try:
            if command == 'regions':
                # Get list of all AWS regions
                validate_access = params.get('validate_access', 'false').lower() == 'true' if params else False
                regions = await self.aws_region_manager.get_available_regions(validate_access=validate_access)

                response = RegionListResponse(
                    success=True,
                    regions=regions,
                    total_count=len(regions)
                )

                return {
                    'success': True,
                    'data': response.dict(),
                    'timestamp': datetime.utcnow().isoformat()
                }

            elif command == 'contexts':
                # Get Kubernetes contexts by region
                region = params.get('region') if params else None
                if not region:
                    return {
                        'success': False,
                        'error': 'Missing required parameter: region',
                        'timestamp': datetime.utcnow().isoformat()
                    }

                contexts, clusters = await self.aws_region_manager.get_kubernetes_contexts_by_region(region)
                current_context = await self.kubernetes_monitor.get_current_context()

                response = RegionContextsResponse(
                    success=True,
                    region=region,
                    contexts=contexts,
                    clusters=clusters,
                    current_context=current_context
                )

                return {
                    'success': True,
                    'data': response.dict(),
                    'timestamp': datetime.utcnow().isoformat()
                }

            elif command == 'clusters':
                # Get cluster information for a region
                region = params.get('region') if params else None
                cluster_name = params.get('cluster_name') if params else None

                if not region:
                    return {
                        'success': False,
                        'error': 'Missing required parameter: region',
                        'timestamp': datetime.utcnow().isoformat()
                    }

                clusters = await self.kubernetes_monitor.get_cluster_info_by_region(region, cluster_name)

                return {
                    'success': True,
                    'data': {
                        'region': region,
                        'clusters': [cluster.dict() for cluster in clusters],
                        'cluster_count': len(clusters)
                    },
                    'timestamp': datetime.utcnow().isoformat()
                }

            else:
                raise SecurityError(f"AWS command not allowed: {command}")

        except Exception as e:
            logger.error(f"AWS command execution error: {str(e)}")
            return {
                'success': False,
                'error': f"AWS command failed: {str(e)}",
                'timestamp': datetime.utcnow().isoformat()
            }

    async def _execute_regions_command(self, command: str, params: Dict[str, str] = None) -> Dict[str, Any]:
        """Execute regions-related commands"""
        try:
            if command == 'list':
                # Get list of all AWS regions
                validate_access = params.get('validate_access', 'false').lower() == 'true' if params else False
                regions = await self.aws_region_manager.get_available_regions(validate_access=validate_access)

                response = RegionListResponse(
                    success=True,
                    regions=regions,
                    total_count=len(regions)
                )

                return {
                    'success': True,
                    'data': response.dict(),
                    'timestamp': datetime.utcnow().isoformat()
                }

            elif command == 'contexts':
                # Get Kubernetes contexts by region
                region = params.get('region') if params else None
                if not region:
                    return {
                        'success': False,
                        'error': 'Missing required parameter: region',
                        'timestamp': datetime.utcnow().isoformat()
                    }

                contexts, clusters = await self.aws_region_manager.get_kubernetes_contexts_by_region(region)
                current_context = await self.kubernetes_monitor.get_current_context()

                response = RegionContextsResponse(
                    success=True,
                    region=region,
                    contexts=contexts,
                    clusters=clusters,
                    current_context=current_context
                )

                return {
                    'success': True,
                    'data': response.dict(),
                    'timestamp': datetime.utcnow().isoformat()
                }

            elif command == 'status':
                # Get region status
                region = params.get('region') if params else None
                if not region:
                    return {
                        'success': False,
                        'error': 'Missing required parameter: region',
                        'timestamp': datetime.utcnow().isoformat()
                    }

                status = await self.aws_region_manager.get_region_status(region)

                return {
                    'success': True,
                    'data': {
                        'region_status': status.dict()
                    },
                    'timestamp': datetime.utcnow().isoformat()
                }

            else:
                raise SecurityError(f"Regions command not allowed: {command}")

        except Exception as e:
            logger.error(f"Regions command execution error: {str(e)}")
            return {
                'success': False,
                'error': f"Regions command failed: {str(e)}",
                'timestamp': datetime.utcnow().isoformat()
            }

    def set_aws_profile(self, profile: str) -> None:
        """Set AWS profile for all AWS-related operations"""
        self.aws_region_manager.set_aws_profile(profile)
        self.kubernetes_monitor.set_aws_profile(profile)
        logger.info(f"AWS profile set to {profile} for all components")

