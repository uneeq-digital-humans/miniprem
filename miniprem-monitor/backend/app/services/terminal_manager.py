"""
Terminal Manager - Handles PTY sessions and command execution for interactive terminal
"""

import asyncio
import logging
import os
import pty
import select
import struct
import termios
import fcntl
import signal
from typing import Dict, Optional, Callable
from datetime import datetime

logger = logging.getLogger(__name__)


class TerminalSession:
    """Represents a single PTY terminal session"""

    def __init__(self, session_id: str):
        self.session_id = session_id
        self.master_fd: Optional[int] = None
        self.slave_fd: Optional[int] = None
        self.pid: Optional[int] = None
        self.created_at = datetime.utcnow()
        self.last_activity = datetime.utcnow()
        self._read_task: Optional[asyncio.Task] = None
        self._running = False

    async def start(self, callback: Callable[[bytes], None]):
        """Start the PTY session with a bash shell"""
        try:
            # Create PTY
            self.master_fd, self.slave_fd = pty.openpty()

            # Set terminal size (default 80x24)
            winsize = struct.pack("HHHH", 24, 80, 0, 0)
            fcntl.ioctl(self.master_fd, termios.TIOCSWINSZ, winsize)

            # Fork process
            self.pid = os.fork()

            if self.pid == 0:
                # Child process
                os.close(self.master_fd)

                # Make slave PTY the controlling terminal
                os.setsid()
                fcntl.ioctl(self.slave_fd, termios.TIOCSCTTY, 0)

                # Redirect stdin, stdout, stderr to slave PTY
                os.dup2(self.slave_fd, 0)
                os.dup2(self.slave_fd, 1)
                os.dup2(self.slave_fd, 2)

                os.close(self.slave_fd)

                # Set environment variables
                env = os.environ.copy()
                env['TERM'] = 'xterm-256color'
                env['PS1'] = '\\[\\033[1;34m\\]$ \\[\\033[0m\\]'

                # Execute shell
                os.execve('/bin/bash', ['/bin/bash'], env)

            else:
                # Parent process
                os.close(self.slave_fd)
                self.slave_fd = None

                # Set non-blocking mode
                flags = fcntl.fcntl(self.master_fd, fcntl.F_GETFL)
                fcntl.fcntl(self.master_fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)

                # Start reading output
                self._running = True
                self._read_task = asyncio.create_task(self._read_output(callback))

                logger.info(f"Terminal session {self.session_id} started with PID {self.pid}")

        except Exception as e:
            logger.error(f"Failed to start terminal session {self.session_id}: {e}")
            await self.cleanup()
            raise

    async def _read_output(self, callback: Callable[[bytes], None]):
        """Read output from PTY master and send to callback"""
        while self._running:
            try:
                # Use select to check if data is available
                readable, _, _ = select.select([self.master_fd], [], [], 0.1)

                if readable:
                    try:
                        data = os.read(self.master_fd, 4096)
                        if data:
                            self.last_activity = datetime.utcnow()
                            callback(data)
                        else:
                            # EOF - shell exited
                            logger.info(f"Terminal session {self.session_id} shell exited")
                            break
                    except OSError as e:
                        if e.errno == 5:  # EIO - process exited
                            logger.info(f"Terminal session {self.session_id} process exited")
                            break
                        raise
                else:
                    # No data available, yield control
                    await asyncio.sleep(0.05)

            except Exception as e:
                logger.error(f"Error reading from terminal {self.session_id}: {e}")
                break

        # Session ended
        await self.cleanup()

    async def write(self, data: bytes):
        """Write data to PTY master (send to shell)"""
        if self.master_fd is not None:
            try:
                os.write(self.master_fd, data)
                self.last_activity = datetime.utcnow()
            except Exception as e:
                logger.error(f"Error writing to terminal {self.session_id}: {e}")

    async def resize(self, rows: int, cols: int):
        """Resize the terminal"""
        if self.master_fd is not None:
            try:
                winsize = struct.pack("HHHH", rows, cols, 0, 0)
                fcntl.ioctl(self.master_fd, termios.TIOCSWINSZ, winsize)
                logger.debug(f"Terminal {self.session_id} resized to {rows}x{cols}")
            except Exception as e:
                logger.error(f"Error resizing terminal {self.session_id}: {e}")

    async def cleanup(self):
        """Clean up terminal resources"""
        self._running = False

        if self._read_task:
            self._read_task.cancel()
            try:
                await self._read_task
            except asyncio.CancelledError:
                pass

        if self.pid:
            try:
                os.kill(self.pid, signal.SIGTERM)
                os.waitpid(self.pid, 0)
                logger.info(f"Terminal session {self.session_id} process terminated")
            except ProcessLookupError:
                pass  # Process already exited
            except Exception as e:
                logger.error(f"Error terminating terminal process {self.session_id}: {e}")

        if self.master_fd is not None:
            try:
                os.close(self.master_fd)
            except Exception as e:
                logger.error(f"Error closing master fd for {self.session_id}: {e}")

        if self.slave_fd is not None:
            try:
                os.close(self.slave_fd)
            except Exception as e:
                logger.error(f"Error closing slave fd for {self.session_id}: {e}")

        self.master_fd = None
        self.slave_fd = None
        self.pid = None


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
        logger.info("Terminal manager started")

    async def stop(self):
        """Stop the terminal manager and cleanup all sessions"""
        self._running = False

        if self._cleanup_task:
            self._cleanup_task.cancel()
            try:
                await self._cleanup_task
            except asyncio.CancelledError:
                pass

        # Cleanup all sessions
        for session_id in list(self.sessions.keys()):
            await self.remove_session(session_id)

        logger.info("Terminal manager stopped")

    async def create_session(
        self,
        session_id: str,
        output_callback: Callable[[bytes], None]
    ) -> TerminalSession:
        """Create a new terminal session"""
        if session_id in self.sessions:
            raise ValueError(f"Session {session_id} already exists")

        session = TerminalSession(session_id)
        await session.start(output_callback)
        self.sessions[session_id] = session

        logger.info(f"Created terminal session {session_id}")
        return session

    async def get_session(self, session_id: str) -> Optional[TerminalSession]:
        """Get an existing terminal session"""
        return self.sessions.get(session_id)

    async def remove_session(self, session_id: str):
        """Remove and cleanup a terminal session"""
        session = self.sessions.pop(session_id, None)
        if session:
            await session.cleanup()
            logger.info(f"Removed terminal session {session_id}")

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

                for session_id in inactive_sessions:
                    logger.info(f"Cleaning up inactive session {session_id}")
                    await self.remove_session(session_id)

                await asyncio.sleep(300)  # Check every 5 minutes

            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Error in terminal cleanup task: {e}")
                await asyncio.sleep(60)


# Global terminal manager instance
terminal_manager = TerminalManager()
