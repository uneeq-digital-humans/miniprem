"""
Comprehensive test suite for AWS SNS integration and metrics support API.

Tests sending metrics snapshots to support teams via AWS SNS, including
email validation, SNS configuration checks, and error handling.
"""

import pytest
import os
from unittest.mock import patch, MagicMock, AsyncMock, ANY
from fastapi.testclient import TestClient
from botocore.exceptions import ClientError, BotoCoreError

from app.integrations.aws_sns_sender import AwsSnsSender


class TestSendMetricsToSupport:
    """Test cases for POST /api/metrics/send/support endpoint."""

    def test_send_metrics_success(self, client: TestClient, sample_metrics: dict, mock_sns_client):
        """
        Test successfully sending metrics snapshot to support via SNS.

        Verifies that a valid request with existing snapshot triggers
        SNS publish with correct parameters.
        """
        # Create snapshot first
        snapshot_response = client.post("/api/metrics/snapshot", json={
            "container_name": "renny",
            "metrics": sample_metrics
        })
        snapshot_id = snapshot_response.json()["snapshot_id"]

        # Mock SNS sender (must be AsyncMock for async method)
        with patch("app.main.sns_sender") as mock_sender:
            mock_sender.send_metrics_snapshot = AsyncMock(return_value=True)

            # Send to support
            response = client.post("/api/metrics/send/support", json={
                "container_name": "renny",
                "snapshot_id": snapshot_id,
                "user_email": "admin@example.com"
            })

            assert response.status_code == 200
            data = response.json()

            assert data["success"] is True
            assert data["container_name"] == "renny"
            assert data["snapshot_id"] == snapshot_id
            assert data["user_email"] == "admin@example.com"
            assert "message" in data
            assert "sent successfully" in data["message"].lower()

            # Verify SNS sender was called
            mock_sender.send_metrics_snapshot.assert_called_once()

    def test_send_metrics_sns_not_configured(self, client: TestClient, sample_metrics: dict):
        """
        Test sending metrics when SNS is not configured (503 error).

        Verifies that requests fail gracefully with appropriate error
        when SNS integration is not initialized.
        """
        # Create snapshot
        snapshot_response = client.post("/api/metrics/snapshot", json={
            "container_name": "renny",
            "metrics": sample_metrics
        })
        snapshot_id = snapshot_response.json()["snapshot_id"]

        # Mock SNS sender as None (not configured)
        with patch("app.main.sns_sender", None):
            response = client.post("/api/metrics/send/support", json={
                "container_name": "renny",
                "snapshot_id": snapshot_id,
                "user_email": "admin@example.com"
            })

            assert response.status_code == 503  # Service Unavailable
            error = response.json()
            assert "detail" in error
            assert "not configured" in str(error["detail"]).lower()

    def test_send_metrics_snapshot_not_found(self, client: TestClient):
        """
        Test sending metrics with non-existent snapshot ID (404 error).

        Verifies that invalid snapshot IDs are detected and rejected
        with appropriate error message.
        """
        fake_snapshot_id = "00000000-0000-0000-0000-000000000000"

        with patch("app.main.sns_sender") as mock_sender:
            mock_sender.send_metrics_snapshot.return_value = True

            response = client.post("/api/metrics/send/support", json={
                "container_name": "renny",
                "snapshot_id": fake_snapshot_id,
                "user_email": "admin@example.com"
            })

            assert response.status_code == 404
            error = response.json()
            assert "detail" in error
            assert "not found" in str(error["detail"]).lower()

    def test_send_metrics_invalid_email(self, client: TestClient, sample_metrics: dict):
        """
        Test sending metrics with invalid email address (validation error).

        Verifies that Pydantic EmailStr validation rejects malformed
        email addresses.
        """
        # Create snapshot
        snapshot_response = client.post("/api/metrics/snapshot", json={
            "container_name": "renny",
            "metrics": sample_metrics
        })
        snapshot_id = snapshot_response.json()["snapshot_id"]

        invalid_emails = [
            "not-an-email",
            "missing-at-sign.com",
            "@no-local-part.com",
            "spaces in email@example.com",
            ""
        ]

        for invalid_email in invalid_emails:
            response = client.post("/api/metrics/send/support", json={
                "container_name": "renny",
                "snapshot_id": snapshot_id,
                "user_email": invalid_email
            })

            assert response.status_code == 422, f"Failed to reject invalid email: {invalid_email}"

    def test_send_metrics_missing_fields(self, client: TestClient):
        """
        Test sending metrics with missing required fields.

        Verifies that requests with incomplete data are rejected
        with validation errors.
        """
        # Missing container_name
        response = client.post("/api/metrics/send/support", json={
            "snapshot_id": "test-id",
            "user_email": "admin@example.com"
        })
        assert response.status_code == 422

        # Missing snapshot_id
        response = client.post("/api/metrics/send/support", json={
            "container_name": "renny",
            "user_email": "admin@example.com"
        })
        assert response.status_code == 422

        # Missing user_email
        response = client.post("/api/metrics/send/support", json={
            "container_name": "renny",
            "snapshot_id": "test-id"
        })
        assert response.status_code == 422

    def test_send_metrics_sns_publish_failure(self, client: TestClient, sample_metrics: dict):
        """
        Test handling of SNS publish failures.

        Verifies that SNS API errors are handled gracefully with
        appropriate error responses.
        """
        # Create snapshot
        snapshot_response = client.post("/api/metrics/snapshot", json={
            "container_name": "renny",
            "metrics": sample_metrics
        })
        snapshot_id = snapshot_response.json()["snapshot_id"]

        # Mock SNS sender to return failure (use AsyncMock)
        with patch("app.main.sns_sender") as mock_sender:
            mock_sender.send_metrics_snapshot = AsyncMock(return_value=False)

            response = client.post("/api/metrics/send/support", json={
                "container_name": "renny",
                "snapshot_id": snapshot_id,
                "user_email": "admin@example.com"
            })

            assert response.status_code == 500
            error = response.json()
            assert "detail" in error

    def test_send_metrics_valid_email_formats(self, client: TestClient, sample_metrics: dict):
        """
        Test sending metrics with various valid email formats.

        Verifies that all standard-compliant email formats are accepted.
        """
        # Create snapshot
        snapshot_response = client.post("/api/metrics/snapshot", json={
            "container_name": "renny",
            "metrics": sample_metrics
        })
        snapshot_id = snapshot_response.json()["snapshot_id"]

        valid_emails = [
            "admin@example.com",
            "user.name@example.co.uk",
            "first+last@subdomain.example.com",
            "test123@company-name.io"
        ]

        with patch("app.main.sns_sender") as mock_sender:
            mock_sender.send_metrics_snapshot = AsyncMock(return_value=True)

            for email in valid_emails:
                response = client.post("/api/metrics/send/support", json={
                    "container_name": "renny",
                    "snapshot_id": snapshot_id,
                    "user_email": email
                })

                assert response.status_code == 200, f"Failed to accept valid email: {email}"


