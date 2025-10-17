"""
Terminal Manager - Handles subprocess-based terminal sessions for cross-platform compatibility

This implementation uses asyncio.create_subprocess_exec instead of PTY/fork to ensure
compatibility across macOS, Linux, and Windows, especially in Docker containers.

Key differences from PTY-based approach:
- No os.fork() - works in Docker on macOS
- No pty.openpty() - works without TTY support
- Uses asyncio subprocess management
- Streams stdout/stderr directly to WebSocket
- Cross-platform compatible
"""

import asyncio
import logging
import signal
from typing import Dict, Optional, Callable
from datetime import datetime

logger = logging.getLogger(__name__)


class TerminalSession:
    """Represents a single terminal session using subprocess"""

    def __init__(self, session_id: str):
        self.session_id = session_id
        self.process: Optional[asyncio.subprocess.Process] = None
        self.created_at = datetime.utcnow()
        self.last_activity = datetime.utcnow()
        self._output_task: Optional[asyncio.Task] = None
        self._running = False

    async def start(self, callback: Callable[[bytes], None]):
        """
        Start the terminal session with a bash shell using subprocess.

        Args:
            callback: Async function to call with output data

        Raises:
            Exception: If subprocess creation fails
        """
        try:
            # Create subprocess without PTY/fork (cross-platform compatible)
            self.process = await asyncio.create_subprocess_exec(
                '/bin/bash',
                '--norc',  # Don't read initialization files
                '--noprofile',  # Don't read profile
                '-i',  # Interactive mode
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.STDOUT,  # Combine stderr with stdout
                env={
                    'TERM': 'xterm-256color',
                    'PS1': '\\[\\033[1;34m\\]$ \\[\\033[0m\\]',  # Blue prompt
                    'PATH': '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
                    'HOME': '/root',
                    'LANG': 'en_US.UTF-8',
                    'LC_ALL': 'en_US.UTF-8'
                },
                cwd='/app'
            )

            # Start streaming output
            self._running = True
            self._output_task = asyncio.create_task(self._stream_output(callback))

            logger.info(f"Terminal session {self.session_id} started with PID {self.process.pid}")

        except Exception as e:
            logger.error(f"Failed to start terminal session {self.session_id}: {e}")
            await self.cleanup()
            raise

    async def _stream_output(self, callback: Callable[[bytes], None]):
        """
        Stream output from subprocess to callback function.

        Args:
            callback: Async function to receive output bytes
        """
        try:
            while self._running and self.process and self.process.stdout:
                # Read output in chunks (4KB at a time)
                data = await self.process.stdout.read(4096)

                if not data:
                    # EOF - process exited
                    logger.info(f"Terminal session {self.session_id} process exited")
                    break

                # Update last activity timestamp
                self.last_activity = datetime.utcnow()

                # Send data to callback (WebSocket)
                try:
                    await callback(data)
                except Exception as e:
                    logger.error(f"Error in output callback for {self.session_id}: {e}")
                    break

        except asyncio.CancelledError:
            # Task was cancelled during cleanup
            logger.debug(f"Output streaming cancelled for {self.session_id}")
        except Exception as e:
            logger.error(f"Error streaming output for {self.session_id}: {e}")
        finally:
            # Session ended
            await self.cleanup()

    async def write(self, data: bytes):
        """
        Write data to subprocess stdin (user input).

        Args:
            data: Bytes to write to subprocess
        """
        if self.process and self.process.stdin and not self.process.stdin.is_closing():
            try:
                self.process.stdin.write(data)
                await self.process.stdin.drain()
                self.last_activity = datetime.utcnow()
            except Exception as e:
                logger.error(f"Error writing to terminal {self.session_id}: {e}")

    async def resize(self, rows: int, cols: int):
        """
        Resize the terminal (no-op without PTY, but kept for API compatibility).

        Args:
            rows: Number of rows
            cols: Number of columns
        """
        logger.debug(f"Terminal {self.session_id} resize requested to {rows}x{cols} (no-op without PTY)")

    async def cleanup(self):
        """Clean up terminal resources"""
        self._running = False

        # Cancel output streaming task
        if self._output_task and not self._output_task.done():
            self._output_task.cancel()
            try:
                await self._output_task
            except asyncio.CancelledError:
                pass

        # Terminate subprocess
        if self.process:
            try:
                if self.process.returncode is None:
                    # Process is still running
                    self.process.terminate()

                    # Wait for graceful termination
                    try:
                        await asyncio.wait_for(self.process.wait(), timeout=2.0)
                        logger.info(f"Terminal session {self.session_id} terminated gracefully")
                    except asyncio.TimeoutError:
                        # Force kill if not terminated
                        self.process.kill()
                        await self.process.wait()
                        logger.warning(f"Terminal session {self.session_id} force killed")
                else:
                    logger.info(f"Terminal session {self.session_id} already exited with code {self.process.returncode}")

            except Exception as e:
                logger.error(f"Error terminating process for {self.session_id}: {e}")

        self.process = None
        logger.debug(f"Terminal session {self.session_id} cleanup completed")


