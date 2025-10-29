"""
Tests for MiniPrem Telemetry Service.

This module tests the anonymous telemetry collection system to ensure:
    - Privacy: No PII is collected or transmitted
    - Reliability: Network failures don't impact user operations
    - Correctness: Data payloads match expected schema
    - Opt-out: Telemetry can be disabled via environment variable
"""

import asyncio
import json
import os
import tempfile
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch
from typing import Dict, Any

import httpx
import pytest

from app.services.telemetry import (
    TelemetryService,
    get_telemetry_service,
    close_telemetry_service
)


@pytest.fixture
def mock_installation_id_file():
    """Create a temporary installation ID file for testing."""
    with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='_miniprem_id') as f:
        test_id = "a3f5b8c9-1234-5678-9abc-def012345678"
        f.write(test_id)
        f.flush()
        yield f.name, test_id

    # Cleanup
    try:
        os.unlink(f.name)
    except FileNotFoundError:
        pass


@pytest.fixture
def telemetry_service_enabled(mock_installation_id_file):
    """Create a TelemetryService instance with telemetry enabled."""
    id_file_path, expected_id = mock_installation_id_file

    # Clear any existing singleton
    import app.services.telemetry
    app.services.telemetry._telemetry_service = None

    # Create service with test ID file
    with patch.dict(os.environ, {"MINIPREM_TELEMETRY_DISABLED": "0"}):
        service = TelemetryService(
            installation_id_path=id_file_path,
            endpoint="https://test.uneeq.io/telemetry",
            version="2.1.0-test"
        )
        yield service

    # Cleanup
    app.services.telemetry._telemetry_service = None


@pytest.fixture
def telemetry_service_disabled():
    """Create a TelemetryService instance with telemetry disabled."""
    # Clear any existing singleton
    import app.services.telemetry
    app.services.telemetry._telemetry_service = None

    with patch.dict(os.environ, {"MINIPREM_TELEMETRY_DISABLED": "1"}):
        service = TelemetryService(
            installation_id_path="/nonexistent/path",
            endpoint="https://test.uneeq.io/telemetry",
            version="2.1.0-test"
        )
        yield service

    # Cleanup
    app.services.telemetry._telemetry_service = None


class TestTelemetryServiceInitialization:
    """Test telemetry service initialization and configuration."""

    def test_initialization_with_valid_id_file(self, mock_installation_id_file):
        """Test service initializes correctly with valid installation ID file."""
        id_file_path, expected_id = mock_installation_id_file

        with patch.dict(os.environ, {"MINIPREM_TELEMETRY_DISABLED": "0"}):
            service = TelemetryService(
                installation_id_path=id_file_path,
                endpoint="https://test.uneeq.io/telemetry"
            )

        assert service.installation_id == expected_id
        assert service.disabled is False
        assert service.endpoint == "https://test.uneeq.io/telemetry"
        assert service.version == "2.1.0"
        assert service.platform_type == "docker"

    def test_initialization_with_missing_id_file(self):
        """Test service disables telemetry when installation ID file is missing."""
        with patch.dict(os.environ, {"MINIPREM_TELEMETRY_DISABLED": "0"}):
            service = TelemetryService(
                installation_id_path="/nonexistent/installation_id"
            )

        assert service.installation_id is None
        assert service.disabled is True

    def test_initialization_with_disabled_env_var(self, mock_installation_id_file):
        """Test service disables when MINIPREM_TELEMETRY_DISABLED=1."""
        id_file_path, _ = mock_installation_id_file

        with patch.dict(os.environ, {"MINIPREM_TELEMETRY_DISABLED": "1"}):
            service = TelemetryService(installation_id_path=id_file_path)

        assert service.disabled is True

    def test_platform_detection_kubernetes(self, mock_installation_id_file):
        """Test platform detection identifies Kubernetes environment."""
        id_file_path, _ = mock_installation_id_file

        with patch.dict(os.environ, {
            "MINIPREM_TELEMETRY_DISABLED": "0",
            "KUBERNETES_SERVICE_HOST": "10.0.0.1"
        }):
            service = TelemetryService(installation_id_path=id_file_path)

        assert service.platform_type == "kubernetes"

    def test_platform_detection_docker(self, mock_installation_id_file, tmp_path):
        """Test platform detection identifies Docker environment."""
        id_file_path, _ = mock_installation_id_file

        # Mock the /.dockerenv file check
        with patch.dict(os.environ, {"MINIPREM_TELEMETRY_DISABLED": "0"}):
            with patch("pathlib.Path.exists") as mock_exists:
                # Return True only for /.dockerenv
                mock_exists.side_effect = lambda: str(mock_exists.call_args[0][0]) == "/.dockerenv"

                service = TelemetryService(installation_id_path=id_file_path)

        assert service.platform_type == "docker"

    def test_custom_endpoint_from_env_var(self, mock_installation_id_file):
        """Test custom telemetry endpoint from environment variable."""
        id_file_path, _ = mock_installation_id_file

        with patch.dict(os.environ, {
            "MINIPREM_TELEMETRY_DISABLED": "0",
            "MINIPREM_TELEMETRY_ENDPOINT": "https://custom.endpoint.io/metrics"
        }):
            service = TelemetryService(installation_id_path=id_file_path)

        assert service.endpoint == "https://custom.endpoint.io/metrics"


