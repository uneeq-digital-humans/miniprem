import asyncio
import subprocess
import json
import logging
import os
import time
from typing import Dict, List, Any, Optional, Tuple
from datetime import datetime
from ..models.schemas import KubernetesContext, ClusterInfo, ServiceControlRequest, ServiceControlResponse

logger = logging.getLogger(__name__)

class KubernetesMonitor:
    """Real Kubernetes cluster monitoring using kubectl commands with region-aware capabilities"""

    def __init__(self):
        self._kubectl_available = None
        self._current_context = None
        self._available_contexts = []
        self._aws_profile = None
        self._region_cache: Dict[str, Any] = {}
        self._cache_ttl = 300  # 5 minutes

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

    async def get_available_contexts(self) -> List[Dict[str, Any]]:
        """Get available Kubernetes contexts"""
        try:
            result = await asyncio.create_subprocess_exec(
                'kubectl', 'config', 'get-contexts',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await result.communicate()

            if result.returncode == 0:
                contexts = []
                lines = stdout.decode().strip().split('\n')

                # Skip header line
                if len(lines) > 1:
                    header = lines[0]

                    for line in lines[1:]:
                        if line.strip():
                            # Parse the table format: CURRENT   NAME   CLUSTER   AUTHINFO   NAMESPACE
                            parts = line.split()
                            if len(parts) >= 3:
                                is_current = line.startswith('*')
                                name_idx = 1 if is_current else 0

                                if len(parts) > name_idx:
                                    context_info = {
                                        'name': parts[name_idx],
                                        'cluster': parts[name_idx + 1] if len(parts) > name_idx + 1 else parts[name_idx],
                                        'user': parts[name_idx + 2] if len(parts) > name_idx + 2 else 'unknown',
                                        'namespace': parts[name_idx + 3] if len(parts) > name_idx + 3 else 'default',
                                        'current': is_current
                                    }
                                    contexts.append(context_info)

                                    if is_current:
                                        self._current_context = parts[name_idx]

                self._available_contexts = contexts
                return contexts
            else:
                error_msg = stderr.decode()
                logger.error(f"Error getting contexts: {error_msg}")

                # Check for authentication errors
                if "SSO session" in error_msg or "credentials" in error_msg:
                    raise Exception(f"Authentication error: {error_msg}")
                elif "Unable to connect" in error_msg:
                    raise Exception(f"Connection error: {error_msg}")
                else:
                    raise Exception(f"kubectl error: {error_msg}")

        except Exception as e:
            logger.error(f"Error getting available contexts: {str(e)}")
            raise  # Re-raise to let caller handle the error

    async def get_current_context(self) -> Optional[str]:
        """Get current kubectl context"""
        try:
            result = await asyncio.create_subprocess_exec(
                'kubectl', 'config', 'current-context',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await result.communicate()

            if result.returncode == 0:
                self._current_context = stdout.decode().strip()
                return self._current_context
            else:
                logger.warning(f"No current context: {stderr.decode()}")
                return None

        except Exception as e:
            logger.error(f"Error getting current context: {str(e)}")
            return None

    async def switch_context(self, context_name: str) -> bool:
        """Switch to a different kubectl context"""
        try:
            result = await asyncio.create_subprocess_exec(
                'kubectl', 'config', 'use-context', context_name,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await result.communicate()

            if result.returncode == 0:
                self._current_context = context_name
                logger.info(f"Switched to context: {context_name}")
                return True
            else:
                logger.error(f"Error switching context: {stderr.decode()}")
                return False

        except Exception as e:
            logger.error(f"Error switching context: {str(e)}")
            return False

    async def get_cluster_info(self) -> Dict[str, Any]:
        """Get Kubernetes cluster information"""
        try:
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

            cluster_info = {
                'available': True,
                'current_context': await self.get_current_context()
            }

            if info_result.returncode == 0:
                try:
                    info_data = json.loads(info_stdout.decode())
                    cluster_info['cluster_info'] = info_data
                except json.JSONDecodeError:
                    # If JSON parsing fails, try to parse text output
                    info_text = info_stdout.decode().strip()
                    cluster_info['cluster_info'] = {'raw_output': info_text}

            if version_result.returncode == 0:
                try:
                    version_data = json.loads(version_stdout.decode())
                    cluster_info['version'] = {
                        'client': version_data.get('clientVersion', {}).get('gitVersion', 'Unknown'),
                        'server': version_data.get('serverVersion', {}).get('gitVersion', 'Unknown')
                    }
                except json.JSONDecodeError:
                    cluster_info['version'] = {'client': 'Unknown', 'server': 'Unknown'}

            return cluster_info

        except Exception as e:
            logger.error(f"Error getting cluster info: {str(e)}")
            return {
                'available': False,
                'error': str(e)
            }

    async def get_pods(self, namespace: str = None, all_namespaces: bool = False) -> List[Dict[str, Any]]:
        """Get pods from the cluster"""
        try:
            cmd = ['kubectl', 'get', 'pods', '-o', 'json']

            if all_namespaces:
                cmd.append('--all-namespaces')
            elif namespace:
                cmd.extend(['-n', namespace])

            result = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await result.communicate()

            if result.returncode == 0:
                data = json.loads(stdout.decode())
                pods = []

                for pod in data.get('items', []):
                    metadata = pod.get('metadata', {})
                    status = pod.get('status', {})
                    spec = pod.get('spec', {})

                    pod_info = {
                        'name': metadata.get('name', 'Unknown'),
                        'namespace': metadata.get('namespace', 'default'),
                        'status': status.get('phase', 'Unknown'),
                        'ready': self._get_pod_ready_status(status),
                        'restarts': self._get_pod_restart_count(status),
                        'age': self._calculate_age(metadata.get('creationTimestamp')),
                        'node': spec.get('nodeName', 'Unknown'),
                        'ip': status.get('podIP', ''),
                        'labels': metadata.get('labels', {}),
                        'containers': self._get_container_info(spec.get('containers', [])),
                        'conditions': status.get('conditions', [])
                    }
                    pods.append(pod_info)

                return pods
            else:
                logger.error(f"Error getting pods: {stderr.decode()}")
                return []

        except Exception as e:
            logger.error(f"Error getting pods: {str(e)}")
            return []

    async def get_nodes(self) -> List[Dict[str, Any]]:
        """Get nodes from the cluster"""
        try:
            result = await asyncio.create_subprocess_exec(
                'kubectl', 'get', 'nodes', '-o', 'json',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await result.communicate()

            if result.returncode == 0:
                data = json.loads(stdout.decode())
                nodes = []

                for node in data.get('items', []):
                    metadata = node.get('metadata', {})
                    status = node.get('status', {})

                    node_info = {
                        'name': metadata.get('name', 'Unknown'),
                        'status': self._get_node_status(status),
                        'roles': self._get_node_roles(metadata.get('labels', {})),
                        'age': self._calculate_age(metadata.get('creationTimestamp')),
                        'version': status.get('nodeInfo', {}).get('kubeletVersion', 'Unknown'),
                        'os': status.get('nodeInfo', {}).get('operatingSystem', 'Unknown'),
                        'arch': status.get('nodeInfo', {}).get('architecture', 'Unknown'),
                        'kernel': status.get('nodeInfo', {}).get('kernelVersion', 'Unknown'),
                        'runtime': status.get('nodeInfo', {}).get('containerRuntimeVersion', 'Unknown'),
                        'conditions': status.get('conditions', []),
                        'capacity': status.get('capacity', {}),
                        'allocatable': status.get('allocatable', {}),
                        'labels': metadata.get('labels', {})
                    }
                    nodes.append(node_info)

                return nodes
            else:
                logger.error(f"Error getting nodes: {stderr.decode()}")
                return []

        except Exception as e:
            logger.error(f"Error getting nodes: {str(e)}")
            return []

    async def get_namespaces(self) -> List[Dict[str, Any]]:
        """Get namespaces from the cluster"""
        try:
            result = await asyncio.create_subprocess_exec(
                'kubectl', 'get', 'namespaces', '-o', 'json',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await result.communicate()

            if result.returncode == 0:
                data = json.loads(stdout.decode())
                namespaces = []

                for ns in data.get('items', []):
                    metadata = ns.get('metadata', {})
                    status = ns.get('status', {})

                    ns_info = {
                        'name': metadata.get('name', 'Unknown'),
                        'status': status.get('phase', 'Unknown'),
                        'age': self._calculate_age(metadata.get('creationTimestamp')),
                        'labels': metadata.get('labels', {}),
                        'annotations': metadata.get('annotations', {})
                    }
                    namespaces.append(ns_info)

                return namespaces
            else:
                logger.error(f"Error getting namespaces: {stderr.decode()}")
                return []

        except Exception as e:
            logger.error(f"Error getting namespaces: {str(e)}")
            return []

    async def get_pod_logs(self, pod_name: str, namespace: str = 'default', tail: int = 100) -> str:
        """Get logs from a specific pod"""
        try:
            result = await asyncio.create_subprocess_exec(
                'kubectl', 'logs', pod_name, '-n', namespace, f'--tail={tail}', '--timestamps',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await result.communicate()

            if result.returncode == 0:
                return stdout.decode('utf-8', errors='ignore')
            else:
                error_msg = stderr.decode('utf-8', errors='ignore')
                logger.error(f"Error getting pod logs: {error_msg}")
                return f"Error getting logs: {error_msg}"

        except Exception as e:
            logger.error(f"Error getting pod logs: {str(e)}")
            return f"Error getting logs: {str(e)}"

    async def get_cluster_health(self) -> Dict[str, Any]:
        """Get comprehensive cluster health information"""
        try:
            if not await self.check_kubectl_availability():
                return {'available': False, 'error': 'kubectl not available or no cluster accessible'}

            # Get cluster info
            cluster_info = await self.get_cluster_info()

            # Get nodes
            nodes = await self.get_nodes()

            # Get namespaces count
            namespaces = await self.get_namespaces()

            # Analyze cluster health
            total_nodes = len(nodes)
            ready_nodes = len([n for n in nodes if n['status'] == 'Ready'])
            not_ready_nodes = total_nodes - ready_nodes

            health_status = 'healthy'
            if not_ready_nodes > 0:
                health_status = 'degraded'
            if ready_nodes == 0:
                health_status = 'unhealthy'

            return {
                'available': True,
                'cluster_status': health_status,
                'current_context': cluster_info.get('current_context'),
                'version': cluster_info.get('version', {}),
                'nodes': {
                    'total_nodes': total_nodes,
                    'ready_nodes': ready_nodes,
                    'not_ready_nodes': not_ready_nodes,
                    'node_details': nodes
                },
                'namespaces_count': len(namespaces),
                'cluster_info': cluster_info.get('cluster_info', {})
            }

        except Exception as e:
            logger.error(f"Error getting cluster health: {str(e)}")
            return {
                'available': False,
                'error': str(e)
            }

    def _get_pod_ready_status(self, status: Dict) -> str:
        """Get pod ready status"""
        container_statuses = status.get('containerStatuses', [])
        if not container_statuses:
            return '0/0'

        ready_count = len([c for c in container_statuses if c.get('ready', False)])
        total_count = len(container_statuses)
        return f'{ready_count}/{total_count}'

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
            if condition.get('type') == 'Ready':
                if condition.get('status') == 'True':
                    return 'Ready'
                else:
                    return 'NotReady'
        return 'Unknown'

    def _get_node_roles(self, labels: Dict) -> str:
        """Get node roles from labels"""
        roles = []
        for key in labels:
            if key.startswith('node-role.kubernetes.io/'):
                role = key.split('/')[-1]
                if role:
                    roles.append(role)
        return ','.join(roles) if roles else 'worker'

    def _get_container_info(self, containers: List[Dict]) -> List[Dict[str, Any]]:
        """Extract container information from pod spec"""
        container_info = []
        for container in containers:
            info = {
                'name': container.get('name', 'Unknown'),
                'image': container.get('image', 'Unknown'),
                'ports': container.get('ports', []),
                'resources': container.get('resources', {})
            }
            container_info.append(info)
        return container_info

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
        except Exception:
            return 'Unknown'

    # New region-aware methods

    async def get_available_contexts_by_region(self, region: str) -> List[KubernetesContext]:
        """
        Get available Kubernetes contexts filtered by AWS region.

        Args:
            region: AWS region name (e.g., 'us-east-1')

        Returns:
            List of KubernetesContext objects for the specified region

        Raises:
            Exception: If context discovery fails
        """
        try:
            # Get all available contexts
            all_contexts = await self.get_available_contexts()
            region_contexts = []

            for context_info in all_contexts:
                # Try to determine region from context name or cluster info
                context_region = await self._discover_context_region(context_info['name'])

                if context_region == region:
                    k8s_context = KubernetesContext(
                        name=context_info['name'],
                        cluster=context_info['cluster'],
                        user=context_info['user'],
                        namespace=context_info['namespace'],
                        current=context_info['current'],
                        region=region
                    )
                    region_contexts.append(k8s_context)

            logger.info(f"Found {len(region_contexts)} contexts for region {region}")
            return region_contexts

        except Exception as e:
            logger.error(f"Error getting contexts for region {region}: {str(e)}")
            raise

    async def get_cluster_info_by_region(self, region: str, cluster_name: Optional[str] = None) -> List[ClusterInfo]:
        """
        Get Kubernetes cluster information for a specific region.

        Args:
            region: AWS region name
            cluster_name: Optional specific cluster name to filter

        Returns:
            List of ClusterInfo objects

        Raises:
            Exception: If cluster discovery fails
        """
        try:
            clusters = []

            # Get EKS clusters for the region using AWS CLI
            eks_clusters = await self._get_eks_clusters_in_region(region)

            for eks_cluster_name in eks_clusters:
                if cluster_name and eks_cluster_name != cluster_name:
                    continue

                cluster_info = await self._get_cluster_details(eks_cluster_name, region)
                if cluster_info:
                    clusters.append(cluster_info)

            logger.info(f"Found {len(clusters)} clusters in region {region}")
            return clusters

        except Exception as e:
            logger.error(f"Error getting cluster info for region {region}: {str(e)}")
            raise

    async def start_cluster(self, region: str, cluster_name: str) -> ServiceControlResponse:
        """
        Start a Kubernetes cluster (primarily for EKS).

        Args:
            region: AWS region name
            cluster_name: Name of the cluster to start

        Returns:
            ServiceControlResponse with operation results

        Raises:
            Exception: If start operation fails
        """
        start_time = time.time()

        try:
            logger.info(f"Starting EKS cluster {cluster_name} in region {region}")

            # Check current cluster status
            cluster_info = await self._get_cluster_details(cluster_name, region)
            if not cluster_info:
                execution_time = time.time() - start_time
                return ServiceControlResponse(
                    success=False,
                    action="start",
                    service_type="kubernetes",
                    region=region,
                    cluster_name=cluster_name,
                    status="not_found",
                    error=f"Cluster {cluster_name} not found in region {region}",
                    execution_time=execution_time
                )

            if cluster_info.status == "running":
                execution_time = time.time() - start_time
                return ServiceControlResponse(
                    success=True,
                    action="start",
                    service_type="kubernetes",
                    region=region,
                    cluster_name=cluster_name,
                    status="already_running",
                    message=f"Cluster {cluster_name} is already running",
                    execution_time=execution_time
                )

            # For EKS, clusters don't typically "start" - they're either created or running
            # But we can check if the cluster becomes available/accessible

            # Try to make the cluster context available
            context_created = await self._ensure_cluster_context(cluster_name, region)

            if context_created:
                # Wait for cluster to be accessible
                accessible = await self._wait_for_cluster_accessible(cluster_name, region, timeout=300)
                execution_time = time.time() - start_time

                if accessible:
                    return ServiceControlResponse(
                        success=True,
                        action="start",
                        service_type="kubernetes",
                        region=region,
                        cluster_name=cluster_name,
                        status="started",
                        message=f"Cluster {cluster_name} is now accessible",
                        execution_time=execution_time
                    )
                else:
                    return ServiceControlResponse(
                        success=False,
                        action="start",
                        service_type="kubernetes",
                        region=region,
                        cluster_name=cluster_name,
                        status="timeout",
                        error=f"Cluster {cluster_name} did not become accessible within timeout",
                        execution_time=execution_time
                    )
            else:
                execution_time = time.time() - start_time
                return ServiceControlResponse(
                    success=False,
                    action="start",
                    service_type="kubernetes",
                    region=region,
                    cluster_name=cluster_name,
                    status="context_failed",
                    error=f"Failed to create kubectl context for cluster {cluster_name}",
                    execution_time=execution_time
                )

        except Exception as e:
            execution_time = time.time() - start_time
            logger.error(f"Error starting cluster {cluster_name}: {str(e)}")
            return ServiceControlResponse(
                success=False,
                action="start",
                service_type="kubernetes",
                region=region,
                cluster_name=cluster_name,
                status="error",
                error=f"Start operation failed: {str(e)}",
                execution_time=execution_time
            )

    async def stop_cluster(self, region: str, cluster_name: str) -> ServiceControlResponse:
        """
        Stop a Kubernetes cluster (limited for EKS - mainly context removal).

        Args:
            region: AWS region name
            cluster_name: Name of the cluster to stop

        Returns:
            ServiceControlResponse with operation results

        Note:
            For EKS clusters, this primarily removes the kubectl context
            and doesn't actually stop the cluster (which would require deletion)
        """
        start_time = time.time()

        try:
            logger.info(f"Stopping access to EKS cluster {cluster_name} in region {region}")

            # Check if cluster context exists
            context_name = await self._find_cluster_context(cluster_name, region)

            if not context_name:
                execution_time = time.time() - start_time
                return ServiceControlResponse(
                    success=True,
                    action="stop",
                    service_type="kubernetes",
                    region=region,
                    cluster_name=cluster_name,
                    status="already_stopped",
                    message=f"No kubectl context found for cluster {cluster_name}",
                    execution_time=execution_time
                )

            # Remove kubectl context
            context_removed = await self._remove_cluster_context(context_name)
            execution_time = time.time() - start_time

            if context_removed:
                return ServiceControlResponse(
                    success=True,
                    action="stop",
                    service_type="kubernetes",
                    region=region,
                    cluster_name=cluster_name,
                    status="stopped",
                    message=f"Kubectl context for cluster {cluster_name} removed",
                    execution_time=execution_time
                )
            else:
                return ServiceControlResponse(
                    success=False,
                    action="stop",
                    service_type="kubernetes",
                    region=region,
                    cluster_name=cluster_name,
                    status="context_removal_failed",
                    error=f"Failed to remove kubectl context for cluster {cluster_name}",
                    execution_time=execution_time
                )

        except Exception as e:
            execution_time = time.time() - start_time
            logger.error(f"Error stopping cluster access {cluster_name}: {str(e)}")
            return ServiceControlResponse(
                success=False,
                action="stop",
                service_type="kubernetes",
                region=region,
                cluster_name=cluster_name,
                status="error",
                error=f"Stop operation failed: {str(e)}",
                execution_time=execution_time
            )

    def set_aws_profile(self, profile: str) -> None:
        """
        Set AWS profile for EKS operations.

        Args:
            profile: AWS profile name
        """
        self._aws_profile = profile
        logger.info(f"Kubernetes monitor AWS profile set to: {profile}")

    async def _discover_context_region(self, context_name: str) -> Optional[str]:
        """
        Discover AWS region from Kubernetes context name.

        Args:
            context_name: Name of the kubectl context

        Returns:
            AWS region name if discovered, None otherwise
        """
        try:
            # Common AWS region names to look for in context names
            aws_regions = [
                'us-east-1', 'us-east-2', 'us-west-1', 'us-west-2',
                'eu-west-1', 'eu-west-2', 'eu-west-3', 'eu-central-1', 'eu-north-1',
                'ap-northeast-1', 'ap-northeast-2', 'ap-southeast-1', 'ap-southeast-2',
                'ap-south-1', 'ca-central-1', 'sa-east-1'
            ]

            for region in aws_regions:
                if region in context_name:
                    return region

            # Try to get region from cluster endpoint if context is EKS
            if 'eks' in context_name.lower():
                return await self._get_region_from_cluster_endpoint(context_name)

            return None

        except Exception as e:
            logger.debug(f"Error discovering region from context {context_name}: {str(e)}")
            return None

    async def _get_eks_clusters_in_region(self, region: str) -> List[str]:
        """
        Get EKS cluster names in a specific region.

        Args:
            region: AWS region name

        Returns:
            List of EKS cluster names
        """
        try:
            cmd = ['aws', 'eks', 'list-clusters', '--region', region, '--output', 'json']

            if self._aws_profile:
                cmd.extend(['--profile', self._aws_profile])

            result = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            stdout, stderr = await asyncio.wait_for(
                result.communicate(),
                timeout=15.0
            )

            if result.returncode == 0:
                data = json.loads(stdout.decode())
                return data.get('clusters', [])
            else:
                logger.debug(f"Failed to list EKS clusters in {region}: {stderr.decode()}")
                return []

        except Exception as e:
            logger.debug(f"Error getting EKS clusters in region {region}: {str(e)}")
            return []

    async def _get_cluster_details(self, cluster_name: str, region: str) -> Optional[ClusterInfo]:
        """
        Get detailed information about an EKS cluster.

        Args:
            cluster_name: Name of the EKS cluster
            region: AWS region name

        Returns:
            ClusterInfo object or None if failed
        """
        try:
            cmd = ['aws', 'eks', 'describe-cluster', '--name', cluster_name, '--region', region, '--output', 'json']

            if self._aws_profile:
                cmd.extend(['--profile', self._aws_profile])

            result = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            stdout, stderr = await asyncio.wait_for(
                result.communicate(),
                timeout=10.0
            )

            if result.returncode != 0:
                logger.debug(f"Failed to describe cluster {cluster_name}: {stderr.decode()}")
                return None

            data = json.loads(stdout.decode())
            cluster = data.get('cluster', {})

            # Map EKS status to our status format
            status_map = {
                'ACTIVE': 'running',
                'CREATING': 'pending',
                'DELETING': 'pending',
                'FAILED': 'error',
                'UPDATING': 'pending'
            }

            cluster_status = cluster.get('status', 'UNKNOWN')
            mapped_status = status_map.get(cluster_status, 'unknown')

            # Parse timestamps
            created_at = None
            if 'createdAt' in cluster:
                try:
                    created_at = datetime.fromtimestamp(cluster['createdAt'])
                except (ValueError, TypeError):
                    pass

            # Get node group count
            node_count = await self._get_cluster_node_count(cluster_name, region)

            return ClusterInfo(
                name=cluster_name,
                region=region,
                status=mapped_status,
                available=(mapped_status == 'running'),
                endpoint=cluster.get('endpoint'),
                version={'server': cluster.get('version', 'unknown')},
                node_count=node_count,
                created_at=created_at,
                last_activity=datetime.utcnow()
            )

        except Exception as e:
            logger.debug(f"Error getting cluster details for {cluster_name}: {str(e)}")
            return None

    async def _get_cluster_node_count(self, cluster_name: str, region: str) -> int:
        """
        Get node count for an EKS cluster.

        Args:
            cluster_name: Name of the EKS cluster
            region: AWS region name

        Returns:
            Number of nodes in the cluster
        """
        try:
            # Get node groups
            cmd = ['aws', 'eks', 'list-nodegroups', '--cluster-name', cluster_name, '--region', region, '--output', 'json']

            if self._aws_profile:
                cmd.extend(['--profile', self._aws_profile])

            result = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            stdout, stderr = await asyncio.wait_for(
                result.communicate(),
                timeout=10.0
            )

            if result.returncode != 0:
                return 0

            data = json.loads(stdout.decode())
            nodegroups = data.get('nodegroups', [])

            total_nodes = 0
            for nodegroup_name in nodegroups:
                # Get nodegroup details to count nodes
                ng_cmd = ['aws', 'eks', 'describe-nodegroup',
                         '--cluster-name', cluster_name,
                         '--nodegroup-name', nodegroup_name,
                         '--region', region, '--output', 'json']

                if self._aws_profile:
                    ng_cmd.extend(['--profile', self._aws_profile])

                ng_result = await asyncio.create_subprocess_exec(
                    *ng_cmd,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE
                )

                ng_stdout, _ = await asyncio.wait_for(
                    ng_result.communicate(),
                    timeout=10.0
                )

                if ng_result.returncode == 0:
                    ng_data = json.loads(ng_stdout.decode())
                    nodegroup = ng_data.get('nodegroup', {})
                    scaling_config = nodegroup.get('scalingConfig', {})
                    total_nodes += scaling_config.get('currentSize', 0)

            return total_nodes

        except Exception as e:
            logger.debug(f"Error getting node count for cluster {cluster_name}: {str(e)}")
            return 0

    async def _ensure_cluster_context(self, cluster_name: str, region: str) -> bool:
        """
        Ensure kubectl context exists for the cluster.

        Args:
            cluster_name: Name of the EKS cluster
            region: AWS region name

        Returns:
            True if context exists or was created successfully
        """
        try:
            # Check if context already exists
            existing_context = await self._find_cluster_context(cluster_name, region)
            if existing_context:
                return True

            # Create kubectl context for EKS cluster
            cmd = ['aws', 'eks', 'update-kubeconfig', '--name', cluster_name, '--region', region]

            if self._aws_profile:
                cmd.extend(['--profile', self._aws_profile])

            result = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            stdout, stderr = await asyncio.wait_for(
                result.communicate(),
                timeout=30.0
            )

            if result.returncode == 0:
                logger.info(f"kubectl context created for cluster {cluster_name}")
                return True
            else:
                logger.error(f"Failed to create kubectl context: {stderr.decode()}")
                return False

        except Exception as e:
            logger.error(f"Error ensuring cluster context: {str(e)}")
            return False

    async def _find_cluster_context(self, cluster_name: str, region: str) -> Optional[str]:
        """
        Find kubectl context name for a cluster.

        Args:
            cluster_name: Name of the cluster
            region: AWS region name

        Returns:
            Context name if found, None otherwise
        """
        try:
            contexts = await self.get_available_contexts()

            for context in contexts:
                context_name = context['name']
                # Check if context name contains cluster name and region
                if cluster_name in context_name and region in context_name:
                    return context_name

            return None

        except Exception as e:
            logger.debug(f"Error finding cluster context: {str(e)}")
            return None

    async def _remove_cluster_context(self, context_name: str) -> bool:
        """
        Remove kubectl context.

        Args:
            context_name: Name of the context to remove

        Returns:
            True if context was removed successfully
        """
        try:
            # Remove context
            result = await asyncio.create_subprocess_exec(
                'kubectl', 'config', 'delete-context', context_name,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            stdout, stderr = await result.communicate()

            if result.returncode == 0:
                logger.info(f"kubectl context {context_name} removed")
                return True
            else:
                logger.error(f"Failed to remove context {context_name}: {stderr.decode()}")
                return False

        except Exception as e:
            logger.error(f"Error removing context {context_name}: {str(e)}")
            return False

    async def _wait_for_cluster_accessible(self, cluster_name: str, region: str, timeout: int = 300) -> bool:
        """
        Wait for cluster to become accessible.

        Args:
            cluster_name: Name of the cluster
            region: AWS region name
            timeout: Maximum time to wait in seconds

        Returns:
            True if cluster becomes accessible
        """
        start_time = time.time()

        while time.time() - start_time < timeout:
            try:
                # Try to get cluster info via kubectl
                context_name = await self._find_cluster_context(cluster_name, region)
                if context_name:
                    # Switch to the context and test connectivity
                    await self.switch_context(context_name)

                    # Test cluster connectivity
                    result = await asyncio.create_subprocess_exec(
                        'kubectl', 'cluster-info', '--request-timeout=10s',
                        stdout=asyncio.subprocess.PIPE,
                        stderr=asyncio.subprocess.PIPE
                    )

                    stdout, stderr = await result.communicate()

                    if result.returncode == 0:
                        logger.info(f"Cluster {cluster_name} is accessible")
                        return True

                await asyncio.sleep(10)  # Check every 10 seconds

            except Exception as e:
                logger.debug(f"Cluster accessibility check failed: {str(e)}")
                await asyncio.sleep(10)

        logger.warning(f"Cluster {cluster_name} did not become accessible within {timeout} seconds")
        return False

    async def _get_region_from_cluster_endpoint(self, context_name: str) -> Optional[str]:
        """
        Extract region from cluster endpoint URL.

        Args:
            context_name: Name of the kubectl context

        Returns:
            AWS region name if found in endpoint
        """
        try:
            # Get cluster endpoint from kubeconfig
            result = await asyncio.create_subprocess_exec(
                'kubectl', 'config', 'view', '-o', 'json',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            stdout, stderr = await result.communicate()

            if result.returncode == 0:
                config_data = json.loads(stdout.decode())
                clusters = config_data.get('clusters', [])

                for cluster in clusters:
                    cluster_name = cluster.get('name', '')
                    if context_name in cluster_name or cluster_name in context_name:
                        server = cluster.get('cluster', {}).get('server', '')

                        # Extract region from EKS endpoint format
                        # e.g., https://A1B2C3D4E5F6.gr7.us-west-2.eks.amazonaws.com
                        if '.eks.amazonaws.com' in server:
                            parts = server.split('.')
                            for part in parts:
                                if part.count('-') >= 2:  # Region format: us-west-2
                                    aws_regions = [
                                        'us-east-1', 'us-east-2', 'us-west-1', 'us-west-2',
                                        'eu-west-1', 'eu-west-2', 'eu-west-3', 'eu-central-1',
                                        'ap-northeast-1', 'ap-northeast-2', 'ap-southeast-1',
                                        'ap-southeast-2', 'ap-south-1', 'ca-central-1', 'sa-east-1'
                                    ]
                                    if part in aws_regions:
                                        return part

            return None

        except Exception as e:
            logger.debug(f"Error extracting region from cluster endpoint: {str(e)}")
            return None