"""
kubectl Service Module

Provides helper functions for kubectl operations using subprocess-based CLI approach.
Supports multi-cloud providers: AWS EKS, Azure AKS, Google GKE.

Author: MiniPrem Monitor Backend
Date: 2025-10-16
"""

import asyncio
import json
import logging
import re
import os
from typing import Dict, List, Optional, Tuple
from datetime import datetime

logger = logging.getLogger(__name__)


async def get_all_contexts() -> Optional[Dict]:
    """
    Get all kubectl contexts from kubeconfig.

    Returns:
        Dict containing contexts array and current-context, or None if failed

    Raises:
        Exception: If kubectl command execution fails

    Example:
        >>> contexts = await get_all_contexts()
        >>> print(contexts['current-context'])
        'arn:aws:eks:us-east-1:123456789012:cluster/renny-prod'
    """
    try:
        result = await asyncio.create_subprocess_exec(
            'kubectl', 'config', 'view', '-o', 'json',
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )

        stdout, stderr = await asyncio.wait_for(
            result.communicate(),
            timeout=10.0
        )

        if result.returncode == 0:
            config = json.loads(stdout.decode())
            return config
        else:
            error_msg = stderr.decode()
            logger.error(f"Error getting kubectl contexts: {error_msg}")
            raise Exception(f"kubectl config view failed: {error_msg}")

    except asyncio.TimeoutError:
        logger.error("Timeout getting kubectl contexts")
        raise Exception("kubectl config view timed out")
    except Exception as e:
        logger.error(f"Error getting kubectl contexts: {str(e)}")
        raise


async def get_current_context() -> Optional[str]:
    """
    Get currently active kubectl context.

    Returns:
        Current context name, or None if no context is set

    Example:
        >>> current = await get_current_context()
        >>> print(current)
        'arn:aws:eks:us-east-1:123456789012:cluster/renny-prod'
    """
    try:
        result = await asyncio.create_subprocess_exec(
            'kubectl', 'config', 'current-context',
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )

        stdout, stderr = await asyncio.wait_for(
            result.communicate(),
            timeout=10.0
        )

        if result.returncode == 0:
            return stdout.decode().strip()
        else:
            logger.warning(f"No current context set: {stderr.decode()}")
            return None

    except Exception as e:
        logger.error(f"Error getting current context: {str(e)}")
        return None


async def check_cluster_accessible(context_name: str) -> bool:
    """
    Check if a Kubernetes cluster is accessible with the given context.

    Args:
        context_name: Name of the kubectl context to test

    Returns:
        True if cluster is accessible, False otherwise

    Example:
        >>> accessible = await check_cluster_accessible("my-cluster")
        >>> if accessible:
        ...     print("Cluster is reachable")
    """
    try:
        result = await asyncio.create_subprocess_exec(
            'kubectl', '--context', context_name, 'cluster-info', '--request-timeout=5s',
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )

        stdout, stderr = await asyncio.wait_for(
            result.communicate(),
            timeout=10.0
        )

        accessible = result.returncode == 0

        if not accessible:
            logger.debug(f"Cluster {context_name} not accessible: {stderr.decode()}")

        return accessible

    except asyncio.TimeoutError:
        logger.debug(f"Timeout checking accessibility for {context_name}")
        return False
    except Exception as e:
        logger.debug(f"Error checking accessibility for {context_name}: {str(e)}")
        return False


