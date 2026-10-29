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

# No RENNY_GPU_LOCK_PATH leaves the CVar at its default 0 (off).
if [ -n "${RENNY_GPU_LOCK_PATH:-}" ]; then
    echo "[$(date)] GPU submission serialization on (lock dir: ${RENNY_GPU_LOCK_PATH})"
    set -- "$@" "-ExecCmds=r.Renny.GpuSerialization.Enabled 2"
fi

# Extra engine arguments from docker-compose.env, e.g. a console variable override:
# RENNY_EXTRA_ARGS=-ini:Engine:[ConsoleVariables]:r.Renny.GpuSerialization.SuspendDuringSessionStart=1
if [ -n "${RENNY_EXTRA_ARGS:-}" ]; then
    echo "[$(date)] Extra Renny arguments: ${RENNY_EXTRA_ARGS}"
    # shellcheck disable=SC2086 # intentional word splitting into separate arguments
    set -- "$@" ${RENNY_EXTRA_ARGS}
fi

# Start Renny application using the original container entrypoint
# This ensures proper initialization (PulseAudio cleanup, etc.)
echo "[$(date)] Starting Renny application via original entrypoint..."
exec /opt/renny/entrypoint.sh "$@"
