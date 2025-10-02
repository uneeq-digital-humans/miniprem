"""
CommandExecutor: Central command execution with privilege detection and authentication.

This module provides secure command execution with automatic privilege detection,
authentication management, and cross-platform compatibility for Docker and
Kubernetes monitoring operations.
"""

import asyncio
import logging
import os
import platform
import re
from dataclasses import dataclass
from enum import Enum
from typing import Dict, List, Optional, Tuple, Any, Union
from pathlib import Path

logger = logging.getLogger(__name__)


class CommandType(Enum):
    """Enumeration of supported command types."""
    DOCKER = "docker"
    KUBECTL = "kubectl"
    SYSTEM = "system"


class PrivilegeLevel(Enum):
    """Enumeration of privilege levels."""
    DIRECT = "direct"           # Command can run directly
    SUDO = "sudo"              # Command requires sudo
    AWS_PROFILE = "aws_profile" # Command requires AWS profile
    AUTH_REQUIRED = "auth_required" # Authentication required but method TBD
    UNAVAILABLE = "unavailable" # Command/tool not available


@dataclass
class CommandResult:
    """
    Result of command execution.

    Attributes:
        success: Whether the command succeeded
        stdout: Standard output from command
        stderr: Standard error from command
        return_code: Command exit code
        command_used: Actual command that was executed (including prefixes)
        privilege_level: Privilege level used for execution
        execution_time: Time taken to execute command in seconds
    """
    success: bool
    stdout: str
    stderr: str
    return_code: int
    command_used: List[str]
    privilege_level: PrivilegeLevel
    execution_time: float


@dataclass
class AuthChallenge:
    """
    Authentication challenge sent to client.

    Attributes:
        challenge_id: Unique identifier for this challenge
        challenge_type: Type of authentication required
        message: Human-readable message for the user
        command_type: Type of command that triggered the challenge
        retry_count: Number of retry attempts remaining
    """
    challenge_id: str
    challenge_type: str
    message: str
    command_type: CommandType
    retry_count: int = 3


class CommandExecutionError(Exception):
    """Custom exception for command execution errors."""

    def __init__(self, message: str, return_code: int = None, stderr: str = None):
        super().__init__(message)
        self.return_code = return_code
        self.stderr = stderr


class PrivilegeError(CommandExecutionError):
    """Exception raised when command fails due to insufficient privileges."""
    pass


