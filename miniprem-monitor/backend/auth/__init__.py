"""
Authentication and privilege management module.

This module provides secure command execution with privilege detection,
authentication management, and cross-platform compatibility for Docker
and Kubernetes monitoring operations.
"""

from .command_executor import CommandExecutor
from .auth_manager import AuthManager
from .privilege_detector import PrivilegeDetector
from .session_manager import SessionManager
from .websocket_auth_handler import WebSocketAuthHandler

__all__ = [
    "CommandExecutor",
    "AuthManager",
    "PrivilegeDetector",
    "SessionManager",
    "WebSocketAuthHandler"
]