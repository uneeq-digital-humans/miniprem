#!/bin/bash
#
# deploy-chatflow.sh — deploy a custom Flowise chatflow JSON into the running
# Flowise container via its REST API, WITHOUT using the GUI import feature.
#
# Each run CREATES A NEW chatflow (no update/dedupe) so you always get a fresh
# copy. It handles Flowise 3.x session auth, normalizes the input JSON into a
# valid API payload, and (optionally) wires a vLLM/OpenAI credential into
# ChatOpenAI nodes so the deployed flow actually runs.
#
# Usage:
#   ./deploy-chatflow.sh <flow.json> [--name "My Flow"] [--vllm] [--no-deploy]
#                        [--url http://localhost:3000]
#
# Options:
#   --name NAME    Chatflow name (default: "name" field in the JSON, else filename)
#   --vllm         Create/reuse a "vLLM (local)" openAIApi credential and wire it
#                  into every ChatOpenAI node (also sets basepath + modelName).
#   --no-deploy    Create the chatflow but leave it undeployed (default: deployed).
#   --url URL      Flowise base URL (default: http://localhost:3000).
#
# Input JSON may be either a raw export ({nodes, edges, viewport}) or a full
# chatflow record ({name, flowData, ...}); both are accepted.
set -euo pipefail

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }
die()         { log_error "$1"; exit 1; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
FLOW_FILE=""
CHATFLOW_NAME=""
FLOWISE_URL="http://localhost:3000"
WIRE_VLLM=false
DEPLOYED=true

usage() { sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
    case "$1" in
        --name)      CHATFLOW_NAME="${2:-}"; shift 2 ;;
        --url)       FLOWISE_URL="${2:-}"; shift 2 ;;
        --vllm)      WIRE_VLLM=true; shift ;;
        --no-deploy) DEPLOYED=false; shift ;;
        -h|--help)   usage; exit 0 ;;
        -*)          die "Unknown option: $1 (use --help)" ;;
        *)           FLOW_FILE="$1"; shift ;;
    esac
done

[ -n "$FLOW_FILE" ] || { usage; die "No chatflow JSON file given."; }
[ -f "$FLOW_FILE" ] || die "File not found: $FLOW_FILE"
command_exists jq   || die "jq is required but not installed."
command_exists curl || die "curl is required but not installed."
jq -e . "$FLOW_FILE" >/dev/null 2>&1 || die "Not valid JSON: $FLOW_FILE"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLOWISE_ENV_FILE="$SCRIPT_DIR/docker/flowise.env"

# vLLM endpoint (only used with --vllm). Same defaults as the install seeder.
VLLM_BASE_URL="${VLLM_BASE_URL:-http://localhost:8800/v1}"
VLLM_MODEL_NAME="${VLLM_MODEL_NAME:-HuggingFaceH4/zephyr-7b-beta}"
CREDENTIAL_NAME="vLLM (local)"
CREDENTIAL_ID=""

# Flowise runs with NODE_ENV=production -> secure cookies. Sending
# X-Forwarded-Proto: https makes Flowise issue the session cookie over plain
# HTTP; we capture Set-Cookie ourselves and replay it (curl won't resend Secure
# cookies over http://). Mirrors setup-chatflow-post-deployment.sh.
FLOWISE_XFP_HEADER="X-Forwarded-Proto: https"
FLOWISE_COOKIES=""

# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------
load_admin_credentials() {
    if [ -z "${FLOWISE_ADMIN_EMAIL:-}" ] || [ -z "${FLOWISE_ADMIN_PASSWORD:-}" ]; then
        if [ -f "$FLOWISE_ENV_FILE" ]; then
            FLOWISE_ADMIN_EMAIL=$(grep '^FLOWISE_ADMIN_EMAIL=' "$FLOWISE_ENV_FILE" | cut -d'=' -f2-)
            FLOWISE_ADMIN_PASSWORD=$(grep '^FLOWISE_ADMIN_PASSWORD=' "$FLOWISE_ENV_FILE" | cut -d'=' -f2-)
        fi
    fi
    [ -n "${FLOWISE_ADMIN_EMAIL:-}" ] && [ -n "${FLOWISE_ADMIN_PASSWORD:-}" ] \
        || die "Flowise admin credentials not found (expected in $FLOWISE_ENV_FILE or FLOWISE_ADMIN_EMAIL/FLOWISE_ADMIN_PASSWORD)."
}

