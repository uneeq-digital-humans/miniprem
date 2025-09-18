"""
AuthManager: Authentication strategy management for multi-platform privilege handling.

This module implements the Strategy pattern for different authentication methods
across platforms and services, providing a unified interface for authentication
across Docker, Kubernetes, and system commands.
"""

import asyncio
import logging
import platform
import os
import uuid
from abc import ABC, abstractmethod
from dataclasses import dataclass
from enum import Enum
from typing import Dict, List, Optional, Any, Union
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.hazmat.primitives import serialization
import base64
import json

from .command_executor import CommandType, PrivilegeLevel

logger = logging.getLogger(__name__)


class AuthStrategyType(Enum):
    """Types of authentication strategies."""
    SUDO_PASSWORD = "sudo_password"
    PASSWORDLESS_SUDO = "passwordless_sudo"
    AWS_EKS = "aws_eks"
    TOUCH_ID = "touch_id"
    DIRECT = "direct"


@dataclass
class AuthCredentials:
    """
    Authentication credentials container.

    Attributes:
        strategy_type: Type of authentication strategy
        username: Username if applicable
        password: Encrypted password if applicable
        aws_profile: AWS profile name if applicable
        token: Authentication token if applicable
        expires_at: Expiration timestamp
        metadata: Additional authentication metadata
    """
    strategy_type: AuthStrategyType
    username: Optional[str] = None
    password: Optional[str] = None
    aws_profile: Optional[str] = None
    token: Optional[str] = None
    expires_at: Optional[float] = None
    metadata: Optional[Dict[str, Any]] = None


@dataclass
class AuthChallenge:
    """
    Authentication challenge for client interaction.

    Attributes:
        challenge_id: Unique challenge identifier
        strategy_type: Required authentication strategy
        message: Human-readable challenge message
        public_key: RSA public key for encryption (if needed)
        options: Additional challenge options (e.g., AWS profiles)
        retry_count: Number of retry attempts remaining
    """
    challenge_id: str
    strategy_type: AuthStrategyType
    message: str
    public_key: Optional[str] = None
    options: Optional[Dict[str, Any]] = None
    retry_count: int = 3


class AuthStrategy(ABC):
    """Abstract base class for authentication strategies."""

    def __init__(self, auth_manager: 'AuthManager'):
        self.auth_manager = auth_manager
        self.logger = logging.getLogger(f"{__name__}.{self.__class__.__name__}")

    @abstractmethod
    async def can_handle(self, command_type: CommandType, privilege_level: PrivilegeLevel) -> bool:
        """
        Check if this strategy can handle the given command type and privilege level.

        Args:
            command_type: Type of command to authenticate
            privilege_level: Required privilege level

        Returns:
            True if strategy can handle this authentication
        """
        pass

    @abstractmethod
    async def authenticate(self, credentials: AuthCredentials) -> bool:
        """
        Perform authentication with provided credentials.

        Args:
            credentials: Authentication credentials

        Returns:
            True if authentication successful
        """
        pass

    @abstractmethod
    async def create_challenge(self, command_type: CommandType) -> AuthChallenge:
        """
        Create an authentication challenge for the client.

        Args:
            command_type: Type of command requiring authentication

        Returns:
            Authentication challenge for client
        """
        pass

    @abstractmethod
    async def is_authenticated(self, command_type: CommandType) -> bool:
        """
        Check if authentication is currently valid.

        Args:
            command_type: Type of command to check

        Returns:
            True if currently authenticated
        """
        pass

    @abstractmethod
    async def get_command_prefix(self, command_type: CommandType) -> List[str]:
        """
        Get command prefix for authenticated execution.

        Args:
            command_type: Type of command

        Returns:
            Command prefix to prepend to commands
        """
        pass


