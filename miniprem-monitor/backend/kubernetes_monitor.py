"""
Kubernetes monitoring module with secure kubectl command execution.

This module provides secure kubectl command execution with input validation
and command injection prevention for monitoring Kubernetes resources.
"""

import asyncio
import json
import logging
import re
from typing import Dict, List, Any, Optional, Union
from dataclasses import dataclass
from pathlib import Path

from auth.command_executor import CommandExecutor, CommandType, CommandResult, PrivilegeError
from auth.auth_manager import AuthManager
from auth.session_manager import SessionManager


logger = logging.getLogger(__name__)


@dataclass
class KubernetesPod:
    """
    Data class representing a Kubernetes pod.

    Attributes:
        name: Pod name
        namespace: Pod namespace
        status: Current pod status
        ready: Ready status (e.g., "1/1")
        restarts: Number of restarts
        age: Pod age
        node: Node where pod is running
        ip: Pod IP address
    """
    name: str
    namespace: str
    status: str
    ready: str
    restarts: int
    age: str
    node: str
    ip: str


@dataclass
class KubernetesService:
    """
    Data class representing a Kubernetes service.

    Attributes:
        name: Service name
        namespace: Service namespace
        type: Service type (ClusterIP, NodePort, LoadBalancer, etc.)
        cluster_ip: Internal cluster IP
        external_ip: External IP (if applicable)
        ports: Port configuration
        age: Service age
    """
    name: str
    namespace: str
    type: str
    cluster_ip: str
    external_ip: str
    ports: str
    age: str


@dataclass
class KubernetesNode:
    """
    Data class representing a Kubernetes node.

    Attributes:
        name: Node name
        status: Node status (Ready/NotReady)
        roles: Node roles (master, worker, etc.)
        age: Node age
        version: Kubernetes version
        internal_ip: Internal IP address
        external_ip: External IP address
        os_image: Operating system image
        kernel_version: Kernel version
        container_runtime: Container runtime version
    """
    name: str
    status: str
    roles: str
    age: str
    version: str
    internal_ip: str
    external_ip: str
    os_image: str
    kernel_version: str
    container_runtime: str


class KubernetesCommandError(Exception):
    """Custom exception for kubectl command execution errors."""
    pass


