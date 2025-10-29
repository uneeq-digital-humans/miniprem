#!/bin/bash
##
# MiniPrem Renny Telemetry Client (Bash version)
#
# Sends installation events and periodic heartbeats to the telemetry backend.
# Pure bash implementation - no Python dependencies.
##

set -euo pipefail

# Configuration from environment variables
TELEMETRY_BACKEND_URL="${TELEMETRY_BACKEND_URL:-https://renny.services.uneeq.io}"
HEARTBEAT_INTERVAL_SECONDS="${HEARTBEAT_INTERVAL_SECONDS:-900}"
PLATFORM="${PLATFORM:-docker-ubuntu}"
DEPLOYMENT_ID="${DEPLOYMENT_ID:-}"
VERSION="${VERSION:-renny-0.713}"  # Default version if not provided

# Installation ID persistence
INSTALLATION_ID_FILE="${INSTALLATION_ID_FILE:-/tmp/miniprem_installation_id}"

# Logging function (output to stderr to avoid polluting function returns)
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >&2
}

log "INFO: Telemetry endpoint: $TELEMETRY_BACKEND_URL"
log "INFO: Heartbeat interval: ${HEARTBEAT_INTERVAL_SECONDS}s"
log "INFO: Platform: $PLATFORM"

# Get or generate installation ID
get_installation_id() {
    if [ -f "$INSTALLATION_ID_FILE" ] && [ -s "$INSTALLATION_ID_FILE" ]; then
        cat "$INSTALLATION_ID_FILE"
        log "INFO: Loaded existing installation ID"
    else
        local timestamp=$(date +%s)
        # Use od instead of xxd for better portability
        local random=$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')
        local installation_id="${PLATFORM}-${timestamp}-${random}"
        echo "$installation_id" > "$INSTALLATION_ID_FILE"
        log "INFO: Generated new installation ID: $installation_id"
        echo "$installation_id"
    fi
}

# Get machine ID from Kubernetes node name, GPU UUID, or hostname fallback
get_machine_id() {
    # Priority 1: For Kubernetes, use NODE_NAME (maps to physical GPU node)
    # This ensures all pods on the same node report the same machine_id
    if [ -n "${NODE_NAME:-}" ]; then
        echo -n "$NODE_NAME" | sha256sum | awk '{print $1}'
        log "INFO: Machine ID from Kubernetes node: $NODE_NAME"
        return
    fi

    # Priority 2: Try to get GPU UUID via nvidia-smi (Docker deployments)
    local gpu_uuid=""
    if command -v nvidia-smi &> /dev/null; then
        gpu_uuid=$(nvidia-smi --query-gpu=uuid --format=csv,noheader 2>/dev/null | head -n1 || true)
    fi

    if [ -n "$gpu_uuid" ]; then
        # Hash the GPU UUID for privacy (SHA-256)
        echo -n "$gpu_uuid" | sha256sum | awk '{print $1}'
        log "INFO: Machine ID from GPU UUID"
        return
    fi

    # Priority 3: Fallback to hostname hash (Docker without GPU access)
    local hostname=$(hostname)
    echo -n "$hostname" | sha256sum | awk '{print $1}'
    log "WARN: Machine ID from hostname (GPU/NODE_NAME not available)"
}

# Get container/pod ID
get_instance_name() {
    # Kubernetes pod name takes priority
    if [ -n "${POD_NAME:-}" ]; then
        echo "$POD_NAME"
        return
    fi

    # Try to get Docker container ID from cgroup
    if [ -f /proc/self/cgroup ]; then
        local container_id=$(grep 'docker' /proc/self/cgroup | tail -n1 | sed 's/^.*\///' | cut -c1-12)
        if [ -n "$container_id" ]; then
            echo "$container_id"
            return
        fi
    fi

    # Fallback to hostname
    hostname
}

# Get instance type
get_instance_type() {
    if [ -n "${POD_NAME:-}" ]; then
        echo "kubernetes-pod"
    else
        echo "docker-container"
    fi
}

# Get container uptime in seconds
get_uptime() {
    if [ -f /proc/uptime ]; then
        awk '{print int($1)}' /proc/uptime
    else
        echo "0"
    fi
}

