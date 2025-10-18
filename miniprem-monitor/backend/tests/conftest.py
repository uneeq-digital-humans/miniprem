"""
Pytest configuration and shared fixtures for MiniPrem Monitor backend tests.

This module provides reusable fixtures for FastAPI TestClient, mock database,
and test utilities to ensure isolated and consistent test execution.
"""

import pytest
import asyncio
import tempfile
import os
from typing import AsyncGenerator, Generator
from fastapi.testclient import TestClient
from unittest.mock import MagicMock, AsyncMock, patch

# Import app components
from app.main import app
from app.services.snapshot_manager import SnapshotManager, get_snapshot_manager, _snapshot_manager
from app.services.prometheus_client import PrometheusMetrics


@pytest.fixture(scope="session")
def event_loop():
    """
    Create event loop for the test session.

    Required for pytest-asyncio to work correctly with session-scoped fixtures.
    """
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()


@pytest.fixture
def client() -> Generator[TestClient, None, None]:
    """
    Create FastAPI TestClient for API endpoint testing.

    Creates a temporary database for snapshot manager and overrides
    the global instance to use test database.

    Yields:
        TestClient instance configured with the FastAPI app

    Example:
        >>> def test_endpoint(client):
        ...     response = client.get("/")
        ...     assert response.status_code == 200
    """
    # Create temporary database for testing
    with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as tmp:
        test_db_path = tmp.name

    # Patch the snapshot manager to use temporary database
    test_manager = SnapshotManager(db_path=test_db_path, retention_hours=1)

    # Override global snapshot manager
    import app.services.snapshot_manager as sm_module
    original_manager = sm_module._snapshot_manager
    sm_module._snapshot_manager = test_manager

    try:
        with TestClient(app) as test_client:
            yield test_client
    finally:
        # Restore original manager
        sm_module._snapshot_manager = original_manager

        # Cleanup: Remove temporary database
        try:
            if os.path.exists(test_db_path):
                os.unlink(test_db_path)
        except Exception:
            pass


@pytest.fixture
async def temp_db_path() -> AsyncGenerator[str, None]:
    """
    Create a temporary database file path for isolated testing.

    Creates a temporary SQLite database that is automatically cleaned up
    after the test completes.

    Yields:
        String path to temporary database file

    Example:
        >>> async def test_with_db(temp_db_path):
        ...     manager = SnapshotManager(db_path=temp_db_path)
        ...     await manager.initialize()
    """
    # Create temporary file
    with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as tmp:
        db_path = tmp.name

    yield db_path

    # Cleanup: Remove temporary database file
    try:
        if os.path.exists(db_path):
            os.unlink(db_path)
    except Exception:
        pass


@pytest.fixture
async def snapshot_manager(temp_db_path: str) -> AsyncGenerator[SnapshotManager, None]:
    """
    Create an initialized SnapshotManager with temporary database.

    Provides a clean SnapshotManager instance with in-memory database
    for isolated testing without affecting production data.

    Args:
        temp_db_path: Path to temporary database (from temp_db_path fixture)

    Yields:
        Initialized SnapshotManager instance

    Example:
        >>> async def test_snapshot_creation(snapshot_manager):
        ...     metrics = PrometheusMetrics()
        ...     snapshot = await snapshot_manager.create_snapshot(
        ...         "test-id", "test-container", metrics
        ...     )
        ...     assert snapshot.id == "test-id"
    """
    manager = SnapshotManager(db_path=temp_db_path, retention_hours=1)
    await manager.initialize()

    yield manager

    # Cleanup: Stop any background tasks
    if manager.cleanup_running:
        await manager.stop_cleanup_task()


