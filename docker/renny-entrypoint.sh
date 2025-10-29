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

# Start Renny application using the original container entrypoint
# This ensures proper initialization (PulseAudio cleanup, etc.)
echo "[$(date)] Starting Renny application via original entrypoint..."
exec /opt/renny/entrypoint.sh "$@"
