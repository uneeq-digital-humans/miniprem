"""
Metrics snapshot management system for storing and retrieving historical metrics data.

This module provides async SQLite-based storage for Prometheus metrics snapshots,
enabling temporal analysis and historical data retrieval. Includes automatic cleanup
of expired snapshots based on configurable retention policies.
"""

import os
import json
import logging
import asyncio
from datetime import datetime, timedelta
from typing import List, Optional, Dict, Any
from pathlib import Path
import aiosqlite

from .prometheus_client import PrometheusMetrics

logger = logging.getLogger(__name__)


class MetricSnapshot:
    """
    Represents a single metrics snapshot with metadata.

    Attributes:
        id: Unique snapshot identifier (UUID format)
        container_name: Name of the container the metrics belong to
        metrics: PrometheusMetrics object with metric values
        timestamp: ISO 8601 timestamp when the snapshot was captured
    """

    def __init__(
        self,
        snapshot_id: str,
        container_name: str,
        metrics: PrometheusMetrics,
        timestamp: str
    ):
        """
        Initialize a metric snapshot.

        Args:
            snapshot_id: Unique identifier for the snapshot
            container_name: Name of the monitored container
            metrics: PrometheusMetrics object with captured values
            timestamp: ISO 8601 formatted timestamp
        """
        self.id = snapshot_id
        self.container_name = container_name
        self.metrics = metrics
        self.timestamp = timestamp

    def to_dict(self) -> Dict[str, Any]:
        """
        Convert snapshot to dictionary for JSON serialization.

        Returns:
            Dictionary with snapshot metadata and metrics
        """
        return {
            "id": self.id,
            "container_name": self.container_name,
            "metrics": self.metrics.to_dict(),
            "timestamp": self.timestamp
        }

    def preview_dict(self) -> Dict[str, Any]:
        """
        Generate a preview dictionary with key metrics only.

        Returns:
            Dictionary with snapshot ID, timestamp, and essential metrics
        """
        metrics_dict = self.metrics.to_dict()
        preview = {
            "id": self.id,
            "timestamp": self.timestamp,
            "gpu_percent": metrics_dict.get("gpu_percent"),
            "cpu_percent": metrics_dict.get("cpu_percent"),
            "memory_percent": metrics_dict.get("memory_percent"),
            "frames_rendered": metrics_dict.get("frames_rendered"),
        }
        return preview


