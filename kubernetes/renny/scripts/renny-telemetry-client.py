#!/usr/bin/env python3
"""
MiniPrem Renny Telemetry Client

Sends installation events and periodic heartbeats to the telemetry backend.
Runs as a background process inside the Renny container.
"""

import os
import sys
import time
import json
import hashlib
import logging
import platform
import subprocess
from datetime import datetime
from typing import Optional
from urllib.request import Request, urlopen
from urllib.error import URLError, HTTPError

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] %(levelname)s: %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)


class TelemetryClient:
    """MiniPrem telemetry client for Renny instances"""

    def __init__(self):
        """Initialize telemetry client with environment configuration"""
        self.backend_url = os.getenv('TELEMETRY_BACKEND_URL', 'https://miniprem.services.uneeq.io')
        self.heartbeat_interval = int(os.getenv('HEARTBEAT_INTERVAL_SECONDS', '900'))
        self.platform = os.getenv('PLATFORM', 'docker-ubuntu')

        # Installation ID persistence
        self.installation_id_file = '/tmp/miniprem_installation_id'
        self.installation_id = self._get_or_generate_installation_id()

        # Machine ID (GPU-based, for deduplication)
        self.machine_id = self._get_machine_id()

        # Instance metadata (pod name for K8s, container ID for Docker)
        self.instance_name = os.getenv('POD_NAME') or self._get_container_id()
        self.instance_type = 'kubernetes-pod' if os.getenv('POD_NAME') else 'docker-container'
        self.node_name = os.getenv('NODE_NAME')  # Only set in Kubernetes

        logger.info(f"Telemetry endpoint: {self.backend_url}")
        logger.info(f"Heartbeat interval: {self.heartbeat_interval}s")
        logger.info(f"Platform: {self.platform}")
        logger.info(f"Installation ID: {self.installation_id}")
        logger.info(f"Machine ID: {self.machine_id[:16]}...")
        logger.info(f"Instance: {self.instance_name}")

    def _get_or_generate_installation_id(self) -> str:
        """Get existing or generate new installation ID"""
        # Try to read existing ID
        if os.path.exists(self.installation_id_file):
            try:
                with open(self.installation_id_file, 'r') as f:
                    installation_id = f.read().strip()
                    if installation_id:
                        logger.info(f"Loaded existing installation ID from {self.installation_id_file}")
                        return installation_id
            except Exception as e:
                logger.warning(f"Failed to read installation ID: {e}")

        # Generate new ID
        timestamp = int(time.time())
        random_component = os.urandom(8).hex()
        installation_id = f"{self.platform}-{timestamp}-{random_component}"

        # Save for next time
        try:
            with open(self.installation_id_file, 'w') as f:
                f.write(installation_id)
            logger.info(f"Generated new installation ID: {installation_id}")
        except Exception as e:
            logger.warning(f"Failed to save installation ID: {e}")

        return installation_id

    def _get_machine_id(self) -> str:
        """Get machine ID based on GPU UUID (for deduplication)"""
        try:
            # Try to get GPU UUID via nvidia-smi
            result = subprocess.run(
                ['nvidia-smi', '--query-gpu=uuid', '--format=csv,noheader'],
                capture_output=True,
                text=True,
                timeout=5
            )

            if result.returncode == 0 and result.stdout.strip():
                gpu_uuid = result.stdout.strip().split('\n')[0]
                # Hash the GPU UUID for privacy
                machine_id = hashlib.sha256(gpu_uuid.encode()).hexdigest()
                logger.info(f"Machine ID from GPU UUID: {machine_id[:16]}...")
                return machine_id
        except Exception as e:
            logger.warning(f"Failed to get GPU UUID: {e}")

        # Fallback: Use hostname hash
        try:
            hostname = platform.node()
            machine_id = hashlib.sha256(hostname.encode()).hexdigest()
            logger.warning(f"Using hostname-based machine ID (GPU not available)")
            return machine_id
        except Exception as e:
            logger.error(f"Failed to generate machine ID: {e}")
            return "unknown-" + os.urandom(16).hex()

    def _get_container_id(self) -> str:
        """Get Docker container ID or hostname"""
        try:
            # Try to read Docker container ID
            with open('/proc/self/cgroup', 'r') as f:
                for line in f:
                    if 'docker' in line:
                        return line.strip().split('/')[-1][:12]
        except Exception:
            pass

        # Fallback to hostname
        try:
            return platform.node()
        except Exception:
            return "unknown"

    def _send_event(self, event_type: str, data: dict) -> bool:
        """Send telemetry event to backend"""
        url = f"{self.backend_url}/telemetry"

        # Prepare payload
        payload = {
            'event_type': event_type,
            'installation_id': self.installation_id,
            'machine_id': self.machine_id,
            'timestamp': datetime.utcnow().isoformat() + 'Z',
            'platform': self.platform,
            'instance_name': self.instance_name,
            'instance_type': self.instance_type,
            **data
        }

        # Add node_name if running in Kubernetes
        if self.node_name:
            payload['node_name'] = self.node_name

        try:
            # Create request
            req = Request(
                url,
                data=json.dumps(payload).encode('utf-8'),
                headers={'Content-Type': 'application/json'},
                method='POST'
            )

            # Send request
            with urlopen(req, timeout=10) as response:
                status = response.status
                if status == 200:
                    logger.info(f"{event_type.capitalize()} sent successfully (HTTP {status})")
                    return True
                else:
                    logger.warning(f"{event_type.capitalize()} sent with status {status}")
                    return False

        except HTTPError as e:
            logger.error(f"HTTP error sending {event_type}: {e.code} {e.reason}")
            return False
        except URLError as e:
            logger.error(f"URL error sending {event_type}: {e.reason}")
            return False
        except Exception as e:
            logger.error(f"Failed to send {event_type}: {e}")
            return False

    def send_installation_event(self) -> bool:
        """Send installation event (first time setup)"""
        logger.info("Sending installation event...")
        return self._send_event('installation', {
            'version': 'renny-0.713',
            'source': 'docker-compose'
        })

    def send_heartbeat(self) -> bool:
        """Send heartbeat event"""
        logger.info("Sending heartbeat...")
        return self._send_event('heartbeat', {
            'status': 'online',
            'uptime_seconds': self._get_uptime()
        })

    def _get_uptime(self) -> int:
        """Get container uptime in seconds"""
        try:
            with open('/proc/uptime', 'r') as f:
                uptime = float(f.read().split()[0])
                return int(uptime)
        except Exception:
            return 0

    def run(self):
        """Main telemetry loop"""
        # Send initial installation event
        self.send_installation_event()

        # Start heartbeat loop
        logger.info(f"Starting heartbeat loop (interval: {self.heartbeat_interval}s)")

        while True:
            try:
                time.sleep(self.heartbeat_interval)
                self.send_heartbeat()
            except KeyboardInterrupt:
                logger.info("Telemetry client stopped by user")
                break
            except Exception as e:
                logger.error(f"Error in heartbeat loop: {e}")
                time.sleep(60)  # Wait 1 minute before retrying


if __name__ == '__main__':
    try:
        client = TelemetryClient()
        client.run()
    except Exception as e:
        logger.error(f"Fatal error: {e}")
        sys.exit(1)
