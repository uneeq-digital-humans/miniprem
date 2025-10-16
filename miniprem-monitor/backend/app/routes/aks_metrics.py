"""
AKS Metrics API Routes

Provides real-time Azure Kubernetes Service (AKS) metrics including:
- Node pool metrics (autoscaling, health, resource utilization)
- Cluster-wide totals (nodes, pods, namespaces)
- Cost estimates based on VM sizes
- Resource utilization per node pool

Uses Azure CLI and kubectl commands via subprocess for cross-platform compatibility.
"""

import asyncio
import json
import logging
import time
from typing import Dict, Any, List, Optional
from datetime import datetime
from functools import wraps

from fastapi import HTTPException
from pydantic import BaseModel, Field

logger = logging.getLogger(__name__)


# Azure VM pricing (USD per hour) - US East region as baseline
# Source: https://azure.microsoft.com/en-us/pricing/details/virtual-machines/linux/
VM_PRICING = {
    "Standard_D2s_v3": 0.096,
    "Standard_D4s_v3": 0.192,
    "Standard_D8s_v3": 0.384,
    "Standard_D16s_v3": 0.768,
    "Standard_DS2_v2": 0.107,
    "Standard_DS3_v2": 0.214,
    "Standard_DS4_v2": 0.428,
    "Standard_NC6s_v3": 3.06,  # GPU VM
    "Standard_NC12s_v3": 6.12,  # GPU VM
    "Standard_NC24s_v3": 12.24,  # GPU VM
    "Standard_B2s": 0.0416,
    "Standard_B4ms": 0.166,
    "Standard_E4s_v3": 0.252,
    "Standard_E8s_v3": 0.504,
}


# Pydantic Models
class NodePoolMetrics(BaseModel):
    """Metrics for a single AKS node pool."""
    name: str
    vm_size: str
    current_count: int
    min_count: Optional[int] = None
    max_count: Optional[int] = None
    auto_scaling_enabled: bool = False
    health_status: str  # healthy, degraded, unhealthy
    ready_nodes: int
    not_ready_nodes: int
    provisioning_state: str
    kubernetes_version: Optional[str] = None
    os_disk_size_gb: Optional[int] = None
    mode: Optional[str] = None  # System or User


class ClusterTotals(BaseModel):
    """Cluster-wide totals."""
    total_nodes: int
    ready_nodes: int
    not_ready_nodes: int
    total_pods: int
    running_pods: int
    pending_pods: int
    failed_pods: int
    succeeded_pods: int
    namespace_count: int


class CostBreakdown(BaseModel):
    """Cost breakdown for a node pool."""
    node_pool: str
    vm_size: str
    node_count: int
    hourly_per_node: float
    hourly_total: float
    daily_total: float
    monthly_total: float


class CostEstimate(BaseModel):
    """Total cost estimate."""
    hourly_usd: float
    daily_usd: float
    monthly_usd: float
    breakdown: List[CostBreakdown]
    last_updated: str
    note: str = "Estimated costs based on US East region pricing. Actual costs may vary."


class AKSMetricsResponse(BaseModel):
    """Complete AKS metrics response."""
    success: bool
    metrics: Optional[Dict[str, Any]] = None
    error: Optional[str] = None
    error_type: Optional[str] = None
    timestamp: str


# Cache configuration
class MetricsCache:
    """Simple in-memory cache for AKS metrics."""

    def __init__(self, ttl: int = 30):
        """
        Initialize metrics cache.

        Args:
            ttl: Time-to-live in seconds (default: 30)
        """
        self.ttl = ttl
        self._cache: Dict[str, Dict[str, Any]] = {}
        self._timestamps: Dict[str, float] = {}

    def get(self, key: str) -> Optional[Dict[str, Any]]:
        """
        Get cached value if not expired.

        Args:
            key: Cache key

        Returns:
            Cached value or None if expired/not found
        """
        if key not in self._cache:
            return None

        if time.time() - self._timestamps.get(key, 0) > self.ttl:
            # Cache expired
            del self._cache[key]
            del self._timestamps[key]
            return None

        return self._cache[key]

    def set(self, key: str, value: Dict[str, Any]) -> None:
        """
        Set cache value.

        Args:
            key: Cache key
            value: Value to cache
        """
        self._cache[key] = value
        self._timestamps[key] = time.time()

    def clear(self) -> None:
        """Clear all cached values."""
        self._cache.clear()
        self._timestamps.clear()


# Global cache instance
metrics_cache = MetricsCache(ttl=30)


