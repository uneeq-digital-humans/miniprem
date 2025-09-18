"""
WebSocketAuthHandler: Secure authentication protocol for WebSocket connections.

This module provides authentication challenge handling, secure password transmission,
and integration with the authentication system for WebSocket-based monitoring commands.
"""

import asyncio
import json
import logging
import uuid
from typing import Dict, Optional, Any, Callable
from dataclasses import dataclass, asdict
from enum import Enum

from fastapi import WebSocket, WebSocketDisconnect

from .command_executor import CommandType, CommandExecutionError, PrivilegeError
from .auth_manager import AuthManager, AuthChallenge, AuthResponse, AuthResult
from .session_manager import SessionManager

logger = logging.getLogger(__name__)


class WebSocketMessageType(Enum):
    """WebSocket message types for authentication protocol."""
    AUTH_CHALLENGE = "auth_challenge"
    AUTH_RESPONSE = "auth_response"
    AUTH_SUCCESS = "auth_success"
    AUTH_ERROR = "auth_error"
    MONITORING_DATA = "monitoring_data"
    PRIVILEGE_STATUS = "privilege_status"


@dataclass
class WebSocketAuthMessage:
    """
    WebSocket authentication message structure.

    Attributes:
        type: Message type from WebSocketMessageType enum
        client_id: WebSocket client identifier
        challenge_id: Optional challenge ID for multi-step auth
        data: Message payload data
        timestamp: Message timestamp
    """
    type: str
    client_id: str
    challenge_id: Optional[str] = None
    data: Optional[Dict[str, Any]] = None
    timestamp: Optional[str] = None


