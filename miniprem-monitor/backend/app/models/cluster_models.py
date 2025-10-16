"""
Cluster Management Models

Pydantic models for multi-cluster Kubernetes management API endpoints.

Author: MiniPrem Monitor Backend
Date: 2025-10-16
"""

from pydantic import BaseModel, Field, validator
from typing import Dict, List, Optional, Literal
from datetime import datetime


class ClusterContext(BaseModel):
    """
    Individual Kubernetes cluster context with metadata.

    Attributes:
        context_name: Full kubectl context name
        cluster_name: Short cluster name
        provider: Cloud provider (eks, aks, gke, local, unknown)
        region: Cloud region or 'local' for local clusters
        is_current: Whether this is the currently active context
        accessible: Whether the cluster is reachable
        node_count: Number of nodes in the cluster (0 if inaccessible)
        pod_count: Number of pods across all namespaces (0 if inaccessible)
        last_sync: Timestamp of last status check
        server_url: Kubernetes API server URL
    """
    context_name: str = Field(..., description="Full kubectl context name")
    cluster_name: str = Field(..., description="Short cluster name")
    provider: Literal["eks", "aks", "gke", "local", "unknown"] = Field(
        ..., description="Cloud provider type"
    )
    region: str = Field(..., description="Cloud region or 'local'")
    is_current: bool = Field(..., description="Currently active context")
    accessible: bool = Field(..., description="Cluster is reachable")
    node_count: int = Field(default=0, ge=0, description="Number of nodes")
    pod_count: int = Field(default=0, ge=0, description="Number of pods")
    last_sync: datetime = Field(
        default_factory=datetime.utcnow,
        description="Last status check timestamp"
    )
    server_url: Optional[str] = Field(None, description="Kubernetes API server URL")

    class Config:
        json_schema_extra = {
            "example": {
                "context_name": "arn:aws:eks:us-east-1:123456789012:cluster/renny-prod",
                "cluster_name": "renny-prod",
                "provider": "eks",
                "region": "us-east-1",
                "is_current": True,
                "accessible": True,
                "node_count": 12,
                "pod_count": 48,
                "last_sync": "2025-10-16T10:30:00Z",
                "server_url": "https://XXXXX.gr7.us-east-1.eks.amazonaws.com"
            }
        }


class ClusterListResponse(BaseModel):
    """
    Response model for /api/kubernetes/clusters/list endpoint.

    Attributes:
        success: Whether the operation succeeded
        clusters: List of all available cluster contexts
        current_context: Name of the currently active context
        total_count: Total number of clusters
        accessible_count: Number of accessible clusters
        timestamp: Response generation timestamp
        error: Error message if operation failed
    """
    success: bool = Field(..., description="Operation success status")
    clusters: List[ClusterContext] = Field(
        default_factory=list,
        description="List of cluster contexts"
    )
    current_context: Optional[str] = Field(
        None,
        description="Currently active context name"
    )
    total_count: int = Field(default=0, ge=0, description="Total cluster count")
    accessible_count: int = Field(default=0, ge=0, description="Accessible cluster count")
    timestamp: datetime = Field(
        default_factory=datetime.utcnow,
        description="Response timestamp"
    )
    error: Optional[str] = Field(None, description="Error message if failed")

    @validator('accessible_count', always=True)
    def validate_accessible_count(cls, v, values):
        """Ensure accessible_count matches the actual count in clusters list."""
        clusters = values.get('clusters', [])
        if clusters:
            actual_count = len([c for c in clusters if c.accessible])
            return actual_count
        return v

    class Config:
        json_schema_extra = {
            "example": {
                "success": True,
                "clusters": [
                    {
                        "context_name": "arn:aws:eks:us-east-1:123456789012:cluster/renny-prod",
                        "cluster_name": "renny-prod",
                        "provider": "eks",
                        "region": "us-east-1",
                        "is_current": True,
                        "accessible": True,
                        "node_count": 12,
                        "pod_count": 48,
                        "last_sync": "2025-10-16T10:30:00Z",
                        "server_url": "https://XXXXX.eks.amazonaws.com"
                    }
                ],
                "current_context": "arn:aws:eks:us-east-1:123456789012:cluster/renny-prod",
                "total_count": 2,
                "accessible_count": 1,
                "timestamp": "2025-10-16T10:30:00Z",
                "error": None
            }
        }