class TestSystemInfoCollection:
    """Test system information collection (ensuring no PII)."""

    def test_system_info_contains_no_pii(self, telemetry_service_enabled):
        """Test system info contains only non-identifiable metadata."""
        system_info = telemetry_service_enabled._get_system_info()

        # Verify expected keys are present
        assert "os" in system_info
        assert "platform" in system_info
        assert "python_version" in system_info

        # Verify no PII is present
        assert "hostname" not in system_info
        assert "username" not in system_info
        assert "ip_address" not in system_info
        assert "mac_address" not in system_info

    def test_system_info_values_are_anonymized(self, telemetry_service_enabled):
        """Test system info values are generic and anonymized."""
        system_info = telemetry_service_enabled._get_system_info()

        # OS should be lowercase generic name
        assert system_info["os"] in ["linux", "darwin", "windows", "freebsd"]

        # Platform should be architecture only
        assert system_info["platform"] in ["x86_64", "aarch64", "arm64", "i386", "i686"]

        # Python version should be version string only
        assert "." in system_info["python_version"]


class TestRennyStatusCollection:
    """Test Renny status collection (count only, no names)."""

    @pytest.mark.asyncio
    async def test_renny_status_returns_pod_count(self, telemetry_service_enabled):
        """Test Renny status returns anonymous pod count."""
        renny_status = await telemetry_service_enabled._get_renny_status()

        # Verify expected keys are present
        assert "renny_pods_running" in renny_status
        assert "platform" in renny_status

        # Verify no identifiable information
        assert "pod_names" not in renny_status
        assert "container_ids" not in renny_status
        assert "node_names" not in renny_status

    @pytest.mark.asyncio
    async def test_renny_status_defaults_to_unknown(self, telemetry_service_enabled):
        """Test Renny status defaults to -1 (unknown) if detection fails."""
        renny_status = await telemetry_service_enabled._get_renny_status()

        # Should default to -1 if unable to detect
        assert renny_status["renny_pods_running"] == -1


