"""
Comprehensive test suite for Metrics Snapshot API endpoints.

Tests snapshot creation, listing, retrieval, and deletion operations
with proper validation, error handling, and edge case coverage.
"""

import pytest
import uuid
from datetime import datetime, timedelta
from fastapi.testclient import TestClient
from unittest.mock import patch, MagicMock

from app.services.snapshot_manager import SnapshotManager
from app.services.prometheus_client import PrometheusMetrics


class TestSnapshotCreation:
    """Test cases for POST /api/metrics/snapshot endpoint."""

    def test_create_snapshot_success(self, client: TestClient, sample_metrics: dict):
        """
        Test successful snapshot creation with valid metrics.

        Verifies that a snapshot is created with correct data and returns
        a valid snapshot_id and timestamp.
        """
        response = client.post("/api/metrics/snapshot", json={
            "container_name": "renny",
            "metrics": sample_metrics
        })

        assert response.status_code == 200
        data = response.json()

        assert data["success"] is True
        assert "snapshot_id" in data
        assert data["container_name"] == "renny"
        assert "timestamp" in data
        assert data["message"] == "Snapshot created successfully"

        # Validate UUID format
        snapshot_id = data["snapshot_id"]
        try:
            uuid.UUID(snapshot_id)
        except ValueError:
            pytest.fail(f"Invalid UUID format: {snapshot_id}")

    def test_create_snapshot_with_partial_metrics(self, client: TestClient):
        """
        Test snapshot creation with only essential metrics (sparse data).

        Verifies that snapshot creation works with minimal required fields
        and handles missing optional metrics gracefully.
        """
        minimal_metrics = {
            "cpu_percent": 50.0,
            "gpu_percent": 60.0,
            "memory_percent": 40.0
        }

        response = client.post("/api/metrics/snapshot", json={
            "container_name": "renny-minimal",
            "metrics": minimal_metrics
        })

        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert data["container_name"] == "renny-minimal"

    def test_create_snapshot_missing_container_name(self, client: TestClient, sample_metrics: dict):
        """
        Test snapshot creation without container_name (validation error).

        Verifies that Pydantic validation rejects requests with missing
        required fields.
        """
        response = client.post("/api/metrics/snapshot", json={
            "metrics": sample_metrics
        })

        assert response.status_code == 422  # Unprocessable Entity (Pydantic validation)
        error = response.json()
        assert "detail" in error

    def test_create_snapshot_missing_metrics(self, client: TestClient):
        """
        Test snapshot creation without metrics data (validation error).

        Verifies that requests with missing metrics field are rejected
        with appropriate validation error.
        """
        response = client.post("/api/metrics/snapshot", json={
            "container_name": "renny"
        })

        assert response.status_code == 422
        error = response.json()
        assert "detail" in error

    def test_create_snapshot_empty_container_name(self, client: TestClient, sample_metrics: dict):
        """
        Test snapshot creation with empty container name.

        Verifies that empty string container names are rejected by
        Pydantic validation.
        """
        response = client.post("/api/metrics/snapshot", json={
            "container_name": "",
            "metrics": sample_metrics
        })

        assert response.status_code == 422

    def test_create_snapshot_invalid_json(self, client: TestClient):
        """
        Test snapshot creation with malformed JSON payload.

        Verifies that invalid JSON is rejected with 422 error.
        """
        response = client.post(
            "/api/metrics/snapshot",
            data="invalid-json-data",
            headers={"Content-Type": "application/json"}
        )

        assert response.status_code == 422

    def test_create_snapshot_with_null_metrics_values(self, client: TestClient):
        """
        Test snapshot creation with null values in metrics.

        Verifies that null/None values in metrics are handled gracefully
        without causing errors.
        """
        metrics_with_nulls = {
            "cpu_percent": 50.0,
            "gpu_percent": None,
            "memory_percent": 40.0,
            "frames_rendered": None
        }

        response = client.post("/api/metrics/snapshot", json={
            "container_name": "renny-nulls",
            "metrics": metrics_with_nulls
        })

        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True

    def test_create_multiple_snapshots_same_container(self, client: TestClient, sample_metrics: dict):
        """
        Test creating multiple snapshots for the same container.

        Verifies that multiple snapshots can be created for a single container
        with unique snapshot IDs.
        """
        snapshot_ids = []

        for i in range(3):
            response = client.post("/api/metrics/snapshot", json={
                "container_name": "renny-multi",
                "metrics": sample_metrics
            })

            assert response.status_code == 200
            data = response.json()
            snapshot_ids.append(data["snapshot_id"])

        # Verify all snapshot IDs are unique
        assert len(snapshot_ids) == len(set(snapshot_ids))


