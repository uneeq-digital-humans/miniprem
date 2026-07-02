#!/usr/bin/env bash
# Package every standalone chart for distribution (OCI push / bundle).
#
#   Usage: package-charts.sh [output-dir]     (default: ./charts-out)
#
# Refreshes packaging copies FIRST so charts stay self-contained without a
# second source of truth in git:
#   host-helper/files/host_helper.py  <-  digitalhuman-host-helper/host_helper.py
# (host-helper >= 0.2.0 bundles its agent source: consumers who pull charts
# from a registry have no repo checkout to create the ConfigMap from.)
set -euo pipefail
KUBE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$KUBE_DIR/charts-out}"
mkdir -p "$OUT"

# --- refresh packaging copies (single source of truth lives outside charts) --
cp "$KUBE_DIR/digitalhuman-host-helper/host_helper.py" \
   "$KUBE_DIR/host-helper/files/host_helper.py"

CHARTS=(
  renny
  digitalhuman-asr
  digitalhuman-interface
  digitalhuman-websocket-api
  remote-mic-relay
  host-helper
  kiosk-ui
  nim-gemma
  riva-tts
  phoenix
  miniprem-monitor/chart
  digitalhuman-rag-adapter/chart
)

for c in "${CHARTS[@]}"; do
  helm lint "$KUBE_DIR/$c" >/dev/null
  helm package "$KUBE_DIR/$c" -d "$OUT" | sed 's|.*/||'
done
echo "Packaged ${#CHARTS[@]} charts -> $OUT"
