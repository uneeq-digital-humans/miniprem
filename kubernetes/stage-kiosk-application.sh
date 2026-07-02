#!/usr/bin/env bash
# Stage a clean, shareable copy of the kubernetes/ tree for the kiosk-application repo.
set -euo pipefail
STAGE="${1:?usage: stage-kiosk-application.sh <stage-dir>}"
SRC="$(cd "$(dirname "$0")" && pwd)"
rm -rf "$STAGE" && mkdir -p "$STAGE"
rsync -a \
  --exclude "watch_*" \
  --exclude "*.tgz*" \
  --exclude "conversation-config.t2*.json" \
  --exclude "terraform" \
  --exclude "scripts/t2-*" \
  --exclude "*node_modules*" \
  --exclude ".DS_Store" \
  --exclude "*.pyc" \
  --exclude ".pytest_cache" \
  --exclude "stage-kiosk-application.sh" \
  "$SRC/" "$STAGE/"
echo "staged: $(find "$STAGE" -type f | wc -l | tr -d ' ') files"