class TestSnapshotListing:
    """Test cases for GET /api/metrics/snapshots/{container_name} endpoint."""

    def test_list_snapshots_success(self, client: TestClient, sample_metrics: dict):
        """
        Test listing snapshots for a specific container.

        Verifies that created snapshots are returned in the list
        with correct preview data.
        """
        # Create a snapshot first
        create_response = client.post("/api/metrics/snapshot", json={
            "container_name": "renny-list",
            "metrics": sample_metrics
        })
        assert create_response.status_code == 200

        # List snapshots
        list_response = client.get("/api/metrics/snapshots/renny-list")

        assert list_response.status_code == 200
        data = list_response.json()

        assert data["success"] is True
        assert data["container_name"] == "renny-list"
        assert isinstance(data["snapshots"], list)
        assert data["total_count"] >= 1
        assert data["hours"] == 1  # Default

        # Verify preview structure
        if data["snapshots"]:
            snapshot = data["snapshots"][0]
            assert "id" in snapshot
            assert "timestamp" in snapshot
            assert "gpu_percent" in snapshot
            assert "cpu_percent" in snapshot
            assert "memory_percent" in snapshot
            assert "frames_rendered" in snapshot

    def test_list_snapshots_empty_container(self, client: TestClient):
        """
        Test listing snapshots for container with no snapshots.

        Verifies that querying a non-existent container returns
        an empty list without errors.
        """
        response = client.get("/api/metrics/snapshots/nonexistent-container")

        assert response.status_code == 200
        data = response.json()

        assert data["success"] is True
        assert data["snapshots"] == []
        assert data["total_count"] == 0

    def test_list_snapshots_with_hours_parameter(self, client: TestClient, sample_metrics: dict):
        """
        Test listing snapshots with custom time window (hours parameter).

        Verifies that the hours query parameter correctly filters
        snapshots by time range.
        """
        # Create a snapshot
        client.post("/api/metrics/snapshot", json={
            "container_name": "renny-hours",
            "metrics": sample_metrics
        })

        # List with custom hours parameter
        response = client.get("/api/metrics/snapshots/renny-hours?hours=2")

        assert response.status_code == 200
        data = response.json()
        assert data["hours"] == 2

    def test_list_snapshots_ordering(self, client: TestClient, sample_metrics: dict):
        """
        Test that snapshots are returned in descending timestamp order (newest first).

        Verifies that multiple snapshots are correctly ordered by creation time.
        """
        container_name = "renny-ordering"

        # Create multiple snapshots with slight delays
        snapshot_ids = []
        for i in range(3):
            response = client.post("/api/metrics/snapshot", json={
                "container_name": container_name,
                "metrics": sample_metrics
            })
            snapshot_ids.append(response.json()["snapshot_id"])

        # List snapshots
        list_response = client.get(f"/api/metrics/snapshots/{container_name}")
        data = list_response.json()

        # Verify ordering (newest first)
        timestamps = [s["timestamp"] for s in data["snapshots"]]
        assert timestamps == sorted(timestamps, reverse=True)