@pytest.fixture
def sample_metrics() -> dict:
    """
    Provide sample metrics dictionary for testing.

    Returns comprehensive PrometheusMetrics-compatible dictionary with
    realistic test values for all metric fields.

    Returns:
        Dictionary with all PrometheusMetrics fields populated

    Example:
        >>> def test_endpoint(client, sample_metrics):
        ...     response = client.post("/api/metrics/snapshot", json={
        ...         "container_name": "renny",
        ...         "metrics": sample_metrics
        ...     })
    """
    return {
        "gpu_percent": 75.5,
        "cpu_percent": 45.2,
        "memory_percent": 60.3,
        "memory_bytes": 8589934592,  # 8GB
        "power_watts": 150.0,
        "request_count": 1500,
        "uptime_seconds": 86400,  # 24 hours
        "session_total": 250,
        "session_started": 250,
        "session_successful": 245,
        "session_failed": 5,
        "frames_rendered": 1500000,
        "response_time_p50": 45.5,
        "response_time_p90": 85.2,
        "response_time_p99": 120.8,
        "nlp_response_time_p50": 25.3,
        "a2f_response_time_p50": 15.7,
        "gpu_frame_time_avg": 12.5,
        "render_frame_time_avg": 14.2,
        "game_frame_time_avg": 16.8,
        "frame_time_avg": 14.5
    }


@pytest.fixture
def prometheus_metrics(sample_metrics: dict) -> PrometheusMetrics:
    """
    Create PrometheusMetrics object from sample data.

    Converts sample_metrics dictionary into a PrometheusMetrics object
    for testing database storage and retrieval.

    Args:
        sample_metrics: Sample metrics dictionary from sample_metrics fixture

    Returns:
        PrometheusMetrics object with all fields populated

    Example:
        >>> async def test_storage(snapshot_manager, prometheus_metrics):
        ...     snapshot = await snapshot_manager.create_snapshot(
        ...         "test-id", "renny", prometheus_metrics
        ...     )
    """
    metrics = PrometheusMetrics()

    # Populate all fields from sample_metrics
    metrics.gpu_percent = sample_metrics["gpu_percent"]
    metrics.cpu_percent = sample_metrics["cpu_percent"]
    metrics.memory_percent = sample_metrics["memory_percent"]
    metrics.memory_bytes = sample_metrics["memory_bytes"]
    metrics.power_watts = sample_metrics["power_watts"]
    metrics.request_count = sample_metrics["request_count"]
    metrics.uptime_seconds = sample_metrics["uptime_seconds"]
    metrics.session_total = sample_metrics["session_total"]
    metrics.session_started = sample_metrics["session_started"]
    metrics.session_successful = sample_metrics["session_successful"]
    metrics.session_failed = sample_metrics["session_failed"]
    metrics.frames_rendered = sample_metrics["frames_rendered"]
    metrics.response_time_p50 = sample_metrics["response_time_p50"]
    metrics.response_time_p90 = sample_metrics["response_time_p90"]
    metrics.response_time_p99 = sample_metrics["response_time_p99"]
    metrics.nlp_response_time_p50 = sample_metrics["nlp_response_time_p50"]
    metrics.a2f_response_time_p50 = sample_metrics["a2f_response_time_p50"]
    metrics.gpu_frame_time_avg = sample_metrics["gpu_frame_time_avg"]
    metrics.render_frame_time_avg = sample_metrics["render_frame_time_avg"]
    metrics.game_frame_time_avg = sample_metrics["game_frame_time_avg"]
    metrics.frame_time_avg = sample_metrics["frame_time_avg"]

    return metrics


@pytest.fixture
def mock_sns_client():
    """
    Create a mock AWS SNS client for testing without actual AWS calls.

    Provides a MagicMock configured to simulate successful SNS operations
    without making real AWS API calls.

    Returns:
        MagicMock configured as SNS client

    Example:
        >>> def test_sns_send(mock_sns_client):
        ...     with patch("boto3.client", return_value=mock_sns_client):
        ...         sender = AwsSnsSender()
        ...         success = await sender.send_metrics_snapshot(...)
    """
    mock_client = MagicMock()

    # Configure publish method to return success
    mock_client.publish.return_value = {
        "MessageId": "test-message-id-12345",
        "ResponseMetadata": {
            "RequestId": "test-request-id",
            "HTTPStatusCode": 200
        }
    }

    # Configure get_topic_attributes for validation
    mock_client.get_topic_attributes.return_value = {
        "Attributes": {
            "TopicArn": "arn:aws:sns:us-east-1:123456789012:test-topic",
            "DisplayName": "Test Topic"
        }
    }

    return mock_client