class CommandExecutor:
    """
    Central command executor with privilege detection and authentication.

    This class manages command execution across different platforms and handles
    privilege detection, authentication challenges, and session management.
    """

    # Platform-specific privilege detection patterns
    PERMISSION_DENIED_PATTERNS = [
        r"permission denied",
        r"access denied",
        r"operation not permitted",
        r"connect: permission denied",
        r"got permission denied while trying to connect",
        r"dial unix.*permission denied",
        r"cannot connect to the docker daemon",
        r"error response from daemon.*permission denied"
    ]

    # Safe commands for privilege detection
    PROBE_COMMANDS = {
        CommandType.DOCKER: ["docker", "info"],
        CommandType.KUBECTL: ["kubectl", "version", "--client"],
    }

    # Command whitelist for security
    ALLOWED_COMMANDS = {
        CommandType.DOCKER: {
            "info", "version", "ps", "images", "stats", "logs",
            "inspect", "system", "network", "volume"
        },
        CommandType.KUBECTL: {
            "version", "cluster-info", "get", "describe", "logs",
            "config", "api-resources", "api-versions"
        }
    }

    def __init__(self):
        """Initialize the CommandExecutor."""
        self._privilege_map: Dict[CommandType, PrivilegeLevel] = {}
        self._command_prefixes: Dict[CommandType, List[str]] = {}
        self._auth_manager = None  # Will be injected
        self._session_manager = None  # Will be injected
        self._platform = platform.system().lower()
        self._aws_profiles = {}
        self._detection_complete = False
        logger.info(f"CommandExecutor initialized for platform: {self._platform}")

    def set_auth_manager(self, auth_manager):
        """Inject the auth manager dependency."""
        self._auth_manager = auth_manager

    def set_session_manager(self, session_manager):
        """Inject the session manager dependency."""
        self._session_manager = session_manager

    async def detect_privileges(self) -> Dict[CommandType, PrivilegeLevel]:
        """
        Perform pre-flight privilege detection for all command types.

        Returns:
            Dict mapping command types to their required privilege levels
        """
        logger.info("Starting pre-flight privilege detection...")

        for command_type in [CommandType.DOCKER, CommandType.KUBECTL]:
            await self._detect_command_privileges(command_type)

        self._detection_complete = True
        logger.info(f"Privilege detection complete: {self._privilege_map}")
        return self._privilege_map.copy()

    async def _detect_command_privileges(self, command_type: CommandType) -> PrivilegeLevel:
        """
        Detect privilege requirements for a specific command type.

        Args:
            command_type: Type of command to detect privileges for

        Returns:
            Required privilege level for the command type
        """
        if command_type not in self.PROBE_COMMANDS:
            self._privilege_map[command_type] = PrivilegeLevel.UNAVAILABLE
            return PrivilegeLevel.UNAVAILABLE

        probe_command = self.PROBE_COMMANDS[command_type]

        # First, try direct execution
        try:
            result = await self._execute_raw_command(probe_command, timeout=10)
            if result.return_code == 0:
                self._privilege_map[command_type] = PrivilegeLevel.DIRECT
                self._command_prefixes[command_type] = []
                logger.info(f"{command_type.value}: Direct execution works")
                return PrivilegeLevel.DIRECT
        except Exception as e:
            logger.debug(f"Direct execution failed for {command_type.value}: {e}")

        # Check if error indicates permission issue
        if self._is_permission_error(result.stderr if 'result' in locals() else str(e)):
            # Try passwordless sudo
            try:
                sudo_command = ["sudo", "-n"] + probe_command
                result = await self._execute_raw_command(sudo_command, timeout=10)
                if result.return_code == 0:
                    self._privilege_map[command_type] = PrivilegeLevel.DIRECT
                    self._command_prefixes[command_type] = ["sudo"]
                    logger.info(f"{command_type.value}: Passwordless sudo works")
                    return PrivilegeLevel.DIRECT
            except Exception as sudo_e:
                logger.debug(f"Passwordless sudo failed for {command_type.value}: {sudo_e}")

            # Requires sudo with password
            self._privilege_map[command_type] = PrivilegeLevel.SUDO
            self._command_prefixes[command_type] = ["sudo"]
            logger.info(f"{command_type.value}: Requires sudo with password")
            return PrivilegeLevel.SUDO

        # For kubectl, check if it's an AWS EKS cluster
        if command_type == CommandType.KUBECTL:
            return await self._detect_kubernetes_auth()

        # Command not available
        self._privilege_map[command_type] = PrivilegeLevel.UNAVAILABLE
        logger.warning(f"{command_type.value}: Command not available")
        return PrivilegeLevel.UNAVAILABLE

    async def _detect_kubernetes_auth(self) -> PrivilegeLevel:
        """
        Detect Kubernetes authentication requirements with enhanced EKS detection.

        Returns:
            Required privilege level for kubectl commands
        """
        try:
            # Check current context
            result = await self._execute_raw_command(
                ["kubectl", "config", "current-context"], timeout=5
            )

            if result.return_code == 0:
                context = result.stdout.strip()
                logger.info(f"Kubectl current context: {context}")

                # Enhanced EKS detection
                is_eks_cluster = await self._is_eks_cluster(context)

                if is_eks_cluster:
                    # Detect AWS profiles and validate EKS access
                    await self._detect_aws_profiles()

                    # Test if current AWS credentials work
                    if await self._test_eks_access():
                        self._privilege_map[CommandType.KUBECTL] = PrivilegeLevel.DIRECT
                        self._command_prefixes[CommandType.KUBECTL] = []
                        return PrivilegeLevel.DIRECT
                    else:
                        self._privilege_map[CommandType.KUBECTL] = PrivilegeLevel.AWS_PROFILE
                        return PrivilegeLevel.AWS_PROFILE

                # For non-EKS clusters, try direct connection
                cluster_result = await self._execute_raw_command(
                    ["kubectl", "cluster-info", "--request-timeout=5s"], timeout=10
                )

                if cluster_result.return_code == 0:
                    self._privilege_map[CommandType.KUBECTL] = PrivilegeLevel.DIRECT
                    self._command_prefixes[CommandType.KUBECTL] = []
                    return PrivilegeLevel.DIRECT
                else:
                    self._privilege_map[CommandType.KUBECTL] = PrivilegeLevel.AUTH_REQUIRED
                    return PrivilegeLevel.AUTH_REQUIRED

        except Exception as e:
            logger.warning(f"Kubernetes auth detection failed: {e}")

        self._privilege_map[CommandType.KUBECTL] = PrivilegeLevel.UNAVAILABLE
        return PrivilegeLevel.UNAVAILABLE

    async def _detect_aws_profiles(self) -> None:
        """Detect available AWS profiles."""
        aws_config_paths = [
            Path.home() / ".aws" / "config",
            Path.home() / ".aws" / "credentials"
        ]

        profiles = set()

        # Check environment variable
        if os.getenv("AWS_PROFILE"):
            profiles.add(os.getenv("AWS_PROFILE"))

        # Parse AWS config files
        for config_path in aws_config_paths:
            if config_path.exists():
                try:
                    with open(config_path, 'r') as f:
                        content = f.read()
                        # Simple regex to find profile names
                        profile_matches = re.findall(r'\[(?:profile\s+)?([^\]]+)\]', content)
                        profiles.update(profile_matches)
                except Exception as e:
                    logger.debug(f"Failed to parse AWS config {config_path}: {e}")

        self._aws_profiles = {profile: profile for profile in profiles if profile != "default"}
        logger.info(f"Detected AWS profiles: {list(self._aws_profiles.keys())}")

    async def _is_eks_cluster(self, context: str) -> bool:
        """
        Determine if the current kubectl context is an EKS cluster.

        Args:
            context: Kubectl context name

        Returns:
            bool: True if context appears to be EKS
        """
        # Check context name for EKS patterns
        eks_patterns = ["eks", "aws", ".us-", ".eu-", ".ap-", ".ca-", ".me-", ".af-", ".sa-"]
        if any(pattern in context.lower() for pattern in eks_patterns):
            logger.info(f"Context '{context}' matches EKS pattern")
            return True

        try:
            # Check cluster configuration for EKS indicators
            config_result = await self._execute_raw_command(
                ["kubectl", "config", "view", "--minify", "-o", "json"], timeout=5
            )

            if config_result.return_code == 0:
                import json
                config_data = json.loads(config_result.stdout)
                clusters = config_data.get("clusters", [])

                for cluster in clusters:
                    server = cluster.get("cluster", {}).get("server", "")
                    if "eks.amazonaws.com" in server or ".eks." in server:
                        logger.info(f"Found EKS server URL in config: {server}")
                        return True

        except Exception as e:
            logger.debug(f"Failed to analyze kubectl config for EKS: {e}")

        return False

    async def _test_eks_access(self) -> bool:
        """
        Test if current AWS credentials can access the EKS cluster.

        Returns:
            bool: True if EKS access works
        """
        try:
            # Try a simple kubectl command that requires authentication
            result = await self._execute_raw_command(
                ["kubectl", "auth", "can-i", "get", "pods", "--request-timeout=10s"], timeout=15
            )

            if result.return_code == 0 and "yes" in result.stdout.lower():
                logger.info("EKS authentication successful with current credentials")
                return True

        except Exception as e:
            logger.debug(f"EKS access test failed: {e}")

        logger.info("EKS authentication required - current credentials insufficient")
        return False

    def _is_permission_error(self, error_text: str) -> bool:
        """
        Check if error text indicates a permission/privilege issue.

        Args:
            error_text: Error text to analyze

        Returns:
            True if error indicates permission issue
        """
        if not error_text:
            return False

        error_lower = error_text.lower()
        return any(
            re.search(pattern, error_lower, re.IGNORECASE)
            for pattern in self.PERMISSION_DENIED_PATTERNS
        )

    async def execute_command(
        self,
        command_type: CommandType,
        command: List[str],
        timeout: int = 30,
        require_auth: bool = True
    ) -> CommandResult:
        """
        Execute a command with appropriate privilege handling.

        Args:
            command_type: Type of command being executed
            command: Command parts to execute
            timeout: Command timeout in seconds
            require_auth: Whether to require authentication if needed

        Returns:
            CommandResult with execution details

        Raises:
            CommandExecutionError: If command execution fails
            PrivilegeError: If authentication is required but not available
        """
        if not self._detection_complete:
            await self.detect_privileges()

        # Validate command
        if not self._validate_command(command_type, command):
            raise CommandExecutionError(f"Command not allowed: {command}")

        # Get privilege level and prefix
        privilege_level = self._privilege_map.get(command_type, PrivilegeLevel.UNAVAILABLE)

        if privilege_level == PrivilegeLevel.UNAVAILABLE:
            raise CommandExecutionError(f"Command type {command_type.value} not available")

        # Handle authentication if required
        if privilege_level in [PrivilegeLevel.SUDO, PrivilegeLevel.AWS_PROFILE, PrivilegeLevel.AUTH_REQUIRED]:
            if require_auth and not await self._is_authenticated(command_type):
                raise PrivilegeError(f"Authentication required for {command_type.value}")

        # Build final command with prefixes
        final_command = self._build_command(command_type, command)

        # Execute command
        start_time = asyncio.get_event_loop().time()
        raw_result = await self._execute_raw_command(final_command, timeout)
        execution_time = asyncio.get_event_loop().time() - start_time

        return CommandResult(
            success=raw_result.return_code == 0,
            stdout=raw_result.stdout,
            stderr=raw_result.stderr,
            return_code=raw_result.return_code,
            command_used=final_command,
            privilege_level=privilege_level,
            execution_time=execution_time
        )

    def _validate_command(self, command_type: CommandType, command: List[str]) -> bool:
        """
        Validate that a command is allowed to be executed.

        Args:
            command_type: Type of command
            command: Command parts to validate

        Returns:
            True if command is allowed
        """
        if command_type not in self.ALLOWED_COMMANDS:
            return False

        if not command:
            return False

        # Check if the base command is allowed
        base_command = command[0].lower()
        if base_command not in [command_type.value]:
            return False

        # Check if subcommand is allowed
        if len(command) > 1:
            subcommand = command[1].lower()
            allowed_subcommands = self.ALLOWED_COMMANDS[command_type]
            if subcommand not in allowed_subcommands:
                return False

        return True

    def _build_command(self, command_type: CommandType, command: List[str]) -> List[str]:
        """
        Build the final command with appropriate prefixes and environment variables.

        Args:
            command_type: Type of command
            command: Base command parts

        Returns:
            Complete command with prefixes and environment
        """
        prefixes = self._command_prefixes.get(command_type, [])

        # Handle AWS profile for kubectl
        if command_type == CommandType.KUBECTL and self._privilege_map.get(command_type) == PrivilegeLevel.AWS_PROFILE:
            # Get AWS profile from session manager
            if self._session_manager:
                # Use get_command_prefixes method to get the profile from session
                session_prefixes = self._session_manager.get_command_prefixes("current_client")
                kubectl_prefixes = session_prefixes.get(CommandType.KUBECTL, [])
                if kubectl_prefixes:
                    return kubectl_prefixes + prefixes + command

            # Fallback: use AWS_PROFILE environment variable if set
            if os.getenv("AWS_PROFILE"):
                return ["env", f"AWS_PROFILE={os.getenv('AWS_PROFILE')}"] + prefixes + command

        return prefixes + command

    async def _is_authenticated(self, command_type: CommandType) -> bool:
        """
        Check if authentication is available for a command type.

        Args:
            command_type: Type of command to check authentication for

        Returns:
            True if authentication is available
        """
        if not self._session_manager:
            return False

        privilege_level = self._privilege_map.get(command_type)

        if privilege_level == PrivilegeLevel.SUDO:
            return self._session_manager.is_sudo_authenticated()
        elif privilege_level == PrivilegeLevel.AWS_PROFILE:
            return self._session_manager.is_aws_authenticated()

        return True

    async def _execute_raw_command(
        self,
        command: List[str],
        timeout: int = 30
    ) -> CommandResult:
        """
        Execute a raw command without privilege handling.

        Args:
            command: Command parts to execute
            timeout: Command timeout in seconds

        Returns:
            CommandResult with execution details
        """
        try:
            process = await asyncio.create_subprocess_exec(
                *command,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                stdin=asyncio.subprocess.PIPE if "sudo" in command else None
            )

            start_time = asyncio.get_event_loop().time()
            stdout, stderr = await asyncio.wait_for(
                process.communicate(),
                timeout=timeout
            )
            execution_time = asyncio.get_event_loop().time() - start_time

            return CommandResult(
                success=process.returncode == 0,
                stdout=stdout.decode('utf-8', errors='replace'),
                stderr=stderr.decode('utf-8', errors='replace'),
                return_code=process.returncode,
                command_used=command,
                privilege_level=PrivilegeLevel.DIRECT,  # Will be overridden by caller
                execution_time=execution_time
            )

        except asyncio.TimeoutError:
            raise CommandExecutionError(f"Command timed out after {timeout} seconds")
        except Exception as e:
            raise CommandExecutionError(f"Command execution failed: {str(e)}")

    def get_privilege_status(self) -> Dict[str, Any]:
        """
        Get current privilege detection status with enhanced AWS and Kubernetes info.

        Returns:
            Dictionary with privilege status information
        """
        return {
            "detection_complete": self._detection_complete,
            "privilege_map": {
                cmd_type.value: privilege.value
                for cmd_type, privilege in self._privilege_map.items()
            },
            "command_prefixes": {
                cmd_type.value: prefixes
                for cmd_type, prefixes in self._command_prefixes.items()
            },
            "platform": self._platform,
            "aws_profiles": list(self._aws_profiles.keys()),
            "current_aws_profile": os.getenv("AWS_PROFILE"),
            "kubernetes_context": self._get_current_k8s_context(),
            "eks_cluster": self._is_eks_context()
        }

    def _get_current_k8s_context(self) -> Optional[str]:
        """Get current Kubernetes context synchronously."""
        try:
            import subprocess
            result = subprocess.run(
                ["kubectl", "config", "current-context"],
                capture_output=True,
                text=True,
                timeout=3
            )
            if result.returncode == 0:
                return result.stdout.strip()
        except Exception:
            pass
        return None

    def _is_eks_context(self) -> bool:
        """Check if current context is EKS."""
        context = self._get_current_k8s_context()
        if context:
            eks_patterns = ["eks", "aws", ".us-", ".eu-", ".ap-", ".ca-", ".me-", ".af-", ".sa-"]
            return any(pattern in context.lower() for pattern in eks_patterns)
        return False

    def get_aws_profiles(self) -> Dict[str, str]:
        """
        Get available AWS profiles.

        Returns:
            Dictionary of AWS profiles
        """
        return self._aws_profiles.copy()

    def get_kubernetes_info(self) -> Dict[str, Any]:
        """
        Get Kubernetes context and cluster information.

        Returns:
            Dictionary with Kubernetes information
        """
        context = self._get_current_k8s_context()
        return {
            "current_context": context,
            "is_eks": self._is_eks_context(),
            "privilege_level": self._privilege_map.get(CommandType.KUBECTL, PrivilegeLevel.UNAVAILABLE).value
        }

    async def test_authentication(self, command_type: CommandType) -> bool:
        """
        Test if authentication is working for a command type.

        Args:
            command_type: Type of command to test

        Returns:
            True if authentication test passes
        """
        try:
            probe_command = self.PROBE_COMMANDS.get(command_type)
            if not probe_command:
                return False

            result = await self.execute_command(
                command_type,
                probe_command,
                timeout=10,
                require_auth=False
            )
            return result.success
        except Exception as e:
            logger.warning(f"Authentication test failed for {command_type.value}: {e}")
            return False