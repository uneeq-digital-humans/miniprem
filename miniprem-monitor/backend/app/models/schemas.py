from pydantic import BaseModel, Field, validator
from typing import Dict, List, Optional, Literal, Union
from datetime import datetime
from enum import Enum
import re

class CommandRequest(BaseModel):
    type: Literal["command", "subscribe", "unsubscribe"]
    target: Literal["docker", "kubernetes", "system", "services", "connections", "aws", "regions"]
    command: str
    params: Optional[Dict[str, str]] = {}
    requestId: str = Field(..., min_length=1)
    region: Optional[str] = None

    @validator('command')
    def validate_command(cls, v, values):
        target = values.get('target')
        allowed_commands = {
            'docker': ['ps', 'stats', 'logs', 'health', 'start', 'stop', 'restart', 'status'],
            'kubernetes': ['pods', 'nodes', 'logs', 'health', 'start', 'stop', 'restart', 'status', 'contexts', 'clusters'],
            'system': ['metrics', 'info', 'health'],
            'services': ['availability', 'start', 'stop', 'restart'],
            'connections': ['stats'],
            'aws': ['regions', 'contexts', 'clusters'],
            'regions': ['list', 'contexts', 'status']
        }
        if target and v not in allowed_commands.get(target, []):
            raise ValueError(f'Invalid command {v} for target {target}')
        return v

    @validator('params')
    def validate_params(cls, v, values):
        if not v:
            return v

        # Sanitize container/pod names
        for key, value in v.items():
            if key in ['container', 'pod', 'namespace']:
                if not re.match(r'^[a-zA-Z0-9-_]{1,63}$', value):
                    raise ValueError(f'Invalid {key} name format')
        return v

class CommandResponse(BaseModel):
    requestId: str
    success: bool
    data: Optional[Dict] = None
    error: Optional[str] = None
    timestamp: datetime = Field(default_factory=datetime.utcnow)

class ContainerStatus(BaseModel):
    name: str
    status: str
    image: str
    ports: List[str] = []
    created: str
    cpu_usage: Optional[str] = None
    memory_usage: Optional[str] = None

class PodStatus(BaseModel):
    name: str
    namespace: str
    status: str
    ready: str
    restarts: int
    age: str
    node: Optional[str] = None
    cpu_usage: Optional[str] = None
    memory_usage: Optional[str] = None

class SystemMetrics(BaseModel):
    cpu_percent: float
    memory_percent: float
    disk_percent: float
    network_io: Dict[str, int]
    timestamp: datetime = Field(default_factory=datetime.utcnow)

# AWS Region Management Models
class AwsRegion(BaseModel):
    """AWS region information model."""
    name: str = Field(..., description="Region name (e.g., us-east-1)")
    display_name: str = Field(..., description="Human-readable display name")
    available: bool = Field(default=True, description="Whether region is available for operations")
    endpoint: Optional[str] = Field(None, description="Regional service endpoint")

class RegionStatus(BaseModel):
    """Status information for an AWS region."""
    region: str
    available: bool
    cluster_count: int = Field(default=0)
    last_checked: datetime = Field(default_factory=datetime.utcnow)
    error: Optional[str] = None

# Kubernetes Context and Cluster Models
class KubernetesContext(BaseModel):
    """Kubernetes context information."""
    name: str
    cluster: str
    user: str
    namespace: str = Field(default="default")
    current: bool = Field(default=False)
    region: Optional[str] = None

class ClusterInfo(BaseModel):
    """Kubernetes cluster detailed information."""
    name: str
    region: str
    status: Literal["running", "stopped", "pending", "error", "unknown"]
    context: Optional[str] = None
    version: Optional[Dict[str, str]] = None
    node_count: int = Field(default=0)
    available: bool = Field(default=True)
    endpoint: Optional[str] = None
    created_at: Optional[datetime] = None
    last_activity: Optional[datetime] = None

# Service Control Models
class ServiceControlRequest(BaseModel):
    """Request model for service start/stop operations."""
    action: Literal["start", "stop", "restart", "status"]
    service_type: Literal["docker", "kubernetes"]
    region: Optional[str] = None
    cluster_name: Optional[str] = None
    force: bool = Field(default=False, description="Force operation without confirmation")

    @validator('region')
    def validate_region(cls, v, values):
        if values.get('service_type') == 'kubernetes' and not v:
            raise ValueError('Region is required for Kubernetes operations')
        return v

    @validator('cluster_name')
    def validate_cluster_name(cls, v, values):
        if values.get('service_type') == 'kubernetes' and not v:
            raise ValueError('Cluster name is required for Kubernetes operations')
        return v

class ServiceControlResponse(BaseModel):
    """Response model for service control operations."""
    success: bool
    action: str
    service_type: str
    region: Optional[str] = None
    cluster_name: Optional[str] = None
    status: Optional[str] = None
    message: Optional[str] = None
    error: Optional[str] = None
    execution_time: Optional[float] = None
    timestamp: datetime = Field(default_factory=datetime.utcnow)

# Docker Service Models
class DockerEngineStatus(BaseModel):
    """Docker engine status information."""
    available: bool
    running: bool
    version: Optional[str] = None
    api_version: Optional[str] = None
    containers_running: int = Field(default=0)
    containers_paused: int = Field(default=0)
    containers_stopped: int = Field(default=0)
    images_count: int = Field(default=0)
    error: Optional[str] = None
    last_checked: datetime = Field(default_factory=datetime.utcnow)

class DockerServiceRequest(BaseModel):
    """Request model for Docker service operations."""
    action: Literal["start", "stop", "restart", "status"]
    force: bool = Field(default=False)

class DockerServiceResponse(BaseModel):
    """Response model for Docker service operations."""
    success: bool
    action: str
    status: Optional[str] = None
    message: Optional[str] = None
    error: Optional[str] = None
    engine_status: Optional[DockerEngineStatus] = None
    execution_time: Optional[float] = None
    timestamp: datetime = Field(default_factory=datetime.utcnow)

# Enhanced Region Management Models
class RegionListResponse(BaseModel):
    """Response model for available AWS regions list."""
    success: bool
    regions: List[AwsRegion]
    total_count: int
    timestamp: datetime = Field(default_factory=datetime.utcnow)

class RegionContextsResponse(BaseModel):
    """Response model for Kubernetes contexts by region."""
    success: bool
    region: str
    contexts: List[KubernetesContext]
    clusters: List[ClusterInfo]
    current_context: Optional[str] = None
    error: Optional[str] = None
    timestamp: datetime = Field(default_factory=datetime.utcnow)