class TestTelemetryTransmission:
    """Test telemetry data transmission."""

    @pytest.mark.asyncio
    async def test_send_installation_event_success(self, telemetry_service_enabled):
        """Test sending installation event successfully."""
        mock_response = MagicMock()
        mock_response.status_code = 200

        with patch("httpx.AsyncClient.post", new_callable=AsyncMock) as mock_post:
            mock_post.return_value = mock_response

            success = await telemetry_service_enabled.send_installation_event()

        assert success is True
        assert telemetry_service_enabled._installation_sent is True

        # Verify payload structure
        call_args = mock_post.call_args
        payload = call_args.kwargs["json"]

        assert payload["event_type"] == "installation"
        assert payload["installation_id"] == telemetry_service_enabled.installation_id
        assert payload["version"] == "2.1.0-test"
        assert payload["platform"] == "docker"
        assert "timestamp" in payload

    @pytest.mark.asyncio
    async def test_send_installation_event_idempotent(self, telemetry_service_enabled):
        """Test installation event is only sent once (idempotent)."""
        mock_response = MagicMock()
        mock_response.status_code = 200

        with patch("httpx.AsyncClient.post", new_callable=AsyncMock) as mock_post:
            mock_post.return_value = mock_response

            # First call should send
            success1 = await telemetry_service_enabled.send_installation_event()
            assert success1 is True
            assert mock_post.call_count == 1

            # Second call should not send again
            success2 = await telemetry_service_enabled.send_installation_event()
            assert success2 is True
            assert mock_post.call_count == 1  # Still 1, not 2

    @pytest.mark.asyncio
    async def test_send_heartbeat_success(self, telemetry_service_enabled):
        """Test sending heartbeat event successfully."""
        mock_response = MagicMock()
        mock_response.status_code = 200

        with patch("httpx.AsyncClient.post", new_callable=AsyncMock) as mock_post:
            mock_post.return_value = mock_response

            success = await telemetry_service_enabled.send_heartbeat()

        assert success is True

        # Verify payload structure
        call_args = mock_post.call_args
        payload = call_args.kwargs["json"]

        assert payload["event_type"] == "heartbeat"
        assert payload["status"] == "online"
        assert "renny_pods_running" in payload

    @pytest.mark.asyncio
    async def test_send_telemetry_with_timeout(self, telemetry_service_enabled):
        """Test telemetry request times out gracefully."""
        with patch("httpx.AsyncClient.post", new_callable=AsyncMock) as mock_post:
            mock_post.side_effect = httpx.TimeoutException("Request timeout")

            success = await telemetry_service_enabled.send_heartbeat()

        # Should return False but not raise exception
        assert success is False

    @pytest.mark.asyncio
    async def test_send_telemetry_with_network_error(self, telemetry_service_enabled):
        """Test telemetry handles network errors gracefully."""
        with patch("httpx.AsyncClient.post", new_callable=AsyncMock) as mock_post:
            mock_post.side_effect = httpx.NetworkError("Connection refused")

            success = await telemetry_service_enabled.send_heartbeat()

        # Should return False but not raise exception
        assert success is False

    @pytest.mark.asyncio
    async def test_send_telemetry_with_http_error(self, telemetry_service_enabled):
        """Test telemetry handles HTTP errors gracefully."""
        mock_response = MagicMock()
        mock_response.status_code = 500

        with patch("httpx.AsyncClient.post", new_callable=AsyncMock) as mock_post:
            mock_post.return_value = mock_response

            success = await telemetry_service_enabled.send_heartbeat()

        # Should return False for non-200 status
        assert success is False


class TestTelemetryOptOut:
    """Test telemetry opt-out functionality."""

    @pytest.mark.asyncio
    async def test_disabled_service_skips_installation_event(self, telemetry_service_disabled):
        """Test disabled service does not send installation event."""
        with patch("httpx.AsyncClient.post", new_callable=AsyncMock) as mock_post:
            success = await telemetry_service_disabled.send_installation_event()

        assert success is False
        mock_post.assert_not_called()

    @pytest.mark.asyncio
    async def test_disabled_service_skips_heartbeat(self, telemetry_service_disabled):
        """Test disabled service does not send heartbeats."""
        with patch("httpx.AsyncClient.post", new_callable=AsyncMock) as mock_post:
            success = await telemetry_service_disabled.send_heartbeat()

        assert success is False
        mock_post.assert_not_called()

    @pytest.mark.asyncio
    async def test_disabled_service_does_not_start_heartbeat_loop(self, telemetry_service_disabled):
        """Test disabled service does not start background heartbeat loop."""
        await telemetry_service_disabled.start_heartbeat_loop(interval_seconds=1)

        # Task should not be created
        assert telemetry_service_disabled._heartbeat_task is None


class TestHeartbeatLoop:
    """Test background heartbeat loop functionality."""

    @pytest.mark.asyncio
    async def test_start_heartbeat_loop_sends_periodic_heartbeats(self, telemetry_service_enabled):
        """Test heartbeat loop sends heartbeats at specified interval."""
        mock_response = MagicMock()
        mock_response.status_code = 200

        with patch("httpx.AsyncClient.post", new_callable=AsyncMock) as mock_post:
            mock_post.return_value = mock_response

            # Start loop with 0.5 second interval
            await telemetry_service_enabled.start_heartbeat_loop(interval_seconds=0.5)

            # Wait for at least 2 heartbeats
            await asyncio.sleep(1.2)

            # Stop loop
            await telemetry_service_enabled.stop_heartbeat_loop()

        # Should have sent at least 2 heartbeats
        assert mock_post.call_count >= 2

    @pytest.mark.asyncio
    async def test_stop_heartbeat_loop_cancels_task(self, telemetry_service_enabled):
        """Test stopping heartbeat loop cancels background task."""
        await telemetry_service_enabled.start_heartbeat_loop(interval_seconds=10)

        assert telemetry_service_enabled._heartbeat_task is not None
        assert not telemetry_service_enabled._heartbeat_task.done()

        await telemetry_service_enabled.stop_heartbeat_loop()

        # Task should be cancelled and cleaned up
        assert telemetry_service_enabled._heartbeat_task is None

    @pytest.mark.asyncio
    async def test_heartbeat_loop_continues_after_failure(self, telemetry_service_enabled):
        """Test heartbeat loop continues even if individual heartbeats fail."""
        call_count = 0

        async def mock_post_with_intermittent_failure(*args, **kwargs):
            nonlocal call_count
            call_count += 1

            if call_count == 1:
                # First call fails
                raise httpx.NetworkError("Temporary network issue")
            else:
                # Subsequent calls succeed
                mock_response = MagicMock()
                mock_response.status_code = 200
                return mock_response

        with patch("httpx.AsyncClient.post", new_callable=AsyncMock) as mock_post:
            mock_post.side_effect = mock_post_with_intermittent_failure

            await telemetry_service_enabled.start_heartbeat_loop(interval_seconds=0.3)
            await asyncio.sleep(1.0)
            await telemetry_service_enabled.stop_heartbeat_loop()

        # Should have attempted multiple times despite first failure
        assert call_count >= 2