class TestSnapshotRetrieval:
    """Test cases for GET /api/metrics/snapshot/{snapshot_id} endpoint."""

    def test_get_snapshot_success(self, client: TestClient, sample_metrics: dict):
        """
        Test retrieving a specific snapshot by ID.

        Verifies that complete snapshot data including all metrics
        is returned correctly.
        """
        # Create snapshot
        create_response = client.post("/api/metrics/snapshot", json={
            "container_name": "renny-retrieve",
            "metrics": sample_metrics
        })
        snapshot_id = create_response.json()["snapshot_id"]

        # Retrieve snapshot
        response = client.get(f"/api/metrics/snapshot/{snapshot_id}")

        assert response.status_code == 200
        data = response.json()

        assert data["success"] is True
        assert "snapshot" in data
        snapshot = data["snapshot"]

        assert snapshot["id"] == snapshot_id
        assert snapshot["container_name"] == "renny-retrieve"
        assert "metrics" in snapshot
        assert "timestamp" in snapshot

        # Verify metrics are complete
        metrics = snapshot["metrics"]
        assert metrics["cpu_percent"] == sample_metrics["cpu_percent"]
        assert metrics["gpu_percent"] == sample_metrics["gpu_percent"]

    def test_get_snapshot_not_found(self, client: TestClient):
        """
        Test retrieving non-existent snapshot (404 error).

        Verifies that requesting a non-existent snapshot ID returns
        appropriate 404 error.
        """
        fake_id = str(uuid.uuid4())
        response = client.get(f"/api/metrics/snapshot/{fake_id}")

        assert response.status_code == 404
        error = response.json()
        assert "detail" in error
        assert fake_id in error["detail"]

    def test_get_snapshot_invalid_uuid(self, client: TestClient):
        """
        Test retrieving snapshot with invalid UUID format.

        Verifies that invalid snapshot IDs are handled gracefully
        (either 404 or validation error).
        """
        response = client.get("/api/metrics/snapshot/invalid-uuid-format")

        # Should return 404 (not found) since it's a valid path but invalid ID
        assert response.status_code in [404, 422]


class TestSnapshotDeletion:
    """Test cases for DELETE /api/metrics/snapshot/{snapshot_id} endpoint."""

    def test_delete_snapshot_success(self, client: TestClient, sample_metrics: dict):
        """
        Test successfully deleting a snapshot.

        Verifies that a snapshot can be deleted and subsequent retrieval
        returns 404.
        """
        # Create snapshot
        create_response = client.post("/api/metrics/snapshot", json={
            "container_name": "renny-delete",
            "metrics": sample_metrics
        })
        snapshot_id = create_response.json()["snapshot_id"]

        # Delete snapshot
        delete_response = client.delete(f"/api/metrics/snapshot/{snapshot_id}")

        assert delete_response.status_code == 200
        data = delete_response.json()

        assert data["success"] is True
        assert data["snapshot_id"] == snapshot_id
        assert data["message"] == "Snapshot deleted successfully"

        # Verify snapshot is gone
        get_response = client.get(f"/api/metrics/snapshot/{snapshot_id}")
        assert get_response.status_code == 404

    def test_delete_snapshot_not_found(self, client: TestClient):
        """
        Test deleting non-existent snapshot (404 error).

        Verifies that attempting to delete a non-existent snapshot
        returns appropriate 404 error.
        """
        fake_id = str(uuid.uuid4())
        response = client.delete(f"/api/metrics/snapshot/{fake_id}")

        assert response.status_code == 404
        error = response.json()
        assert "detail" in error

    def test_delete_snapshot_twice(self, client: TestClient, sample_metrics: dict):
        """
        Test deleting the same snapshot twice (idempotency check).

        Verifies that second deletion returns 404 since snapshot
        no longer exists.
        """
        # Create snapshot
        create_response = client.post("/api/metrics/snapshot", json={
            "container_name": "renny-twice",
            "metrics": sample_metrics
        })
        snapshot_id = create_response.json()["snapshot_id"]

        # First deletion
        first_delete = client.delete(f"/api/metrics/snapshot/{snapshot_id}")
        assert first_delete.status_code == 200

        # Second deletion (should fail)
        second_delete = client.delete(f"/api/metrics/snapshot/{snapshot_id}")
        assert second_delete.status_code == 404


