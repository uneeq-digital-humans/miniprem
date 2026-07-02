#!/bin/bash

# Set up logging
LOG_FILE="flowise_setup.log"
ERROR_LOG_FILE="flowise_setup_error.log"

# Create log files if they don't exist
rm -f "$LOG_FILE" "$ERROR_LOG_FILE" # Clear previous logs
touch "$LOG_FILE"
touch "$ERROR_LOG_FILE"

# Helper functions for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "[INFO $(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    echo "[WARNING] $(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[ERROR $(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$ERROR_LOG_FILE"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install jq if it's not already installed
ensure_jq_installed() {
    if ! command_exists jq; then
        log_info "jq is not installed. Attempting to install jq..."
        if command_exists apt-get; then
             # Check if running as root or use sudo
            if [ "$(id -u)" -eq 0 ]; then
                 apt-get update && apt-get install -y jq
             else
                 sudo apt-get update && sudo apt-get install -y jq
             fi
        elif command_exists yum; then
            if [ "$(id -u)" -eq 0 ]; then
                 yum install -y jq
             else
                 sudo yum install -y jq
             fi
        elif command_exists brew; then
            brew install jq # Brew usually doesn't need sudo
        else
            log_error "Unsupported package manager. Please install jq manually and run this script again."
            exit 1
        fi

        if ! command_exists jq; then
            log_error "Failed to install jq automatically. Please install it manually and run this script again."
            exit 1
        fi
        log_success "jq installed successfully."
    else
        log_info "jq is already installed."
    fi
}

# Flowise 3.x authentication: an admin account (email + password) replaces the
# legacy FLOWISE_USERNAME/FLOWISE_PASSWORD basic auth and the api.json key file.
# The installer generates the credentials into docker/flowise.env; we register
# the account if it doesn't exist yet, then log in to obtain a session cookie.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLOWISE_ENV_FILE="$SCRIPT_DIR/docker/flowise.env"
FLOWISE_URL="http://localhost:3000"

# Flowise runs with NODE_ENV=production, which forces secure cookies. Over plain
# HTTP that has two consequences we have to work around:
#   1. express-session only issues its session cookie (connect.sid) when it
#      believes the connection is secure. The JWT auth guard needs that session
#      to populate req.user, so without it every authenticated call returns 401.
#   2. curl will not resend Secure cookies from a cookie jar over http://, so the
#      classic --cookie-jar/--cookie round-trip silently sends nothing.
# We send X-Forwarded-Proto: https (Flowise trusts the proxy header) so the
# session cookie is issued, capture the Set-Cookie values ourselves, and replay
# them via an explicit Cookie header on subsequent requests.
FLOWISE_XFP_HEADER="X-Forwarded-Proto: https"
FLOWISE_COOKIES=""

# vLLM endpoint as seen from the Flowise container. In docker-compose.full.yml both
# vllm and flowise run with network_mode: host, so vLLM's --port 8800 is reachable
# at localhost:8800 from inside Flowise. The /v1 suffix is the OpenAI-compatible base.
# Model must match the vllm `--model` arg (served model id) exactly.
VLLM_BASE_URL="${VLLM_BASE_URL:-http://localhost:8800/v1}"
VLLM_MODEL_NAME="${VLLM_MODEL_NAME:-HuggingFaceH4/zephyr-7b-beta}"
FLOWDATA_TEMPLATE="$SCRIPT_DIR/docker/flowise/vllm-chatflow.flowdata.json"

# Name used for both the auto-created chatflow and the OpenAI-compatible credential,
# so re-runs are idempotent (we reuse the existing records instead of duplicating).
CHATFLOW_NAME="vLLM Chatflow"
CREDENTIAL_NAME="vLLM (local)"
CREDENTIAL_ID=""

