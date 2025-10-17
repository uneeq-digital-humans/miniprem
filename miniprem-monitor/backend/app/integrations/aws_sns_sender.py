"""
AWS SNS integration service for sending metrics snapshots to support teams.

This module provides functionality to send container metrics snapshots via AWS SNS
to configured email endpoints for support and monitoring purposes.
"""

import os
import json
import logging
from datetime import datetime
from typing import Dict, Any, Optional

import boto3
from botocore.exceptions import ClientError, BotoCoreError

logger = logging.getLogger(__name__)


class AwsSnsSender:
    """
    AWS SNS sender service for metrics snapshot notifications.

    This service sends formatted metrics snapshots via AWS SNS to email subscribers.
    It handles message formatting, SNS client initialization, and error handling.

    Environment Variables:
        AWS_SNS_TOPIC_ARN: Required. ARN of the SNS topic for metrics notifications
        AWS_SNS_REGION: Optional. AWS region for SNS (default: us-east-1)
        AWS_ACCESS_KEY_ID: Optional. AWS access key (uses boto3 default chain if not set)
        AWS_SECRET_ACCESS_KEY: Optional. AWS secret key (uses boto3 default chain if not set)

    Example:
        >>> sender = AwsSnsSender()
        >>> metrics = {"cpu_percent": 67.0, "gpu_percent": 52.0, "memory_percent": 45.0}
        >>> success = await sender.send_metrics_snapshot(
        ...     container_name="renny-container",
        ...     metrics=metrics,
        ...     user_email="user@example.com"
        ... )
        >>> if success:
        ...     print("Metrics snapshot sent successfully")
    """

    def __init__(self) -> None:
        """
        Initialize AWS SNS sender with configuration from environment variables.

        Raises:
            ValueError: If AWS_SNS_TOPIC_ARN environment variable is not set
        """
        self.topic_arn: Optional[str] = os.getenv("AWS_SNS_TOPIC_ARN")
        self.region: str = os.getenv("AWS_SNS_REGION", "us-east-1")

        if not self.topic_arn:
            error_msg = "AWS_SNS_TOPIC_ARN environment variable is required"
            logger.error(error_msg)
            raise ValueError(error_msg)

        # Initialize boto3 SNS client
        # If AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are not set,
        # boto3 will use the default credential chain (IAM role, ~/.aws/credentials, etc.)
        try:
            self.sns_client = boto3.client(
                'sns',
                region_name=self.region,
                aws_access_key_id=os.getenv("AWS_ACCESS_KEY_ID"),
                aws_secret_access_key=os.getenv("AWS_SECRET_ACCESS_KEY")
            )
            logger.info(f"AWS SNS sender initialized successfully (region: {self.region})")
        except Exception as e:
            logger.error(f"Failed to initialize AWS SNS client: {str(e)}")
            raise

    def _format_metrics_message(
        self,
        container_name: str,
        metrics: Dict[str, Any],
        user_email: str
    ) -> tuple[str, str]:
        """
        Format metrics data into a readable email message.

        Args:
            container_name: Name of the container being monitored
            metrics: Dictionary containing metrics data
            user_email: Email address of the requesting user

        Returns:
            Tuple of (subject, body) strings formatted for email delivery

        Example:
            >>> subject, body = sender._format_metrics_message(
            ...     "renny-container",
            ...     {"cpu_percent": 67.0},
            ...     "user@example.com"
            ... )
        """
        timestamp = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC")

        # Create subject line
        subject = f"MiniPrem Metrics Snapshot - {container_name}"

        # Extract key metrics for summary (with safe defaults)
        cpu_usage = metrics.get("cpu_percent", "N/A")
        gpu_usage = metrics.get("gpu_percent", "N/A")
        memory_usage = metrics.get("memory_percent", "N/A")
        session_total = metrics.get("session_total", "N/A")
        response_time_p50 = metrics.get("response_time_p50", "N/A")

        # Format key metrics values
        cpu_str = f"{cpu_usage:.1f}%" if isinstance(cpu_usage, (int, float)) else str(cpu_usage)
        gpu_str = f"{gpu_usage:.1f}%" if isinstance(gpu_usage, (int, float)) else str(gpu_usage)
        memory_str = f"{memory_usage:.1f}%" if isinstance(memory_usage, (int, float)) else str(memory_usage)
        session_str = f"{session_total:,}" if isinstance(session_total, int) else str(session_total)
        response_str = f"{response_time_p50:.1f}ms" if isinstance(response_time_p50, (int, float)) else str(response_time_p50)

        # Create message body with clear formatting
        body = f"""MiniPrem Metrics Support Request

Container: {container_name}
Timestamp: {timestamp}
Requested by: {user_email}

Key Metrics:
- CPU Usage: {cpu_str}
- GPU Usage: {gpu_str}
- Memory: {memory_str}
- Session Total: {session_str}
- Response Time (p50): {response_str}

Full metrics (JSON):
{json.dumps(metrics, indent=2, default=str)}

---
This is an automated message from MiniPrem Monitor.
For questions or assistance, please contact UneeQ support.
"""

        return subject, body

    async def send_metrics_snapshot(
        self,
        container_name: str,
        metrics: Dict[str, Any],
        user_email: str
    ) -> bool:
        """
        Send metrics snapshot to support team via AWS SNS.

        Args:
            container_name: Name of the container being monitored
            metrics: Dictionary containing complete metrics data
            user_email: Email address of the user requesting support

        Returns:
            True if message was sent successfully, False otherwise

        Raises:
            Does not raise exceptions - all errors are logged and return False

        Example:
            >>> success = await sender.send_metrics_snapshot(
            ...     container_name="renny-gpu-01",
            ...     metrics={"cpu_percent": 67.0, "gpu_percent": 52.0},
            ...     user_email="admin@company.com"
            ... )
        """
        try:
            logger.info(
                f"Preparing to send metrics snapshot for container: {container_name} "
                f"(requested by: {user_email})"
            )

            # Format message
            subject, body = self._format_metrics_message(
                container_name=container_name,
                metrics=metrics,
                user_email=user_email
            )

            # Send via SNS
            response = self.sns_client.publish(
                TopicArn=self.topic_arn,
                Subject=subject,
                Message=body,
                MessageAttributes={
                    'container_name': {
                        'DataType': 'String',
                        'StringValue': container_name
                    },
                    'user_email': {
                        'DataType': 'String',
                        'StringValue': user_email
                    },
                    'timestamp': {
                        'DataType': 'String',
                        'StringValue': datetime.utcnow().isoformat()
                    }
                }
            )

            message_id = response.get('MessageId')
            logger.info(
                f"Metrics snapshot sent successfully via SNS "
                f"(MessageId: {message_id}, Container: {container_name})"
            )

            return True

        except ClientError as e:
            error_code = e.response.get('Error', {}).get('Code', 'Unknown')
            error_message = e.response.get('Error', {}).get('Message', str(e))
            logger.error(
                f"AWS SNS ClientError sending metrics snapshot: "
                f"Code={error_code}, Message={error_message}, "
                f"Container={container_name}"
            )
            return False

        except BotoCoreError as e:
            logger.error(
                f"AWS BotoCore error sending metrics snapshot: {str(e)}, "
                f"Container={container_name}"
            )
            return False

        except Exception as e:
            logger.error(
                f"Unexpected error sending metrics snapshot via SNS: {str(e)}, "
                f"Container={container_name}",
                exc_info=True
            )
            return False

    def validate_configuration(self) -> tuple[bool, Optional[str]]:
        """
        Validate SNS configuration and connectivity.

        Returns:
            Tuple of (is_valid, error_message).
            If valid, error_message is None.
            If invalid, error_message contains the reason.

        Example:
            >>> sender = AwsSnsSender()
            >>> is_valid, error = sender.validate_configuration()
            >>> if not is_valid:
            ...     print(f"Configuration error: {error}")
        """
        try:
            # Check if topic exists and is accessible
            response = self.sns_client.get_topic_attributes(
                TopicArn=self.topic_arn
            )

            topic_name = response['Attributes'].get('TopicArn', 'Unknown')
            logger.info(f"SNS configuration validated successfully: {topic_name}")
            return True, None

        except ClientError as e:
            error_code = e.response.get('Error', {}).get('Code', 'Unknown')
            error_message = e.response.get('Error', {}).get('Message', str(e))

            if error_code == 'NotFound':
                error = f"SNS topic not found: {self.topic_arn}"
            elif error_code == 'AuthorizationError':
                error = f"Access denied to SNS topic: {self.topic_arn}"
            else:
                error = f"SNS error ({error_code}): {error_message}"

            logger.error(f"SNS configuration validation failed: {error}")
            return False, error

        except Exception as e:
            error = f"Failed to validate SNS configuration: {str(e)}"
            logger.error(error)
            return False, error
