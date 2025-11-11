#!/bin/bash

# NOT TO BE RUN DIRECTLY, PLEASE RUN THE MAIN SCRIPT CALLED "install_miniprem.sh"

# This module contains interactive prompt functions for gathering user input during installation

# Function to prompt user for installation type (default vs full)
prompt_for_install_type() {
    INSTALL_TYPE=""
    echo "Select installation type:"
    echo "1) Default Install (Renny with internal speech processing only)"
    echo "2) Full Install (All services: Renny with internal speech, Flowise, vLLM, Grafana, Prometheus, RIME, Whisper etc.)"
    read -p "Enter choice [1-2]: " install_choice
    if [[ "$install_choice" == "1" ]]; then
        INSTALL_TYPE="default"
        echo "default" > "$PROJECT_ROOT/.miniprem_install_type" || {
            warning "Failed to write installation type marker, but continuing..."
        }
        mark_installation_marker_created
    elif [[ "$install_choice" == "2" ]]; then
        INSTALL_TYPE="full"
        echo "full" > "$PROJECT_ROOT/.miniprem_install_type" || {
            warning "Failed to write installation type marker, but continuing..."
        }
        mark_installation_marker_created
    else
        echo "Invalid choice, exiting."
        exit 1
    fi

    # Verify the variable is set before returning
    if [ -z "$INSTALL_TYPE" ]; then
        fatal "Failed to set installation type"
    fi
}

# Function to prompt for deployment target
prompt_deployment_target() {
    # Check if deployment target already set (e.g., via CLI argument)
    if [ -n "$DEPLOYMENT_TARGET" ]; then
        info "$CHECKMARK Using deployment target from command line: $DEPLOYMENT_TARGET"
        return 0
    fi

    # Check if deployment target already persisted from previous installation
    if [ -f "$PROJECT_ROOT/.miniprem_deployment_target" ]; then
        DEPLOYMENT_TARGET=$(cat "$PROJECT_ROOT/.miniprem_deployment_target" 2>/dev/null | tr -d '[:space:]')
        if [ -n "$DEPLOYMENT_TARGET" ]; then
            info "$CHECKMARK Using previously configured deployment target: $DEPLOYMENT_TARGET"
            return 0
        fi
    fi

    log_section "Deployment Target Selection"

    DEPLOYMENT_TARGET=""
    local max_retries=3
    local attempts=0

    while [ $attempts -lt $max_retries ]; do
        echo ""
        echo "Select deployment target:"
        echo "1) Dedicated Hardware (PC/Server) - Optimized for local/on-premise installations"
        echo "2) Cloud Platform (AWS/Azure/GCP) - Optimized for cloud infrastructure"
        read -p "Enter choice [1-2]: " deployment_choice

        case "$deployment_choice" in
            1)
                DEPLOYMENT_TARGET="hardware"
                info "$CHECKMARK Selected: Dedicated Hardware deployment"
                ;;
            2)
                DEPLOYMENT_TARGET="cloud"
                info "$CHECKMARK Selected: Cloud Platform deployment"
                ;;
            *)
                attempts=$((attempts + 1))
                if [ $attempts -lt $max_retries ]; then
                    warning "Invalid choice. Please enter 1 or 2. (Attempt $attempts/$max_retries)"
                    continue
                else
                    fatal "Invalid choice after $max_retries attempts. Exiting."
                fi
                ;;
        esac

        # Persist the choice for future installations
        if echo "$DEPLOYMENT_TARGET" > "$PROJECT_ROOT/.miniprem_deployment_target" 2>/dev/null; then
            success "$CHECKMARK Deployment target saved for future installations"
        else
            warning "Failed to save deployment target, but continuing..."
        fi
        break
    done

    # Final validation
    if [ -z "$DEPLOYMENT_TARGET" ]; then
        fatal "Failed to set deployment target"
    fi
}

