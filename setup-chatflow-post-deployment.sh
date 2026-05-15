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

# Function to get API key from Flowise
get_api_key() {
    log_info "Attempting to retrieve API key from Flowise container..."
    # Increased timeout for docker exec, just in case
    DOCKER_API_KEY=$(timeout 10s docker exec flowise cat /usr/src/.flowise/api.json 2>/dev/null)
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
         log_warning "docker exec command failed or timed out (exit code $exit_code)."
    elif [ ! -z "$DOCKER_API_KEY" ]; then
        # Validate if it's JSON before trying to parse
        if echo "$DOCKER_API_KEY" | jq -e . > /dev/null 2>&1; then
            API_KEY=$(echo "$DOCKER_API_KEY" | jq -r '.[0].apiKey // empty' | head -n 1) # Assumes the key is in the first element of an array
            if [ ! -z "$API_KEY" ]; then
                log_success "Successfully extracted API key from container: ${API_KEY:0:5}..."
                # Sanity check the key format (basic length check)
                if [ ${#API_KEY} -gt 10 ]; then
                     return 0
                else
                     log_warning "Extracted API key seems too short. Proceeding with caution."
                     return 0 # Still return success, but log warning
                fi
            else
                 log_warning "Extracted JSON from container, but couldn't find apiKey field."
            fi
        else
             log_warning "Content read from api.json is not valid JSON. Content: $DOCKER_API_KEY"
        fi
    else
         log_warning "api.json file inside container is empty or could not be read."
    fi

    log_warning "Could not reliably extract API key from container. Using predefined key 'miniprem_demo_secret_key'."
    API_KEY="miniprem_demo_secret_key" # Fallback key
    return 0
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
    echo -e "${YELLOW}CREATING A CHATFLOW WITH vLLM:${NC}"
    echo "1. Go to http://localhost:3000 and log in (default: user/password)"
    echo "2. Click 'Chatflows' in the sidebar and then 'Create New'"
    echo
    echo -e "${YELLOW}TO USE vLLM IN YOUR CHATFLOW:${NC}"
    echo "1. Search for 'OpenAI Compatible' or 'Custom LLM' in the nodes panel"
    echo "2. Configure the node with:"
    echo "   - Base URL: http://vllm:8000/v1"
    echo "   - Model: gemma-4-E4B-it (or your chosen model)"
    echo
    echo -e "${YELLOW}DOWNLOADING MODELS IN vLLM:${NC}"
    echo "vLLM will automatically download the model the first time it is requested."
    echo "To pre-download the model, you can run:"
    echo "docker exec -it vllm python3 -m vllm.entrypoints.openai.api_server --model facebook/opt-125m"
    echo
    echo -e "${YELLOW}CONNECTING NODES:${NC}"
    echo "1. Add 'Chat Message' and 'Memory' nodes"
    echo "2. Connect them to create a conversation flow"
    echo "3. Save and test your chatflow"
    echo
    echo -e "${BLUE}For more help, visit: https://vllm.readthedocs.io/en/latest/${NC}"
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

# Get authorization token
get_api_key
log_info "Using API key: ${API_KEY:0:5}..." # Show only the beginning of the key

# Create a simple empty chatflow
log_info "Creating an empty chatflow via API..."

# Valid flowData with empty nodes and edges
EMPTY_FLOWDATA=$(cat <<EOF
{
  "nodes": [],
  "edges": [],
  "viewport": {"x": 0, "y": 0, "zoom": 1}
}
EOF
)

# Construct the POST payload JSON string
CREATE_PAYLOAD=$(cat <<EOF
{
  "name": "My vLLM Chatflow",
  "description": "An empty chatflow for vLLM integration",
  "flowData": $(echo "$EMPTY_FLOWDATA" | jq -c .),
  "deployed": false,
  "isPublic": false,
  "type": "CHATFLOW"
}
EOF
)

# Create the chatflow
HTTP_RESPONSE=$(curl --silent --write-out "\n%{http_code}" --request POST "http://localhost:3000/api/v1/chatflows" \
  --header "Content-Type: application/json" \
  --header "Authorization: Bearer ${API_KEY}" \
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
    log_error "Failed to create empty chatflow. HTTP status: $HTTP_STATUS"
    log_error "Response: $RESPONSE"
    log_warning "Cannot create chatflow automatically. Please create one manually at http://localhost:3000"
else
    # Extract the chatflow ID using jq for safety
    CHATFLOW_ID=$(echo "$RESPONSE" | jq -r '.id // empty')

    if [ -z "$CHATFLOW_ID" ]; then
        log_warning "Created chatflow but couldn't extract ID from response."
        log_info "You can now manually configure a chatflow at http://localhost:3000"
    else
        log_success "Created empty chatflow with ID: $CHATFLOW_ID"
        log_info "You can now configure this chatflow at http://localhost:3000/chatflows/$CHATFLOW_ID"
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