async def get_cluster_stats(context_name: str) -> Dict[str, int]:
    """
    Get node and pod counts for a Kubernetes cluster.

    Args:
        context_name: Name of the kubectl context

    Returns:
        Dictionary with node_count and pod_count

    Example:
        >>> stats = await get_cluster_stats("my-cluster")
        >>> print(f"Nodes: {stats['node_count']}, Pods: {stats['pod_count']}")
    """
    stats = {"node_count": 0, "pod_count": 0}

    try:
        # Get node count
        nodes_result = await asyncio.create_subprocess_exec(
            'kubectl', '--context', context_name, 'get', 'nodes', '--no-headers',
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )

        nodes_stdout, _ = await asyncio.wait_for(
            nodes_result.communicate(),
            timeout=10.0
        )

        if nodes_result.returncode == 0:
            node_lines = nodes_stdout.decode().strip().split('\n')
            stats['node_count'] = len([line for line in node_lines if line.strip()])

        # Get pod count across all namespaces
        pods_result = await asyncio.create_subprocess_exec(
            'kubectl', '--context', context_name, 'get', 'pods', '--all-namespaces', '--no-headers',
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )

        pods_stdout, _ = await asyncio.wait_for(
            pods_result.communicate(),
            timeout=10.0
        )

        if pods_result.returncode == 0:
            pod_lines = pods_stdout.decode().strip().split('\n')
            stats['pod_count'] = len([line for line in pod_lines if line.strip()])

        return stats

    except asyncio.TimeoutError:
        logger.debug(f"Timeout getting stats for {context_name}")
        return stats
    except Exception as e:
        logger.debug(f"Error getting stats for {context_name}: {str(e)}")
        return stats


def detect_provider_from_server(server_url: str) -> str:
    """
    Detect cloud provider from Kubernetes API server URL.

    Args:
        server_url: Kubernetes API server URL

    Returns:
        Provider name: 'eks', 'aks', 'gke', 'local', or 'unknown'

    Example:
        >>> provider = detect_provider_from_server("https://xxx.eks.amazonaws.com")
        >>> print(provider)
        'eks'
    """
    if not server_url:
        return 'unknown'

    server_lower = server_url.lower()

    if 'eks.amazonaws.com' in server_lower or '.eks.' in server_lower:
        return 'eks'
    elif 'azmk8s.io' in server_lower or '.aks.' in server_lower:
        return 'aks'
    elif 'gke.io' in server_lower or '.gke.' in server_lower or 'container.googleapis.com' in server_lower:
        return 'gke'
    elif 'localhost' in server_lower or '127.0.0.1' in server_lower:
        return 'local'
    else:
        return 'unknown'


def extract_region(context_name: str, server_url: str, provider: str) -> str:
    """
    Extract region from context name or server URL based on provider.

    Args:
        context_name: Name of the kubectl context
        server_url: Kubernetes API server URL
        provider: Cloud provider name (eks, aks, gke)

    Returns:
        Region name or 'unknown' if not found

    Example:
        >>> region = extract_region(
        ...     "arn:aws:eks:us-east-1:123:cluster/prod",
        ...     "https://xxx.us-east-1.eks.amazonaws.com",
        ...     "eks"
        ... )
        >>> print(region)
        'us-east-1'
    """
    search_text = (context_name + server_url).lower()

    if provider == 'eks':
        # EKS: arn:aws:eks:us-east-1:123456789012:cluster/name
        # or server: https://XXXXX.gr7.us-east-1.eks.amazonaws.com
        match = re.search(r'(us|eu|ap|ca|sa|me|af)-[a-z]+-\d+', search_text)
        return match.group(0) if match else 'unknown'

    elif provider == 'aks':
        # AKS: context usually contains region, or server: xxx.eastus.azmk8s.io
        azure_regions = [
            'eastus', 'eastus2', 'westus', 'westus2', 'westus3', 'centralus',
            'northcentralus', 'southcentralus', 'westcentralus',
            'northeurope', 'westeurope', 'uksouth', 'ukwest',
            'francecentral', 'francesouth', 'germanywestcentral', 'norwayeast',
            'switzerlandnorth', 'swedencentral',
            'southeastasia', 'eastasia', 'japaneast', 'japanwest',
            'koreacentral', 'koreasouth', 'australiaeast', 'australiasoutheast',
            'centralindia', 'southindia', 'westindia',
            'canadacentral', 'canadaeast',
            'brazilsouth', 'southafricanorth', 'uaenorth'
        ]

        for region in azure_regions:
            if region in search_text:
                return region

        return 'unknown'

    elif provider == 'gke':
        # GKE: context: gke_project-id_us-central1_cluster-name
        # or server: https://xxx.xxx.xxx.xxx (IP-based)
        match = re.search(r'(us|europe|asia|australia|northamerica|southamerica)-[a-z0-9-]+', search_text)
        return match.group(0) if match else 'unknown'

    elif provider == 'local':
        return 'local'

    return 'unknown'


