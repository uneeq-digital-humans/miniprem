"""
Integration services for external platforms and messaging.

This module provides integration services for:
- AWS SNS: Sending metrics snapshots to support teams via email
- Future integrations: Slack, PagerDuty, etc.
"""

from .aws_sns_sender import AwsSnsSender

__all__ = ["AwsSnsSender"]