class AKSMetricsService:
    """Service for collecting AKS cluster metrics."""

    def __init__(self):
        """Initialize AKS metrics service."""
        self._az_available: Optional[bool] = None
        self._kubectl_available: Optional[bool] = None

    async def check_az_availability(self) -> bool:
        """
        Check if Azure CLI is available.

        Returns:
            True if az CLI is available and authenticated

        Raises:
            Exception: If az CLI check fails
        """
        if self._az_available is not None:
            return self._az_available

        try:
            result = await asyncio.create_subprocess_exec(
                'az', 'version',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await asyncio.wait_for(
                result.communicate(),
                timeout=5.0
            )

            self._az_available = result.returncode == 0
            if not self._az_available:
                logger.warning(f"Azure CLI not available: {stderr.decode()}")

            return self._az_available

        except asyncio.TimeoutError:
            logger.error("Azure CLI check timed out")
            self._az_available = False
            return False
        except Exception as e:
            logger.error(f"Error checking Azure CLI availability: {str(e)}")
            self._az_available = False
            return False

    async def check_kubectl_availability(self) -> bool:
        """
        Check if kubectl is available.

        Returns:
            True if kubectl is available

        Raises:
            Exception: If kubectl check fails
        """
        if self._kubectl_available is not None:
            return self._kubectl_available

        try:
            result = await asyncio.create_subprocess_exec(
                'kubectl', 'version', '--client', '--output=json',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await asyncio.wait_for(
                result.communicate(),
                timeout=5.0
            )

            self._kubectl_available = result.returncode == 0
            if not self._kubectl_available:
                logger.warning(f"kubectl not available: {stderr.decode()}")

            return self._kubectl_available

        except Exception as e:
            logger.error(f"Error checking kubectl availability: {str(e)}")
            self._kubectl_available = False
            return False

    async def detect_aks_cluster(self) -> Dict[str, Any]:
        """
        Detect if current context is an AKS cluster.

        Returns:
            Dict with cluster info including provider type

        Raises:
            Exception: If cluster detection fails
        """
        try:
            # Get current context
            result = await asyncio.create_subprocess_exec(
                'kubectl', 'config', 'current-context',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await asyncio.wait_for(
                result.communicate(),
                timeout=5.0
            )

            if result.returncode != 0:
                raise Exception(f"No current kubectl context: {stderr.decode()}")

            context_name = stdout.decode().strip()

            # Check if it's an AKS cluster by checking server URL
            result = await asyncio.create_subprocess_exec(
                'kubectl', 'config', 'view', '-o', 'json',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await asyncio.wait_for(
                result.communicate(),
                timeout=5.0
            )

            if result.returncode == 0:
                config = json.loads(stdout.decode())

                # Find cluster server URL for current context
                for context in config.get('contexts', []):
                    if context['name'] == context_name:
                        cluster_name_in_config = context['context']['cluster']

                        for cluster in config.get('clusters', []):
                            if cluster['name'] == cluster_name_in_config:
                                server = cluster['cluster']['server']

                                # AKS clusters have 'azmk8s.io' in server URL
                                if 'azmk8s.io' in server:
                                    return {
                                        'provider': 'aks',
                                        'context': context_name,
                                        'cluster': cluster_name_in_config,
                                        'server': server
                                    }
                                else:
                                    return {
                                        'provider': 'other',
                                        'context': context_name,
                                        'cluster': cluster_name_in_config,
                                        'server': server
                                    }

            # Fallback: check by context name
            if 'aks' in context_name.lower() or 'azure' in context_name.lower():
                return {
                    'provider': 'aks',
                    'context': context_name,
                    'cluster': context_name
                }

            return {
                'provider': 'unknown',
                'context': context_name
            }

        except Exception as e:
            logger.error(f"Error detecting AKS cluster: {str(e)}")
            raise

    async def get_aks_cluster_info(self, cluster_name: str) -> Optional[Dict[str, Any]]:
        """
        Get AKS cluster information using az CLI.

        Args:
            cluster_name: Name of the AKS cluster

        Returns:
            Dict with cluster information or None if failed
        """
        try:
            result = await asyncio.create_subprocess_exec(
                'az', 'aks', 'list', '--query',
                f"[?name=='{cluster_name}']", '-o', 'json',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            stdout, stderr = await asyncio.wait_for(
                result.communicate(),
                timeout=15.0
            )

            if result.returncode == 0:
                clusters = json.loads(stdout.decode())
                if clusters:
                    cluster = clusters[0]
                    return {
                        'name': cluster.get('name'),
                        'resource_group': cluster.get('resourceGroup'),
                        'location': cluster.get('location'),
                        'kubernetes_version': cluster.get('kubernetesVersion'),
                        'provisioning_state': cluster.get('provisioningState'),
                        'fqdn': cluster.get('fqdn')
                    }
            else:
                logger.warning(f"Failed to get AKS cluster info: {stderr.decode()}")

            return None

        except asyncio.TimeoutError:
            logger.error("AKS cluster info request timed out")
            return None
        except Exception as e:
            logger.error(f"Error getting AKS cluster info: {str(e)}")
            return None

    async def get_node_pool_metrics_from_azure(
        self,
        cluster_name: str,
        resource_group: str
    ) -> List[NodePoolMetrics]:
        """
        Get node pool metrics from Azure CLI.

        Args:
            cluster_name: Name of the AKS cluster
            resource_group: Azure resource group name

        Returns:
            List of NodePoolMetrics objects
        """
        try:
            result = await asyncio.create_subprocess_exec(
                'az', 'aks', 'nodepool', 'list',
                '--cluster-name', cluster_name,
                '--resource-group', resource_group,
                '-o', 'json',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            stdout, stderr = await asyncio.wait_for(
                result.communicate(),
                timeout=15.0
            )

            if result.returncode != 0:
                logger.error(f"Failed to get node pools: {stderr.decode()}")
                return []

            nodepools = json.loads(stdout.decode())
            metrics = []

            for np in nodepools:
                # Determine health status
                provisioning_state = np.get('provisioningState', 'Unknown')
                if provisioning_state == 'Succeeded':
                    health_status = 'healthy'
                elif provisioning_state == 'Failed':
                    health_status = 'unhealthy'
                else:
                    health_status = 'degraded'

                # Get scaling config
                scaling_config = np.get('enableAutoScaling', False)
                current_count = np.get('count', 0)
                min_count = np.get('minCount') if scaling_config else None
                max_count = np.get('maxCount') if scaling_config else None

                metrics.append(NodePoolMetrics(
                    name=np.get('name', 'unknown'),
                    vm_size=np.get('vmSize', 'unknown'),
                    current_count=current_count,
                    min_count=min_count,
                    max_count=max_count,
                    auto_scaling_enabled=scaling_config,
                    health_status=health_status,
                    ready_nodes=current_count,  # Will be updated from kubectl
                    not_ready_nodes=0,
                    provisioning_state=provisioning_state,
                    kubernetes_version=np.get('orchestratorVersion'),
                    os_disk_size_gb=np.get('osDiskSizeGb'),
                    mode=np.get('mode')
                ))

            return metrics

        except asyncio.TimeoutError:
            logger.error("Node pool list request timed out")
            return []
        except Exception as e:
            logger.error(f"Error getting node pool metrics from Azure: {str(e)}")
            return []

    async def get_node_health_from_kubectl(self) -> Dict[str, Dict[str, int]]:
        """
        Get node health status from kubectl.

        Returns:
            Dict mapping node pool name to health counts
        """
        try:
            result = await asyncio.create_subprocess_exec(
                'kubectl', 'get', 'nodes', '-o', 'json',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            stdout, stderr = await asyncio.wait_for(
                result.communicate(),
                timeout=10.0
            )

            if result.returncode != 0:
                logger.error(f"Failed to get nodes: {stderr.decode()}")
                return {}

            nodes = json.loads(stdout.decode())
            node_pool_health: Dict[str, Dict[str, int]] = {}

            for node in nodes.get('items', []):
                labels = node['metadata'].get('labels', {})
                pool_name = labels.get(
                    'agentpool',
                    labels.get('kubernetes.azure.com/agentpool', 'unknown')
                )

                if pool_name not in node_pool_health:
                    node_pool_health[pool_name] = {'ready': 0, 'not_ready': 0}

                # Check node ready status
                conditions = node['status'].get('conditions', [])
                ready_condition = next((c for c in conditions if c['type'] == 'Ready'), None)

                if ready_condition and ready_condition['status'] == 'True':
                    node_pool_health[pool_name]['ready'] += 1
                else:
                    node_pool_health[pool_name]['not_ready'] += 1

            return node_pool_health

        except asyncio.TimeoutError:
            logger.error("Node health check timed out")
            return {}
        except Exception as e:
            logger.error(f"Error getting node health from kubectl: {str(e)}")
            return {}

    async def get_cluster_totals(self) -> ClusterTotals:
        """
        Get cluster-wide totals from kubectl.

        Returns:
            ClusterTotals object
        """
        try:
            # Get all nodes
            nodes_result = await asyncio.create_subprocess_exec(
                'kubectl', 'get', 'nodes', '-o', 'json',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            # Get all pods
            pods_result = await asyncio.create_subprocess_exec(
                'kubectl', 'get', 'pods', '--all-namespaces', '-o', 'json',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            # Get all namespaces
            ns_result = await asyncio.create_subprocess_exec(
                'kubectl', 'get', 'namespaces', '-o', 'json',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            # Wait for all commands
            nodes_stdout, nodes_stderr = await asyncio.wait_for(
                nodes_result.communicate(),
                timeout=10.0
            )
            pods_stdout, pods_stderr = await asyncio.wait_for(
                pods_result.communicate(),
                timeout=10.0
            )
            ns_stdout, ns_stderr = await asyncio.wait_for(
                ns_result.communicate(),
                timeout=10.0
            )

            # Process nodes
            total_nodes = 0
            ready_nodes = 0
            if nodes_result.returncode == 0:
                nodes_data = json.loads(nodes_stdout.decode())
                total_nodes = len(nodes_data.get('items', []))

                for node in nodes_data.get('items', []):
                    conditions = node['status'].get('conditions', [])
                    ready_condition = next((c for c in conditions if c['type'] == 'Ready'), None)
                    if ready_condition and ready_condition['status'] == 'True':
                        ready_nodes += 1

            # Process pods
            total_pods = 0
            running_pods = 0
            pending_pods = 0
            failed_pods = 0
            succeeded_pods = 0

            if pods_result.returncode == 0:
                pods_data = json.loads(pods_stdout.decode())
                pods_list = pods_data.get('items', [])
                total_pods = len(pods_list)

                for pod in pods_list:
                    phase = pod['status'].get('phase', 'Unknown')
                    if phase == 'Running':
                        running_pods += 1
                    elif phase == 'Pending':
                        pending_pods += 1
                    elif phase == 'Failed':
                        failed_pods += 1
                    elif phase == 'Succeeded':
                        succeeded_pods += 1

            # Process namespaces
            namespace_count = 0
            if ns_result.returncode == 0:
                ns_data = json.loads(ns_stdout.decode())
                namespace_count = len(ns_data.get('items', []))

            return ClusterTotals(
                total_nodes=total_nodes,
                ready_nodes=ready_nodes,
                not_ready_nodes=total_nodes - ready_nodes,
                total_pods=total_pods,
                running_pods=running_pods,
                pending_pods=pending_pods,
                failed_pods=failed_pods,
                succeeded_pods=succeeded_pods,
                namespace_count=namespace_count
            )

        except asyncio.TimeoutError:
            logger.error("Cluster totals request timed out")
            return ClusterTotals(
                total_nodes=0, ready_nodes=0, not_ready_nodes=0,
                total_pods=0, running_pods=0, pending_pods=0,
                failed_pods=0, succeeded_pods=0, namespace_count=0
            )
        except Exception as e:
            logger.error(f"Error getting cluster totals: {str(e)}")
            return ClusterTotals(
                total_nodes=0, ready_nodes=0, not_ready_nodes=0,
                total_pods=0, running_pods=0, pending_pods=0,
                failed_pods=0, succeeded_pods=0, namespace_count=0
            )

    def calculate_cost_estimate(
        self,
        node_pool_metrics: List[NodePoolMetrics]
    ) -> CostEstimate:
        """
        Calculate cost estimates based on node pool VM sizes.

        Args:
            node_pool_metrics: List of node pool metrics

        Returns:
            CostEstimate object
        """
        breakdown = []
        total_hourly = 0.0

        for np in node_pool_metrics:
            vm_size = np.vm_size
            node_count = np.current_count

            # Get hourly cost per node
            hourly_per_node = VM_PRICING.get(vm_size, 0.0)

            # Calculate totals
            hourly_total = hourly_per_node * node_count
            daily_total = hourly_total * 24
            monthly_total = hourly_total * 730  # Average hours per month

            total_hourly += hourly_total

            breakdown.append(CostBreakdown(
                node_pool=np.name,
                vm_size=vm_size,
                node_count=node_count,
                hourly_per_node=round(hourly_per_node, 4),
                hourly_total=round(hourly_total, 2),
                daily_total=round(daily_total, 2),
                monthly_total=round(monthly_total, 2)
            ))

        return CostEstimate(
            hourly_usd=round(total_hourly, 2),
            daily_usd=round(total_hourly * 24, 2),
            monthly_usd=round(total_hourly * 730, 2),
            breakdown=breakdown,
            last_updated=datetime.utcnow().isoformat()
        )

    async def get_aks_metrics(self) -> Dict[str, Any]:
        """
        Get comprehensive AKS cluster metrics.

        Returns:
            Dict with complete metrics data

        Raises:
            Exception: If metrics collection fails
        """
        # Check cache first
        cache_key = "aks_metrics"
        cached = metrics_cache.get(cache_key)
        if cached:
            logger.debug("Returning cached AKS metrics")
            return cached

        # Verify tools availability
        if not await self.check_az_availability():
            raise Exception("Azure CLI (az) is not available. Please install and authenticate.")

        if not await self.check_kubectl_availability():
            raise Exception("kubectl is not available. Please install kubectl.")

        # Detect AKS cluster
        cluster_info = await self.detect_aks_cluster()
        if cluster_info['provider'] != 'aks':
            raise Exception(
                f"Current cluster is {cluster_info['provider']}, not AKS. "
                f"Switch to an AKS cluster context first."
            )

        cluster_name = cluster_info.get('cluster', cluster_info.get('context', ''))

        # Get detailed cluster info from Azure
        aks_cluster_info = await self.get_aks_cluster_info(cluster_name)

        if not aks_cluster_info:
            raise Exception(
                f"Failed to get AKS cluster information for '{cluster_name}'. "
                "Ensure Azure CLI is authenticated (az login) and you have access."
            )

        # Get node pool metrics from Azure CLI
        node_pool_metrics = await self.get_node_pool_metrics_from_azure(
            aks_cluster_info['name'],
            aks_cluster_info['resource_group']
        )

        if not node_pool_metrics:
            raise Exception("Failed to retrieve node pool information from Azure.")

        # Update node health from kubectl
        node_health = await self.get_node_health_from_kubectl()
        for np in node_pool_metrics:
            if np.name in node_health:
                np.ready_nodes = node_health[np.name]['ready']
                np.not_ready_nodes = node_health[np.name]['not_ready']

                # Update health status based on actual node readiness
                if np.not_ready_nodes > 0:
                    np.health_status = 'degraded'
                elif np.ready_nodes == 0:
                    np.health_status = 'unhealthy'
                else:
                    np.health_status = 'healthy'

        # Get cluster totals
        cluster_totals = await self.get_cluster_totals()

        # Calculate cost estimate
        cost_estimate = self.calculate_cost_estimate(node_pool_metrics)

        # Build response
        metrics = {
            'cluster_name': aks_cluster_info['name'],
            'resource_group': aks_cluster_info['resource_group'],
            'location': aks_cluster_info['location'],
            'kubernetes_version': aks_cluster_info['kubernetes_version'],
            'provisioning_state': aks_cluster_info['provisioning_state'],
            'fqdn': aks_cluster_info.get('fqdn'),
            'node_pools': [np.dict() for np in node_pool_metrics],
            'cluster_totals': cluster_totals.dict(),
            'cost_estimate': cost_estimate.dict()
        }

        # Cache the result
        metrics_cache.set(cache_key, metrics)

        return metrics


# Global service instance
aks_metrics_service = AKSMetricsService()


async def get_aks_metrics_endpoint() -> AKSMetricsResponse:
    """
    FastAPI endpoint handler for AKS metrics.

    Returns:
        AKSMetricsResponse with metrics data or error
    """
    try:
        metrics = await aks_metrics_service.get_aks_metrics()

        return AKSMetricsResponse(
            success=True,
            metrics=metrics,
            timestamp=datetime.utcnow().isoformat()
        )

    except Exception as e:
        error_msg = str(e)
        logger.error(f"Error getting AKS metrics: {error_msg}")

        # Determine error type
        error_type = "unknown_error"
        if "not available" in error_msg.lower():
            error_type = "tool_not_available"
        elif "not AKS" in error_msg or "not aks" in error_msg:
            error_type = "wrong_provider"
        elif "authentication" in error_msg.lower() or "authenticated" in error_msg.lower():
            error_type = "authentication_error"
        elif "Failed to get" in error_msg or "Failed to retrieve" in error_msg:
            error_type = "data_retrieval_error"

        return AKSMetricsResponse(
            success=False,
            error=error_msg,
            error_type=error_type,
            timestamp=datetime.utcnow().isoformat()
        )