load_admin_credentials() {
    if [ -z "${FLOWISE_ADMIN_EMAIL:-}" ] || [ -z "${FLOWISE_ADMIN_PASSWORD:-}" ]; then
        if [ -f "$FLOWISE_ENV_FILE" ]; then
            FLOWISE_ADMIN_EMAIL=$(grep '^FLOWISE_ADMIN_EMAIL=' "$FLOWISE_ENV_FILE" | cut -d'=' -f2-)
            FLOWISE_ADMIN_PASSWORD=$(grep '^FLOWISE_ADMIN_PASSWORD=' "$FLOWISE_ENV_FILE" | cut -d'=' -f2-)
        fi
    fi
    if [ -z "${FLOWISE_ADMIN_EMAIL:-}" ] || [ -z "${FLOWISE_ADMIN_PASSWORD:-}" ]; then
        log_error "Flowise admin credentials not found (expected in $FLOWISE_ENV_FILE or FLOWISE_ADMIN_EMAIL/FLOWISE_ADMIN_PASSWORD env vars)."
        log_error "Re-run docker/scripts/install_miniprem.sh, or create the admin account manually at http://localhost:3000."
        return 1
    fi
    return 0
}

flowise_login() {
    log_info "Registering Flowise admin account (no-op if it already exists)..."
    # Registration uses a {user:{name,email,credential}} body. On a fresh install
    # this returns 201; on re-runs it returns 400 ("You can only have one
    # organization"), which is harmless — we just log it and proceed to login.
    REGISTER_RESPONSE=$(curl --silent --request POST "$FLOWISE_URL/api/v1/account/register" \
        --header "Content-Type: application/json" \
        --header "$FLOWISE_XFP_HEADER" \
        --data "{\"user\":{\"name\":\"MiniPrem Admin\",\"email\":\"${FLOWISE_ADMIN_EMAIL}\",\"credential\":\"${FLOWISE_ADMIN_PASSWORD}\"}}")
    echo "Register response: $REGISTER_RESPONSE" >> "$LOG_FILE"

    log_info "Logging in to Flowise as ${FLOWISE_ADMIN_EMAIL}..."
    # Login is POST /api/v1/auth/login with a TOP-LEVEL {email,password} body
    # (NOT {user:{email,credential}} — a wrong shape silently falls through to the
    # SPA and returns 200 text/html with no cookies). We capture the response
    # headers so we can extract the auth cookies (token + refreshToken +
    # connect.sid) and replay them on the chatflow request.
    local login_headers
    login_headers=$(curl --silent --dump-header - --output /dev/null \
        --request POST "$FLOWISE_URL/api/v1/auth/login" \
        --header "Content-Type: application/json" \
        --header "$FLOWISE_XFP_HEADER" \
        --data "{\"email\":\"${FLOWISE_ADMIN_EMAIL}\",\"password\":\"${FLOWISE_ADMIN_PASSWORD}\"}")

    # Assemble a "name=value; ..." Cookie header from every Set-Cookie line.
    FLOWISE_COOKIES=$(printf '%s' "$login_headers" | tr -d '\r' \
        | awk -F': ' 'tolower($1)=="set-cookie"{split($2,a,";"); printf "%s; ", a[1]}')

    # A successful login sets the JWT "token" cookie. Its absence means auth
    # failed (bad credentials, or the request fell through to the SPA) — this
    # replaces the old HTTP-200 check, which the SPA fallthrough passed falsely.
    if ! printf '%s' "$FLOWISE_COOKIES" | grep -qE '(^|; )token='; then
        log_error "Flowise login failed: no session cookie returned."
        log_error "If the admin account was created manually with different credentials, update $FLOWISE_ENV_FILE to match."
        return 1
    fi
    log_success "Logged in to Flowise."
    return 0
}

