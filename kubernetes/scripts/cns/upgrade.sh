#!/bin/bash

################################################################################
# MiniPrem CNS Upgrade Script
#
# Full upgrade for CNS deployments - pulls latest code and Renny images.
#
# Usage:
#   ./upgrade.sh                    # Full upgrade (git pull + helm + new image)
#   ./upgrade.sh --config-only      # Just apply values file changes (no git pull)
#   ./upgrade.sh --restart          # Just restart pods (no helm upgrade)
#   ./upgrade.sh --replicas 5       # Change replica count
#
################################################################################

set -euo pipefail

# Script directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBERNETES_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
PROJECT_ROOT="$(dirname "$KUBERNETES_DIR")"
VALUES_FILE="$KUBERNETES_DIR/values/renny-values-cns.yaml"
CHART_DIR="$KUBERNETES_DIR/renny"
CNS_CONFIG_FILE="$SCRIPT_DIR/.cns_config"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

print_color() { echo -e "${1}${2}${NC}"; }
info() { print_color "$BLUE" "ℹ️  $*"; }
success() { print_color "$GREEN" "✅ $*"; }
warning() { print_color "$YELLOW" "⚠️  $*"; }
error() { print_color "$RED" "❌ $*"; }

################################################################################
# Detect kubectl/helm commands
################################################################################

if command -v microk8s &> /dev/null; then
    KUBECTL="microk8s kubectl"
    HELM="microk8s helm3"
else
    KUBECTL="kubectl"
    HELM="helm"
fi

################################################################################
# Load saved configuration
################################################################################

load_config() {
    if [[ -f "$CNS_CONFIG_FILE" ]]; then
        info "Loading saved configuration..."
        source "$CNS_CONFIG_FILE"
        return 0
    else
        warning "No saved configuration found at $CNS_CONFIG_FILE"
        warning "Credentials will need to be provided manually or will be empty."
        return 1
    fi
}

################################################################################
# Config file backup/restore (for git pull)
################################################################################

backup_config() {
    local backup_dir="/tmp/miniprem-cns-backup-$$"
    mkdir -p "$backup_dir"

    # Backup .cns_config
    if [[ -f "$CNS_CONFIG_FILE" ]]; then
        cp "$CNS_CONFIG_FILE" "$backup_dir/"
    fi

    echo "$backup_dir"
}

restore_config() {
    local backup_dir="$1"

    if [[ -f "$backup_dir/.cns_config" ]]; then
        cp "$backup_dir/.cns_config" "$CNS_CONFIG_FILE"
        success "Configuration restored"
    fi

    rm -rf "$backup_dir"
}

################################################################################
# Parse arguments
################################################################################

REPLICAS=""
RESTART_ONLY=false
CONFIG_ONLY=false
CLEAR_SECRETS=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --replicas|-r)
            REPLICAS="$2"
            shift 2
            ;;
        --restart)
            RESTART_ONLY=true
            shift
            ;;
        --config-only|--helm-only)
            CONFIG_ONLY=true
            shift
            ;;
        --clear-secrets|--clear-tts)
            CLEAR_SECRETS=true
            shift
            ;;
        --force|-f)
            FORCE=true
            shift
            ;;
        --help|-h)
            echo ""
            print_color "$BOLD" "MiniPrem CNS Upgrade"
            echo ""
            echo "Usage: $0 [options]"
            echo ""
            echo "Upgrade Modes:"
            echo "  (default)              Full upgrade: git pull + helm upgrade + new Renny image"
            echo "  --config-only          Only apply values file changes (no git pull)"
            echo "  --restart              Only restart pods (no helm upgrade)"
            echo ""
            echo "Options:"
            echo "  --replicas, -r <N>     Set number of Renny replicas"
            echo "  --clear-secrets        Clear TTS/LLM API keys (use Admin Portal config)"
            echo "  --force, -f            Skip confirmation prompts"
            echo "  --help, -h             Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                     # Full upgrade (recommended)"
            echo "  $0 --config-only       # Just apply config changes"
            echo "  $0 --replicas 5        # Scale to 5 replicas"
            echo "  $0 --restart           # Restart pods only"
            echo ""
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information."
            exit 1
            ;;
    esac
done

################################################################################
# Main
################################################################################

print_color "$BOLD" "
╔═══════════════════════════════════════════════════════════════╗
║                   MiniPrem CNS Upgrade                        ║
╚═══════════════════════════════════════════════════════════════╝
"

