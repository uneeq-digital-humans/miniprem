"""
Prometheus metrics client for fetching and parsing metrics from containers.

This module provides a client for fetching Prometheus metrics from containers
like Renny that expose metrics endpoints. It parses Prometheus text format
and extracts key metrics like GPU, CPU, and memory usage.
"""

import re
import logging
from typing import Dict, Optional, List, Tuple
import httpx

logger = logging.getLogger(__name__)


class PrometheusMetrics:
    """Parsed Prometheus metrics for a container."""

    def __init__(self):
        self.gpu_percent: Optional[float] = None
        self.cpu_percent: Optional[float] = None
        self.memory_percent: Optional[float] = None
        self.memory_bytes: Optional[int] = None
        self.request_count: Optional[int] = None
        self.uptime_seconds: Optional[float] = None

    def to_dict(self) -> Dict[str, Optional[float]]:
        """Convert metrics to dictionary for JSON serialization."""
        return {
            "gpu_percent": self.gpu_percent,
            "cpu_percent": self.cpu_percent,
            "memory_percent": self.memory_percent,
            "memory_bytes": self.memory_bytes,
            "request_count": self.request_count,
            "uptime_seconds": self.uptime_seconds,
        }


class PrometheusClient:
    """
    Client for fetching and parsing Prometheus metrics.

    Supports fetching metrics from containers that expose Prometheus-compatible
    /metrics endpoints. Handles connection errors gracefully.

    Attributes:
        timeout: HTTP request timeout in seconds (default: 5.0)
        max_retries: Maximum number of connection retries (default: 0)
    """

    def __init__(self, timeout: float = 5.0, max_retries: int = 0):
        """
        Initialize Prometheus client.

        Args:
            timeout: HTTP request timeout in seconds
            max_retries: Maximum number of connection retries
        """
        self.timeout = timeout
        self.max_retries = max_retries
        self._client = httpx.AsyncClient(timeout=timeout)

    async def close(self):
        """Close the HTTP client."""
        await self._client.aclose()

    async def fetch_metrics(self, url: str) -> Optional[str]:
        """
        Fetch raw Prometheus metrics from a URL.

        Args:
            url: Full URL to the metrics endpoint (e.g., http://localhost:8080/metrics)

        Returns:
            Raw metrics text or None if connection fails
        """
        try:
            response = await self._client.get(url)
            response.raise_for_status()
            return response.text
        except httpx.HTTPError as e:
            logger.debug(f"Failed to fetch metrics from {url}: {e}")
            return None
        except Exception as e:
            logger.warning(f"Unexpected error fetching metrics from {url}: {e}")
            return None

    def parse_metrics(self, metrics_text: str) -> PrometheusMetrics:
        """
        Parse Prometheus text format metrics.

        Extracts common metrics like GPU utilization, CPU, memory usage, etc.

        Args:
            metrics_text: Raw Prometheus metrics in text format

        Returns:
            PrometheusMetrics object with parsed values
        """
        metrics = PrometheusMetrics()

        # Parse each line
        for line in metrics_text.split('\n'):
            line = line.strip()

            # Skip comments and empty lines
            if not line or line.startswith('#'):
                continue

            # Parse metric line: metric_name{labels} value timestamp
            try:
                # Split metric name and value
                parts = line.split()
                if len(parts) < 2:
                    continue

                metric_name_with_labels = parts[0]
                value = float(parts[1])

                # Extract metric name (before '{' or entire string)
                if '{' in metric_name_with_labels:
                    metric_name = metric_name_with_labels.split('{')[0]
                else:
                    metric_name = metric_name_with_labels

                # Match known metrics
                self._extract_metric(metric_name, value, metrics)

            except (ValueError, IndexError) as e:
                logger.debug(f"Failed to parse metric line: {line}, error: {e}")
                continue

        return metrics

    def _extract_metric(self, metric_name: str, value: float, metrics: PrometheusMetrics):
        """
        Extract specific metrics from parsed Prometheus data.

        Args:
            metric_name: Name of the metric
            value: Metric value
            metrics: PrometheusMetrics object to populate
        """
        # GPU metrics (common patterns)
        if 'gpu' in metric_name.lower() and 'util' in metric_name.lower():
            metrics.gpu_percent = value
        elif 'gpu_utilization' in metric_name.lower():
            metrics.gpu_percent = value
        elif 'nvidia_gpu_duty_cycle' in metric_name.lower():
            metrics.gpu_percent = value

        # CPU metrics
        elif 'cpu_usage' in metric_name.lower() or 'process_cpu' in metric_name.lower():
            metrics.cpu_percent = value
        elif metric_name == 'process_cpu_seconds_total':
            # This is cumulative, would need calculation between samples
            pass

        # Memory metrics
        elif 'memory_usage_bytes' in metric_name.lower():
            metrics.memory_bytes = int(value)
        elif 'process_resident_memory_bytes' in metric_name:
            metrics.memory_bytes = int(value)
        elif 'memory_percent' in metric_name.lower():
            metrics.memory_percent = value

        # Request count
        elif 'request_total' in metric_name.lower() or 'requests_total' in metric_name.lower():
            metrics.request_count = int(value)
        elif metric_name == 'http_requests_total':
            metrics.request_count = int(value)

        # Uptime
        elif metric_name == 'process_start_time_seconds':
            # Would need current time to calculate uptime
            pass
        elif 'uptime' in metric_name.lower():
            metrics.uptime_seconds = value

    async def get_container_metrics(
        self,
        container_name: str,
        metrics_port: int = 8080,
        metrics_path: str = "/metrics"
    ) -> Optional[PrometheusMetrics]:
        """
        Fetch and parse metrics for a specific container.

        Args:
            container_name: Name of the container
            metrics_port: Port where metrics are exposed (default: 8080)
            metrics_path: Path to metrics endpoint (default: /metrics)

        Returns:
            PrometheusMetrics object or None if metrics unavailable
        """
        url = f"http://localhost:{metrics_port}{metrics_path}"

        logger.debug(f"Fetching metrics for container '{container_name}' from {url}")

        metrics_text = await self.fetch_metrics(url)
        if not metrics_text:
            logger.debug(f"No metrics available for container '{container_name}'")
            return None

        metrics = self.parse_metrics(metrics_text)
        logger.debug(f"Parsed metrics for '{container_name}': {metrics.to_dict()}")

        return metrics


# Singleton instance
_prometheus_client: Optional[PrometheusClient] = None


def get_prometheus_client() -> PrometheusClient:
    """
    Get or create singleton Prometheus client instance.

    Returns:
        PrometheusClient instance
    """
    global _prometheus_client
    if _prometheus_client is None:
        _prometheus_client = PrometheusClient()
    return _prometheus_client


async def close_prometheus_client():
    """Close the singleton Prometheus client."""
    global _prometheus_client
    if _prometheus_client is not None:
        await _prometheus_client.close()
        _prometheus_client = None