# Send telemetry event
send_event() {
    local event_type="$1"
    local extra_data="${2:-}"

    # Build JSON payload (single-line compact format)
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local json_payload="{\"event_type\":\"$event_type\",\"installation_id\":\"$INSTALLATION_ID\",\"machine_id\":\"$MACHINE_ID\",\"timestamp\":\"$timestamp\",\"version\":\"$VERSION\",\"platform\":\"$PLATFORM\",\"instance_name\":\"$INSTANCE_NAME\",\"instance_type\":\"$INSTANCE_TYPE\""

    # Add deployment_id if provided
    if [ -n "$DEPLOYMENT_ID" ]; then
        json_payload="$json_payload,\"deployment_id\":\"$DEPLOYMENT_ID\""
    fi

    # Add node_name if running in Kubernetes
    if [ -n "${NODE_NAME:-}" ]; then
        json_payload="$json_payload,\"node_name\":\"$NODE_NAME\""
    fi

    # Add extra data if provided
    if [ -n "$extra_data" ]; then
        json_payload="$json_payload,$extra_data"
    fi

    json_payload="$json_payload}"

    # Debug: log the JSON payload
    log "DEBUG: Sending JSON: $json_payload"

    # Send HTTP POST request
    local url="${TELEMETRY_BACKEND_URL}/telemetry/heartbeat"
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -d "$json_payload" \
        --max-time 10 \
        "$url" 2>/dev/null || echo "000")

    if [ "$http_code" = "200" ]; then
        log "INFO: $event_type sent successfully (HTTP $http_code)"
        return 0
    else
        log "ERROR: $event_type failed (HTTP $http_code)"
        return 1
    fi
}

# Initialize
INSTALLATION_ID=$(get_installation_id)
MACHINE_ID=$(get_machine_id)
INSTANCE_NAME=$(get_instance_name)
INSTANCE_TYPE=$(get_instance_type)

log "INFO: Installation ID: $INSTALLATION_ID"
log "INFO: Machine ID: ${MACHINE_ID:0:16}..."
log "INFO: Instance: $INSTANCE_NAME ($INSTANCE_TYPE)"

# Send installation event
log "INFO: Sending installation event..."
if send_event "installation" '"source":"kubernetes"'; then
    log "INFO: Installation event sent"
else
    log "WARN: Installation event failed, continuing anyway"
fi

# Send immediate first heartbeat for instant online status
log "INFO: Sending immediate first heartbeat..."
uptime=$(get_uptime)
if send_event "heartbeat" "\"status\":\"online\",\"uptime_seconds\":$uptime"; then
    log "INFO: First heartbeat sent (uptime: ${uptime}s)"
else
    log "WARN: First heartbeat failed, will retry in loop"
fi

# Shutdown flag for graceful termination
SHUTDOWN_REQUESTED=false

# Handle SIGTERM and SIGINT for clean shutdown
shutdown_handler() {
    log "INFO: Shutdown signal received, stopping heartbeat loop..."
    SHUTDOWN_REQUESTED=true
}

# Trap termination signals
trap shutdown_handler SIGTERM SIGINT

# Start heartbeat loop
log "INFO: Starting heartbeat loop (interval: ${HEARTBEAT_INTERVAL_SECONDS}s)"
log "INFO: Telemetry will stop cleanly on pod termination (SIGTERM)"

while [ "$SHUTDOWN_REQUESTED" = "false" ]; do
    sleep "$HEARTBEAT_INTERVAL_SECONDS" &
    wait $!  # Wait for sleep, but allow signal interruption

    # Check shutdown flag after sleep
    if [ "$SHUTDOWN_REQUESTED" = "true" ]; then
        log "INFO: Shutdown flag set, exiting heartbeat loop"
        break
    fi

    uptime=$(get_uptime)
    if send_event "heartbeat" "\"status\":\"online\",\"uptime_seconds\":$uptime"; then
        log "INFO: Heartbeat sent (uptime: ${uptime}s)"
    else
        log "WARN: Heartbeat failed, will retry in ${HEARTBEAT_INTERVAL_SECONDS}s"
    fi
done

log "INFO: Telemetry client stopped cleanly"
exit 0