# Check prerequisites
if [[ ! -f "$VALUES_FILE" ]]; then
    error "Values file not found: $VALUES_FILE"
    exit 1
fi

if [[ ! -d "$CHART_DIR" ]]; then
    error "Helm chart not found: $CHART_DIR"
    exit 1
fi

# Check if deployment exists
if ! $KUBECTL get deployment renny -n uneeq &>/dev/null 2>&1; then
    error "No Renny deployment found in uneeq namespace"
    echo ""
    echo "Use './miniprem.sh deploy' to deploy first."
    exit 1
fi

# Load saved configuration
load_config || true

# Handle restart-only mode
if [[ "$RESTART_ONLY" == "true" ]]; then
    info "Restarting Renny pods..."
    $KUBECTL rollout restart deployment/renny -n uneeq

    info "Waiting for pods to be ready..."
    $KUBECTL rollout status deployment/renny -n uneeq --timeout=300s

    success "Pods restarted successfully"
    echo ""
    $KUBECTL get pods -n uneeq
    exit 0
fi

################################################################################
# Full Upgrade: Git Pull + Helm + New Image
################################################################################

if [[ "$CONFIG_ONLY" != "true" ]]; then
    echo ""
    info "Full upgrade mode - will pull latest code and Renny image"
    echo ""

    # Check if we're in a git repository
    cd "$PROJECT_ROOT"
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        error "Not a git repository. Use --config-only for helm-only upgrade."
        exit 1
    fi

    # Show what will happen
    echo "This will:"
    echo "  1. Backup your credentials (.cns_config)"
    echo "  2. Pull latest code from git"
    echo "  3. Restore your credentials"
    echo "  4. Apply helm upgrade with new chart/values"
    echo "  5. Restart pods to pull latest Renny image"
    echo ""

    if [[ "$FORCE" != "true" ]]; then
        read -p "Continue with full upgrade? [Y/n]: " confirm
        if [[ "$confirm" =~ ^[Nn]$ ]]; then
            echo "Cancelled. Use --config-only to just apply config changes."
            exit 0
        fi
    fi

    # Step 1: Backup config
    info "Step 1/5: Backing up configuration..."
    BACKUP_DIR=$(backup_config)
    success "Backup saved to $BACKUP_DIR"

    # Step 2: Git pull
    info "Step 2/5: Pulling latest code from git..."

    # Stash any uncommitted changes
    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        warning "Stashing uncommitted changes..."
        git stash push -m "miniprem-cns-upgrade-$(date +%Y%m%d_%H%M%S)" || true
    fi

    if git pull; then
        success "Git pull successful"
    else
        warning "Git pull failed. Restoring config..."
        restore_config "$BACKUP_DIR"
        error "Failed to pull updates from git."
        exit 1
    fi

    # Step 3: Restore config
    info "Step 3/5: Restoring configuration..."
    restore_config "$BACKUP_DIR"

    # Reload config after restore
    load_config || true

    echo ""
    info "Step 4/5: Applying helm upgrade..."
fi

################################################################################
# Helm Upgrade
################################################################################

# Get current state
info "Current deployment status:"
$KUBECTL get deployment renny -n uneeq -o wide 2>/dev/null
echo ""

