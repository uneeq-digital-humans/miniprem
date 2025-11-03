"""
GPU monitoring service using nvidia-smi.

Provides GPU statistics including utilization, memory, power, and temperature.
Gracefully handles cases where nvidia-smi is not available or fails.
"""

import subprocess
import logging
from typing import List, Optional

logger = logging.getLogger(__name__)


class GpuStats:
    """Container for GPU statistics from nvidia-smi."""

    def __init__(
        self,
        index: int,
        name: str,
        temperature_celsius: Optional[float],
        utilization_percent: Optional[float],
        memory_used_mb: Optional[int],
        memory_total_mb: Optional[int],
        power_watts: Optional[float],
        clock_graphics_mhz: Optional[int],
        clock_memory_mhz: Optional[int],
        fan_speed_percent: Optional[int],
    ):
        self.index = index
        self.name = name
        self.temperature_celsius = temperature_celsius
        self.utilization_percent = utilization_percent
        self.memory_used_mb = memory_used_mb
        self.memory_total_mb = memory_total_mb
        self.power_watts = power_watts
        self.clock_graphics_mhz = clock_graphics_mhz
        self.clock_memory_mhz = clock_memory_mhz
        self.fan_speed_percent = fan_speed_percent


def detect_and_parse_gpus() -> List[GpuStats]:
    """
    Detect and parse GPU statistics using nvidia-smi.

    Returns:
        List of GpuStats objects, empty list if nvidia-smi not available or fails.
    """
    try:
        # Query nvidia-smi for comprehensive GPU stats
        result = subprocess.run(
            [
                'nvidia-smi',
                '--query-gpu=index,name,temperature.gpu,utilization.gpu,memory.used,memory.total,power.draw,clocks.current.graphics,clocks.current.memory,fan.speed',
                '--format=csv,noheader,nounits'
            ],
            capture_output=True,
            text=True,
            timeout=5,
            check=False
        )

        if result.returncode != 0:
            logger.warning(f"nvidia-smi failed with return code {result.returncode}: {result.stderr}")
            return []

        gpus = []
        for line in result.stdout.strip().split('\n'):
            if not line.strip():
                continue

            try:
                parts = [p.strip() for p in line.split(',')]
                if len(parts) < 10:
                    logger.warning(f"Unexpected nvidia-smi output format: {line}")
                    continue

                gpu = GpuStats(
                    index=int(parts[0]),
                    name=parts[1],
                    temperature_celsius=_safe_float(parts[2]),
                    utilization_percent=_safe_float(parts[3]),
                    memory_used_mb=_safe_int(parts[4]),
                    memory_total_mb=_safe_int(parts[5]),
                    power_watts=_safe_float(parts[6]),
                    clock_graphics_mhz=_safe_int(parts[7]),
                    clock_memory_mhz=_safe_int(parts[8]),
                    fan_speed_percent=_safe_int(parts[9]),
                )
                gpus.append(gpu)

            except (ValueError, IndexError) as e:
                logger.warning(f"Failed to parse GPU stats from line '{line}': {e}")
                continue

        if gpus:
            logger.debug(f"Successfully detected {len(gpus)} GPU(s)")

        return gpus

    except FileNotFoundError:
        logger.info("nvidia-smi not found - GPU monitoring unavailable")
        return []
    except subprocess.TimeoutExpired:
        logger.warning("nvidia-smi timed out after 5 seconds")
        return []
    except Exception as e:
        logger.error(f"Unexpected error detecting GPUs: {e}", exc_info=True)
        return []


def _safe_float(value: str) -> Optional[float]:
    """Safely convert string to float, return None if invalid."""
    try:
        if value.lower() in ['n/a', '[n/a]', '']:
            return None
        return float(value)
    except (ValueError, AttributeError):
        return None


def _safe_int(value: str) -> Optional[int]:
    """Safely convert string to int, return None if invalid."""
    try:
        if value.lower() in ['n/a', '[n/a]', '']:
            return None
        return int(float(value))  # Handle "1234.0" format
    except (ValueError, AttributeError):
        return None
