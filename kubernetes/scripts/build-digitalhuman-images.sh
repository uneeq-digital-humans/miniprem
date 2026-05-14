#!/bin/bash
# Build and push all three Digital Human images to Harbor.
#
# Prerequisites:
#   docker login cr.uneeq.io
#   docker buildx create --use   (for linux/amd64 cross-builds on Apple Silicon)
#
# Usage:
#   ./build-digitalhuman-images.sh            # builds :latest
#   ./build-digitalhuman-images.sh v1.2.3     # also tags :v1.2.3

set -euo pipefail

TAG="${1:-latest}"
REGISTRY="cr.uneeq.io/uneeq"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MINIPREM_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

INTERFACE_SRC="$MINIPREM_DIR/../../dell-kiosk-application/interface"
WSAPI_SRC="$MINIPREM_DIR/../../../dell-kiosk-websocket-api"
PROXY_SRC="$MINIPREM_DIR/kubernetes/digitalhuman-asr/ws-proxy-src"

info()    { echo "ℹ️  $*"; }
success() { echo "✅ $*"; }
error()   { echo "❌ $*"; exit 1; }

# ── Verify source directories ────────────────────────────────────────────────

[[ -d "$INTERFACE_SRC" ]] || error "Interface source not found: $INTERFACE_SRC"
[[ -d "$WSAPI_SRC" ]]     || error "WS API source not found: $WSAPI_SRC"
[[ -d "$PROXY_SRC" ]]     || error "WS proxy source not found: $PROXY_SRC"

# ── 1. digitalhuman-interface ────────────────────────────────────────────────

info "Building digitalhuman-interface..."
docker buildx build --platform linux/amd64 \
    -t "$REGISTRY/digitalhuman-interface:latest" \
    ${TAG:+-t "$REGISTRY/digitalhuman-interface:$TAG"} \
    --push \
    "$INTERFACE_SRC"
success "digitalhuman-interface pushed"

# ── 2. digitalhuman-websocket-api ────────────────────────────────────────────

info "Building digitalhuman-websocket-api..."
docker buildx build --platform linux/amd64 \
    -t "$REGISTRY/digitalhuman-websocket-api:latest" \
    ${TAG:+-t "$REGISTRY/digitalhuman-websocket-api:$TAG"} \
    --push \
    "$WSAPI_SRC"
success "digitalhuman-websocket-api pushed"

# ── 3. riva-ws-proxy ─────────────────────────────────────────────────────────

info "Building riva-ws-proxy..."
docker buildx build --platform linux/amd64 \
    -t "$REGISTRY/riva-ws-proxy:latest" \
    ${TAG:+-t "$REGISTRY/riva-ws-proxy:$TAG"} \
    --push \
    "$PROXY_SRC"
success "riva-ws-proxy pushed"

echo ""
echo "All images pushed to $REGISTRY:"
echo "  $REGISTRY/digitalhuman-interface:latest"
echo "  $REGISTRY/digitalhuman-websocket-api:latest"
echo "  $REGISTRY/riva-ws-proxy:latest"