# Create (or reuse) an OpenAI-compatible credential pointing at vLLM. The ChatOpenAI
# node requires an openAIApi credential to instantiate its client; vLLM does not
# validate the key, so a placeholder is fine. Sets CREDENTIAL_ID on success.
flowise_ensure_credential() {
    log_info "Ensuring Flowise credential '${CREDENTIAL_NAME}' exists..."

    # Reuse an existing credential with the same name (idempotent re-runs).
    local existing
    existing=$(curl --silent --request GET "$FLOWISE_URL/api/v1/credentials?credentialName=openAIApi" \
        --header "x-request-from: internal" \
        --header "$FLOWISE_XFP_HEADER" \
        --header "Cookie: $FLOWISE_COOKIES")
    CREDENTIAL_ID=$(printf '%s' "$existing" \
        | jq -r --arg n "$CREDENTIAL_NAME" 'if type=="array" then ([.[] | select(.name==$n)][0].id // empty) else empty end' 2>/dev/null)
    if [ -n "$CREDENTIAL_ID" ]; then
        log_success "Reusing existing credential (${CREDENTIAL_ID})."
        return 0
    fi

    local resp
    resp=$(curl --silent --request POST "$FLOWISE_URL/api/v1/credentials" \
        --header "Content-Type: application/json" \
        --header "x-request-from: internal" \
        --header "$FLOWISE_XFP_HEADER" \
        --header "Cookie: $FLOWISE_COOKIES" \
        --data "$(jq -n --arg name "$CREDENTIAL_NAME" \
            '{name:$name, credentialName:"openAIApi", plainDataObj:{openAIApiKey:"sk-no-key-required"}}')")
    CREDENTIAL_ID=$(printf '%s' "$resp" | jq -r '.id // empty' 2>/dev/null)

    if [ -z "$CREDENTIAL_ID" ]; then
        log_error "Failed to create Flowise credential. Response: $resp"
        return 1
    fi
    log_success "Created credential '${CREDENTIAL_NAME}' (${CREDENTIAL_ID})."
    return 0
}

# Returns the id of an existing chatflow named "$CHATFLOW_NAME", or empty.
flowise_find_chatflow() {
    local list
    list=$(curl --silent --request GET "$FLOWISE_URL/api/v1/chatflows" \
        --header "x-request-from: internal" \
        --header "$FLOWISE_XFP_HEADER" \
        --header "Cookie: $FLOWISE_COOKIES")
    printf '%s' "$list" \
        | jq -r --arg n "$CHATFLOW_NAME" 'if type=="array" then ([.[] | select(.name==$n)][0].id // empty) else empty end' 2>/dev/null
}

# Function to prompt user to open browser
open_browser_prompt() {
    if command_exists xdg-open; then
        read -p "Would you like to open Flowise in your browser now? (y/n): " open_browser
        if [[ "$open_browser" == "y" || "$open_browser" == "Y" ]]; then
            xdg-open "http://localhost:3000" 2>/dev/null || (
                log_warning "Failed to open browser with xdg-open. Trying alternative methods..."
                if command_exists google-chrome; then
                    google-chrome "http://localhost:3000" &>/dev/null &
                elif command_exists firefox; then
                    firefox "http://localhost:3000" &>/dev/null &
                elif command_exists chromium-browser; then
                    chromium-browser "http://localhost:3000" &>/dev/null &
                else
                    log_warning "Could not open browser automatically. Please manually visit http://localhost:3000"
                fi
            )
            log_info "Opened browser to http://localhost:3000"
        fi
    else
        log_info "xdg-open not available. Please manually visit http://localhost:3000 in your browser."
    fi
}