class TerminalManager:
    """Manages multiple terminal sessions"""

    def __init__(self):
        self.sessions: Dict[str, TerminalSession] = {}
        self._cleanup_task: Optional[asyncio.Task] = None
        self._running = False

    async def start(self):
        """Start the terminal manager"""
        self._running = True
        self._cleanup_task = asyncio.create_task(self._cleanup_inactive_sessions())
        logger.info("Terminal manager started (subprocess-based, cross-platform)")

    async def stop(self):
        """Stop the terminal manager and cleanup all sessions"""
        self._running = False

        # Cancel cleanup task
        if self._cleanup_task and not self._cleanup_task.done():
            self._cleanup_task.cancel()
            try:
                await self._cleanup_task
            except asyncio.CancelledError:
                pass

        # Cleanup all active sessions
        session_ids = list(self.sessions.keys())
        for session_id in session_ids:
            await self.remove_session(session_id)

        logger.info("Terminal manager stopped")

    async def create_session(
        self,
        session_id: str,
        output_callback: Callable[[bytes], None]
    ) -> TerminalSession:
        """
        Create a new terminal session.

        Args:
            session_id: Unique identifier for the session
            output_callback: Async function to receive output data

        Returns:
            TerminalSession instance

        Raises:
            ValueError: If session already exists
            Exception: If session creation fails
        """
        if session_id in self.sessions:
            raise ValueError(f"Session {session_id} already exists")

        session = TerminalSession(session_id)
        await session.start(output_callback)
        self.sessions[session_id] = session

        logger.info(f"Created terminal session {session_id} (total active: {len(self.sessions)})")
        return session

    async def get_session(self, session_id: str) -> Optional[TerminalSession]:
        """
        Get an existing terminal session.

        Args:
            session_id: Session identifier

        Returns:
            TerminalSession if found, None otherwise
        """
        return self.sessions.get(session_id)

    async def remove_session(self, session_id: str):
        """
        Remove and cleanup a terminal session.

        Args:
            session_id: Session identifier
        """
        session = self.sessions.pop(session_id, None)
        if session:
            await session.cleanup()
            logger.info(f"Removed terminal session {session_id} (total active: {len(self.sessions)})")

    async def _cleanup_inactive_sessions(self):
        """Periodically cleanup inactive sessions (older than 1 hour)"""
        while self._running:
            try:
                now = datetime.utcnow()
                inactive_sessions = []

                for session_id, session in self.sessions.items():
                    age = (now - session.last_activity).total_seconds()
                    if age > 3600:  # 1 hour
                        inactive_sessions.append(session_id)

                # Cleanup inactive sessions
                for session_id in inactive_sessions:
                    logger.info(f"Cleaning up inactive session {session_id}")
                    await self.remove_session(session_id)

                # Check every 5 minutes
                await asyncio.sleep(300)

            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Error in terminal cleanup task: {e}")
                await asyncio.sleep(60)


# Global terminal manager instance
terminal_manager = TerminalManager()