class WebSocketAuthHandler:
    """
    WebSocket authentication handler for secure privilege escalation.

    This class manages authentication challenges, secure password transmission,
    and session coordination for WebSocket-based monitoring operations.
    """

    def __init__(
        self,
        auth_manager: AuthManager,
        session_manager: SessionManager,
        websocket_manager: Any  # To avoid circular import
    ):
        """
        Initialize the WebSocket authentication handler.

        Args:
            auth_manager: AuthManager instance for authentication strategies
            session_manager: SessionManager instance for session persistence
            websocket_manager: WebSocketManager instance for connection management
        """
        self.auth_manager = auth_manager
        self.session_manager = session_manager
        self.websocket_manager = websocket_manager

        # Track pending authentication challenges per client
        self._pending_challenges: Dict[str, AuthChallenge] = {}

        # Track client authentication states
        self._client_auth_states: Dict[str, Dict[CommandType, bool]] = {}

        logger.info("WebSocketAuthHandler initialized")

    async def handle_privilege_error(
        self,
        client_id: str,
        privilege_error: PrivilegeError,
        command_type: CommandType,
        original_command: str
    ) -> bool:
        """
        Handle privilege error by initiating authentication challenge.

        Args:
            client_id: WebSocket client identifier
            privilege_error: The privilege error that occurred
            command_type: Type of command that failed
            original_command: Original command that triggered the error

        Returns:
            bool: True if authentication challenge was sent successfully
        """
        try:
            logger.info(f"Handling privilege error for client {client_id}, command type {command_type.value}")

            # Create authentication challenge
            challenge = await self.auth_manager.create_auth_challenge(
                command_type=command_type,
                error_context=str(privilege_error),
                metadata={"original_command": original_command}
            )

            if not challenge:
                logger.error(f"Failed to create auth challenge for client {client_id}")
                await self._send_auth_error(client_id, "Failed to create authentication challenge")
                return False

            # Store pending challenge
            self._pending_challenges[client_id] = challenge

            # Send challenge to client
            await self._send_auth_challenge(client_id, challenge)

            logger.info(f"Sent auth challenge {challenge.challenge_id} to client {client_id}")
            return True

        except Exception as e:
            logger.error(f"Error handling privilege error for client {client_id}: {e}")
            await self._send_auth_error(client_id, f"Authentication error: {str(e)}")
            return False

    async def handle_auth_response(
        self,
        client_id: str,
        auth_response_data: Dict[str, Any]
    ) -> bool:
        """
        Handle authentication response from client.

        Args:
            client_id: WebSocket client identifier
            auth_response_data: Authentication response data from client

        Returns:
            bool: True if authentication succeeded
        """
        try:
            # Check if there's a pending challenge for this client
            if client_id not in self._pending_challenges:
                logger.warning(f"No pending challenge for client {client_id}")
                await self._send_auth_error(client_id, "No pending authentication challenge")
                return False

            challenge = self._pending_challenges[client_id]

            # Create AuthResponse object
            auth_response = AuthResponse(
                challenge_id=challenge.challenge_id,
                client_id=client_id,
                encrypted_credentials=auth_response_data.get("encrypted_credentials"),
                strategy_type=auth_response_data.get("strategy_type"),
                metadata=auth_response_data.get("metadata", {})
            )

            # Process authentication through AuthManager
            auth_result = await self.auth_manager.handle_auth_response(auth_response)

            if auth_result.success:
                # Authentication successful
                logger.info(f"Authentication successful for client {client_id}, command {challenge.command_type.value}")

                # Update session manager based on strategy
                if auth_result.strategy_type.value == "sudo_password":
                    await self.session_manager.authenticate_sudo(client_id)
                elif auth_result.strategy_type.value == "aws_eks":
                    profile = auth_result.metadata.get("aws_profile")
                    if profile:
                        await self.session_manager.authenticate_aws_profile(client_id, profile)

                # Update client auth state
                if client_id not in self._client_auth_states:
                    self._client_auth_states[client_id] = {}
                self._client_auth_states[client_id][challenge.command_type] = True

                # Clean up pending challenge
                del self._pending_challenges[client_id]

                # Send success message to client
                await self._send_auth_success(client_id, auth_result)

                return True

            else:
                # Authentication failed
                logger.warning(f"Authentication failed for client {client_id}: {auth_result.error_message}")
                await self._send_auth_error(client_id, auth_result.error_message or "Authentication failed")

                # Update retry count
                challenge.retry_count -= 1
                if challenge.retry_count > 0:
                    # Allow retry
                    await self._send_auth_challenge(client_id, challenge)
                else:
                    # No more retries, clean up
                    del self._pending_challenges[client_id]

                return False

        except Exception as e:
            logger.error(f"Error handling auth response for client {client_id}: {e}")
            await self._send_auth_error(client_id, f"Authentication processing error: {str(e)}")
            return False

    async def _send_auth_challenge(
        self,
        client_id: str,
        challenge: AuthChallenge
    ) -> None:
        """
        Send authentication challenge to client.

        Args:
            client_id: WebSocket client identifier
            challenge: Authentication challenge to send
        """
        message = WebSocketAuthMessage(
            type=WebSocketMessageType.AUTH_CHALLENGE.value,
            client_id=client_id,
            challenge_id=challenge.challenge_id,
            data={
                "challenge_type": challenge.challenge_type,
                "message": challenge.message,
                "command_type": challenge.command_type.value,
                "retry_count": challenge.retry_count,
                "public_key": challenge.public_key,
                "available_strategies": challenge.available_strategies,
                "metadata": challenge.metadata
            }
        )

        await self._send_websocket_message(client_id, message)

    async def _send_auth_success(
        self,
        client_id: str,
        auth_result: AuthResult
    ) -> None:
        """
        Send authentication success message to client.

        Args:
            client_id: WebSocket client identifier
            auth_result: Successful authentication result
        """
        message = WebSocketAuthMessage(
            type=WebSocketMessageType.AUTH_SUCCESS.value,
            client_id=client_id,
            data={
                "strategy_type": auth_result.strategy_type.value,
                "session_duration": auth_result.session_duration,
                "message": "Authentication successful",
                "metadata": auth_result.metadata
            }
        )

        await self._send_websocket_message(client_id, message)

    async def _send_auth_error(
        self,
        client_id: str,
        error_message: str
    ) -> None:
        """
        Send authentication error message to client.

        Args:
            client_id: WebSocket client identifier
            error_message: Error message to send
        """
        message = WebSocketAuthMessage(
            type=WebSocketMessageType.AUTH_ERROR.value,
            client_id=client_id,
            data={
                "error": error_message,
                "message": "Authentication failed"
            }
        )

        await self._send_websocket_message(client_id, message)

    async def _send_websocket_message(
        self,
        client_id: str,
        message: WebSocketAuthMessage
    ) -> bool:
        """
        Send WebSocket message to client.

        Args:
            client_id: WebSocket client identifier
            message: Message to send

        Returns:
            bool: True if sent successfully
        """
        try:
            message_dict = asdict(message)
            return await self.websocket_manager.send_custom_message(client_id, message_dict)
        except Exception as e:
            logger.error(f"Failed to send WebSocket message to client {client_id}: {e}")
            return False

    async def send_privilege_status(self, client_id: str) -> bool:
        """
        Send privilege detection status to client.

        Args:
            client_id: WebSocket client identifier

        Returns:
            bool: True if sent successfully
        """
        try:
            # Get privilege status from command executor
            privilege_status = self.websocket_manager.command_executor.get_privilege_status()

            message = WebSocketAuthMessage(
                type=WebSocketMessageType.PRIVILEGE_STATUS.value,
                client_id=client_id,
                data=privilege_status
            )

            return await self._send_websocket_message(client_id, message)

        except Exception as e:
            logger.error(f"Failed to send privilege status to client {client_id}: {e}")
            return False

    def cleanup_client(self, client_id: str) -> None:
        """
        Cleanup authentication state for disconnected client.

        Args:
            client_id: WebSocket client identifier
        """
        # Clean up pending challenges
        self._pending_challenges.pop(client_id, None)

        # Clean up client auth states
        self._client_auth_states.pop(client_id, None)

        logger.info(f"Cleaned up auth state for client {client_id}")

    def is_client_authenticated(
        self,
        client_id: str,
        command_type: CommandType
    ) -> bool:
        """
        Check if client is authenticated for a specific command type.

        Args:
            client_id: WebSocket client identifier
            command_type: Command type to check

        Returns:
            bool: True if client is authenticated
        """
        client_state = self._client_auth_states.get(client_id, {})
        return client_state.get(command_type, False)

    async def get_auth_stats(self) -> Dict[str, Any]:
        """
        Get authentication statistics.

        Returns:
            Dict[str, Any]: Authentication statistics
        """
        return {
            "pending_challenges": len(self._pending_challenges),
            "authenticated_clients": len(self._client_auth_states),
            "challenge_details": {
                client_id: {
                    "challenge_id": challenge.challenge_id,
                    "command_type": challenge.command_type.value,
                    "retry_count": challenge.retry_count
                }
                for client_id, challenge in self._pending_challenges.items()
            },
            "session_stats": await self.session_manager.get_session_stats()
        }