class SnapshotManager:
    """
    Manages metrics snapshots with SQLite storage and automatic cleanup.

    Provides async operations for creating, retrieving, and deleting metrics snapshots.
    Includes background task for automatic cleanup of expired snapshots based on
    retention policy.

    Attributes:
        db_path: Path to SQLite database file
        retention_hours: Number of hours to retain snapshots before cleanup
        cleanup_running: Flag indicating if cleanup task is active
    """

    def __init__(self, db_path: str = "/app/data/snapshots.db", retention_hours: int = 1):
        """
        Initialize the snapshot manager.

        Creates database directory if it doesn't exist and sets up retention policy.

        Args:
            db_path: Path to SQLite database file (default: /app/data/snapshots.db)
            retention_hours: Hours to retain snapshots (default: 1)

        Raises:
            OSError: If database directory cannot be created
        """
        self.db_path = db_path
        self.retention_hours = retention_hours
        self.cleanup_running = False
        self._cleanup_task: Optional[asyncio.Task] = None

        # Ensure database directory exists
        db_dir = Path(db_path).parent
        db_dir.mkdir(parents=True, exist_ok=True)
        logger.info(f"SnapshotManager initialized with db_path={db_path}, retention={retention_hours}h")

    async def initialize(self):
        """
        Initialize the database schema.

        Creates the metric_snapshots table if it doesn't exist.
        Should be called during application startup.

        Raises:
            aiosqlite.Error: If database initialization fails
        """
        try:
            async with aiosqlite.connect(self.db_path) as db:
                await db.execute("""
                    CREATE TABLE IF NOT EXISTS metric_snapshots (
                        id TEXT PRIMARY KEY,
                        container_name TEXT NOT NULL,
                        metrics_json TEXT NOT NULL,
                        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
                    )
                """)

                # Create index for efficient container_name queries
                await db.execute("""
                    CREATE INDEX IF NOT EXISTS idx_container_timestamp
                    ON metric_snapshots(container_name, timestamp DESC)
                """)

                # Create index for cleanup queries
                await db.execute("""
                    CREATE INDEX IF NOT EXISTS idx_timestamp
                    ON metric_snapshots(timestamp)
                """)

                await db.commit()
                logger.info("Database schema initialized successfully")

        except aiosqlite.Error as e:
            logger.error(f"Failed to initialize database: {e}")
            raise

    async def create_snapshot(
        self,
        snapshot_id: str,
        container_name: str,
        metrics: PrometheusMetrics
    ) -> MetricSnapshot:
        """
        Create a new metrics snapshot and store it in the database.

        Args:
            snapshot_id: Unique identifier for the snapshot (UUID)
            container_name: Name of the container being monitored
            metrics: PrometheusMetrics object with current metrics

        Returns:
            MetricSnapshot object with stored data

        Raises:
            aiosqlite.Error: If database operation fails
            ValueError: If required parameters are missing
        """
        if not snapshot_id or not container_name:
            raise ValueError("snapshot_id and container_name are required")

        timestamp = datetime.utcnow().isoformat()
        metrics_json = json.dumps(metrics.to_dict())

        try:
            async with aiosqlite.connect(self.db_path) as db:
                await db.execute(
                    """
                    INSERT INTO metric_snapshots (id, container_name, metrics_json, timestamp)
                    VALUES (?, ?, ?, ?)
                    """,
                    (snapshot_id, container_name, metrics_json, timestamp)
                )
                await db.commit()

            logger.info(f"Created snapshot {snapshot_id} for container '{container_name}'")
            return MetricSnapshot(snapshot_id, container_name, metrics, timestamp)

        except aiosqlite.Error as e:
            logger.error(f"Failed to create snapshot: {e}")
            raise

    async def get_snapshot(self, snapshot_id: str) -> Optional[MetricSnapshot]:
        """
        Retrieve a specific snapshot by ID.

        Args:
            snapshot_id: Unique identifier of the snapshot

        Returns:
            MetricSnapshot object if found, None otherwise

        Raises:
            aiosqlite.Error: If database query fails
        """
        try:
            async with aiosqlite.connect(self.db_path) as db:
                db.row_factory = aiosqlite.Row
                async with db.execute(
                    """
                    SELECT id, container_name, metrics_json, timestamp
                    FROM metric_snapshots
                    WHERE id = ?
                    """,
                    (snapshot_id,)
                ) as cursor:
                    row = await cursor.fetchone()

                    if row:
                        metrics_dict = json.loads(row['metrics_json'])
                        metrics = self._dict_to_metrics(metrics_dict)
                        return MetricSnapshot(
                            row['id'],
                            row['container_name'],
                            metrics,
                            row['timestamp']
                        )
                    return None

        except aiosqlite.Error as e:
            logger.error(f"Failed to retrieve snapshot {snapshot_id}: {e}")
            raise
        except (json.JSONDecodeError, KeyError) as e:
            logger.error(f"Failed to parse snapshot {snapshot_id}: {e}")
            return None

    async def list_snapshots(
        self,
        container_name: str,
        hours: int = 1,
        limit: int = 100
    ) -> List[Dict[str, Any]]:
        """
        List recent snapshots for a specific container.

        Returns preview data (key metrics only) for efficient listing.

        Args:
            container_name: Name of the container to filter by
            hours: Number of hours to look back (default: 1)
            limit: Maximum number of snapshots to return (default: 100)

        Returns:
            List of snapshot preview dictionaries sorted by timestamp (newest first)

        Raises:
            aiosqlite.Error: If database query fails
        """
        cutoff_time = datetime.utcnow() - timedelta(hours=hours)
        cutoff_timestamp = cutoff_time.isoformat()

        try:
            async with aiosqlite.connect(self.db_path) as db:
                db.row_factory = aiosqlite.Row
                async with db.execute(
                    """
                    SELECT id, container_name, metrics_json, timestamp
                    FROM metric_snapshots
                    WHERE container_name = ? AND timestamp >= ?
                    ORDER BY timestamp DESC
                    LIMIT ?
                    """,
                    (container_name, cutoff_timestamp, limit)
                ) as cursor:
                    rows = await cursor.fetchall()

                    snapshots = []
                    for row in rows:
                        try:
                            metrics_dict = json.loads(row['metrics_json'])
                            metrics = self._dict_to_metrics(metrics_dict)
                            snapshot = MetricSnapshot(
                                row['id'],
                                row['container_name'],
                                metrics,
                                row['timestamp']
                            )
                            snapshots.append(snapshot.preview_dict())
                        except (json.JSONDecodeError, KeyError) as e:
                            logger.warning(f"Skipping invalid snapshot {row['id']}: {e}")
                            continue

                    logger.debug(
                        f"Retrieved {len(snapshots)} snapshots for '{container_name}' "
                        f"(last {hours}h)"
                    )
                    return snapshots

        except aiosqlite.Error as e:
            logger.error(f"Failed to list snapshots for '{container_name}': {e}")
            raise

    async def delete_snapshot(self, snapshot_id: str) -> bool:
        """
        Delete a specific snapshot by ID.

        Args:
            snapshot_id: Unique identifier of the snapshot to delete

        Returns:
            True if snapshot was deleted, False if not found

        Raises:
            aiosqlite.Error: If database operation fails
        """
        try:
            async with aiosqlite.connect(self.db_path) as db:
                cursor = await db.execute(
                    "DELETE FROM metric_snapshots WHERE id = ?",
                    (snapshot_id,)
                )
                await db.commit()
                deleted = cursor.rowcount > 0

                if deleted:
                    logger.info(f"Deleted snapshot {snapshot_id}")
                else:
                    logger.warning(f"Snapshot {snapshot_id} not found for deletion")

                return deleted

        except aiosqlite.Error as e:
            logger.error(f"Failed to delete snapshot {snapshot_id}: {e}")
            raise

    async def delete_old_snapshots(self, hours: int = None) -> int:
        """
        Delete snapshots older than the specified retention period.

        Args:
            hours: Number of hours to retain (uses instance default if None)

        Returns:
            Number of snapshots deleted

        Raises:
            aiosqlite.Error: If database operation fails
        """
        retention = hours if hours is not None else self.retention_hours
        cutoff_time = datetime.utcnow() - timedelta(hours=retention)
        cutoff_timestamp = cutoff_time.isoformat()

        try:
            async with aiosqlite.connect(self.db_path) as db:
                cursor = await db.execute(
                    "DELETE FROM metric_snapshots WHERE timestamp < ?",
                    (cutoff_timestamp,)
                )
                await db.commit()
                deleted_count = cursor.rowcount

                if deleted_count > 0:
                    logger.info(
                        f"Cleanup: Deleted {deleted_count} snapshots older than {retention}h "
                        f"(before {cutoff_timestamp})"
                    )
                else:
                    logger.debug(f"Cleanup: No snapshots older than {retention}h to delete")

                return deleted_count

        except aiosqlite.Error as e:
            logger.error(f"Failed to delete old snapshots: {e}")
            raise

    async def start_cleanup_task(self, interval_minutes: int = 5):
        """
        Start the background cleanup task.

        Runs periodic cleanup of expired snapshots based on retention policy.

        Args:
            interval_minutes: Minutes between cleanup runs (default: 5)

        Raises:
            RuntimeError: If cleanup task is already running
        """
        if self.cleanup_running:
            raise RuntimeError("Cleanup task is already running")

        self.cleanup_running = True
        self._cleanup_task = asyncio.create_task(
            self._cleanup_loop(interval_minutes)
        )
        logger.info(f"Started snapshot cleanup task (interval={interval_minutes}m)")

    async def stop_cleanup_task(self):
        """
        Stop the background cleanup task gracefully.

        Waits for current cleanup operation to complete before stopping.
        """
        if not self.cleanup_running:
            logger.warning("Cleanup task is not running")
            return

        self.cleanup_running = False

        if self._cleanup_task:
            self._cleanup_task.cancel()
            try:
                await self._cleanup_task
            except asyncio.CancelledError:
                pass

        logger.info("Stopped snapshot cleanup task")

    async def _cleanup_loop(self, interval_minutes: int):
        """
        Background task loop for periodic snapshot cleanup.

        Args:
            interval_minutes: Minutes between cleanup runs
        """
        logger.info(f"Cleanup loop started (retention={self.retention_hours}h)")

        while self.cleanup_running:
            try:
                # Perform cleanup
                deleted_count = await self.delete_old_snapshots()

                # Wait for next cleanup interval
                await asyncio.sleep(interval_minutes * 60)

            except asyncio.CancelledError:
                logger.info("Cleanup loop cancelled")
                break
            except Exception as e:
                logger.error(f"Error in cleanup loop: {e}")
                # Continue running even after errors
                await asyncio.sleep(interval_minutes * 60)

    def _dict_to_metrics(self, metrics_dict: Dict[str, Any]) -> PrometheusMetrics:
        """
        Convert a dictionary back to a PrometheusMetrics object.

        Args:
            metrics_dict: Dictionary with metric key-value pairs

        Returns:
            PrometheusMetrics object populated with values from dictionary
        """
        metrics = PrometheusMetrics()

        # Standard metrics
        metrics.gpu_percent = metrics_dict.get("gpu_percent")
        metrics.cpu_percent = metrics_dict.get("cpu_percent")
        metrics.memory_percent = metrics_dict.get("memory_percent")
        metrics.memory_bytes = metrics_dict.get("memory_bytes")
        metrics.power_watts = metrics_dict.get("power_watts")
        metrics.request_count = metrics_dict.get("request_count")
        metrics.uptime_seconds = metrics_dict.get("uptime_seconds")

        # Renny application metrics
        metrics.session_total = metrics_dict.get("session_total")
        metrics.session_started = metrics_dict.get("session_started")
        metrics.session_successful = metrics_dict.get("session_successful")
        metrics.session_failed = metrics_dict.get("session_failed")
        metrics.frames_rendered = metrics_dict.get("frames_rendered")

        # Response times
        metrics.response_time_p50 = metrics_dict.get("response_time_p50")
        metrics.response_time_p90 = metrics_dict.get("response_time_p90")
        metrics.response_time_p99 = metrics_dict.get("response_time_p99")
        metrics.nlp_response_time_p50 = metrics_dict.get("nlp_response_time_p50")
        metrics.a2f_response_time_p50 = metrics_dict.get("a2f_response_time_p50")

        # Frame timings
        metrics.gpu_frame_time_avg = metrics_dict.get("gpu_frame_time_avg")
        metrics.render_frame_time_avg = metrics_dict.get("render_frame_time_avg")
        metrics.game_frame_time_avg = metrics_dict.get("game_frame_time_avg")
        metrics.frame_time_avg = metrics_dict.get("frame_time_avg")

        return metrics


# Singleton instance
_snapshot_manager: Optional[SnapshotManager] = None


def get_snapshot_manager(retention_hours: int = None) -> SnapshotManager:
    """
    Get or create singleton SnapshotManager instance.

    Args:
        retention_hours: Hours to retain snapshots (uses env var or default if None)

    Returns:
        SnapshotManager instance
    """
    global _snapshot_manager

    if _snapshot_manager is None:
        # Read retention from environment or use default
        if retention_hours is None:
            retention_hours = int(os.getenv("METRICS_SNAPSHOT_RETENTION_HOURS", "1"))

        _snapshot_manager = SnapshotManager(retention_hours=retention_hours)

    return _snapshot_manager


async def close_snapshot_manager():
    """
    Stop the snapshot manager and cleanup background tasks.

    Should be called during application shutdown.
    """
    global _snapshot_manager
    if _snapshot_manager is not None:
        await _snapshot_manager.stop_cleanup_task()
        _snapshot_manager = None
        logger.info("SnapshotManager closed")
