from pydantic import BaseModel, Field, validator
from typing import Dict, List, Optional, Literal
from datetime import datetime
import re

class CommandRequest(BaseModel):
    type: Literal["command", "subscribe", "unsubscribe"]
    target: Literal["docker", "kubernetes", "system", "services", "connections"]
    command: str
    params: Optional[Dict[str, str]] = {}
    requestId: str = Field(..., min_length=1)

    @validator('command')
    def validate_command(cls, v, values):
        target = values.get('target')
        allowed_commands = {
            'docker': ['ps', 'stats', 'logs', 'health'],
            'kubernetes': ['pods', 'nodes', 'logs', 'health'],
            'system': ['metrics', 'info', 'health'],
            'services': ['availability'],
            'connections': ['stats']
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