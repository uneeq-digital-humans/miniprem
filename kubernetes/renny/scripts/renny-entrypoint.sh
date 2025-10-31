#!/bin/bash
##
# MiniPrem Renny Entrypoint Script
#
# Starts both the telemetry client (background) and Renny application (foreground)
##

set -e

echo "[$(date)] Starting MiniPrem Renny with telemetry..."

# Start telemetry client in background (bash version - no Python needed)
echo "[$(date)] Starting telemetry client..."
/opt/renny/telemetry-client.sh &
TELEMETRY_PID=$!
echo "[$(date)] Telemetry client started (PID: $TELEMETRY_PID)"

# Start Renny application (foreground)
# The Renny executable is at /opt/renny/Renny/Binaries/Linux/Renny
# Arguments passed to this script ($@) are Unreal Engine level/map arguments
echo "[$(date)] Starting Renny application..."
exec /opt/renny/Renny/Binaries/Linux/Renny "$@"
