#!/bin/bash

# NOT TO BE RUN DIRECTLY, PLEASE RUN THE MAIN SCRIPT CALLED "install_miniprem.sh"

# This module contains interactive prompt functions for gathering user input during installation

# Function to prompt user for installation type (default vs full)
prompt_for_install_type() {
    # Honor a pre-set value (from --seed or CLI) if present
    if [ -n "${INSTALL_TYPE:-}" ]; then
        seed_validate_choice INSTALL_TYPE "default|full"
        echo "$INSTALL_TYPE" > "$PROJECT_ROOT/.miniprem_install_type" || \
            warning "Failed to write installation type marker, but continuing..."
        mark_installation_marker_created
        info "Using installation type: $INSTALL_TYPE"
        return 0
    fi

    if seed_is_non_interactive; then
        seed_record_missing "MINIPREM_SEED_INSTALL_TYPE" "default|full"
        return 0
    fi

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

# Function to prompt user whether to install MiniPrem as a systemd service
# (auto-start at boot regardless of which user logs in). Sets INSTALL_AS_SERVICE
# to "yes" or "no". Defaults to "no" on empty/invalid input.
prompt_for_autostart() {
    # Honor a pre-set value (from --seed or CLI). Default to "no" in
    # non-interactive mode if unspecified — autostart is opt-in.
    if [ -n "${INSTALL_AS_SERVICE:-}" ]; then
        seed_validate_choice INSTALL_AS_SERVICE "yes|no"
        info "Using install-as-service: $INSTALL_AS_SERVICE"
        return 0
    fi
    if seed_is_non_interactive; then
        INSTALL_AS_SERVICE="no"
        info "Install-as-service defaulted to 'no' (set MINIPREM_SEED_INSTALL_AS_SERVICE=yes to enable)"
        return 0
    fi

    INSTALL_AS_SERVICE="no"
    echo ""
    echo "Install MiniPrem as a systemd service?"
    echo "  - Auto-starts at boot, even before any user logs in"
    echo "  - Requires root (this installer is already running with sudo)"
    echo "  - Disable later with: sudo systemctl disable miniprem.service"
    read -p "Install as service? [y/N] " autostart_choice
    case "${autostart_choice}" in
        y|Y|yes|YES|Yes)
            INSTALL_AS_SERVICE="yes"
            ;;
        *)
            INSTALL_AS_SERVICE="no"
            ;;
    esac
}

