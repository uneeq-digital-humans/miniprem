#!/usr/bin/env bash
# Render Deepgram license configs from templates.
#
# WHY THIS EXISTS: the engine (impeller 3.128.0) reads its license key ONLY
# from the [license] key field of the TOML. The env var is NOT read for
# licensing in this build — verified on t2 2026-09-01:
#   env-only boot     -> exits "Error: Missing license configuration."
#   [license] key set -> completes the mTLS handshake, 401 with a dummy key
# (matches the official Deepgram self-hosted docs: "Replace the value at
#  [license.key] with your API key secret").
#
# Usage:
#   render-configs.sh              render in-place next to the templates
#   render-configs.sh --to <dir>   render into <dir> (k8s node: /opt/deepgram/config)
#   render-configs.sh --check      only validate the key is present, no writes
#
# Key source: DEEPGRAM_API_KEY in the environment, else in ./../.env.
# Never commits real keys: .gitignore covers rendered *.toml (templates stay).
set -euo pipefail
cd "$(dirname "$0")"          # .../docker/allinone
CFG=deepgram/config
ENVFILE="$(pwd)/.env"

OUTDIR=""
CHECK_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --to) OUTDIR="${2:?--to needs a directory}"; shift 2 ;;
    --check) CHECK_ONLY=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# shellcheck disable=SC1090
if [ -f "$ENVFILE" ]; then
  KEY="$(sed -nE 's/^DEEPGRAM_API_KEY=[[:space:]]*//p' "$ENVFILE" | tail -1 | tr -d '"' | tr -d '[:space:]')"
fi
KEY="${DEEPGRAM_API_KEY:-$KEY}"

if [ -z "$KEY" ]; then
  if [ "$CHECK_ONLY" = 1 ]; then
    echo "render-configs: DEEPGRAM_API_KEY not set (deepgram profile cannot license)" >&2
    exit 0
  fi
  echo "render-configs: DEEPGRAM_API_KEY is required (set in .env or the environment)" >&2
  exit 1
fi

DIRS=("$CFG")
[ -n "$OUTDIR" ] && DIRS=("$OUTDIR")    # --to <dir> renders ONLY into <dir> (e.g. a node's /opt/deepgram/config)

for base in api engine-stt engine-tts; do
  tpl="$CFG/$base.toml.template"
  [ -f "$tpl" ] || { echo "render-configs: missing template $tpl" >&2; exit 1; }
  grep -qF '{DEEPGRAM_API_KEY}' "$tpl" || { echo "render-configs: $tpl lacks the {DEEPGRAM_API_KEY} placeholder — refusing" >&2; exit 1; }
  [ "$CHECK_ONLY" = 1 ] && continue
  for outdir in "${DIRS[@]}"; do
    mkdir -p "$outdir"
    out="$outdir/$base.toml"
    sed "s|{DEEPGRAM_API_KEY}|$KEY|g" "$tpl" > "$out"
    chmod 600 "$out"
    echo "render-configs: wrote $out (0600)"
  done
done

echo "render-configs: OK — deepgram configs carry a license key"