# Function to display setup guidance for vLLM and Flowise
display_setup_guidance() {
    echo
    echo -e "${GREEN}=== FLOWISE AND vLLM SETUP GUIDE ===${NC}"
    echo
    echo -e "${YELLOW}USING THE AUTO-CREATED CHATFLOW:${NC}"
    echo "1. Go to http://localhost:3000 and log in with the admin account from docker/flowise.env"
    echo "   (on a fresh install, the first visit prompts you to create the admin account)"
    echo "2. Open the '${CHATFLOW_NAME}' chatflow under 'Chatflows' and click the chat icon to test it."
    echo "   It is pre-wired as: ChatOpenAI -> Conversation Chain (+ Buffer Memory)."
    echo
    echo -e "${YELLOW}HOW IT IS CONFIGURED (if you want to rebuild it manually):${NC}"
    echo "1. Add a 'ChatOpenAI' node, then in its additional params set:"
    echo "   - BasePath:  ${VLLM_BASE_URL}"
    echo "   - Model Name: ${VLLM_MODEL_NAME}"
    echo "   - Connect Credential: any OpenAI credential (vLLM ignores the API key)"
    echo "2. Add 'Conversation Chain' and 'Buffer Memory' nodes."
    echo "3. Connect ChatOpenAI -> Conversation Chain (Chat Model) and"
    echo "   Buffer Memory -> Conversation Chain (Memory). Save and test."
    echo
    echo -e "${YELLOW}NOTE ON THE vLLM MODEL:${NC}"
    echo "The Model Name must match the vllm container's --model argument exactly."
    echo "Current full-install default: ${VLLM_MODEL_NAME} (see docker/docker-compose.full.yml)."
    echo
    echo -e "${BLUE}For more help, visit: https://docs.flowiseai.com/ and https://docs.vllm.ai/${NC}"
    echo
}

# --- Main Script ---

# Ensure jq is installed
ensure_jq_installed

# Wait for Flowise to be ready
log_info "Waiting for Flowise to be ready (checking ping endpoint)..."
MAX_WAIT=120 # Wait up to 2 minutes
WAIT_INTERVAL=5
elapsed=0
while ! curl --output /dev/null --silent --fail http://localhost:3000/api/v1/ping; do
    printf '.'
    sleep $WAIT_INTERVAL
    elapsed=$((elapsed + WAIT_INTERVAL))
    if [ $elapsed -ge $MAX_WAIT ]; then
        log_error "Flowise ping endpoint did not become available within $MAX_WAIT seconds."
        exit 1
    fi
done
echo # Newline after dots
log_success "Flowise is up and running!"

# Authenticate against Flowise (register admin account on first run, then log in)
if ! load_admin_credentials || ! flowise_login; then
    log_warning "Cannot authenticate with Flowise. Please create the admin account and chatflow manually at http://localhost:3000"
    display_setup_guidance
    exit 1
fi

# Build a fully-wired vLLM chatflow (ChatOpenAI -> Conversation Chain + Buffer
# Memory) from the versioned flowData template, pointed at the local vLLM endpoint.
if [ ! -f "$FLOWDATA_TEMPLATE" ]; then
    log_error "flowData template not found at $FLOWDATA_TEMPLATE"
    log_warning "Cannot create chatflow automatically. Please create one manually at http://localhost:3000"
    display_setup_guidance
    exit 1
fi

# Create/reuse the credential the ChatOpenAI node needs (vLLM ignores the key).
if ! flowise_ensure_credential; then
    log_warning "Cannot create chatflow without a credential. Please configure one manually at http://localhost:3000"
    display_setup_guidance
    exit 1
fi

# Skip creation if a chatflow with this name already exists (idempotent re-runs).
EXISTING_CHATFLOW_ID=$(flowise_find_chatflow)
if [ -n "$EXISTING_CHATFLOW_ID" ]; then
    log_success "Chatflow '${CHATFLOW_NAME}' already exists (ID: ${EXISTING_CHATFLOW_ID})."
    log_info "Open it at http://localhost:3000/chatflows/$EXISTING_CHATFLOW_ID"
    display_setup_guidance
    log_info "Flowise UI: http://localhost:3000"
    log_success "Setup process completed."
    open_browser_prompt
    exit 0
fi

log_info "Creating vLLM chatflow via API (model: ${VLLM_MODEL_NAME}, endpoint: ${VLLM_BASE_URL})..."

