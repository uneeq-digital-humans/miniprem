#!/usr/bin/env bash
# Build the shareable Helm-charts bundle (Timothy / partner handoff).
# Excludes box-specific configs, build junk, and terraform (cloud infra is not
# part of the chart handoff).
set -euo pipefail
cd "$(dirname "$0")"
OUT="${1:-/Users/mbpro/uneeq-code/uneeq-dh-kiosk-charts-iteration1.tgz}"
tar --exclude="kubernetes/watch_*" \
    --exclude="kubernetes/*.tgz*" \
    --exclude="kubernetes/conversation-config.t2*.json" \
    --exclude="kubernetes/terraform" \
    --exclude="kubernetes/scripts/t2-*" \
    --exclude="*node_modules*" \
    --exclude=".DS_Store" \
    -czf "$OUT" kubernetes
echo "bundle: $OUT"
tar -tzf "$OUT" | grep -icE "t2|watch_|\.tgz" || true
echo "^ leaked-junk count (0 = clean)"
