"""
SessionManager: Session persistence and authentication state management.

This module manages authentication sessions, including sudo session heartbeats,
AWS profile persistence, and command prefix caching across client connections.
"""

import asyncio
import logging
import time
import uuid
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Any, Set
from enum import Enum

from .command_executor import CommandType, PrivilegeLevel
from .auth_manager import AuthStrategyType

logger = logging.getLogger(__name__)


class SessionStatus(Enum):
    """Session status enumeration."""
    ACTIVE = "active"
    EXPIRED = "expired"
    AUTHENTICATING = "authenticating"
    FAILED = "failed"


@dataclass
class AuthSession:
    """
    Authentication session data.

    Attributes:
        session_id: Unique session identifier
        client_id: WebSocket client ID
        command_type: Type of command this session applies to
        strategy_type: Authentication strategy used
        created_at: Session creation timestamp
        last_activity: Last activity timestamp
        expires_at: Session expiration timestamp
        status: Current session status
        metadata: Additional session metadata
    """
    session_id: str
    client_id: str
    command_type: CommandType
    strategy_type: AuthStrategyType
    created_at: float
    last_activity: float
    expires_at: Optional[float] = None
    status: SessionStatus = SessionStatus.AUTHENTICATING
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class SudoSession:
    """
    Sudo-specific session data.

    Attributes:
        client_id: WebSocket client ID associated with this sudo session
        authenticated_at: Timestamp when sudo auth succeeded
        last_heartbeat: Timestamp of last heartbeat
        heartbeat_task: Asyncio task for heartbeat maintenance
        failures: Number of consecutive heartbeat failures
    """
    client_id: str
    authenticated_at: float
    last_heartbeat: float
    heartbeat_task: Optional[asyncio.Task] = None
    failures: int = 0


@dataclass
class AwsSession:
    """
    AWS profile session data.

    Attributes:
        client_id: WebSocket client ID
        profile: AWS profile name
        authenticated_at: Timestamp when profile was set
        last_used: Timestamp of last usage
    """
    client_id: str
    profile: str
    authenticated_at: float
    last_used: float