class ContextSwitchRequest(BaseModel):
    """
    Request model for /api/kubernetes/context/switch endpoint.

    Attributes:
        context_name: Full kubectl context name to switch to
    """
    context_name: str = Field(
        ...,
        min_length=1,
        description="Full kubectl context name to switch to"
    )

    @validator('context_name')
    def validate_context_name(cls, v):
        """Ensure context name is not empty and has valid characters."""
        if not v or not v.strip():
            raise ValueError("context_name cannot be empty")
        return v.strip()

    class Config:
        json_schema_extra = {
            "example": {
                "context_name": "renny-aks-eastus"
            }
        }


class ClusterBasicInfo(BaseModel):
    """
    Basic cluster information returned after context switch.

    Attributes:
        cluster_name: Short cluster name
        provider: Cloud provider type
        region: Cloud region
        node_count: Number of nodes
        pod_count: Number of pods
        accessible: Whether cluster is accessible
    """
    cluster_name: str = Field(..., description="Short cluster name")
    provider: str = Field(..., description="Cloud provider")
    region: str = Field(..., description="Cloud region")
    node_count: int = Field(default=0, ge=0, description="Number of nodes")
    pod_count: int = Field(default=0, ge=0, description="Number of pods")
    accessible: bool = Field(..., description="Cluster accessibility")

    class Config:
        json_schema_extra = {
            "example": {
                "cluster_name": "renny-aks",
                "provider": "aks",
                "region": "eastus",
                "node_count": 10,
                "pod_count": 40,
                "accessible": True
            }
        }


class ContextSwitchResponse(BaseModel):
    """
    Response model for /api/kubernetes/context/switch endpoint.

    Attributes:
        success: Whether the context switch succeeded
        new_context: Name of the new active context
        cluster_info: Basic information about the new cluster
        previous_context: Name of the previous context (if any)
        timestamp: Response timestamp
        error: Error message if operation failed
    """
    success: bool = Field(..., description="Operation success status")
    new_context: str = Field(..., description="New active context name")
    cluster_info: Optional[ClusterBasicInfo] = Field(
        None,
        description="Basic cluster information"
    )
    previous_context: Optional[str] = Field(
        None,
        description="Previous active context"
    )
    timestamp: datetime = Field(
        default_factory=datetime.utcnow,
        description="Response timestamp"
    )
    error: Optional[str] = Field(None, description="Error message if failed")

    class Config:
        json_schema_extra = {
            "example": {
                "success": True,
                "new_context": "renny-aks-eastus",
                "cluster_info": {
                    "cluster_name": "renny-aks",
                    "provider": "aks",
                    "region": "eastus",
                    "node_count": 10,
                    "pod_count": 40,
                    "accessible": True
                },
                "previous_context": "arn:aws:eks:us-east-1:123456789012:cluster/renny-prod",
                "timestamp": "2025-10-16T10:35:00Z",
                "error": None
            }
        }


class ClusterErrorResponse(BaseModel):
    """
    Error response model for cluster management endpoints.

    Attributes:
        success: Always False for error responses
        error: Human-readable error message
        error_type: Machine-readable error code
        timestamp: Error timestamp
    """
    success: bool = Field(default=False, description="Always False for errors")
    error: str = Field(..., description="Error message")
    error_type: Literal[
        "kubectl_not_available",
        "no_contexts",
        "context_not_found",
        "cluster_not_accessible",
        "switch_failed",
        "server_error"
    ] = Field(..., description="Error type code")
    timestamp: datetime = Field(
        default_factory=datetime.utcnow,
        description="Error timestamp"
    )

    class Config:
        json_schema_extra = {
            "example": {
                "success": False,
                "error": "Context 'invalid-cluster' not found in kubeconfig",
                "error_type": "context_not_found",
                "timestamp": "2025-10-16T10:40:00Z"
            }
        }