# Function to prompt for deployment target
prompt_deployment_target() {
    # Check if deployment target already set (e.g., via CLI argument or seed)
    if [ -n "${DEPLOYMENT_TARGET:-}" ]; then
        seed_validate_choice DEPLOYMENT_TARGET "hardware|cloud"
        info "$CHECKMARK Using deployment target: $DEPLOYMENT_TARGET"
        echo "$DEPLOYMENT_TARGET" > "$PROJECT_ROOT/.miniprem_deployment_target" 2>/dev/null || true
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

    if seed_is_non_interactive; then
        seed_record_missing "MINIPREM_SEED_DEPLOYMENT_TARGET" "hardware|cloud"
        return 0
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

# Function to prompt for UneeQ platform region (US or EU)
prompt_for_region() {
    # Check CLI argument first
    if [ -n "${UNEEQ_REGION:-}" ]; then
        info "Using region from CLI argument: $UNEEQ_REGION"
        echo "$UNEEQ_REGION" > "$PROJECT_ROOT/.miniprem_region"
        export UNEEQ_REGION
        return
    fi

    # Check persisted value
    if [ -f "$PROJECT_ROOT/.miniprem_region" ]; then
        UNEEQ_REGION=$(cat "$PROJECT_ROOT/.miniprem_region")
        info "Using previously selected region: $UNEEQ_REGION"
        export UNEEQ_REGION
        return
    fi

    # Interactive prompt
    echo ""
    echo "Select UneeQ platform region:"
    echo "  1) US Enterprise (default)"
    echo "  2) EU Enterprise"
    echo ""
    read -r -p "Enter choice [1-2]: " choice

    case "$choice" in
        2)
            UNEEQ_REGION="eu"
            ;;
        *)
            UNEEQ_REGION="us"
            ;;
    esac

    echo "$UNEEQ_REGION" > "$PROJECT_ROOT/.miniprem_region"
    export UNEEQ_REGION
    info "Selected region: $UNEEQ_REGION"
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

    # Prompt for consent (or honor a pre-set TELEMETRY_CONSENT from --seed/CLI)
    echo ""
    local telemetry_consent
    if [ -n "${TELEMETRY_CONSENT:-}" ]; then
        seed_validate_choice TELEMETRY_CONSENT "yes|no"
        # Normalize to single-char form expected by the downstream regex below.
        if [ "$TELEMETRY_CONSENT" = "yes" ]; then
            telemetry_consent="y"
        else
            telemetry_consent="n"
        fi
        info "Using telemetry consent from seed/CLI: $TELEMETRY_CONSENT"
    elif seed_is_non_interactive; then
        # No silent opt-in for telemetry under unattended installs.
        seed_record_missing "MINIPREM_SEED_TELEMETRY_CONSENT" "yes|no"
        echo ""
        return 0
    else
        read -p "Do you consent to anonymous telemetry? [Y/n] " telemetry_consent
        # Default to yes if user just presses enter
        if [[ -z "$telemetry_consent" ]]; then
            telemetry_consent="y"
        fi
    fi

    # Handle response
    if [[ "$telemetry_consent" =~ ^[Yy]$ ]]; then
        # Initialize installation ID variable
        INSTALLATION_ID=""

        # Persistent storage location (survives reboots and reinstalls)
        local MINIPREM_DATA_DIR="/var/lib/miniprem"
        local INSTALLATION_ID_FILE="$MINIPREM_DATA_DIR/installation_id"

        # Create persistent data directory if it doesn't exist
        if [ ! -d "$MINIPREM_DATA_DIR" ]; then
            sudo mkdir -p "$MINIPREM_DATA_DIR" 2>/dev/null || mkdir -p "$MINIPREM_DATA_DIR"
            sudo chmod 755 "$MINIPREM_DATA_DIR" 2>/dev/null || chmod 755 "$MINIPREM_DATA_DIR"
        fi

        # Check if installation ID already exists (reuse for reinstalls/upgrades)
        if [ -f "$INSTALLATION_ID_FILE" ] && [ -s "$INSTALLATION_ID_FILE" ]; then
            INSTALLATION_ID=$(cat "$INSTALLATION_ID_FILE" 2>/dev/null | tr -d '[:space:]')
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
            if [ -d "$INSTALLATION_ID_FILE" ]; then
                sudo rm -rf "$INSTALLATION_ID_FILE" 2>/dev/null || rm -rf "$INSTALLATION_ID_FILE"
            fi

            # Generate using uuidgen (POSIX-compatible)
            if command -v uuidgen >/dev/null 2>&1; then
                INSTALLATION_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
            else
                # Fallback: use random data if uuidgen not available
                INSTALLATION_ID=$(cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 32 | head -n 1)
                INSTALLATION_ID="${INSTALLATION_ID:0:8}-${INSTALLATION_ID:8:4}-${INSTALLATION_ID:12:4}-${INSTALLATION_ID:16:4}-${INSTALLATION_ID:20:12}"
            fi

            # Save installation ID to persistent location (survives reboots)
            echo "$INSTALLATION_ID" | sudo tee "$INSTALLATION_ID_FILE" > /dev/null
            sudo chmod 644 "$INSTALLATION_ID_FILE"

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
        sudo rm -f /var/lib/miniprem/installation_id 2>/dev/null || rm -f /var/lib/miniprem/installation_id 2>/dev/null || true

        info "Telemetry disabled - continuing with installation"
    fi

    echo ""
}