class SessionManager:
    """
    Session manager for authentication state persistence.

    Manages authentication sessions, sudo heartbeats, AWS profiles,
    and command prefix caching across client connections.
    """

    def __init__(self, heartbeat_interval: int = 60, session_timeout: int = 3600):
        """
        Initialize the SessionManager.

        Args:
            heartbeat_interval: Interval in seconds for sudo heartbeat
            session_timeout: Default session timeout in seconds
        """
        self.heartbeat_interval = heartbeat_interval
        self.session_timeout = session_timeout

        # Session storage
        self._auth_sessions: Dict[str, AuthSession] = {}
        self._sudo_sessions: Dict[str, SudoSession] = {}
        self._aws_sessions: Dict[str, AwsSession] = {}

        # Client tracking
        self._client_sessions: Dict[str, Set[str]] = {}  # client_id -> session_ids
        self._command_prefixes: Dict[str, Dict[CommandType, List[str]]] = {}  # client_id -> prefixes

        # Background tasks
        self._cleanup_task: Optional[asyncio.Task] = None
        self._running = False

        self.logger = logging.getLogger(__name__)

    async def start(self) -> None:
        """Start the session manager background tasks."""
        if self._running:
            return

        self._running = True
        self._cleanup_task = asyncio.create_task(self._cleanup_loop())
        self.logger.info("SessionManager started")

    async def stop(self) -> None:
        """Stop the session manager and cleanup resources."""
        self._running = False

        if self._cleanup_task:
            self._cleanup_task.cancel()
            try:
                await self._cleanup_task
            except asyncio.CancelledError:
                pass

        # Stop all sudo heartbeat tasks
        for sudo_session in self._sudo_sessions.values():
            if sudo_session.heartbeat_task:
                sudo_session.heartbeat_task.cancel()

        self.logger.info("SessionManager stopped")

    async def create_auth_session(
        self,
        client_id: str,
        command_type: CommandType,
        strategy_type: AuthStrategyType,
        expires_in: Optional[int] = None
    ) -> str:
        """
        Create a new authentication session.

        Args:
            client_id: WebSocket client ID
            command_type: Type of command this session applies to
            strategy_type: Authentication strategy being used
            expires_in: Optional expiration time in seconds

        Returns:
            Session ID for the created session
        """
        session_id = str(uuid.uuid4())
        now = time.time()
        expires_at = now + (expires_in or self.session_timeout) if expires_in else None

        session = AuthSession(
            session_id=session_id,
            client_id=client_id,
            command_type=command_type,
            strategy_type=strategy_type,
            created_at=now,
            last_activity=now,
            expires_at=expires_at,
            status=SessionStatus.AUTHENTICATING
        )

        self._auth_sessions[session_id] = session

        # Track client sessions
        if client_id not in self._client_sessions:
            self._client_sessions[client_id] = set()
        self._client_sessions[client_id].add(session_id)

        self.logger.info(f"Created auth session {session_id} for client {client_id}, command {command_type.value}")
        return session_id

    async def authenticate_sudo(self, client_id: str) -> bool:
        """
        Mark sudo authentication as successful and start heartbeat.

        Args:
            client_id: WebSocket client ID

        Returns:
            True if sudo session was created successfully
        """
        now = time.time()

        # Create or update sudo session
        if client_id in self._sudo_sessions:
            # Update existing session
            sudo_session = self._sudo_sessions[client_id]
            sudo_session.authenticated_at = now
            sudo_session.last_heartbeat = now
            sudo_session.failures = 0
        else:
            # Create new sudo session
            sudo_session = SudoSession(
                client_id=client_id,
                authenticated_at=now,
                last_heartbeat=now
            )
            self._sudo_sessions[client_id] = sudo_session

        # Start heartbeat task
        await self._start_sudo_heartbeat(client_id)

        # Update command prefixes
        if client_id not in self._command_prefixes:
            self._command_prefixes[client_id] = {}
        self._command_prefixes[client_id][CommandType.DOCKER] = ["sudo"]

        # Mark auth sessions as active
        await self._activate_client_sessions(client_id, CommandType.DOCKER, AuthStrategyType.SUDO_PASSWORD)

        self.logger.info(f"Sudo authentication successful for client {client_id}")
        return True

    async def authenticate_aws_profile(self, client_id: str, profile: str) -> bool:
        """
        Set AWS profile for client.

        Args:
            client_id: WebSocket client ID
            profile: AWS profile name

        Returns:
            True if AWS session was created successfully
        """
        now = time.time()

        aws_session = AwsSession(
            client_id=client_id,
            profile=profile,
            authenticated_at=now,
            last_used=now
        )

        self._aws_sessions[client_id] = aws_session

        # Update command prefixes
        if client_id not in self._command_prefixes:
            self._command_prefixes[client_id] = {}
        self._command_prefixes[client_id][CommandType.KUBECTL] = ["env", f"AWS_PROFILE={profile}"]

        # Mark auth sessions as active
        await self._activate_client_sessions(client_id, CommandType.KUBECTL, AuthStrategyType.AWS_EKS)

        self.logger.info(f"AWS profile authentication successful for client {client_id}: {profile}")
        return True

    async def _activate_client_sessions(
        self,
        client_id: str,
        command_type: CommandType,
        strategy_type: AuthStrategyType
    ) -> None:
        """Activate authentication sessions for a client."""
        if client_id not in self._client_sessions:
            return

        for session_id in self._client_sessions[client_id]:
            session = self._auth_sessions.get(session_id)
            if (session and
                session.command_type == command_type and
                session.strategy_type == strategy_type and
                session.status == SessionStatus.AUTHENTICATING):
                session.status = SessionStatus.ACTIVE
                session.last_activity = time.time()

    async def _start_sudo_heartbeat(self, client_id: str) -> None:
        """Start sudo heartbeat task for a client."""
        if client_id not in self._sudo_sessions:
            return

        sudo_session = self._sudo_sessions[client_id]

        # Cancel existing heartbeat task
        if sudo_session.heartbeat_task:
            sudo_session.heartbeat_task.cancel()

        # Start new heartbeat task
        sudo_session.heartbeat_task = asyncio.create_task(
            self._sudo_heartbeat_loop(client_id)
        )

    async def _sudo_heartbeat_loop(self, client_id: str) -> None:
        """Sudo heartbeat maintenance loop."""
        self.logger.info(f"Starting sudo heartbeat for client {client_id}")

        try:
            while self._running and client_id in self._sudo_sessions:
                await asyncio.sleep(self.heartbeat_interval)

                if client_id not in self._sudo_sessions:
                    break

                sudo_session = self._sudo_sessions[client_id]

                try:
                    # Run sudo -v to refresh the session
                    process = await asyncio.create_subprocess_exec(
                        "sudo", "-v",
                        stdout=asyncio.subprocess.DEVNULL,
                        stderr=asyncio.subprocess.DEVNULL
                    )
                    await asyncio.wait_for(process.communicate(), timeout=5)

                    if process.returncode == 0:
                        # Heartbeat successful
                        sudo_session.last_heartbeat = time.time()
                        sudo_session.failures = 0
                        self.logger.debug(f"Sudo heartbeat successful for client {client_id}")
                    else:
                        # Heartbeat failed
                        sudo_session.failures += 1
                        self.logger.warning(f"Sudo heartbeat failed for client {client_id} (failures: {sudo_session.failures})")

                        if sudo_session.failures >= 3:
                            # Too many failures, invalidate session
                            await self._invalidate_sudo_session(client_id)
                            break

                except asyncio.TimeoutError:
                    sudo_session.failures += 1
                    self.logger.warning(f"Sudo heartbeat timeout for client {client_id}")

                    if sudo_session.failures >= 3:
                        await self._invalidate_sudo_session(client_id)
                        break

        except asyncio.CancelledError:
            self.logger.info(f"Sudo heartbeat cancelled for client {client_id}")
        except Exception as e:
            self.logger.error(f"Sudo heartbeat error for client {client_id}: {e}")
            await self._invalidate_sudo_session(client_id)

    async def _invalidate_sudo_session(self, client_id: str) -> None:
        """Invalidate sudo session for a client."""
        if client_id in self._sudo_sessions:
            sudo_session = self._sudo_sessions[client_id]
            if sudo_session.heartbeat_task:
                sudo_session.heartbeat_task.cancel()
            del self._sudo_sessions[client_id]

        # Remove sudo command prefixes
        if client_id in self._command_prefixes:
            self._command_prefixes[client_id].pop(CommandType.DOCKER, None)

        # Mark relevant auth sessions as expired
        if client_id in self._client_sessions:
            for session_id in self._client_sessions[client_id]:
                session = self._auth_sessions.get(session_id)
                if (session and
                    session.command_type == CommandType.DOCKER and
                    session.strategy_type == AuthStrategyType.SUDO_PASSWORD):
                    session.status = SessionStatus.EXPIRED

        self.logger.warning(f"Invalidated sudo session for client {client_id}")

    async def is_sudo_authenticated(self, client_id: str) -> bool:
        """Check if client has active sudo session."""
        return client_id in self._sudo_sessions

    async def is_aws_authenticated(self, client_id: str) -> bool:
        """Check if client has active AWS session."""
        if client_id not in self._aws_sessions:
            return False

        aws_session = self._aws_sessions[client_id]
        # Update last used timestamp
        aws_session.last_used = time.time()
        return True

    def get_aws_profile(self, client_id: str) -> Optional[str]:
        """Get AWS profile for client."""
        if client_id not in self._aws_sessions:
            return None
        return self._aws_sessions[client_id].profile

    def get_command_prefixes(self, client_id: str) -> Dict[CommandType, List[str]]:
        """Get command prefixes for client."""
        return self._command_prefixes.get(client_id, {})

    async def cleanup_client(self, client_id: str) -> None:
        """Cleanup all sessions for a disconnected client."""
        self.logger.info(f"Cleaning up sessions for client {client_id}")

        # Stop sudo heartbeat
        if client_id in self._sudo_sessions:
            sudo_session = self._sudo_sessions[client_id]
            if sudo_session.heartbeat_task:
                sudo_session.heartbeat_task.cancel()
            del self._sudo_sessions[client_id]

        # Remove AWS session
        self._aws_sessions.pop(client_id, None)

        # Remove command prefixes
        self._command_prefixes.pop(client_id, None)

        # Mark auth sessions as expired
        if client_id in self._client_sessions:
            for session_id in self._client_sessions[client_id]:
                if session_id in self._auth_sessions:
                    self._auth_sessions[session_id].status = SessionStatus.EXPIRED

            del self._client_sessions[client_id]

        self.logger.info(f"Cleaned up sessions for client {client_id}")

    async def _cleanup_loop(self) -> None:
        """Background cleanup loop for expired sessions."""
        while self._running:
            try:
                await asyncio.sleep(300)  # Run every 5 minutes
                await self._cleanup_expired_sessions()
            except asyncio.CancelledError:
                break
            except Exception as e:
                self.logger.error(f"Session cleanup error: {e}")

    async def _cleanup_expired_sessions(self) -> None:
        """Remove expired authentication sessions."""
        now = time.time()
        expired_sessions = []

        for session_id, session in self._auth_sessions.items():
            # Check if session is expired
            if (session.expires_at and session.expires_at < now) or session.status == SessionStatus.EXPIRED:
                expired_sessions.append(session_id)

        # Remove expired sessions
        for session_id in expired_sessions:
            session = self._auth_sessions[session_id]
            client_id = session.client_id

            del self._auth_sessions[session_id]

            if client_id in self._client_sessions:
                self._client_sessions[client_id].discard(session_id)
                if not self._client_sessions[client_id]:
                    del self._client_sessions[client_id]

        if expired_sessions:
            self.logger.info(f"Cleaned up {len(expired_sessions)} expired sessions")

    async def get_session_stats(self) -> Dict[str, Any]:
        """Get session statistics."""
        active_sudo_sessions = len(self._sudo_sessions)
        active_aws_sessions = len(self._aws_sessions)
        total_auth_sessions = len(self._auth_sessions)
        active_auth_sessions = sum(
            1 for session in self._auth_sessions.values()
            if session.status == SessionStatus.ACTIVE
        )

        return {
            "total_auth_sessions": total_auth_sessions,
            "active_auth_sessions": active_auth_sessions,
            "sudo_sessions": active_sudo_sessions,
            "aws_sessions": active_aws_sessions,
            "clients_with_sessions": len(self._client_sessions),
            "heartbeat_interval": self.heartbeat_interval,
            "session_timeout": self.session_timeout
        }

    async def refresh_session(self, client_id: str, session_id: str) -> bool:
        """
        Refresh session activity timestamp.

        Args:
            client_id: WebSocket client ID
            session_id: Session ID to refresh

        Returns:
            True if session was refreshed
        """
        if session_id in self._auth_sessions:
            session = self._auth_sessions[session_id]
            if session.client_id == client_id and session.status == SessionStatus.ACTIVE:
                session.last_activity = time.time()
                return True
        return False