class TestAwsSnsSender:
    """Test cases for AwsSnsSender class functionality."""

    def test_sns_sender_initialization_success(self, mock_sns_client):
        """
        Test successful initialization of AwsSnsSender.

        Verifies that SNS sender initializes correctly with
        valid environment configuration.
        """
        test_topic_arn = "arn:aws:sns:us-east-1:123456789012:test-topic"

        with patch.dict(os.environ, {
            "AWS_SNS_TOPIC_ARN": test_topic_arn,
            "AWS_SNS_REGION": "us-east-1"
        }):
            with patch("boto3.client", return_value=mock_sns_client):
                sender = AwsSnsSender()

                assert sender.topic_arn == test_topic_arn
                assert sender.region == "us-east-1"
                assert sender.sns_client is not None

    def test_sns_sender_initialization_missing_topic_arn(self):
        """
        Test initialization failure when AWS_SNS_TOPIC_ARN is missing.

        Verifies that ValueError is raised when required environment
        variable is not set.
        """
        with patch.dict(os.environ, {}, clear=True):
            with pytest.raises(ValueError) as exc_info:
                AwsSnsSender()

            assert "AWS_SNS_TOPIC_ARN" in str(exc_info.value)

    def test_sns_sender_default_region(self, mock_sns_client):
        """
        Test that default region (us-east-1) is used when not specified.

        Verifies fallback behavior for AWS_SNS_REGION environment variable.
        """
        with patch.dict(os.environ, {
            "AWS_SNS_TOPIC_ARN": "arn:aws:sns:us-east-1:123456789012:test-topic"
        }, clear=True):
            with patch("boto3.client", return_value=mock_sns_client):
                sender = AwsSnsSender()
                assert sender.region == "us-east-1"

    @pytest.mark.asyncio
    async def test_send_metrics_snapshot_success(self, mock_sns_client, sample_metrics: dict):
        """
        Test successful sending of metrics snapshot via SNS.

        Verifies that SNS publish is called with correct parameters
        including message formatting and attributes.
        """
        with patch.dict(os.environ, {
            "AWS_SNS_TOPIC_ARN": "arn:aws:sns:us-east-1:123456789012:test-topic"
        }):
            with patch("boto3.client", return_value=mock_sns_client):
                sender = AwsSnsSender()

                success = await sender.send_metrics_snapshot(
                    container_name="renny-test",
                    metrics=sample_metrics,
                    user_email="admin@example.com"
                )

                assert success is True
                mock_sns_client.publish.assert_called_once()

                # Verify publish call parameters
                call_args = mock_sns_client.publish.call_args
                assert call_args.kwargs["TopicArn"] == sender.topic_arn
                assert "Subject" in call_args.kwargs
                assert "Message" in call_args.kwargs
                assert "MessageAttributes" in call_args.kwargs

                # Verify message attributes
                attrs = call_args.kwargs["MessageAttributes"]
                assert attrs["container_name"]["StringValue"] == "renny-test"
                assert attrs["user_email"]["StringValue"] == "admin@example.com"

    @pytest.mark.asyncio
    async def test_send_metrics_snapshot_client_error(self, sample_metrics: dict):
        """
        Test handling of AWS ClientError during SNS publish.

        Verifies that ClientError exceptions are caught and logged
        without raising exceptions.
        """
        mock_client = MagicMock()
        mock_client.publish.side_effect = ClientError(
            error_response={"Error": {"Code": "InvalidParameter", "Message": "Invalid topic"}},
            operation_name="Publish"
        )

        with patch.dict(os.environ, {
            "AWS_SNS_TOPIC_ARN": "arn:aws:sns:us-east-1:123456789012:test-topic"
        }):
            with patch("boto3.client", return_value=mock_client):
                sender = AwsSnsSender()

                success = await sender.send_metrics_snapshot(
                    container_name="renny-test",
                    metrics=sample_metrics,
                    user_email="admin@example.com"
                )

                assert success is False

    @pytest.mark.asyncio
    async def test_send_metrics_snapshot_botocore_error(self, sample_metrics: dict):
        """
        Test handling of BotoCoreError during SNS publish.

        Verifies that BotoCoreError exceptions are caught and handled
        gracefully.
        """
        mock_client = MagicMock()
        mock_client.publish.side_effect = BotoCoreError()

        with patch.dict(os.environ, {
            "AWS_SNS_TOPIC_ARN": "arn:aws:sns:us-east-1:123456789012:test-topic"
        }):
            with patch("boto3.client", return_value=mock_client):
                sender = AwsSnsSender()

                success = await sender.send_metrics_snapshot(
                    container_name="renny-test",
                    metrics=sample_metrics,
                    user_email="admin@example.com"
                )

                assert success is False

    @pytest.mark.asyncio
    async def test_send_metrics_snapshot_generic_exception(self, sample_metrics: dict):
        """
        Test handling of generic exceptions during SNS publish.

        Verifies that unexpected exceptions are caught and logged
        without crashing the application.
        """
        mock_client = MagicMock()
        mock_client.publish.side_effect = Exception("Unexpected error")

        with patch.dict(os.environ, {
            "AWS_SNS_TOPIC_ARN": "arn:aws:sns:us-east-1:123456789012:test-topic"
        }):
            with patch("boto3.client", return_value=mock_client):
                sender = AwsSnsSender()

                success = await sender.send_metrics_snapshot(
                    container_name="renny-test",
                    metrics=sample_metrics,
                    user_email="admin@example.com"
                )

                assert success is False

    def test_format_metrics_message(self, mock_sns_client, sample_metrics: dict):
        """
        Test message formatting for SNS email delivery.

        Verifies that metrics are formatted into readable email
        with proper structure and key metrics highlighted.
        """
        with patch.dict(os.environ, {
            "AWS_SNS_TOPIC_ARN": "arn:aws:sns:us-east-1:123456789012:test-topic"
        }):
            with patch("boto3.client", return_value=mock_sns_client):
                sender = AwsSnsSender()

                subject, body = sender._format_metrics_message(
                    container_name="renny-test",
                    metrics=sample_metrics,
                    user_email="admin@example.com"
                )

                # Verify subject
                assert "MiniPrem Metrics Snapshot" in subject
                assert "renny-test" in subject

                # Verify body structure
                assert "Container: renny-test" in body
                assert "admin@example.com" in body
                assert "CPU Usage:" in body
                assert "GPU Usage:" in body
                assert "Memory:" in body
                assert "Session Total:" in body
                assert "Response Time (p50):" in body

                # Verify JSON metrics are included
                assert "Full metrics (JSON):" in body

    def test_format_metrics_message_with_missing_values(self, mock_sns_client):
        """
        Test message formatting with missing/null metric values.

        Verifies that missing metrics are handled gracefully with
        "N/A" or appropriate placeholder values.
        """
        incomplete_metrics = {
            "cpu_percent": 50.0,
            # gpu_percent missing
            "memory_percent": None,
        }

        with patch.dict(os.environ, {
            "AWS_SNS_TOPIC_ARN": "arn:aws:sns:us-east-1:123456789012:test-topic"
        }):
            with patch("boto3.client", return_value=mock_sns_client):
                sender = AwsSnsSender()

                subject, body = sender._format_metrics_message(
                    container_name="renny-test",
                    metrics=incomplete_metrics,
                    user_email="admin@example.com"
                )

                # Should not crash and should contain N/A for missing values
                assert "N/A" in body or "None" in body

    def test_validate_configuration_success(self, mock_sns_client):
        """
        Test SNS configuration validation with valid setup.

        Verifies that validate_configuration correctly checks
        topic accessibility and returns success.
        """
        with patch.dict(os.environ, {
            "AWS_SNS_TOPIC_ARN": "arn:aws:sns:us-east-1:123456789012:test-topic"
        }):
            with patch("boto3.client", return_value=mock_sns_client):
                sender = AwsSnsSender()
                is_valid, error = sender.validate_configuration()

                assert is_valid is True
                assert error is None

    def test_validate_configuration_topic_not_found(self):
        """
        Test configuration validation when SNS topic doesn't exist.

        Verifies that NotFound errors are detected and reported
        with appropriate error messages.
        """
        mock_client = MagicMock()
        mock_client.get_topic_attributes.side_effect = ClientError(
            error_response={"Error": {"Code": "NotFound", "Message": "Topic not found"}},
            operation_name="GetTopicAttributes"
        )

        with patch.dict(os.environ, {
            "AWS_SNS_TOPIC_ARN": "arn:aws:sns:us-east-1:123456789012:nonexistent"
        }):
            with patch("boto3.client", return_value=mock_client):
                sender = AwsSnsSender()
                is_valid, error = sender.validate_configuration()

                assert is_valid is False
                assert error is not None
                assert "not found" in error.lower()

    def test_validate_configuration_access_denied(self):
        """
        Test configuration validation when access is denied to SNS topic.

        Verifies that authorization errors are detected and reported
        appropriately.
        """
        mock_client = MagicMock()
        mock_client.get_topic_attributes.side_effect = ClientError(
            error_response={"Error": {"Code": "AuthorizationError", "Message": "Access denied"}},
            operation_name="GetTopicAttributes"
        )

        with patch.dict(os.environ, {
            "AWS_SNS_TOPIC_ARN": "arn:aws:sns:us-east-1:123456789012:restricted"
        }):
            with patch("boto3.client", return_value=mock_client):
                sender = AwsSnsSender()
                is_valid, error = sender.validate_configuration()

                assert is_valid is False
                assert error is not None
                assert "access denied" in error.lower()


