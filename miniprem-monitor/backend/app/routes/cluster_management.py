"""
Cluster Management Routes

Multi-cluster Kubernetes management API endpoints.
Supports AWS EKS, Azure AKS, and Google GKE clusters.

Author: MiniPrem Monitor Backend
Date: 2025-10-16
"""

import logging
from datetime import datetime
from fastapi import APIRouter, HTTPException
from fastapi.responses import JSONResponse
from typing import List, Optional

from ..models.cluster_models import (
    ClusterListResponse,
    ClusterContext,
    ContextSwitchRequest,
    ContextSwitchResponse,
    ClusterBasicInfo,
    ClusterErrorResponse
)
from ..services import kubectl_service

logger = logging.getLogger(__name__)

router = APIRouter(tags=["Cluster Management"])


@router.get(
    "/clusters/list",
    response_model=ClusterListResponse,
    summary="List all Kubernetes clusters",
    description=(
        "Get all available kubectl contexts with metadata including provider, "
        "region, accessibility status, and resource counts."
    )
)
async def list_clusters():
    """
    List all Kubernetes clusters with comprehensive metadata.

    This endpoint retrieves all kubectl contexts from the kubeconfig file,
    enriches them with cloud provider detection, region extraction, and
    real-time accessibility checks.

    Returns:
        ClusterListResponse: Complete cluster list with metadata

    Raises:
        HTTPException: 503 if kubectl is not available
        HTTPException: 500 for unexpected errors

    Example:
        >>> response = requests.get("http://localhost:8000/api/kubernetes/clusters/list")
        >>> print(f"Found {response.json()['total_count']} clusters")
    """
    try:
        # Check if kubectl is available
        kubectl_available = await kubectl_service.check_kubectl_available()
        if not kubectl_available:
            logger.error("kubectl is not available")
            return JSONResponse(
                status_code=503,
                content=ClusterErrorResponse(
                    error="kubectl is not installed or not in PATH",
                    error_type="kubectl_not_available",
                    timestamp=datetime.utcnow()
                ).dict()
            )

        # Get all contexts from kubeconfig
        config = await kubectl_service.get_all_contexts()
        if not config:
            logger.warning("No kubectl contexts found")
            return ClusterListResponse(
                success=True,
                clusters=[],
                current_context=None,
                total_count=0,
                accessible_count=0,
                timestamp=datetime.utcnow()
            )

        # Get current context
        current_context = config.get('current-context')
        logger.info(f"Current context: {current_context}")

        # Parse contexts
        contexts = config.get('contexts', [])
        clusters = config.get('clusters', [])

        cluster_list: List[ClusterContext] = []

        for context_entry in contexts:
            context_name = context_entry.get('name')
            context_details = context_entry.get('context', {})
            cluster_name = context_details.get('cluster', context_name)

            # Get server URL for this context
            server_url = None
            for cluster in clusters:
                if cluster.get('name') == cluster_name:
                    server_url = cluster.get('cluster', {}).get('server')
                    break

            # Detect provider from server URL
            provider = kubectl_service.detect_provider_from_server(server_url or '')

            # Extract region
            region = kubectl_service.extract_region(context_name, server_url or '', provider)

            # Extract short cluster name
            if provider == 'eks':
                # EKS: arn:aws:eks:region:account:cluster/name -> name
                short_name = context_name.split('/')[-1] if '/' in context_name else context_name
            elif provider == 'aks':
                # AKS: typically just the cluster name
                short_name = cluster_name
            elif provider == 'gke':
                # GKE: gke_project_region_name -> name
                parts = context_name.split('_')
                short_name = parts[-1] if len(parts) > 1 else context_name
            else:
                short_name = cluster_name

            # Check if this is the current context
            is_current = (context_name == current_context)

            # Check accessibility (only for current context to save time)
            accessible = False
            node_count = 0
            pod_count = 0

            if is_current:
                logger.info(f"Checking accessibility for current context: {context_name}")
                accessible = await kubectl_service.check_cluster_accessible(context_name)

                if accessible:
                    stats = await kubectl_service.get_cluster_stats(context_name)
                    node_count = stats.get('node_count', 0)
                    pod_count = stats.get('pod_count', 0)
                    logger.info(f"Current cluster: {node_count} nodes, {pod_count} pods")
                else:
                    logger.warning(f"Current cluster {context_name} is not accessible")

            # Create cluster context model
            cluster_context = ClusterContext(
                context_name=context_name,
                cluster_name=short_name,
                provider=provider,
                region=region,
                is_current=is_current,
                accessible=accessible,
                node_count=node_count,
                pod_count=pod_count,
                last_sync=datetime.utcnow(),
                server_url=server_url
            )

            cluster_list.append(cluster_context)

        # Calculate counts
        total_count = len(cluster_list)
        accessible_count = len([c for c in cluster_list if c.accessible])

        logger.info(f"Found {total_count} clusters, {accessible_count} accessible")

        return ClusterListResponse(
            success=True,
            clusters=cluster_list,
            current_context=current_context,
            total_count=total_count,
            accessible_count=accessible_count,
            timestamp=datetime.utcnow()
        )

    except Exception as e:
        error_msg = str(e)
        logger.error(f"Error listing clusters: {error_msg}", exc_info=True)

        return JSONResponse(
            status_code=500,
            content=ClusterErrorResponse(
                error=f"Failed to list clusters: {error_msg}",
                error_type="server_error",
                timestamp=datetime.utcnow()
            ).dict()
        )