class KubernetesMonitor:
    """
    Secure Kubernetes monitoring class with command injection prevention.

    This class provides methods to safely execute kubectl commands and retrieve
    information about pods, services, nodes, and other Kubernetes resources.
    """

    # Whitelist of allowed kubectl commands with their safe parameters
    ALLOWED_COMMANDS = {
        "get_pods": ["kubectl", "get", "pods", "-o", "json"],
        "get_services": ["kubectl", "get", "services", "-o", "json"],
        "get_nodes": ["kubectl", "get", "nodes", "-o", "json"],
        "get_namespaces": ["kubectl", "get", "namespaces", "-o", "json"]
    }

    # Regex patterns for input validation
    NAMESPACE_PATTERN = re.compile(r"^[a-z0-9]([-a-z0-9]*[a-z0-9])?$")
    RESOURCE_NAME_PATTERN = re.compile(r"^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$")

    def __init__(self, command_executor: Optional[CommandExecutor] = None):
        """
        Initialize the Kubernetes monitor.

        Args:
            command_executor: CommandExecutor instance for authentication and privilege detection
        """
        self.command_executor = command_executor or CommandExecutor()
        self.kubectl_available = None
        self._privilege_detected = False

    async def _check_kubectl_availability(self) -> bool:
        """
        Check if kubectl is available and accessible using CommandExecutor.

        Returns:
            bool: True if kubectl is available, False otherwise
        """
        if self.kubectl_available is not None:
            return self.kubectl_available

        try:
            # Use CommandExecutor to check kubectl availability
            if not self._privilege_detected:
                await self.command_executor.detect_privileges()
                self._privilege_detected = True

            # Test kubectl availability
            result = await self.command_executor.execute_command(
                CommandType.KUBECTL,
                ["kubectl", "version", "--client"],
                timeout=10,
                require_auth=False
            )
            self.kubectl_available = result.success

            if result.success:
                logger.info("kubectl is available and accessible")
            else:
                logger.warning(f"kubectl not available: {result.stderr}")

        except Exception as e:
            logger.warning(f"kubectl availability check failed: {str(e)}")
            self.kubectl_available = False

        return self.kubectl_available

    async def _execute_kubectl_command(
        self,
        command: List[str],
        timeout: int = 30,
        require_auth: bool = True
    ) -> CommandResult:
        """
        Execute a kubectl command using CommandExecutor with authentication.

        Args:
            command: List of command parts (prevents shell injection)
            timeout: Command timeout in seconds
            require_auth: Whether to require authentication

        Returns:
            CommandResult: Command execution result

        Raises:
            KubernetesCommandError: If command execution fails
            PrivilegeError: If authentication is required but not available
        """
        try:
            # Ensure privilege detection is complete
            if not self._privilege_detected:
                await self.command_executor.detect_privileges()
                self._privilege_detected = True

            # Execute command through CommandExecutor
            result = await self.command_executor.execute_command(
                CommandType.KUBECTL,
                command,
                timeout=timeout,
                require_auth=require_auth
            )

            if not result.success:
                raise KubernetesCommandError(
                    f"kubectl command failed with return code {result.return_code}: {result.stderr}"
                )

            return result

        except PrivilegeError as e:
            # Re-raise privilege errors for WebSocket authentication handling
            raise e
        except Exception as e:
            raise KubernetesCommandError(f"kubectl command execution failed: {str(e)}")

    def _validate_namespace(self, namespace: str) -> bool:
        """
        Validate namespace name to prevent injection attacks.

        Args:
            namespace: Namespace name to validate

        Returns:
            bool: True if namespace is valid, False otherwise
        """
        if not namespace or len(namespace) > 253:
            return False
        return bool(self.NAMESPACE_PATTERN.match(namespace))

    def _validate_resource_name(self, name: str) -> bool:
        """
        Validate Kubernetes resource name to prevent injection attacks.

        Args:
            name: Resource name to validate

        Returns:
            bool: True if name is valid, False otherwise
        """
        if not name or len(name) > 253:
            return False
        return bool(self.RESOURCE_NAME_PATTERN.match(name))

    def _parse_kubectl_json_output(self, output: str, resource_type: str) -> List[Dict[str, Any]]:
        """
        Parse kubectl JSON output into structured data.

        Args:
            output: Raw JSON output from kubectl command
            resource_type: Type of Kubernetes resource (pods, services, nodes)

        Returns:
            List[Dict[str, Any]]: Parsed resource information

        Raises:
            KubernetesCommandError: If output parsing fails
        """
        try:
            if not output.strip():
                return []

            data = json.loads(output)
            items = data.get("items", [])

            parsed_items = []
            for item in items:
                if resource_type == "pods":
                    parsed_items.append(self._parse_pod_item(item))
                elif resource_type == "services":
                    parsed_items.append(self._parse_service_item(item))
                elif resource_type == "nodes":
                    parsed_items.append(self._parse_node_item(item))
                else:
                    # Generic parsing for other resources
                    parsed_items.append(self._parse_generic_item(item))

            return parsed_items

        except json.JSONDecodeError as e:
            raise KubernetesCommandError(f"Failed to parse kubectl JSON output: {str(e)}")
        except Exception as e:
            raise KubernetesCommandError(f"Unexpected error parsing kubectl output: {str(e)}")

    def _parse_pod_item(self, pod: Dict[str, Any]) -> Dict[str, Any]:
        """
        Parse a single pod item from kubectl JSON output.

        Args:
            pod: Pod JSON object from kubectl

        Returns:
            Dict[str, Any]: Parsed pod information
        """
        metadata = pod.get("metadata", {})
        spec = pod.get("spec", {})
        status = pod.get("status", {})

        # Calculate ready containers
        container_statuses = status.get("containerStatuses", [])
        ready_count = sum(1 for cs in container_statuses if cs.get("ready", False))
        total_count = len(container_statuses)

        # Calculate restarts
        restart_count = sum(cs.get("restartCount", 0) for cs in container_statuses)

        return {
            "name": metadata.get("name", ""),
            "namespace": metadata.get("namespace", ""),
            "status": status.get("phase", "Unknown"),
            "ready": f"{ready_count}/{total_count}",
            "restarts": restart_count,
            "age": metadata.get("creationTimestamp", ""),
            "node": spec.get("nodeName", ""),
            "ip": status.get("podIP", ""),
            "labels": metadata.get("labels", {}),
            "annotations": metadata.get("annotations", {}),
            "conditions": status.get("conditions", [])
        }

    def _parse_service_item(self, service: Dict[str, Any]) -> Dict[str, Any]:
        """
        Parse a single service item from kubectl JSON output.

        Args:
            service: Service JSON object from kubectl

        Returns:
            Dict[str, Any]: Parsed service information
        """
        metadata = service.get("metadata", {})
        spec = service.get("spec", {})
        status = service.get("status", {})

        # Parse ports
        ports = spec.get("ports", [])
        port_strings = []
        for port in ports:
            port_str = f"{port.get('port', '')}"
            if port.get("protocol"):
                port_str += f"/{port['protocol']}"
            if port.get("targetPort"):
                port_str += f":{port['targetPort']}"
            port_strings.append(port_str)

        # Get external IPs
        external_ips = []
        if spec.get("type") == "LoadBalancer":
            lb_ingress = status.get("loadBalancer", {}).get("ingress", [])
            external_ips = [ing.get("ip", ing.get("hostname", "")) for ing in lb_ingress]

        return {
            "name": metadata.get("name", ""),
            "namespace": metadata.get("namespace", ""),
            "type": spec.get("type", "ClusterIP"),
            "cluster_ip": spec.get("clusterIP", ""),
            "external_ip": ",".join(filter(None, external_ips)) or "<none>",
            "ports": ",".join(port_strings),
            "age": metadata.get("creationTimestamp", ""),
            "selector": spec.get("selector", {}),
            "labels": metadata.get("labels", {})
        }

    def _parse_node_item(self, node: Dict[str, Any]) -> Dict[str, Any]:
        """
        Parse a single node item from kubectl JSON output.

        Args:
            node: Node JSON object from kubectl

        Returns:
            Dict[str, Any]: Parsed node information
        """
        metadata = node.get("metadata", {})
        spec = node.get("spec", {})
        status = node.get("status", {})

        # Get node status
        conditions = status.get("conditions", [])
        ready_condition = next((c for c in conditions if c.get("type") == "Ready"), {})
        node_status = "Ready" if ready_condition.get("status") == "True" else "NotReady"

        # Get node roles from labels
        labels = metadata.get("labels", {})
        roles = []
        for key in labels:
            if key.startswith("node-role.kubernetes.io/"):
                role = key.split("/", 1)[1]
                if role:
                    roles.append(role)
        role_str = ",".join(roles) if roles else "<none>"

        # Get addresses
        addresses = status.get("addresses", [])
        internal_ip = next((addr["address"] for addr in addresses if addr["type"] == "InternalIP"), "")
        external_ip = next((addr["address"] for addr in addresses if addr["type"] == "ExternalIP"), "<none>")

        # Get system info
        node_info = status.get("nodeInfo", {})

        return {
            "name": metadata.get("name", ""),
            "status": node_status,
            "roles": role_str,
            "age": metadata.get("creationTimestamp", ""),
            "version": node_info.get("kubeletVersion", ""),
            "internal_ip": internal_ip,
            "external_ip": external_ip,
            "os_image": node_info.get("osImage", ""),
            "kernel_version": node_info.get("kernelVersion", ""),
            "container_runtime": node_info.get("containerRuntimeVersion", ""),
            "labels": labels,
            "taints": spec.get("taints", []),
            "conditions": conditions
        }

    def _parse_generic_item(self, item: Dict[str, Any]) -> Dict[str, Any]:
        """
        Parse a generic Kubernetes resource item.

        Args:
            item: Resource JSON object from kubectl

        Returns:
            Dict[str, Any]: Parsed resource information
        """
        metadata = item.get("metadata", {})
        return {
            "name": metadata.get("name", ""),
            "namespace": metadata.get("namespace", ""),
            "kind": item.get("kind", ""),
            "api_version": item.get("apiVersion", ""),
            "labels": metadata.get("labels", {}),
            "annotations": metadata.get("annotations", {}),
            "creation_timestamp": metadata.get("creationTimestamp", ""),
            "resource_version": metadata.get("resourceVersion", "")
        }

    async def get_pods(self, namespace: Optional[str] = None) -> List[Dict[str, Any]]:
        """
        Get list of Kubernetes pods across all namespaces or in a specific namespace.

        Args:
            namespace: Optional namespace filter

        Returns:
            List[Dict[str, Any]]: List of pod information

        Raises:
            KubernetesCommandError: If kubectl is not available or command fails
        """
        if not await self._check_kubectl_availability():
            raise KubernetesCommandError("kubectl is not available or cannot connect to cluster")

        try:
            command = self.ALLOWED_COMMANDS["get_pods"].copy()

            if namespace:
                if not self._validate_namespace(namespace):
                    raise KubernetesCommandError(f"Invalid namespace: {namespace}")
                command.extend(["-n", namespace])
            else:
                command.append("--all-namespaces")

            result = await self._execute_kubectl_command(command)
            output = result.stdout

            pods = self._parse_kubectl_json_output(output, "pods")
            logger.info(f"Retrieved {len(pods)} Kubernetes pods")

            return pods

        except KubernetesCommandError:
            raise
        except Exception as e:
            raise KubernetesCommandError(f"Failed to get Kubernetes pods: {str(e)}")

    async def get_services(self, namespace: Optional[str] = None) -> List[Dict[str, Any]]:
        """
        Get list of Kubernetes services across all namespaces or in a specific namespace.

        Args:
            namespace: Optional namespace filter

        Returns:
            List[Dict[str, Any]]: List of service information

        Raises:
            KubernetesCommandError: If kubectl is not available or command fails
        """
        if not await self._check_kubectl_availability():
            raise KubernetesCommandError("kubectl is not available or cannot connect to cluster")

        try:
            command = self.ALLOWED_COMMANDS["get_services"].copy()

            if namespace:
                if not self._validate_namespace(namespace):
                    raise KubernetesCommandError(f"Invalid namespace: {namespace}")
                command.extend(["-n", namespace])
            else:
                command.append("--all-namespaces")

            result = await self._execute_kubectl_command(command)
            output = result.stdout

            services = self._parse_kubectl_json_output(output, "services")
            logger.info(f"Retrieved {len(services)} Kubernetes services")

            return services

        except KubernetesCommandError:
            raise
        except Exception as e:
            raise KubernetesCommandError(f"Failed to get Kubernetes services: {str(e)}")

    async def get_nodes(self) -> List[Dict[str, Any]]:
        """
        Get list of Kubernetes nodes with their status information.

        Returns:
            List[Dict[str, Any]]: List of node information

        Raises:
            KubernetesCommandError: If kubectl is not available or command fails
        """
        if not await self._check_kubectl_availability():
            raise KubernetesCommandError("kubectl is not available or cannot connect to cluster")

        try:
            command = self.ALLOWED_COMMANDS["get_nodes"]
            result = await self._execute_kubectl_command(command)
            output = result.stdout

            nodes = self._parse_kubectl_json_output(output, "nodes")
            logger.info(f"Retrieved {len(nodes)} Kubernetes nodes")

            return nodes

        except KubernetesCommandError:
            raise
        except Exception as e:
            raise KubernetesCommandError(f"Failed to get Kubernetes nodes: {str(e)}")

    async def get_namespaces(self) -> List[Dict[str, Any]]:
        """
        Get list of Kubernetes namespaces.

        Returns:
            List[Dict[str, Any]]: List of namespace information

        Raises:
            KubernetesCommandError: If kubectl is not available or command fails
        """
        if not await self._check_kubectl_availability():
            raise KubernetesCommandError("kubectl is not available or cannot connect to cluster")

        try:
            command = self.ALLOWED_COMMANDS["get_namespaces"]
            result = await self._execute_kubectl_command(command)
            output = result.stdout

            namespaces = self._parse_kubectl_json_output(output, "namespaces")
            logger.info(f"Retrieved {len(namespaces)} Kubernetes namespaces")

            return namespaces

        except KubernetesCommandError:
            raise
        except Exception as e:
            raise KubernetesCommandError(f"Failed to get Kubernetes namespaces: {str(e)}")

    async def get_pod_logs(
        self,
        pod_name: str,
        namespace: str = "default",
        lines: int = 100,
        container: Optional[str] = None
    ) -> List[str]:
        """
        Get logs from a specific Kubernetes pod.

        Args:
            pod_name: Name of the pod
            namespace: Namespace of the pod
            lines: Number of log lines to retrieve
            container: Specific container name (for multi-container pods)

        Returns:
            List[str]: Pod log lines

        Raises:
            KubernetesCommandError: If parameters are invalid or command fails
        """
        if not await self._check_kubectl_availability():
            raise KubernetesCommandError("kubectl is not available or cannot connect to cluster")

        if not self._validate_resource_name(pod_name):
            raise KubernetesCommandError(f"Invalid pod name: {pod_name}")

        if not self._validate_namespace(namespace):
            raise KubernetesCommandError(f"Invalid namespace: {namespace}")

        if not isinstance(lines, int) or lines < 1 or lines > 10000:
            raise KubernetesCommandError("Lines parameter must be between 1 and 10000")

        try:
            command = [
                "kubectl", "logs",
                pod_name,
                "-n", namespace,
                "--tail", str(lines)
            ]

            if container:
                if not self._validate_resource_name(container):
                    raise KubernetesCommandError(f"Invalid container name: {container}")
                command.extend(["-c", container])

            result = await self._execute_kubectl_command(command)
            output = result.stdout

            log_lines = output.strip().split('\n') if output.strip() else []
            logger.info(f"Retrieved {len(log_lines)} log lines for pod {namespace}/{pod_name}")

            return log_lines

        except KubernetesCommandError:
            raise
        except Exception as e:
            raise KubernetesCommandError(f"Failed to get logs for pod {namespace}/{pod_name}: {str(e)}")