class TestSingletonPattern:
    """Test telemetry service singleton pattern."""

    def test_get_telemetry_service_returns_same_instance(self):
        """Test get_telemetry_service returns singleton instance."""
        # Clear any existing singleton
        import app.services.telemetry
        app.services.telemetry._telemetry_service = None

        service1 = get_telemetry_service()
        service2 = get_telemetry_service()

        assert service1 is service2

        # Cleanup
        app.services.telemetry._telemetry_service = None

    @pytest.mark.asyncio
    async def test_close_telemetry_service_stops_heartbeat(self):
        """Test close_telemetry_service stops heartbeat loop."""
        # Clear any existing singleton
        import app.services.telemetry
        app.services.telemetry._telemetry_service = None

        # Create service and start heartbeat
        service = get_telemetry_service()

        # Mock the stop method to verify it's called
        with patch.object(service, 'stop_heartbeat_loop', new_callable=AsyncMock) as mock_stop:
            await close_telemetry_service()

            mock_stop.assert_called_once()

        # Cleanup
        app.services.telemetry._telemetry_service = None


class TestPrivacyCompliance:
    """Test privacy and compliance requirements."""

    @pytest.mark.asyncio
    async def test_no_pii_in_installation_payload(self, telemetry_service_enabled):
        """Test installation payload contains no personally identifiable information."""
        captured_payload = {}

        async def capture_payload(*args, **kwargs):
            nonlocal captured_payload
            captured_payload = kwargs["json"]
            mock_response = MagicMock()
            mock_response.status_code = 200
            return mock_response

        with patch("httpx.AsyncClient.post", new_callable=AsyncMock) as mock_post:
            mock_post.side_effect = capture_payload

            await telemetry_service_enabled.send_installation_event()

        # Verify no PII fields are present
        pii_fields = [
            "hostname", "username", "ip_address", "mac_address",
            "email", "name", "organization", "location", "credentials",
            "api_key", "password", "token"
        ]

        for field in pii_fields:
            assert field not in captured_payload, f"PII field '{field}' found in payload"

    @pytest.mark.asyncio
    async def test_no_pii_in_heartbeat_payload(self, telemetry_service_enabled):
        """Test heartbeat payload contains no personally identifiable information."""
        captured_payload = {}

        async def capture_payload(*args, **kwargs):
            nonlocal captured_payload
            captured_payload = kwargs["json"]
            mock_response = MagicMock()
            mock_response.status_code = 200
            return mock_response

        with patch("httpx.AsyncClient.post", new_callable=AsyncMock) as mock_post:
            mock_post.side_effect = capture_payload

            await telemetry_service_enabled.send_heartbeat()

        # Verify no PII fields are present
        pii_fields = [
            "hostname", "username", "ip_address", "mac_address",
            "email", "name", "organization", "location", "credentials"
        ]

        for field in pii_fields:
            assert field not in captured_payload, f"PII field '{field}' found in payload"

    def test_installation_id_is_uuid_format(self, telemetry_service_enabled):
        """Test installation ID follows UUID format (anonymous)."""
        installation_id = telemetry_service_enabled.installation_id

        # UUID format: 8-4-4-4-12 hexadecimal characters
        parts = installation_id.split("-")
        assert len(parts) == 5
        assert len(parts[0]) == 8
        assert len(parts[1]) == 4
        assert len(parts[2]) == 4
        assert len(parts[3]) == 4
        assert len(parts[4]) == 12

        # All parts should be hexadecimal
        for part in parts:
            assert all(c in "0123456789abcdef" for c in part)