flowise_login() {
    log_info "Logging in to Flowise at $FLOWISE_URL ..."
    local headers
    headers=$(curl --silent --dump-header - --output /dev/null \
        --request POST "$FLOWISE_URL/api/v1/auth/login" \
        --header "Content-Type: application/json" \
        --header "$FLOWISE_XFP_HEADER" \
        --data "{\"email\":\"${FLOWISE_ADMIN_EMAIL}\",\"password\":\"${FLOWISE_ADMIN_PASSWORD}\"}")
    FLOWISE_COOKIES=$(printf '%s' "$headers" | tr -d '\r' \
        | awk -F': ' 'tolower($1)=="set-cookie"{split($2,a,";"); printf "%s; ", a[1]}')
    printf '%s' "$FLOWISE_COOKIES" | grep -qE '(^|; )token=' \
        || die "Flowise login failed (no session cookie). Check credentials in $FLOWISE_ENV_FILE."
    log_success "Authenticated."
}

# Authenticated GET/POST helpers (cookies + internal marker + forwarded proto).
api_get()  { curl --silent --request GET  "$FLOWISE_URL$1" \
                 --header "x-request-from: internal" --header "$FLOWISE_XFP_HEADER" \
                 --header "Cookie: $FLOWISE_COOKIES"; }
api_post() { curl --silent --request POST "$FLOWISE_URL$1" \
                 --header "Content-Type: application/json" --header "x-request-from: internal" \
                 --header "$FLOWISE_XFP_HEADER" --header "Cookie: $FLOWISE_COOKIES" --data "$2"; }