class TestSNSIntegration:
    """Integration tests combining snapshot and SNS operations."""

    def test_end_to_end_support_workflow(self, client: TestClient, sample_metrics: dict):
        """
        Test complete support workflow: create snapshot, send to support.

        Verifies that the full workflow from snapshot creation to
        SNS delivery works correctly.
        """
        # 1. Create metrics snapshot
        create_response = client.post("/api/metrics/snapshot", json={
            "container_name": "renny-support",
            "metrics": sample_metrics
        })
        assert create_response.status_code == 200
        snapshot_id = create_response.json()["snapshot_id"]

        # 2. Send to support via SNS
        with patch("app.main.sns_sender") as mock_sender:
            mock_sender.send_metrics_snapshot = AsyncMock(return_value=True)

            support_response = client.post("/api/metrics/send/support", json={
                "container_name": "renny-support",
                "snapshot_id": snapshot_id,
                "user_email": "support@uneeq.com"
            })

            assert support_response.status_code == 200
            data = support_response.json()
            assert data["success"] is True

    def test_send_multiple_snapshots_to_support(self, client: TestClient, sample_metrics: dict):
        """
        Test sending multiple snapshots to support sequentially.

        Verifies that multiple support requests can be made without
        interference or caching issues.
        """
        snapshot_ids = []

        # Create 3 snapshots
        for i in range(3):
            response = client.post("/api/metrics/snapshot", json={
                "container_name": f"renny-multi-{i}",
                "metrics": sample_metrics
            })
            snapshot_ids.append(response.json()["snapshot_id"])

        # Send all to support
        with patch("app.main.sns_sender") as mock_sender:
            mock_sender.send_metrics_snapshot = AsyncMock(return_value=True)

            for i, snapshot_id in enumerate(snapshot_ids):
                response = client.post("/api/metrics/send/support", json={
                    "container_name": f"renny-multi-{i}",
                    "snapshot_id": snapshot_id,
                    "user_email": "admin@example.com"
                })

                assert response.status_code == 200
                assert response.json()["success"] is True

        # Verify SNS sender was called 3 times
        assert mock_sender.send_metrics_snapshot.call_count == 3