# Inject the credential id, vLLM base path and model name into the ChatOpenAI node,
# then emit just {nodes, edges, viewport} as the flowData object.
FLOWDATA=$(jq -c \
  --arg cred "$CREDENTIAL_ID" \
  --arg base "$VLLM_BASE_URL" \
  --arg model "$VLLM_MODEL_NAME" '
  .nodes |= map(
    if .data.name == "chatOpenAI" then
        .data.credential = $cred
        | .data.inputs.credential = $cred
        | .data.inputs.basepath = $base
        | .data.inputs.modelName = $model
    else . end)
  | {nodes: .nodes, edges: .edges, viewport: .viewport}' "$FLOWDATA_TEMPLATE")

if [ -z "$FLOWDATA" ]; then
    log_error "Failed to render flowData from template."
    display_setup_guidance
    exit 1
fi

# Construct the POST payload. flowData must be a STRING containing JSON — Flowise
# runs JSON.parse() on it, so passing a raw JSON object fails with HTTP 500
# ("[object Object]" is not valid JSON). Using jq --arg encodes it as a string.
# deployed:true makes it immediately callable via the prediction API.
CREATE_PAYLOAD=$(jq -n \
  --arg name "$CHATFLOW_NAME" \
  --arg description "Conversation chain backed by the local vLLM server (${VLLM_MODEL_NAME})" \
  --arg flowData "$FLOWDATA" \
  '{name: $name, description: $description, flowData: $flowData, deployed: true, isPublic: false, type: "CHATFLOW"}')

# Create the chatflow. Authenticated internal call: the session cookies captured
# at login, the internal-request marker, and the forwarded-proto header (so the
# session is honored over http) are all required.
HTTP_RESPONSE=$(curl --silent --write-out "\n%{http_code}" --request POST "$FLOWISE_URL/api/v1/chatflows" \
  --header "Content-Type: application/json" \
  --header "x-request-from: internal" \
  --header "$FLOWISE_XFP_HEADER" \
  --header "Cookie: $FLOWISE_COOKIES" \
  --data "$CREATE_PAYLOAD")

# Extract status code and response body
HTTP_STATUS=$(echo "$HTTP_RESPONSE" | tail -n1)
RESPONSE=$(echo "$HTTP_RESPONSE" | sed '$d')

# Log the response
echo "Create Chatflow Response:" >> "$LOG_FILE"
echo "$RESPONSE" | jq . >> "$LOG_FILE" 2>&1 || echo "$RESPONSE" >> "$LOG_FILE" # Log formatted JSON or raw response
echo "HTTP Status: $HTTP_STATUS" >> "$LOG_FILE"

# Check if request was successful
if [[ "$HTTP_STATUS" -ne 200 && "$HTTP_STATUS" -ne 201 ]]; then
    log_error "Failed to create vLLM chatflow. HTTP status: $HTTP_STATUS"
    log_error "Response: $RESPONSE"
    log_warning "Cannot create chatflow automatically. Please create one manually at http://localhost:3000"
else
    # Extract the chatflow ID using jq for safety
    CHATFLOW_ID=$(echo "$RESPONSE" | jq -r '.id // empty')

    if [ -z "$CHATFLOW_ID" ]; then
        log_warning "Created chatflow but couldn't extract ID from response."
        log_info "You can now open it at http://localhost:3000"
    else
        log_success "Created vLLM chatflow '${CHATFLOW_NAME}' with ID: $CHATFLOW_ID"
        log_info "Test it at http://localhost:3000/chatflows/$CHATFLOW_ID (model: ${VLLM_MODEL_NAME})"
    fi
fi

# Display guidance for manual setup
display_setup_guidance

log_info "Flowise UI: http://localhost:3000"
log_success "Setup process completed."

open_browser_prompt

# Log script end
echo "----------------------------------------" >> "$LOG_FILE"
echo "Script finished at $(date)" >> "$LOG_FILE"
echo "----------------------------------------" >> "$LOG_FILE"

exit 0 # Exit with success code