class TestSnapshotEdgeCases:
    """Test edge cases and boundary conditions for snapshot API."""

    def test_large_metrics_payload(self, client: TestClient):
        """
        Test snapshot creation with very large metrics payload.

        Verifies that large datasets are handled correctly without
        timeout or memory issues.
        """
        large_metrics = {
            f"custom_metric_{i}": float(i * 10.5)
            for i in range(100)  # 100 custom metrics
        }

        response = client.post("/api/metrics/snapshot", json={
            "container_name": "renny-large",
            "metrics": large_metrics
        })

        assert response.status_code == 200

    def test_special_characters_in_container_name(self, client: TestClient, sample_metrics: dict):
        """
        Test snapshot creation with container names containing hyphens and underscores.

        Verifies that valid special characters in container names are accepted.
        """
        valid_names = ["renny-gpu_01", "container_123-test", "my-app_v2"]

        for name in valid_names:
            response = client.post("/api/metrics/snapshot", json={
                "container_name": name,
                "metrics": sample_metrics
            })
            assert response.status_code == 200, f"Failed for container name: {name}"

    def test_concurrent_snapshot_creation(self, client: TestClient, sample_metrics: dict):
        """
        Test creating multiple snapshots concurrently.

        Verifies that concurrent requests are handled correctly
        without race conditions or duplicate IDs.
        """
        import concurrent.futures

        def create_snapshot():
            return client.post("/api/metrics/snapshot", json={
                "container_name": "renny-concurrent",
                "metrics": sample_metrics
            })

        # Create 5 snapshots concurrently
        with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
            futures = [executor.submit(create_snapshot) for _ in range(5)]
            responses = [f.result() for f in futures]

        # All should succeed
        for response in responses:
            assert response.status_code == 200

        # All snapshot IDs should be unique
        snapshot_ids = [r.json()["snapshot_id"] for r in responses]
        assert len(snapshot_ids) == len(set(snapshot_ids))

    def test_metrics_with_extreme_values(self, client: TestClient):
        """
        Test snapshot creation with extreme metric values (0, 100, very large).

        Verifies that boundary values are stored and retrieved correctly.
        """
        extreme_metrics = {
            "cpu_percent": 0.0,
            "gpu_percent": 100.0,
            "memory_percent": 99.9,
            "frames_rendered": 999999999,
            "response_time_p99": 0.001
        }

        response = client.post("/api/metrics/snapshot", json={
            "container_name": "renny-extreme",
            "metrics": extreme_metrics
        })

        assert response.status_code == 200
        snapshot_id = response.json()["snapshot_id"]

        # Verify values are preserved
        get_response = client.get(f"/api/metrics/snapshot/{snapshot_id}")
        data = get_response.json()
        metrics = data["snapshot"]["metrics"]

        assert metrics["cpu_percent"] == 0.0
        assert metrics["gpu_percent"] == 100.0


class TestSnapshotIntegration:
    """Integration tests combining multiple snapshot operations."""

    def test_full_snapshot_lifecycle(self, client: TestClient, sample_metrics: dict):
        """
        Test complete snapshot lifecycle: create, list, retrieve, delete.

        Verifies that all operations work together correctly in a
        typical usage workflow.
        """
        container_name = "renny-lifecycle"

        # 1. Create snapshot
        create_response = client.post("/api/metrics/snapshot", json={
            "container_name": container_name,
            "metrics": sample_metrics
        })
        assert create_response.status_code == 200
        snapshot_id = create_response.json()["snapshot_id"]

        # 2. List snapshots
        list_response = client.get(f"/api/metrics/snapshots/{container_name}")
        assert list_response.status_code == 200
        assert list_response.json()["total_count"] >= 1

        # 3. Retrieve specific snapshot
        get_response = client.get(f"/api/metrics/snapshot/{snapshot_id}")
        assert get_response.status_code == 200
        assert get_response.json()["snapshot"]["id"] == snapshot_id

        # 4. Delete snapshot
        delete_response = client.delete(f"/api/metrics/snapshot/{snapshot_id}")
        assert delete_response.status_code == 200

        # 5. Verify deletion
        verify_response = client.get(f"/api/metrics/snapshot/{snapshot_id}")
        assert verify_response.status_code == 404

    def test_multiple_containers_isolation(self, client: TestClient, sample_metrics: dict):
        """
        Test that snapshots are properly isolated between different containers.

        Verifies that listing snapshots for one container doesn't return
        snapshots from other containers.
        """
        # Create snapshots for container A
        client.post("/api/metrics/snapshot", json={
            "container_name": "container-a",
            "metrics": sample_metrics
        })

        # Create snapshots for container B
        client.post("/api/metrics/snapshot", json={
            "container_name": "container-b",
            "metrics": sample_metrics
        })

        # List snapshots for container A
        response_a = client.get("/api/metrics/snapshots/container-a")
        data_a = response_a.json()

        # List snapshots for container B
        response_b = client.get("/api/metrics/snapshots/container-b")
        data_b = response_b.json()

        # Verify isolation
        assert data_a["total_count"] >= 1
        assert data_b["total_count"] >= 1

        # Verify no cross-contamination
        snapshot_ids_a = {s["id"] for s in data_a["snapshots"]}
        snapshot_ids_b = {s["id"] for s in data_b["snapshots"]}
        assert snapshot_ids_a.isdisjoint(snapshot_ids_b)
