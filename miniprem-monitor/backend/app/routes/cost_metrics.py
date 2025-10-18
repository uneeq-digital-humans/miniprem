"""
Cost Metrics API Routes

Enhanced cost tracking endpoints for Kubernetes clusters with hardcoded pricing
and comprehensive cost analysis including trends, breakdown, and optimization
recommendations.

Supports AWS EKS, Azure AKS, and GCP GKE clusters.
"""

import asyncio
import json
import logging
from datetime import datetime
from typing import Dict, Any, List, Optional

from fastapi import HTTPException

from ..models.cost_models import EnhancedCostResponse
from ..services.cost_calculator import cost_calculator_service

logger = logging.getLogger(__name__)


async def detect_cluster_provider() -> Dict[str, str]:
    """
    Detect cloud provider from kubectl context.

    Returns:
        Dict with provider type and cluster name

    Raises:
        Exception: If provider detection fails
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

        # Get cluster server URL
        result = await asyncio.create_subprocess_exec(
            'kubectl', 'config', 'view', '-o', 'json',
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        stdout, stderr = await asyncio.wait_for(
            result.communicate(),
            timeout=5.0
        )

        if result.returncode != 0:
            raise Exception(f"Failed to get kubectl config: {stderr.decode()}")

        config = json.loads(stdout.decode())

        # Find cluster server URL for current context
        provider = "unknown"
        cluster_name = context_name

        for context in config.get('contexts', []):
            if context['name'] == context_name:
                cluster_name_in_config = context['context']['cluster']

                for cluster in config.get('clusters', []):
                    if cluster['name'] == cluster_name_in_config:
                        server = cluster['cluster']['server']

                        # Detect provider by server URL
                        if 'eks.amazonaws.com' in server or '.eks.' in server:
                            provider = 'eks'
                        elif 'azmk8s.io' in server or '.aks.' in server:
                            provider = 'aks'
                        elif 'gke.io' in server or '.gke.' in server or 'container.googleapis.com' in server:
                            provider = 'gke'

                        cluster_name = cluster_name_in_config
                        break

        # Fallback: check context name
        if provider == "unknown":
            context_lower = context_name.lower()
            if 'eks' in context_lower or 'aws' in context_lower:
                provider = 'eks'
            elif 'aks' in context_lower or 'azure' in context_lower:
                provider = 'aks'
            elif 'gke' in context_lower or 'gcp' in context_lower or 'google' in context_lower:
                provider = 'gke'

        return {
            'provider': provider,
            'cluster_name': cluster_name,
            'context': context_name
        }

    except Exception as e:
        logger.error(f"Error detecting cluster provider: {str(e)}")
        raise


async def get_node_pools_from_kubectl() -> List[Dict]:
    """
    Get node pool information from kubectl.

    Returns:
        List of node pool dictionaries with name, instance_type, current_nodes

    Raises:
        Exception: If kubectl command fails
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
            raise Exception(f"Failed to get nodes: {stderr.decode()}")

        nodes_data = json.loads(stdout.decode())
        nodes = nodes_data.get('items', [])

        # Group nodes by node pool/instance type
        node_pools_map = {}

        for node in nodes:
            labels = node['metadata'].get('labels', {})

            # Detect node pool name (varies by provider)
            pool_name = (
                labels.get('agentpool') or  # AKS
                labels.get('eks.amazonaws.com/nodegroup') or  # EKS
                labels.get('cloud.google.com/gke-nodepool') or  # GKE
                labels.get('node.kubernetes.io/instance-type', 'unknown')
            )

            # Get instance type
            instance_type = (
                labels.get('node.kubernetes.io/instance-type') or
                labels.get('beta.kubernetes.io/instance-type') or
                'unknown'
            )

            # Group by pool name
            if pool_name not in node_pools_map:
                node_pools_map[pool_name] = {
                    'name': pool_name,
                    'instance_type': instance_type,
                    'current_nodes': 0
                }

            node_pools_map[pool_name]['current_nodes'] += 1

        return list(node_pools_map.values())

    except Exception as e:
        logger.error(f"Error getting node pools from kubectl: {str(e)}")
        raise


