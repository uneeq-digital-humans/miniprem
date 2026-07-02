#!/usr/bin/env bash
# Run ON the T2. Mints a scoped LiteLLM key for the kiosk and verifies Gemma
# actually answers. Reads the master key from .env on the box (never prints it).
set -u
ENVF=/home/admin/uneeq-llm-infra-dell/.env
set -a; . "$ENVF" 2>/dev/null; set +a
MASTER="${LITELLM_MASTER_KEY:-${LITELLM_MASTER:-${MASTER_KEY:-}}}"
if [ -z "${MASTER:-}" ]; then
  echo "MASTER_NOT_FOUND — env var names present:"
  grep -oE '^[A-Z_]+=' "$ENVF" 2>/dev/null | tr -d '='
  exit 1
fi
echo "=== minting scoped kiosk key ==="
NEW=$(curl -s http://localhost:4000/key/generate \
  -H "Authorization: Bearer $MASTER" -H "Content-Type: application/json" \
  -d '{"models":["gemma4-26b","gemma4-31b","nv-embed"],"key_alias":"kiosk-test"}')
KEY=$(printf '%s' "$NEW" | sed -E 's/.*"key"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
if [ -z "$KEY" ] || [ "$KEY" = "$NEW" ]; then echo "MINT_FAILED: $NEW"; exit 1; fi
echo "KIOSK_KEY=$KEY"
echo "=== gemma answer test (model gemma4-26b -> 31B route) ==="
curl -s --max-time 120 http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"model":"gemma4-26b","messages":[{"role":"user","content":"Say hello and wave in one short sentence."}],"max_tokens":64}' \
  | head -c 600
echo
