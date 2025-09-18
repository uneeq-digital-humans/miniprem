import asyncio
import subprocess
import json
import re
from typing import Dict, List, Any, Optional
from datetime import datetime
import logging
from ..services.system_monitor import SystemMonitor

logger = logging.getLogger(__name__)

class SecurityError(Exception):
    pass

class CommandExecutor:
    # Whitelisted commands with their safe parameters
    DOCKER_COMMANDS = {
        'ps': {
            'cmd': ['docker', 'ps', '--format', 'json'],
            'timeout': 10
        },
        'stats': {
            'cmd': ['docker', 'stats', '--no-stream', '--format', 'json'],
            'timeout': 15
        },
        'logs': {
            'cmd': ['docker', 'logs', '--tail', '100', '--timestamps'],
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
        'logs': {
            'cmd': ['kubectl', 'logs', '--tail=100', '--timestamps'],
            'timeout': 30,
            'requires_params': ['pod']
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

        # Return mock data for Kubernetes commands (unless it's health)
        if target == 'kubernetes':
            if command == 'health':
                return await self._execute_kubernetes_health_command(params)
            else:
                return self._get_mock_kubernetes_data(command, params)

        # Handle Docker commands (including health)
        if target == 'docker':
            if command == 'health':
                return await self._execute_docker_health_command(params)
            else:
                cmd_config = self.DOCKER_COMMANDS.get(command)

        # Get command configuration for remaining commands
        elif target == 'system':
            cmd_config = self.SYSTEM_COMMANDS.get(command)
        elif target == 'services':
            cmd_config = self.SERVICES_COMMANDS.get(command)
        elif target == 'connections':
            cmd_config = self.CONNECTIONS_COMMANDS.get(command)
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
        """Parse Docker JSON output"""
        try:
            lines = output.strip().split('\n')
            containers = []

            for line in lines:
                if line.strip():
                    container_data = json.loads(line)
                    containers.append({
                        'name': container_data.get('Names', 'Unknown'),
                        'status': container_data.get('Status', 'Unknown'),
                        'image': container_data.get('Image', 'Unknown'),
                        'ports': container_data.get('Ports', ''),
                        'created': container_data.get('CreatedAt', ''),
                        'cpu_usage': container_data.get('CPUPerc', '0%') if command == 'stats' else None,
                        'memory_usage': container_data.get('MemUsage', '0B / 0B') if command == 'stats' else None
                    })

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
        """Execute services monitoring commands"""
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

    async def _execute_kubernetes_health_command(self, params: Dict[str, str] = None) -> Dict[str, Any]:
        """Execute Kubernetes health command"""
        try:
            k8s_health = await self.system_monitor.get_kubernetes_cluster_health()
            return {
                'success': True,
                'data': {
                    'kubernetes_health': k8s_health
                },
                'timestamp': datetime.utcnow().isoformat()
            }
        except Exception as e:
            logger.error(f"Kubernetes health command execution error: {str(e)}")
            return {
                'success': False,
                'error': f"Kubernetes health command failed: {str(e)}",
                'timestamp': datetime.utcnow().isoformat()
            }

    def _get_mock_kubernetes_data(self, command: str, params: Dict[str, str] = None) -> Dict[str, Any]:
        """Return mock Kubernetes data for demonstration purposes"""
        if command == 'pods':
            mock_pods = [
                {
                    'name': 'nginx-deployment-7d6c85c4c8-abc12',
                    'namespace': 'default',
                    'status': 'Running',
                    'ready': '1/1',
                    'restarts': 0,
                    'age': '2d',
                    'node': 'worker-node-1'
                },
                {
                    'name': 'redis-master-6dd52c5db-xyz89',
                    'namespace': 'default',
                    'status': 'Running',
                    'ready': '1/1',
                    'restarts': 1,
                    'age': '5h',
                    'node': 'worker-node-2'
                },
                {
                    'name': 'app-backend-8f9c7b6d5-qwerty',
                    'namespace': 'production',
                    'status': 'Running',
                    'ready': '1/1',
                    'restarts': 0,
                    'age': '1d',
                    'node': 'worker-node-1'
                },
                {
                    'name': 'monitoring-grafana-9b8a7c6d-mnopq',
                    'namespace': 'monitoring',
                    'status': 'Pending',
                    'ready': '0/1',
                    'restarts': 0,
                    'age': '5m',
                    'node': 'worker-node-3'
                }
            ]

            # Filter by namespace if provided
            if params and 'namespace' in params:
                namespace_filter = params['namespace']
                mock_pods = [pod for pod in mock_pods if pod['namespace'] == namespace_filter]

            return {
                'success': True,
                'data': {'pods': mock_pods},
                'timestamp': datetime.utcnow().isoformat()
            }

        elif command == 'nodes':
            mock_nodes = [
                {
                    'name': 'master-node',
                    'status': 'Ready',
                    'roles': 'control-plane,master',
                    'age': '15d',
                    'version': 'v1.28.2'
                },
                {
                    'name': 'worker-node-1',
                    'status': 'Ready',
                    'roles': 'worker',
                    'age': '15d',
                    'version': 'v1.28.2'
                },
                {
                    'name': 'worker-node-2',
                    'status': 'Ready',
                    'roles': 'worker',
                    'age': '14d',
                    'version': 'v1.28.2'
                },
                {
                    'name': 'worker-node-3',
                    'status': 'NotReady',
                    'roles': 'worker',
                    'age': '12d',
                    'version': 'v1.28.2'
                }
            ]

            return {
                'success': True,
                'data': {'nodes': mock_nodes},
                'timestamp': datetime.utcnow().isoformat()
            }

        elif command == 'logs':
            # Mock pod logs
            pod_name = params.get('pod', 'unknown-pod') if params else 'unknown-pod'
            mock_logs = f"""2025-09-16T23:22:00.123Z INFO Starting application...
2025-09-16T23:22:01.456Z INFO Connected to database
2025-09-16T23:22:02.789Z INFO Server listening on port 8080
2025-09-16T23:22:15.123Z INFO Received request GET /health
2025-09-16T23:22:15.124Z INFO Health check passed
2025-09-16T23:22:30.456Z WARN High memory usage detected: 85%
2025-09-16T23:22:45.789Z INFO Processing batch job
2025-09-16T23:22:50.012Z INFO Batch job completed successfully"""

            return {
                'success': True,
                'data': {'logs': mock_logs},
                'timestamp': datetime.utcnow().isoformat()
            }

        else:
            return {
                'success': False,
                'error': f'Mock data not available for command: {command}',
                'timestamp': datetime.utcnow().isoformat()
            }