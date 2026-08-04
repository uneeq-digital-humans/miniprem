#!/bin/bash
##
# MiniPrem Renny Entrypoint Script
#
# Starts both the telemetry client (background) and Renny application (foreground)
##

set -e

echo "[$(date)] Starting MiniPrem Renny..."

# Start telemetry client in background (bash version - no Python needed)
# Check if telemetry is disabled via MINIPREM_TELEMETRY_DISABLED env var (0=enabled, 1=disabled)
if [ "${MINIPREM_TELEMETRY_DISABLED:-0}" = "0" ]; then
    echo "[$(date)] Starting telemetry client..."
    /opt/renny/telemetry-client.sh &
    TELEMETRY_PID=$!
    echo "[$(date)] Telemetry client started (PID: $TELEMETRY_PID)"
else
    echo "[$(date)] Telemetry disabled by MINIPREM_TELEMETRY_DISABLED flag"
fi

# Cross-process GPU submission serialization. Only worth enabling with 2+ Rennys
# sharing one GPU; unset RENNY_GPU_LOCK_PATH leaves the CVar at its default 0.
if [ -n "${RENNY_GPU_LOCK_PATH:-}" ]; then
    echo "[$(date)] GPU submission serialization on (lock dir: ${RENNY_GPU_LOCK_PATH})"
    set -- "$@" "-ExecCmds=r.Renny.GpuSerialization.Enabled 2"
fi

# Start Renny application using the original container entrypoint
# This ensures proper initialization (PulseAudio cleanup, etc.)
echo "[$(date)] Starting Renny application via original entrypoint..."
exec /opt/renny/entrypoint.sh "$@"