@router.post(
    "/context/switch",
    response_model=ContextSwitchResponse,
    summary="Switch kubectl context",
    description=(
        "Switch to a different Kubernetes cluster by changing the active kubectl context. "
        "Returns the new cluster's basic information after successful switch."
    )
)
async def switch_context(request: ContextSwitchRequest):
    """
    Switch kubectl context to specified cluster.

    Args:
        request: ContextSwitchRequest with context_name to switch to

    Returns:
        ContextSwitchResponse: Confirmation with new cluster info

    Raises:
        HTTPException: 404 if context not found
        HTTPException: 500 if switch operation fails
        HTTPException: 502 if cluster is not accessible after switch

    Example:
        >>> payload = {"context_name": "renny-aks-eastus"}
        >>> response = requests.post(
        ...     "http://localhost:8000/api/kubernetes/context/switch",
        ...     json=payload
        ... )
        >>> print(f"Switched to {response.json()['new_context']}")
    """
    context_name = request.context_name

    try:
        logger.info(f"Attempting to switch context to: {context_name}")

        # Get current context before switching
        previous_context = await kubectl_service.get_current_context()

        # Validate that the context exists
        context_exists = await kubectl_service.validate_context_exists(context_name)
        if not context_exists:
            logger.error(f"Context not found: {context_name}")
            return JSONResponse(
                status_code=404,
                content=ClusterErrorResponse(
                    error=f"Context '{context_name}' not found in kubeconfig",
                    error_type="context_not_found",
                    timestamp=datetime.utcnow()
                ).dict()
            )

        # Perform context switch
        try:
            success = await kubectl_service.switch_context(context_name)
            if not success:
                raise Exception("kubectl use-context returned non-zero exit code")
        except Exception as e:
            logger.error(f"Failed to switch context: {str(e)}")
            return JSONResponse(
                status_code=500,
                content=ClusterErrorResponse(
                    error=f"Failed to switch context: {str(e)}",
                    error_type="switch_failed",
                    timestamp=datetime.utcnow()
                ).dict()
            )

        logger.info(f"Successfully switched context to: {context_name}")

        # Get server URL for the new context
        server_url = await kubectl_service.get_server_url_for_context(context_name)

        # Detect provider
        provider = kubectl_service.detect_provider_from_server(server_url or '')

        # Extract region
        region = kubectl_service.extract_region(context_name, server_url or '', provider)

        # Extract short cluster name
        if provider == 'eks':
            short_name = context_name.split('/')[-1] if '/' in context_name else context_name
        elif provider == 'aks':
            short_name = context_name
        elif provider == 'gke':
            parts = context_name.split('_')
            short_name = parts[-1] if len(parts) > 1 else context_name
        else:
            short_name = context_name

        # Check accessibility and get stats
        accessible = await kubectl_service.check_cluster_accessible(context_name)

        if not accessible:
            logger.warning(f"Cluster {context_name} is not accessible after switch")
            # Return success but indicate cluster is not accessible
            cluster_info = ClusterBasicInfo(
                cluster_name=short_name,
                provider=provider,
                region=region,
                node_count=0,
                pod_count=0,
                accessible=False
            )

            return ContextSwitchResponse(
                success=True,
                new_context=context_name,
                cluster_info=cluster_info,
                previous_context=previous_context,
                timestamp=datetime.utcnow(),
                error="Context switched successfully but cluster is not accessible"
            )

        # Get cluster stats
        stats = await kubectl_service.get_cluster_stats(context_name)
        node_count = stats.get('node_count', 0)
        pod_count = stats.get('pod_count', 0)

        logger.info(f"New cluster stats: {node_count} nodes, {pod_count} pods")

        # Build cluster info
        cluster_info = ClusterBasicInfo(
            cluster_name=short_name,
            provider=provider,
            region=region,
            node_count=node_count,
            pod_count=pod_count,
            accessible=True
        )

        return ContextSwitchResponse(
            success=True,
            new_context=context_name,
            cluster_info=cluster_info,
            previous_context=previous_context,
            timestamp=datetime.utcnow()
        )

    except HTTPException:
        # Re-raise HTTP exceptions
        raise
    except Exception as e:
        error_msg = str(e)
        logger.error(f"Unexpected error switching context: {error_msg}", exc_info=True)

        return JSONResponse(
            status_code=500,
            content=ClusterErrorResponse(
                error=f"Unexpected error: {error_msg}",
                error_type="server_error",
                timestamp=datetime.utcnow()
            ).dict()
        )