# ---------------------------------------------------------------------------
# vLLM credential (only with --vllm)
# ---------------------------------------------------------------------------
flowise_ensure_credential() {
    log_info "Ensuring credential '${CREDENTIAL_NAME}' exists..."
    local existing
    existing=$(api_get "/api/v1/credentials?credentialName=openAIApi")
    CREDENTIAL_ID=$(printf '%s' "$existing" \
        | jq -r --arg n "$CREDENTIAL_NAME" 'if type=="array" then ([.[]|select(.name==$n)][0].id // empty) else empty end' 2>/dev/null)
    if [ -n "$CREDENTIAL_ID" ]; then
        log_success "Reusing credential ${CREDENTIAL_ID}."
        return 0
    fi
    local resp
    resp=$(api_post "/api/v1/credentials" \
        "$(jq -n --arg name "$CREDENTIAL_NAME" '{name:$name, credentialName:"openAIApi", plainDataObj:{openAIApiKey:"sk-no-key-required"}}')")
    CREDENTIAL_ID=$(printf '%s' "$resp" | jq -r '.id // empty' 2>/dev/null)
    [ -n "$CREDENTIAL_ID" ] || die "Failed to create credential. Response: $resp"
    log_success "Created credential ${CREDENTIAL_ID}."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
load_admin_credentials
flowise_login

# Normalize input into a graph object {nodes, edges, viewport}. Accept either a
# raw export or a full chatflow record whose flowData may be a string or object.
if jq -e 'has("flowData")' "$FLOW_FILE" >/dev/null 2>&1; then
    GRAPH=$(jq -c 'if (.flowData|type)=="string" then (.flowData|fromjson) else .flowData end' "$FLOW_FILE")
    [ -n "$CHATFLOW_NAME" ] || CHATFLOW_NAME=$(jq -r '.name // empty' "$FLOW_FILE")
else
    GRAPH=$(jq -c '.' "$FLOW_FILE")
fi

printf '%s' "$GRAPH" | jq -e 'has("nodes") and has("edges")' >/dev/null 2>&1 \
    || die "Input does not contain a chatflow graph (nodes/edges). Is this a Flowise export?"

# Guarantee a viewport so the canvas renders correctly.
GRAPH=$(printf '%s' "$GRAPH" | jq -c '{nodes, edges, viewport: (.viewport // {x:0, y:0, zoom:1})}')

# Default name: explicit > JSON "name" > filename.
[ -n "$CHATFLOW_NAME" ] || CHATFLOW_NAME=$(basename "$FLOW_FILE" .json)

# Optionally wire vLLM credential + endpoint into ChatOpenAI nodes.
if $WIRE_VLLM; then
    flowise_ensure_credential
    GRAPH=$(printf '%s' "$GRAPH" | jq -c \
        --arg cred "$CREDENTIAL_ID" --arg base "$VLLM_BASE_URL" --arg model "$VLLM_MODEL_NAME" '
        .nodes |= map(
            if .data.name == "chatOpenAI" then
                .data.credential = $cred
                | .data.inputs.credential = $cred
                | .data.inputs.basepath = $base
                | .data.inputs.modelName = $model
            else . end)')
    log_info "Wired vLLM credential into ChatOpenAI nodes (model: ${VLLM_MODEL_NAME}, endpoint: ${VLLM_BASE_URL})."
fi

# Warn about credential references that don't exist in this instance — these
# load on the canvas but fail at runtime until a credential is attached.
NEEDED_CREDS=$(printf '%s' "$GRAPH" | jq -r '[.nodes[].data.inputs.credential? // empty] | map(select(. != "")) | unique | .[]' 2>/dev/null || true)
if [ -n "$NEEDED_CREDS" ]; then
    EXISTING_CREDS=$(api_get "/api/v1/credentials" | jq -r 'if type=="array" then .[].id else empty end' 2>/dev/null || true)
    while IFS= read -r cred; do
        [ -n "$cred" ] || continue
        if ! printf '%s\n' "$EXISTING_CREDS" | grep -qx "$cred"; then
            log_warning "Node references credential '$cred' which does not exist here."
            log_warning "  -> attach a credential in the UI, or re-run with --vllm for ChatOpenAI nodes."
        fi
    done <<< "$NEEDED_CREDS"
fi

# Build the payload. flowData MUST be a JSON string (Flowise runs JSON.parse on it).
log_info "Creating new chatflow '${CHATFLOW_NAME}' (deployed: ${DEPLOYED})..."
FLOWDATA=$(printf '%s' "$GRAPH" | jq -c '.')
PAYLOAD=$(jq -n \
    --arg name "$CHATFLOW_NAME" \
    --arg flowData "$FLOWDATA" \
    --argjson deployed "$DEPLOYED" \
    '{name:$name, flowData:$flowData, deployed:$deployed, isPublic:false, type:"CHATFLOW"}')

RESPONSE=$(curl --silent --write-out "\n%{http_code}" --request POST "$FLOWISE_URL/api/v1/chatflows" \
    --header "Content-Type: application/json" \
    --header "x-request-from: internal" \
    --header "$FLOWISE_XFP_HEADER" \
    --header "Cookie: $FLOWISE_COOKIES" \
    --data "$PAYLOAD")
HTTP_STATUS=$(printf '%s' "$RESPONSE" | tail -n1)
BODY=$(printf '%s' "$RESPONSE" | sed '$d')

if [ "$HTTP_STATUS" != "200" ] && [ "$HTTP_STATUS" != "201" ]; then
    log_error "Failed to create chatflow (HTTP $HTTP_STATUS)."
    log_error "Response: $BODY"
    exit 1
fi

CHATFLOW_ID=$(printf '%s' "$BODY" | jq -r '.id // empty')
[ -n "$CHATFLOW_ID" ] || die "Chatflow created but no ID returned: $BODY"

log_success "Created chatflow '${CHATFLOW_NAME}' (ID: ${CHATFLOW_ID})."
log_info "Open it at ${FLOWISE_URL}/chatflows/${CHATFLOW_ID}"

# UneeQ takes the endpoint base and the chatflow id as TWO separate fields:
#   X-Chat-Endpoint = <host>/api/v1/prediction   (no id)
#   X-Chat-Id       = <chatflowId>
# Flowise then serves predictions at POST {X-Chat-Endpoint}/{X-Chat-Id}.
# NOTE: $FLOWISE_URL is localhost here — UneeQ's cloud cannot reach localhost, so
# the X-Chat-Endpoint host must be an address reachable from UneeQ.
CHAT_ENDPOINT="${FLOWISE_URL}/api/v1/prediction"
echo
echo -e "${GREEN}=== COPY INTO THE UneeQ ADMIN PORTAL ===${NC}"
echo -e "${YELLOW}X-Chat-Endpoint:${NC}    ${CHAT_ENDPOINT}"
echo -e "${YELLOW}X-Chat-Id:${NC}          ${CHATFLOW_ID}"
echo
echo -e "${BLUE}Note:${NC} '${FLOWISE_URL}' is local to this host. UneeQ cannot reach localhost —"
echo "      set X-Chat-Endpoint's host to an address reachable from UneeQ"
echo "      (public IP / domain / tunnel), keeping the /api/v1/prediction path, e.g.:"
echo "      https://<your-host>/api/v1/prediction"
echo