class SudoPasswordStrategy(AuthStrategy):
    """Authentication strategy for sudo password authentication."""

    def __init__(self, auth_manager: 'AuthManager'):
        super().__init__(auth_manager)
        self._sudo_session_active = False
        self._encrypted_password = None
        self._rsa_private_key = None

    async def can_handle(self, command_type: CommandType, privilege_level: PrivilegeLevel) -> bool:
        """Check if this strategy handles sudo password authentication."""
        return privilege_level == PrivilegeLevel.SUDO

    async def authenticate(self, credentials: AuthCredentials) -> bool:
        """Authenticate using sudo password."""
        if not credentials.password:
            return False

        try:
            # Decrypt password if it's encrypted
            password = await self._decrypt_password(credentials.password)

            # Test sudo authentication
            process = await asyncio.create_subprocess_exec(
                "sudo", "-S", "true",
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            stdout, stderr = await asyncio.wait_for(
                process.communicate(input=f"{password}\n".encode()),
                timeout=10
            )

            if process.returncode == 0:
                self._sudo_session_active = True
                self._encrypted_password = credentials.password
                self.logger.info("Sudo authentication successful")
                return True
            else:
                self.logger.warning(f"Sudo authentication failed: {stderr.decode()}")
                return False

        except Exception as e:
            self.logger.error(f"Sudo authentication error: {e}")
            return False

    async def create_challenge(self, command_type: CommandType) -> AuthChallenge:
        """Create sudo password challenge."""
        # Generate ephemeral RSA key pair
        private_key = rsa.generate_private_key(
            public_exponent=65537,
            key_size=2048
        )
        self._rsa_private_key = private_key

        public_key = private_key.public_key()
        public_key_pem = public_key.serialize(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo
        ).decode()

        challenge_id = str(uuid.uuid4())

        return AuthChallenge(
            challenge_id=challenge_id,
            strategy_type=AuthStrategyType.SUDO_PASSWORD,
            message=f"Sudo password required for {command_type.value} commands. Please enter your password:",
            public_key=public_key_pem,
            retry_count=3
        )

    async def _decrypt_password(self, encrypted_password: str) -> str:
        """Decrypt password using stored private key."""
        if not self._rsa_private_key:
            raise ValueError("No private key available for decryption")

        try:
            encrypted_bytes = base64.b64decode(encrypted_password)
            decrypted_bytes = self._rsa_private_key.decrypt(
                encrypted_bytes,
                padding.OAEP(
                    mgf=padding.MGF1(algorithm=hashes.SHA256()),
                    algorithm=hashes.SHA256(),
                    label=None
                )
            )
            return decrypted_bytes.decode()
        except Exception as e:
            raise ValueError(f"Password decryption failed: {e}")

    async def is_authenticated(self, command_type: CommandType) -> bool:
        """Check if sudo session is active."""
        if not self._sudo_session_active:
            return False

        try:
            # Check if sudo session is still active
            process = await asyncio.create_subprocess_exec(
                "sudo", "-n", "true",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            await process.communicate()

            is_active = process.returncode == 0
            self._sudo_session_active = is_active
            return is_active
        except Exception:
            self._sudo_session_active = False
            return False

    async def get_command_prefix(self, command_type: CommandType) -> List[str]:
        """Get sudo command prefix."""
        return ["sudo"]


class PasswordlessSudoStrategy(AuthStrategy):
    """Authentication strategy for passwordless sudo."""

    def __init__(self, auth_manager: 'AuthManager'):
        super().__init__(auth_manager)
        self._is_passwordless = None

    async def can_handle(self, command_type: CommandType, privilege_level: PrivilegeLevel) -> bool:
        """Check if passwordless sudo is available."""
        if privilege_level != PrivilegeLevel.SUDO:
            return False

        if self._is_passwordless is None:
            await self._check_passwordless_sudo()

        return self._is_passwordless

    async def _check_passwordless_sudo(self) -> bool:
        """Check if passwordless sudo is configured."""
        try:
            process = await asyncio.create_subprocess_exec(
                "sudo", "-n", "true",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            await process.communicate()
            self._is_passwordless = process.returncode == 0
            return self._is_passwordless
        except Exception:
            self._is_passwordless = False
            return False

    async def authenticate(self, credentials: AuthCredentials) -> bool:
        """No authentication needed for passwordless sudo."""
        return await self._check_passwordless_sudo()

    async def create_challenge(self, command_type: CommandType) -> AuthChallenge:
        """No challenge needed for passwordless sudo."""
        return AuthChallenge(
            challenge_id=str(uuid.uuid4()),
            strategy_type=AuthStrategyType.PASSWORDLESS_SUDO,
            message="Passwordless sudo configured - no authentication required",
            retry_count=0
        )

    async def is_authenticated(self, command_type: CommandType) -> bool:
        """Always authenticated for passwordless sudo."""
        return await self._check_passwordless_sudo()

    async def get_command_prefix(self, command_type: CommandType) -> List[str]:
        """Get sudo command prefix."""
        return ["sudo"]


class AwsEksStrategy(AuthStrategy):
    """Authentication strategy for AWS EKS clusters."""

    def __init__(self, auth_manager: 'AuthManager'):
        super().__init__(auth_manager)
        self._current_profile = None
        self._available_profiles = {}

    async def can_handle(self, command_type: CommandType, privilege_level: PrivilegeLevel) -> bool:
        """Check if this handles AWS EKS authentication."""
        return (command_type == CommandType.KUBECTL and
                privilege_level == PrivilegeLevel.AWS_PROFILE)

    async def authenticate(self, credentials: AuthCredentials) -> bool:
        """Authenticate using AWS profile."""
        if not credentials.aws_profile:
            return False

        try:
            # Test AWS profile by running kubectl with the profile
            env = os.environ.copy()
            env["AWS_PROFILE"] = credentials.aws_profile

            process = await asyncio.create_subprocess_exec(
                "kubectl", "version", "--client",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                env=env
            )
            await process.communicate()

            if process.returncode == 0:
                self._current_profile = credentials.aws_profile
                self.logger.info(f"AWS profile authentication successful: {credentials.aws_profile}")
                return True
            else:
                return False

        except Exception as e:
            self.logger.error(f"AWS profile authentication error: {e}")
            return False

    async def create_challenge(self, command_type: CommandType) -> AuthChallenge:
        """Create AWS profile selection challenge."""
        await self._discover_aws_profiles()

        challenge_id = str(uuid.uuid4())

        return AuthChallenge(
            challenge_id=challenge_id,
            strategy_type=AuthStrategyType.AWS_EKS,
            message="AWS profile required for EKS cluster access. Please select a profile:",
            options={
                "profiles": self._available_profiles,
                "current_profile": os.getenv("AWS_PROFILE")
            },
            retry_count=3
        )

    async def _discover_aws_profiles(self) -> None:
        """Discover available AWS profiles."""
        profiles = {}

        # Check environment
        if os.getenv("AWS_PROFILE"):
            profiles["environment"] = os.getenv("AWS_PROFILE")

        # Parse AWS config files
        import configparser
        from pathlib import Path

        aws_config_path = Path.home() / ".aws" / "config"
        if aws_config_path.exists():
            try:
                config = configparser.ConfigParser()
                config.read(aws_config_path)

                for section in config.sections():
                    if section.startswith("profile "):
                        profile_name = section[8:]  # Remove "profile " prefix
                        profiles[profile_name] = profile_name
                    elif section == "default":
                        profiles["default"] = "default"

            except Exception as e:
                self.logger.debug(f"Failed to parse AWS config: {e}")

        self._available_profiles = profiles

    async def is_authenticated(self, command_type: CommandType) -> bool:
        """Check if AWS profile authentication is valid."""
        return self._current_profile is not None

    async def get_command_prefix(self, command_type: CommandType) -> List[str]:
        """Get command prefix with AWS profile."""
        if self._current_profile:
            return ["env", f"AWS_PROFILE={self._current_profile}"]
        return []


class TouchIDStrategy(AuthStrategy):
    """Authentication strategy for macOS Touch ID."""

    def __init__(self, auth_manager: 'AuthManager'):
        super().__init__(auth_manager)
        self._is_available = None

    async def can_handle(self, command_type: CommandType, privilege_level: PrivilegeLevel) -> bool:
        """Check if Touch ID is available for sudo."""
        if platform.system() != "Darwin" or privilege_level != PrivilegeLevel.SUDO:
            return False

        if self._is_available is None:
            await self._check_touch_id_availability()

        return self._is_available

    async def _check_touch_id_availability(self) -> bool:
        """Check if Touch ID is configured for sudo."""
        try:
            # Check if pam_tid.so is in /etc/pam.d/sudo
            with open("/etc/pam.d/sudo", "r") as f:
                content = f.read()
                self._is_available = "pam_tid.so" in content
        except Exception:
            self._is_available = False

        return self._is_available

    async def authenticate(self, credentials: AuthCredentials) -> bool:
        """Touch ID authentication happens at OS level."""
        return await self._check_touch_id_availability()

    async def create_challenge(self, command_type: CommandType) -> AuthChallenge:
        """Create Touch ID challenge."""
        return AuthChallenge(
            challenge_id=str(uuid.uuid4()),
            strategy_type=AuthStrategyType.TOUCH_ID,
            message="Touch ID authentication available. Please authenticate with Touch ID in the system dialog.",
            retry_count=1
        )

    async def is_authenticated(self, command_type: CommandType) -> bool:
        """Touch ID authentication is handled per-command."""
        return True

    async def get_command_prefix(self, command_type: CommandType) -> List[str]:
        """Get sudo prefix for Touch ID."""
        return ["sudo"]


class DirectStrategy(AuthStrategy):
    """Strategy for commands that don't need authentication."""

    async def can_handle(self, command_type: CommandType, privilege_level: PrivilegeLevel) -> bool:
        """Handle direct execution without privileges."""
        return privilege_level == PrivilegeLevel.DIRECT

    async def authenticate(self, credentials: AuthCredentials) -> bool:
        """No authentication needed."""
        return True

    async def create_challenge(self, command_type: CommandType) -> AuthChallenge:
        """No challenge needed."""
        return AuthChallenge(
            challenge_id=str(uuid.uuid4()),
            strategy_type=AuthStrategyType.DIRECT,
            message="No authentication required",
            retry_count=0
        )

    async def is_authenticated(self, command_type: CommandType) -> bool:
        """Always authenticated."""
        return True

    async def get_command_prefix(self, command_type: CommandType) -> List[str]:
        """No prefix needed."""
        return []


class AuthManager:
    """
    Central authentication manager using strategy pattern.

    Manages multiple authentication strategies and provides a unified
    interface for authentication across different platforms and services.
    """

    def __init__(self):
        """Initialize the AuthManager."""
        self.strategies = [
            DirectStrategy(self),
            PasswordlessSudoStrategy(self),
            TouchIDStrategy(self),
            SudoPasswordStrategy(self),
            AwsEksStrategy(self),
        ]
        self._active_challenges: Dict[str, AuthChallenge] = {}
        self.logger = logging.getLogger(__name__)

    async def get_auth_strategy(
        self,
        command_type: CommandType,
        privilege_level: PrivilegeLevel
    ) -> Optional[AuthStrategy]:
        """
        Get appropriate authentication strategy for command type and privilege level.

        Args:
            command_type: Type of command to authenticate
            privilege_level: Required privilege level

        Returns:
            Appropriate authentication strategy or None
        """
        for strategy in self.strategies:
            if await strategy.can_handle(command_type, privilege_level):
                return strategy
        return None

    async def create_auth_challenge(
        self,
        command_type: CommandType,
        privilege_level: PrivilegeLevel
    ) -> Optional[AuthChallenge]:
        """
        Create authentication challenge for client.

        Args:
            command_type: Type of command requiring authentication
            privilege_level: Required privilege level

        Returns:
            Authentication challenge or None if no auth needed
        """
        strategy = await self.get_auth_strategy(command_type, privilege_level)
        if not strategy:
            return None

        challenge = await strategy.create_challenge(command_type)
        self._active_challenges[challenge.challenge_id] = challenge

        self.logger.info(f"Created auth challenge {challenge.challenge_id} for {command_type.value}")
        return challenge

    async def authenticate(
        self,
        challenge_id: str,
        credentials: AuthCredentials
    ) -> bool:
        """
        Process authentication response from client.

        Args:
            challenge_id: ID of the challenge being responded to
            credentials: Authentication credentials from client

        Returns:
            True if authentication successful
        """
        if challenge_id not in self._active_challenges:
            self.logger.warning(f"Unknown challenge ID: {challenge_id}")
            return False

        challenge = self._active_challenges[challenge_id]

        # Find appropriate strategy
        strategy = None
        for s in self.strategies:
            if hasattr(s, 'auth_manager') and s.auth_manager == self:
                if hasattr(s, 'strategy_type') or challenge.strategy_type == AuthStrategyType.DIRECT:
                    if (challenge.strategy_type == AuthStrategyType.DIRECT and isinstance(s, DirectStrategy)) or \
                       (challenge.strategy_type == AuthStrategyType.SUDO_PASSWORD and isinstance(s, SudoPasswordStrategy)) or \
                       (challenge.strategy_type == AuthStrategyType.PASSWORDLESS_SUDO and isinstance(s, PasswordlessSudoStrategy)) or \
                       (challenge.strategy_type == AuthStrategyType.AWS_EKS and isinstance(s, AwsEksStrategy)) or \
                       (challenge.strategy_type == AuthStrategyType.TOUCH_ID and isinstance(s, TouchIDStrategy)):
                        strategy = s
                        break

        if not strategy:
            self.logger.error(f"No strategy found for challenge type: {challenge.strategy_type}")
            return False

        try:
            success = await strategy.authenticate(credentials)
            if success:
                self.logger.info(f"Authentication successful for challenge {challenge_id}")
                # Remove challenge after successful auth
                del self._active_challenges[challenge_id]
            else:
                # Decrement retry count
                challenge.retry_count -= 1
                if challenge.retry_count <= 0:
                    del self._active_challenges[challenge_id]
                    self.logger.warning(f"Authentication failed - no retries left for {challenge_id}")
                else:
                    self.logger.warning(f"Authentication failed - {challenge.retry_count} retries left")

            return success

        except Exception as e:
            self.logger.error(f"Authentication error for challenge {challenge_id}: {e}")
            return False

    async def is_authenticated(
        self,
        command_type: CommandType,
        privilege_level: PrivilegeLevel
    ) -> bool:
        """
        Check if authentication is valid for command type and privilege level.

        Args:
            command_type: Type of command to check
            privilege_level: Required privilege level

        Returns:
            True if authenticated
        """
        strategy = await self.get_auth_strategy(command_type, privilege_level)
        if not strategy:
            return False

        return await strategy.is_authenticated(command_type)

    async def get_command_prefix(
        self,
        command_type: CommandType,
        privilege_level: PrivilegeLevel
    ) -> List[str]:
        """
        Get command prefix for authenticated execution.

        Args:
            command_type: Type of command
            privilege_level: Required privilege level

        Returns:
            Command prefix to prepend to commands
        """
        strategy = await self.get_auth_strategy(command_type, privilege_level)
        if not strategy:
            return []

        return await strategy.get_command_prefix(command_type)

    def get_active_challenges(self) -> List[AuthChallenge]:
        """Get list of active authentication challenges."""
        return list(self._active_challenges.values())

    def cleanup_expired_challenges(self) -> None:
        """Remove expired authentication challenges."""
        expired_challenges = [
            challenge_id for challenge_id, challenge in self._active_challenges.items()
            if challenge.retry_count <= 0
        ]

        for challenge_id in expired_challenges:
            del self._active_challenges[challenge_id]
            self.logger.info(f"Removed expired challenge: {challenge_id}")

    async def test_authentication(
        self,
        command_type: CommandType,
        privilege_level: PrivilegeLevel
    ) -> bool:
        """
        Test if authentication is working for given command type and privilege level.

        Args:
            command_type: Type of command to test
            privilege_level: Required privilege level

        Returns:
            True if authentication test passes
        """
        strategy = await self.get_auth_strategy(command_type, privilege_level)
        if not strategy:
            return False

        return await strategy.is_authenticated(command_type)