# Function to prompt user for telemetry consent and send initial notification
prompt_for_telemetry_consent() {
    log_section "MiniPrem Telemetry Notice"

    # Display consent dialog
    cat << 'EOF'
┌─────────────────────────────────────────────────────────────────┐
│                    MiniPrem Telemetry Notice                    │
├─────────────────────────────────────────────────────────────────┤
│ This installation sends anonymous usage data to UneeQ:          │
│                                                                 │
│ ✓ Installation notification (one-time)                          │
│ ✓ Heartbeat every 15 minutes to monitor uptime                  │
│                                                                 │
│ Data collected (NO personally identifiable information):        │
│   • Anonymous installation ID (generated locally)               │
│   • GPU hardware identifier (one-way SHA-256 hash)              │
│   • MiniPrem version and deployment type                        │
│   • System uptime and health status                             │
│                                                                 │
│ We DO NOT collect:                                              │
│   ✗ IP addresses, hostnames, or network identifiers             │
│   ✗ UneeQ credentials, API keys, or tokens                      │
│   ✗ Conversation data or chat history                           │
│   ✗ Any content processed by Renny                              │
│   ✗ Customer information                                        │
│                                                                 │
│ Privacy: See docs/TELEMETRY.md for full details                 │
└─────────────────────────────────────────────────────────────────┘
EOF

    # Prompt for consent
    echo ""
    read -p "Do you consent to anonymous telemetry? [Y/n] " telemetry_consent

    # Default to yes if user just presses enter
    if [[ -z "$telemetry_consent" ]]; then
        telemetry_consent="y"
    fi

    # Handle response
    if [[ "$telemetry_consent" =~ ^[Yy]$ ]]; then
        # Initialize installation ID variable
        INSTALLATION_ID=""

        # Check if installation ID already exists (reuse for reinstalls/upgrades)
        if [ -f "/tmp/miniprem_installation_id" ] && [ -s "/tmp/miniprem_installation_id" ]; then
            INSTALLATION_ID=$(cat /tmp/miniprem_installation_id 2>/dev/null | tr -d '[:space:]')
            if [ -n "$INSTALLATION_ID" ]; then
                success "$CHECKMARK Reusing existing installation ID: ${INSTALLATION_ID:0:8}..."
            else
                # File exists but is invalid, generate new one
                INSTALLATION_ID=""
            fi
        fi

        # Generate new installation ID if none exists
        if [ -z "$INSTALLATION_ID" ]; then
            # Remove if it exists as a directory (Docker may have created it)
            if [ -d "/tmp/miniprem_installation_id" ]; then
                sudo rm -rf /tmp/miniprem_installation_id 2>/dev/null || rm -rf /tmp/miniprem_installation_id
            fi

            # Generate using uuidgen (POSIX-compatible)
            if command -v uuidgen >/dev/null 2>&1; then
                INSTALLATION_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
            else
                # Fallback: use random data if uuidgen not available
                INSTALLATION_ID=$(cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 32 | head -n 1)
                INSTALLATION_ID="${INSTALLATION_ID:0:8}-${INSTALLATION_ID:8:4}-${INSTALLATION_ID:12:4}-${INSTALLATION_ID:16:4}-${INSTALLATION_ID:20:12}"
            fi

            # Save installation ID to /tmp (will be mounted into container)
            # Always use sudo tee to avoid permission errors
            echo "$INSTALLATION_ID" | sudo tee /tmp/miniprem_installation_id > /dev/null
            sudo chmod 644 /tmp/miniprem_installation_id

            success "$CHECKMARK Installation ID generated: ${INSTALLATION_ID:0:8}..."
        fi

        # Send initial installation event via curl (best-effort, non-blocking)
        info "Sending installation notification..."

        # Build JSON payload
        local payload=$(cat <<PAYLOAD_EOF
{
  "installation_id": "$INSTALLATION_ID",
  "event_type": "installation",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "version": "2.1.0",
  "platform": "docker",
  "os": "$(uname -s | tr '[:upper:]' '[:lower:]')",
  "platform_arch": "$(uname -m)",
  "status": "installing"
}
PAYLOAD_EOF
)

        # Send with curl (5-second timeout, silent failure)
        if curl -X POST -H "Content-Type: application/json" \
                -d "$payload" \
                --max-time 5 \
                --silent \
                --show-error \
                --fail \
                https://renny.services.uneeq.io/telemetry >/dev/null 2>&1; then
            success "$CHECKMARK Installation notification sent"
        else
            info "Installation notification will be sent when container starts"
        fi

    else
        warning "Telemetry disabled - you can re-enable later by removing MINIPREM_TELEMETRY_DISABLED from docker/docker-compose.env"

        # Set telemetry disabled flag in env file
        update_env_variable "MINIPREM_TELEMETRY_DISABLED" "1"

        # Don't create installation ID file
        sudo rm -f /tmp/miniprem_installation_id 2>/dev/null || rm -f /tmp/miniprem_installation_id 2>/dev/null || true

        info "Telemetry disabled - continuing with installation"
    fi

    echo ""
}