async def get_enhanced_cost_metrics_endpoint() -> EnhancedCostResponse:
    """
    Get enhanced cost metrics with comprehensive analysis.

    Returns:
        EnhancedCostResponse with detailed cost tracking data

    Raises:
        Exception: If cost calculation fails
    """
    try:
        # Detect cloud provider
        cluster_info = await detect_cluster_provider()
        provider = cluster_info['provider']
        cluster_name = cluster_info['cluster_name']

        if provider == 'unknown':
            raise Exception(
                f"Unable to detect cloud provider for cluster '{cluster_name}'. "
                "Ensure kubectl context is configured for EKS, AKS, or GKE."
            )

        # Get node pools
        node_pools = await get_node_pools_from_kubectl()

        if not node_pools:
            raise Exception("No node pools found in cluster")

        logger.info(f"Calculating costs for {provider} cluster '{cluster_name}' with {len(node_pools)} node pools")

        # Calculate node pool costs
        node_pool_costs, total_compute_cost = cost_calculator_service.calculate_node_pool_costs(
            provider=provider,
            node_pools=node_pools
        )

        # Cluster configuration for infrastructure cost calculation
        total_nodes = sum(p['current_nodes'] for p in node_pools)
        cluster_config = {
            'nat_gateway_count': 1,  # Default assumption
            'load_balancer_count': 1,
            'total_nodes': total_nodes,
            'uptime_pattern': '24/7',
            'spot_eligible_workloads': False,
            'gpu_time_slicing_enabled': False
        }

        # Calculate infrastructure costs
        infrastructure_costs = cost_calculator_service.calculate_infrastructure_costs(
            provider=provider,
            cluster_config=cluster_config
        )

        # Calculate cost breakdown
        cost_breakdown = cost_calculator_service.calculate_cost_breakdown(
            compute_cost=total_compute_cost,
            infrastructure_costs=infrastructure_costs
        )

        # Calculate total monthly cost
        total_infra_cost = sum(ic.estimated_cost for ic in infrastructure_costs.values())
        total_monthly_cost = total_compute_cost + total_infra_cost

        # Calculate current period
        current_period = cost_calculator_service.calculate_current_period(
            total_monthly_cost=total_monthly_cost
        )

        # Generate cost trends (simulated for hardcoded pricing)
        cost_trends = cost_calculator_service.generate_cost_trends(
            cluster_name=cluster_name,
            current_daily_cost=current_period.daily_average
        )

        # Generate optimization recommendations
        optimization_recommendations = cost_calculator_service.generate_optimization_recommendations(
            provider=provider,
            total_compute_cost=total_compute_cost,
            node_pool_costs=node_pool_costs,
            cluster_config=cluster_config
        )

        # Calculate budget status (if budget is set)
        today = datetime.utcnow().date()
        days_into_month = today.day
        budget_status = cost_calculator_service.calculate_budget_status(
            current_total_cost=current_period.total_cost,
            days_into_month=days_into_month
        )

        # Determine pricing region
        pricing_region = {
            'eks': 'us-east-1',
            'aks': 'East US',
            'gke': 'us-east1'
        }.get(provider, 'unknown')

        # Build response
        response = EnhancedCostResponse(
            success=True,
            provider=provider,
            cluster_name=cluster_name,
            current_period=current_period,
            cost_breakdown=cost_breakdown,
            node_pool_costs=node_pool_costs,
            cost_trends=cost_trends,
            optimization_recommendations=optimization_recommendations,
            budget_status=budget_status,
            data_source='hardcoded_pricing',
            pricing_region=pricing_region,
            timestamp=datetime.utcnow().isoformat()
        )

        logger.info(
            f"Cost calculation completed for {cluster_name}: "
            f"${total_monthly_cost:,.2f}/month projected"
        )

        return response

    except Exception as e:
        error_msg = str(e)
        logger.error(f"Error calculating enhanced cost metrics: {error_msg}")

        # Determine error type
        error_type = "unknown_error"
        if "No current kubectl context" in error_msg:
            error_type = "no_kubectl_context"
        elif "Unable to detect cloud provider" in error_msg:
            error_type = "provider_detection_failed"
        elif "No node pools found" in error_msg:
            error_type = "no_node_pools"
        elif "Failed to get nodes" in error_msg:
            error_type = "kubectl_command_failed"

        return EnhancedCostResponse(
            success=False,
            provider='unknown',
            cluster_name='unknown',
            current_period=None,
            cost_breakdown={},
            node_pool_costs=[],
            cost_trends=None,
            optimization_recommendations=[],
            budget_status=None,
            data_source='hardcoded_pricing',
            pricing_region='unknown',
            timestamp=datetime.utcnow().isoformat(),
            error=error_msg,
            error_type=error_type
        )