CURRENT_REPLICAS=$($KUBECTL get deployment renny -n uneeq -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
info "Current replicas: $CURRENT_REPLICAS"

# Build helm upgrade command
HELM_ARGS=(
    upgrade renny "$CHART_DIR"
    --namespace uneeq
    --values "$VALUES_FILE"
)

# Add replica count if specified
if [[ -n "$REPLICAS" ]]; then
    HELM_ARGS+=(--set "deployment.totalReplicas=$REPLICAS")
    info "Setting replicas to: $REPLICAS"
fi

# Add credentials from saved config (if available)
if [[ -n "${DHOP_APIKEY:-}" && -n "${DHOP_TENANTID:-}" ]]; then
    info "Using saved DHOP credentials"
    HELM_ARGS+=(
        --set "renderer.dhop.apiKey=$DHOP_APIKEY"
        --set "renderer.dhop.tenantId=$DHOP_TENANTID"
    )

    # Set DHOP URL based on region
    if [[ "${UNEEQ_REGION:-us}" == "eu" ]]; then
        HELM_ARGS+=(--set "renderer.dhop.url=wss://api-eu.enterprise.uneeq.io:443/signalling-service")
    else
        HELM_ARGS+=(--set "renderer.dhop.url=wss://api.enterprise.uneeq.io:443/signalling-service")
    fi
else
    warning "No DHOP credentials found - deployment may not work correctly"
    if [[ "$FORCE" != "true" ]]; then
        read -p "Continue anyway? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Cancelled."
            exit 0
        fi
    fi
fi

# Handle TTS configuration
if [[ "$CLEAR_SECRETS" == "true" ]]; then
    info "Clearing TTS secrets (will use Admin Portal configuration)"
    HELM_ARGS+=(
        --set "renderer.tts.azureRegion="
        --set "renderer.tts.azureSpeechKey="
        --set "renderer.tts.elevenlabsApiKey="
        --set "renderer.tts.elevenlabsModelId="
        --set "renderer.tts.veritoneApiKey="
        --set "renderer.tts.gcpCredentials="
    )
else
    # Add TTS credentials from saved config based on provider
    case "${TTS_PROVIDER:-}" in
        azure)
            if [[ -n "${AZURE_SPEECH_KEY:-}" ]]; then
                info "Using saved Azure TTS credentials"
                HELM_ARGS+=(
                    --set "renderer.tts.azureRegion=$AZURE_REGION"
                    --set "renderer.tts.azureSpeechKey=$AZURE_SPEECH_KEY"
                )
            fi
            ;;
        elevenlabs)
            if [[ -n "${ELEVEN_LABS_API_KEY:-}" ]]; then
                info "Using saved ElevenLabs credentials"
                HELM_ARGS+=(
                    --set "renderer.tts.elevenlabsApiKey=$ELEVEN_LABS_API_KEY"
                    --set "renderer.tts.elevenlabsModelId=eleven_turbo_v2"
                )
            fi
            ;;
        rime)
            if [[ -n "${RIME_API_KEY:-}" ]]; then
                info "Using saved RIME credentials"
                # RIME uses proxy URL
            fi
            ;;
        *)
            # No TTS provider saved - TTS configured in Admin Portal
            ;;
    esac
fi

# Add quality level from config
if [[ -n "${CNS_QUALITY_LEVEL:-}" ]]; then
    HELM_ARGS+=(--set "renderer.qualityLevel=$CNS_QUALITY_LEVEL")
fi

# Show upgrade summary
if [[ "$CONFIG_ONLY" == "true" ]]; then
    echo ""
    print_color "$BOLD" "Config-only Upgrade Summary:"
else
    echo ""
    print_color "$BOLD" "Step 4/5: Helm Upgrade Summary:"
fi
echo "  Values file: $VALUES_FILE"
echo "  Replicas: ${REPLICAS:-from values file}"
echo "  DHOP: ${DHOP_TENANTID:+configured}${DHOP_TENANTID:-NOT CONFIGURED}"
echo "  TTS: ${TTS_PROVIDER:-Admin Portal}"
if [[ "$CLEAR_SECRETS" == "true" ]]; then
    echo "  Secrets: CLEARING (use Admin Portal)"
fi
echo ""

# Confirm unless --force (only for config-only mode, full upgrade already confirmed)
if [[ "$CONFIG_ONLY" == "true" && "$FORCE" != "true" ]]; then
    read -p "Apply these changes? [Y/n]: " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        echo "Cancelled."
        exit 0
    fi
fi

# Delete existing secret to ensure clean update
info "Preparing for upgrade..."
$KUBECTL delete secret renny -n uneeq --ignore-not-found 2>/dev/null || true

# Run helm upgrade
info "Applying configuration changes..."
if $HELM "${HELM_ARGS[@]}" --wait --timeout 10m; then
    success "Helm upgrade completed"
else
    error "Helm upgrade failed"
    exit 1
fi

################################################################################
# Restart Pods (Step 5 for full upgrade)
################################################################################

if [[ "$CONFIG_ONLY" != "true" ]]; then
    echo ""
    info "Step 5/5: Restarting pods to pull latest Renny image..."
fi

$KUBECTL rollout restart deployment/renny -n uneeq

info "Waiting for pods to be ready..."
$KUBECTL rollout status deployment/renny -n uneeq --timeout=300s || {
    warning "Timeout waiting for pods - they may still be starting"
}

# Show final status
echo ""
success "Upgrade completed successfully!"
echo ""
info "Current pod status:"
$KUBECTL get pods -n uneeq -o wide

echo ""
info "Useful commands:"
echo "  ./miniprem.sh logs      # Watch pod logs"
echo "  ./miniprem.sh status    # Check deployment status"
echo "  ./miniprem.sh restart   # Restart pods again"