async def switch_context(context_name: str) -> bool:
    """
    Switch kubectl context to specified cluster.

    Args:
        context_name: Name of the context to switch to

    Returns:
        True if context switch was successful, False otherwise

    Raises:
        Exception: If kubectl command execution fails

    Example:
        >>> success = await switch_context("my-cluster")
        >>> if success:
        ...     print("Switched to my-cluster")
    """
    try:
        result = await asyncio.create_subprocess_exec(
            'kubectl', 'config', 'use-context', context_name,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )

        stdout, stderr = await asyncio.wait_for(
            result.communicate(),
            timeout=10.0
        )

        if result.returncode == 0:
            logger.info(f"Successfully switched to context: {context_name}")
            return True
        else:
            error_msg = stderr.decode()
            logger.error(f"Failed to switch context to {context_name}: {error_msg}")
            raise Exception(f"kubectl use-context failed: {error_msg}")

    except asyncio.TimeoutError:
        logger.error(f"Timeout switching context to {context_name}")
        raise Exception("kubectl use-context timed out")
    except Exception as e:
        logger.error(f"Error switching context to {context_name}: {str(e)}")
        raise


async def validate_context_exists(context_name: str) -> bool:
    """
    Validate that a kubectl context exists in the kubeconfig.

    Args:
        context_name: Name of the context to validate

    Returns:
        True if context exists, False otherwise

    Example:
        >>> exists = await validate_context_exists("my-cluster")
        >>> if not exists:
        ...     print("Context not found")
    """
    try:
        config = await get_all_contexts()
        if not config:
            return False

        contexts = config.get('contexts', [])
        for context in contexts:
            if context.get('name') == context_name:
                return True

        return False

    except Exception as e:
        logger.error(f"Error validating context {context_name}: {str(e)}")
        return False


async def get_server_url_for_context(context_name: str) -> Optional[str]:
    """
    Get Kubernetes API server URL for a specific context.

    Args:
        context_name: Name of the kubectl context

    Returns:
        Server URL or None if not found

    Example:
        >>> url = await get_server_url_for_context("my-cluster")
        >>> print(url)
        'https://xxx.eks.amazonaws.com'
    """
    try:
        config = await get_all_contexts()
        if not config:
            return None

        # Find the context
        contexts = config.get('contexts', [])
        cluster_name = None

        for context in contexts:
            if context.get('name') == context_name:
                cluster_name = context.get('context', {}).get('cluster')
                break

        if not cluster_name:
            return None

        # Find the cluster's server URL
        clusters = config.get('clusters', [])
        for cluster in clusters:
            if cluster.get('name') == cluster_name:
                return cluster.get('cluster', {}).get('server')

        return None

    except Exception as e:
        logger.error(f"Error getting server URL for {context_name}: {str(e)}")
        return None


async def check_kubectl_available() -> bool:
    """
    Check if kubectl is installed and available.

    Returns:
        True if kubectl is available, False otherwise

    Example:
        >>> available = await check_kubectl_available()
        >>> if not available:
        ...     raise Exception("kubectl not installed")
    """
    try:
        result = await asyncio.create_subprocess_exec(
            'kubectl', 'version', '--client', '--output=json',
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )

        stdout, stderr = await asyncio.wait_for(
            result.communicate(),
            timeout=10.0
        )

        return result.returncode == 0

    except Exception as e:
        logger.error(f"Error checking kubectl availability: {str(e)}")
        return False
