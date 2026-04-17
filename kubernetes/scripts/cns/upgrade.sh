#!/bin/bash

################################################################################
# MiniPrem CNS Upgrade Script
#
# Interactive upgrade for CNS deployments.
#
# Usage:
#   ./upgrade.sh                    # Interactive menu
#   ./upgrade.sh --full             # Full upgrade (skip menu)
#   ./upgrade.sh --config-only      # Config changes only (skip menu)
#   ./upgrade.sh --restart          # Just restart pods
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
BOLD='\033[1m'
NC='\033[0m'

info() { echo "ℹ️  $*"; }
success() { echo "✅ $*"; }
warning() { echo "⚠️  $*"; }
error() { echo "❌ $*"; }

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
        return 1
    fi
}

################################################################################
# Config file backup/restore (for git pull)
################################################################################

backup_config() {
    local backup_dir="/tmp/miniprem-cns-backup-$$"
    mkdir -p "$backup_dir"

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
FULL_UPGRADE=false
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
        --full)
            FULL_UPGRADE=true
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
            echo "MiniPrem CNS Upgrade"
            echo ""
            echo "Usage: $0 [options]"
            echo ""
            echo "Upgrade Modes:"
            echo "  (default)              Interactive menu"
            echo "  --full                 Full upgrade: git pull + helm + new Renny image"
            echo "  --config-only          Only apply values file changes (no git pull)"
            echo "  --restart              Only restart pods (no helm upgrade)"
            echo ""
            echo "Options:"
            echo "  --replicas, -r <N>     Set number of Renny replicas"
            echo "  --clear-secrets        Clear TTS/LLM API keys (use Admin Portal config)"
            echo "  --force, -f            Skip confirmation prompts"
            echo "  --help, -h             Show this help message"
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

echo "
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
# Interactive Menu (if no mode specified)
################################################################################

if [[ "$CONFIG_ONLY" != "true" && "$FULL_UPGRADE" != "true" ]]; then
    echo ""
    echo "What would you like to do?"
    echo ""
    echo "  1) Full Upgrade"
    echo "     - Pull latest MiniPrem scripts from GitLab"
    echo "     - Pull latest Renny image from Harbor"
    echo "     - Apply helm chart updates"
    echo ""
    echo "  2) Apply Config Changes Only"
    echo "     - Apply renny-values-cns.yaml changes via helm upgrade"
    echo "     - Restart pods to apply changes"
    echo "     - Does NOT pull new code or images"
    echo ""
    echo "  3) Restart Pods Only"
    echo "     - Just restart Renny pods"
    echo "     - No config changes"
    echo ""
    echo "  4) Cancel"
    echo ""
    read -p "Enter selection [1-4]: " selection

    case "$selection" in
        1)
            FULL_UPGRADE=true
            ;;
        2)
            CONFIG_ONLY=true
            ;;
        3)
            info "Restarting Renny pods..."
            $KUBECTL rollout restart deployment/renny -n uneeq
            info "Waiting for pods to be ready..."
            $KUBECTL rollout status deployment/renny -n uneeq --timeout=300s
            success "Pods restarted successfully"
            echo ""
            $KUBECTL get pods -n uneeq
            exit 0
            ;;
        4|*)
            echo "Cancelled."
            exit 0
            ;;
    esac
fi

################################################################################
# Full Upgrade: Git Pull + Helm + New Image
################################################################################

if [[ "$FULL_UPGRADE" == "true" ]]; then
    echo ""
    echo "Full Upgrade Selected"
    echo ""

    # Check if we're in a git repository
    cd "$PROJECT_ROOT"
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        error "Not a git repository. Cannot do full upgrade."
        exit 1
    fi

    echo "This will:"
    echo "  1. Backup your credentials (.cns_config)"
    echo "  2. Pull latest MiniPrem scripts from GitLab"
    echo "  3. Restore your credentials"
    echo "  4. Apply helm upgrade with new chart/values"
    echo "  5. Restart pods to pull latest Renny image"
    echo ""

    if [[ "$FORCE" != "true" ]]; then
        read -p "Continue with full upgrade? [Y/n]: " confirm
        if [[ "$confirm" =~ ^[Nn]$ ]]; then
            echo "Cancelled."
            exit 0
        fi
    fi

    # Step 1: Backup config
    echo ""
    info "Step 1/5: Backing up configuration..."
    BACKUP_DIR=$(backup_config)
    success "Backup saved"

    # Step 2: Git pull
    info "Step 2/5: Pulling latest code from GitLab..."

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
        error "Failed to pull updates from GitLab."
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
# Config-Only Upgrade
################################################################################

if [[ "$CONFIG_ONLY" == "true" ]]; then
    echo ""
    echo "Config Changes Only"
    echo ""

    echo "This will:"
    echo "  - Apply renny-values-cns.yaml changes via helm upgrade"
    echo "  - Restart pods to apply changes"
    echo ""

    if [[ "$FORCE" != "true" ]]; then
        read -p "Continue? [Y/n]: " confirm
        if [[ "$confirm" =~ ^[Nn]$ ]]; then
            echo "Cancelled."
            exit 0
        fi
    fi
fi

################################################################################
# Helm Upgrade (common to both modes)
################################################################################

# Get current state
echo ""
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
            fi
            ;;
    esac
fi

# Add quality level from config
if [[ -n "${CNS_QUALITY_LEVEL:-}" ]]; then
    HELM_ARGS+=(--set "renderer.qualityLevel=$CNS_QUALITY_LEVEL")
fi

# Delete existing secret to ensure clean update
info "Preparing for upgrade..."
$KUBECTL delete secret renny -n uneeq --ignore-not-found 2>/dev/null || true

# Run helm upgrade
info "Applying helm upgrade..."
if $HELM "${HELM_ARGS[@]}" --wait --timeout 10m; then
    success "Helm upgrade completed"
else
    error "Helm upgrade failed"
    exit 1
fi

################################################################################
# Restart Pods
################################################################################

if [[ "$FULL_UPGRADE" == "true" ]]; then
    echo ""
    info "Step 5/5: Restarting pods to pull latest Renny image..."
else
    info "Restarting pods to apply changes..."
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
echo "Next steps:"
echo "  ./miniprem.sh logs      # Watch pod logs"
echo "  ./miniprem.sh status    # Check deployment status"
