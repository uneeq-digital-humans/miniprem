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
        # Standard system metrics (for compatibility with nvidia-smi, docker stats, etc.)
        self.gpu_percent: Optional[float] = None
        self.cpu_percent: Optional[float] = None
        self.memory_percent: Optional[float] = None
        self.memory_bytes: Optional[int] = None
        self.power_watts: Optional[float] = None
        self.request_count: Optional[int] = None
        self.uptime_seconds: Optional[float] = None

        # Renny application metrics
        self.session_total: Optional[int] = None
        self.session_started: Optional[int] = None
        self.session_successful: Optional[int] = None
        self.session_failed: Optional[int] = None
        self.frames_rendered: Optional[int] = None

        # Response time metrics (milliseconds)
        self.response_time_p50: Optional[float] = None
        self.response_time_p90: Optional[float] = None
        self.response_time_p99: Optional[float] = None
        self.nlp_response_time_p50: Optional[float] = None
        self.a2f_response_time_p50: Optional[float] = None

        # Frame timing metrics (milliseconds, calculated from sum/count)
        self.gpu_frame_time_avg: Optional[float] = None
        self.render_frame_time_avg: Optional[float] = None
        self.game_frame_time_avg: Optional[float] = None
        self.frame_time_avg: Optional[float] = None

        # Raw frame timing data for calculations
        self._frame_times_data: Dict[str, Tuple[float, float]] = {}  # {thread: (sum, count)}

    def to_dict(self) -> Dict[str, Optional[float]]:
        """Convert metrics to dictionary for JSON serialization."""
        return {
            # Standard metrics
            "gpu_percent": self.gpu_percent,
            "cpu_percent": self.cpu_percent,
            "memory_percent": self.memory_percent,
            "memory_bytes": self.memory_bytes,
            "power_watts": self.power_watts,
            "request_count": self.request_count,
            "uptime_seconds": self.uptime_seconds,

            # Renny application metrics
            "session_total": self.session_total,
            "session_started": self.session_started,
            "session_successful": self.session_successful,
            "session_failed": self.session_failed,
            "frames_rendered": self.frames_rendered,

            # Response times
            "response_time_p50": self.response_time_p50,
            "response_time_p90": self.response_time_p90,
            "response_time_p99": self.response_time_p99,
            "nlp_response_time_p50": self.nlp_response_time_p50,
            "a2f_response_time_p50": self.a2f_response_time_p50,

            # Frame timings
            "gpu_frame_time_avg": self.gpu_frame_time_avg,
            "render_frame_time_avg": self.render_frame_time_avg,
            "game_frame_time_avg": self.game_frame_time_avg,
            "frame_time_avg": self.frame_time_avg,
        }

    def _calculate_frame_time_averages(self):
        """Calculate average frame times from sum/count data."""
        for thread, (sum_val, count_val) in self._frame_times_data.items():
            if count_val > 0:
                avg = sum_val / count_val
                if thread == "gpu":
                    self.gpu_frame_time_avg = avg
                elif thread == "render":
                    self.render_frame_time_avg = avg
                elif thread == "game":
                    self.game_frame_time_avg = avg
                elif thread == "frame":
                    self.frame_time_avg = avg


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
        Also parses Renny-specific application metrics with label support.

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
                value_str = parts[1]

                # Handle Nan values
                if value_str.lower() == 'nan':
                    continue

                value = float(value_str)

                # Extract metric name and labels
                if '{' in metric_name_with_labels:
                    metric_name = metric_name_with_labels.split('{')[0]
                    labels_part = metric_name_with_labels.split('{')[1].rstrip('}')
                    labels = self._parse_labels(labels_part)
                else:
                    metric_name = metric_name_with_labels
                    labels = {}

                # Match known metrics
                self._extract_metric(metric_name, value, labels, metrics)

            except (ValueError, IndexError) as e:
                logger.debug(f"Failed to parse metric line: {line}, error: {e}")
                continue

        # Calculate derived metrics
        metrics._calculate_frame_time_averages()

        return metrics

    def _parse_labels(self, labels_str: str) -> Dict[str, str]:
        """
        Parse Prometheus labels from string format.

        Args:
            labels_str: Label string like 'component="total",quantile="0.5"'

        Returns:
            Dictionary of label key-value pairs
        """
        labels = {}
        for label_pair in labels_str.split(','):
            if '=' in label_pair:
                key, value = label_pair.split('=', 1)
                labels[key.strip()] = value.strip().strip('"')
        return labels

    def _extract_metric(self, metric_name: str, value: float, labels: Dict[str, str], metrics: PrometheusMetrics):
        """
        Extract specific metrics from parsed Prometheus data with label support.

        Args:
            metric_name: Name of the metric
            value: Metric value
            labels: Dictionary of metric labels (e.g., {"component": "total", "type": "started"})
            metrics: PrometheusMetrics object to populate
        """
        # ===== RENNY APPLICATION METRICS =====

        # Session count metrics
        if metric_name == 'session_count':
            session_type = labels.get('type', '')
            if session_type == 'total':
                metrics.session_total = int(value)
            elif session_type == 'started':
                metrics.session_started = int(value)
            elif session_type == 'successful':
                metrics.session_successful = int(value)
            elif session_type == 'failed':
                metrics.session_failed = int(value)

        # Frames rendered
        elif metric_name == 'frames_rendered_count':
            if labels.get('map') == 'all':
                metrics.frames_rendered = int(value)

        # Response time metrics (milliseconds)
        elif metric_name == 'dh_response_times':
            component = labels.get('component', '')
            quantile = labels.get('quantile', '')

            if component == 'total' and quantile == '0.5':
                metrics.response_time_p50 = value
            elif component == 'total' and quantile == '0.9':
                metrics.response_time_p90 = value
            elif component == 'total' and quantile == '0.99':
                metrics.response_time_p99 = value
            elif component == 'nlp' and quantile == '0.5':
                metrics.nlp_response_time_p50 = value
            elif component == 'a2f' and quantile == '0.5':
                metrics.a2f_response_time_p50 = value

        # Frame timing - collect sum and count for average calculation
        elif metric_name == 'frame_times_sum':
            thread = labels.get('thread', '')
            if thread and thread in ['gpu', 'render', 'game', 'frame']:
                if thread not in metrics._frame_times_data:
                    metrics._frame_times_data[thread] = [0.0, 0.0]
                metrics._frame_times_data[thread][0] = value

        elif metric_name == 'frame_times_count':
            thread = labels.get('thread', '')
            if thread and thread in ['gpu', 'render', 'game', 'frame']:
                if thread not in metrics._frame_times_data:
                    metrics._frame_times_data[thread] = [0.0, 0.0]
                metrics._frame_times_data[thread][1] = value

        # ===== STANDARD SYSTEM METRICS (for compatibility) =====

        # GPU metrics (common patterns from nvidia-smi, cAdvisor, etc.)
        elif 'gpu' in metric_name.lower() and 'util' in metric_name.lower():
            metrics.gpu_percent = value
        elif 'gpu_utilization' in metric_name.lower():
            metrics.gpu_percent = value
        elif 'nvidia_gpu_duty_cycle' in metric_name.lower():
            metrics.gpu_percent = value

        # Power metrics
        elif 'power' in metric_name.lower() and 'watts' in metric_name.lower():
            metrics.power_watts = value
        elif 'nvidia_gpu_power_usage' in metric_name.lower():
            metrics.power_watts = value

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
