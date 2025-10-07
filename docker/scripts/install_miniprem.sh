#!/bin/bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_ROOT/scripts/docker.sh"
source "$PROJECT_ROOT/scripts/logging.sh"
source "$PROJECT_ROOT/scripts/audio.sh"
source "$PROJECT_ROOT/scripts/hash.sh"
source "$PROJECT_ROOT/scripts/environment.sh"
source "$PROJECT_ROOT/scripts/prerequisites.sh"

# Enable debugging
#set -x

# Enable error handling
set -e
set -o pipefail

# Global variables for cleanup tracking
CLEANUP_NEEDED=false
CONTAINERS_STARTED=()
INSTALLATION_MARKER_CREATED=false
INSTALLATION_START_TIME=$(date +%s)

# Cleanup handler - runs on script exit (success or failure)
cleanup_on_error() {
    local exit_code=$?

    # Only run cleanup if script failed (non-zero exit)
    if [ $exit_code -ne 0 ] && [ "$CLEANUP_NEEDED" = true ]; then
        echo ""
        echo "============================================"
        echo "Installation failed! Running cleanup..."
        echo "============================================"
        echo ""

        # Stop any containers that were started during this run
        if [ ${#CONTAINERS_STARTED[@]} -gt 0 ]; then
            echo "Stopping partially started containers..."
            for container in "${CONTAINERS_STARTED[@]}"; do
                if docker ps -q -f name="$container" > /dev/null 2>&1; then
                    echo "  Stopping $container..."
                    docker stop "$container" > /dev/null 2>&1 || true
                fi
            done
        fi

        # Remove installation marker if it was created recently (within last 5 minutes)
        if [ "$INSTALLATION_MARKER_CREATED" = true ]; then
            local current_time=$(date +%s)
            local elapsed=$((current_time - INSTALLATION_START_TIME))

            if [ $elapsed -lt 300 ]; then  # 5 minutes = 300 seconds
                local marker_file="$PROJECT_ROOT/.miniprem_install_type"
                if [ -f "$marker_file" ]; then
                    echo "Removing installation marker (installation was incomplete)..."
                    rm -f "$marker_file"
                fi
            fi
        fi

        echo ""
        echo "============================================"
        echo "Cleanup completed. System restored to pre-installation state."
        echo ""
        echo "Common issues and solutions:"
        echo "  1. Docker not running: Start Docker Desktop and retry"
        echo "  2. Insufficient disk space: Free up space and retry"
        echo "  3. Port conflicts: Check if ports are in use with 'netstat -an | grep LISTEN'"
        echo "  4. Permission issues: Ensure user is in 'docker' group"
        echo ""
        echo "For detailed logs, check: docker logs <container_name>"
        echo "============================================"
    fi

    # Always restore terminal state
    stty sane 2>/dev/null || true
}

# Register cleanup handler for EXIT signal
trap cleanup_on_error EXIT

# Function to mark cleanup as needed (call when starting containers)
enable_cleanup() {
    CLEANUP_NEEDED=true
}

# Function to register a started container for potential cleanup
register_container() {
    local container_name=$1
    CONTAINERS_STARTED+=("$container_name")
}

# Function to mark installation marker as created
mark_installation_marker_created() {
    INSTALLATION_MARKER_CREATED=true
}

usage() {
    echo -e $WHITE
    cat <<EOF
$(basename "$0") [--platform-address <UneeQ platform address>] [--platform-key <UneeQ platform API key>] [--tenant <Tenant ID>] [--azure-region <Azure region>] [--azure-speech-key <Azure speech key>] [--renny-image <Docker image name for Renny>] [h]
Install and configure Renny digital human with internal speech processing on a laptop/kiosk

Options:
    -h: usage
EOF
    echo -e $NC
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate cloud service
validate_cloud_service() {
    local address=$1
    local port=$2

    # Input validation for address (hostname or IP)
    if [[ ! "$address" =~ ^[a-zA-Z0-9.-]+$ ]]; then
        error "Invalid address format: $address"
        fatal "Address must contain only alphanumeric characters, dots, and hyphens"
    fi

    # Input validation for port (must be numeric, 1-65535)
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        error "Invalid port number: $port"
        fatal "Port must be a number between 1 and 65535"
    fi

    # Perform a curl request to the given address and port (using validated inputs)
    response=$(curl -s -o /dev/null -w "%{http_code}" "http://$address:$port")

    # Check if the response code is 200 (OK)
    if [ "$response" -eq 200 ]; then
        echo "Success: Service at $address:$port is reachable."
    else
        echo "Error: Service at $address:$port is not reachable. HTTP status code: $response"
        exit 1
    fi
}

extract_url_components() {
    local url=$1
    local protocol=$(echo $url | sed -n 's,^\(.*://\).*,\1,p')
    local address=$(echo $url | sed -n 's,.*://\([^:/]*\).*,\1,p')
    local port=$(echo $url | sed -n 's,.*://[^:/]*:\([0-9]*\).*,\1,p')
    local path=$(echo $url | sed -n 's,.*://[^/]*/\(.*\),/\1,p')

    # If port is not found, set it to an empty string
    if [[ -z $port ]]; then
        port="443"
    fi

    echo "$protocol" "$address" "$port" "$path"
}

# Function to prompt for installation type
prompt_for_install_type() {
    INSTALL_TYPE=""
    echo "Select installation type:"
    echo "1) Default Install (Renny with internal speech processing only)"
    echo "2) Full Install (All services: Renny with internal speech, Flowise, vLLM, Grafana, Prometheus, RIME, Whisper etc.)"
    read -p "Enter choice [1-2]: " install_choice
    if [[ "$install_choice" == "1" ]]; then
        INSTALL_TYPE="default"
        echo "default" > "$PROJECT_ROOT/.miniprem_install_type"
        mark_installation_marker_created
    elif [[ "$install_choice" == "2" ]]; then
        INSTALL_TYPE="full"
        echo "full" > "$PROJECT_ROOT/.miniprem_install_type"
        mark_installation_marker_created
    else
        echo "Invalid choice, exiting."
        exit 1
    fi
}

# Function to configure Eleven Labs
configure_eleven_labs() {
    USE_ELEVEN_LABS=""
    echo -e "\nWould you like to use Eleven Labs for text-to-speech?"
    echo "1) Yes"
    echo "2) No"
    read -p "Enter choice [1-2]: " eleven_choice
    if [[ "$eleven_choice" == "1" ]]; then
        USE_ELEVEN_LABS="yes"
        echo "yes" > "$PROJECT_ROOT/.miniprem_eleven_labs"
        # Prompt for Eleven Labs API key
        read -p "Enter your Eleven Labs API key: " ELEVEN_LABS_API_KEY
        if [ -z "$ELEVEN_LABS_API_KEY" ]; then
            warning "No Eleven Labs API key provided. Eleven Labs services may not function correctly."
        else
            # Update the environment variable
            update_env_variable "ELEVEN_LABS_API_KEY" "\"$ELEVEN_LABS_API_KEY\""
            # Set default values for other Eleven Labs parameters
            update_env_variable "ELEVEN_LABS_MODEL_ID" "\"eleven_flash_v2_5\""
            update_env_variable "ELEVEN_LABS_OPTIMIZE_LATENCY_LEVEL" "1"
            update_env_variable "ELEVEN_LABS_SIMILARITY_BOOST" "0.5"
            update_env_variable "ELEVEN_LABS_STABILITY" "0.5"
            success "$CHECKMARK Eleven Labs API key configured"
        fi
    else
        USE_ELEVEN_LABS="no"
        echo "no" > "$PROJECT_ROOT/.miniprem_eleven_labs"
        # Clear any existing Eleven Labs environment variables
        update_env_variable "ELEVEN_LABS_API_KEY" "\"\""
        update_env_variable "ELEVEN_LABS_MODEL_ID" "\"\""
        update_env_variable "ELEVEN_LABS_OPTIMIZE_LATENCY_LEVEL" "\"\""
        update_env_variable "ELEVEN_LABS_SIMILARITY_BOOST" "\"\""
        update_env_variable "ELEVEN_LABS_STABILITY" "\"\""
        info "Eleven Labs integration disabled"
    fi
    
    # Check and prompt for required env variables (after USE_ELEVEN_LABS has been set)
    check_and_prompt_required_env_vars
}

# Function to pull necessary Docker images
pull_required_images() {

    DOCKER_CMD="sudo docker"

    # Only pull images for selected services
    if [ "$INSTALL_TYPE" = "full" ]; then
        # Pull common images
        info "Pulling basic services images..."
        $DOCKER_CMD pull prom/prometheus:v2.45.0
        $DOCKER_CMD pull grafana/grafana:10.2.0
        $DOCKER_CMD pull redis:latest
        $DOCKER_CMD pull vllm/vllm-openai:v0.2.7
        
        # Pull TTS-specific images based on selection
        if [ "$TTS_PROVIDER" = "rime" ]; then
            # RIME credentials and images are handled in setup_rime_credentials
            setup_rime_credentials
        fi
    else
        # Only pull images for Renny with internal speech processing
        info "Pulling Renny images..."
        $DOCKER_CMD pull facemeproduction/renny:0.484-37235
        
        # If using RIME in default install, pull RIME images
        if [ "$TTS_PROVIDER" = "rime" ]; then
            setup_rime_credentials
        fi
    fi
}


check_wss_service() {
    local url=$1

    # Extract the protocol, address, port, and path from the URL
    read protocol address port path < <(extract_url_components "$url")
   
    # Default port if not specified
    if [[ -z $port ]]; then
        if [[ $protocol == "wss://" ]]; then
            port=443
        else
            port=80
        fi
    fi

    # Generate a valid Sec-WebSocket-Key
    local valid_key=$(openssl rand -base64 16)

    # Use socat to test the WebSocket connection
    if [[ $protocol == "wss://" ]]; then
        response=$(echo -e "GET $path HTTP/1.1\r\nHost: $address\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: $valid_key\r\nSec-WebSocket-Version: 13\r\n\r\n" | socat -t 5 - SSL:$address:$port,verify=0 2>&1)
    else
        response=$(echo -e "GET $path HTTP/1.1\r\nHost: $address\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: $valid_key\r\nSec-WebSocket-Version: 13\r\n\r\n" | socat -t 5 - TCP:$address:$port 2>&1)
    fi

    # Check if the response contains "101 Switching Protocols"
    if [[ $response == *"101 Switching Protocols"* || $response == *"200 OK"* ]]; then
        success "$CHECKMARK Service at $url is reachable."
    else
        fatal "$CROSS Service at $url is not reachable."
    fi
}

# Function to prompt for a value with a default, only if value is not already set
check_and_prompt_for_value() {
    local prompt_message=$1
    local current_value=$2
    local input_value=$current_value

    if [ -z "$current_value" ]; then
        read -p "$prompt_message: " input_value
        if [ -z "$input_value" ]; then
            echo ""
            return 1  # Return failure if no value provided
        fi
    fi

    echo "$input_value"
}

# Function to ensure DHOP_ADDRESS starts with ws:// and ends with suffix (endpoint) provided
format_dhop_address() {
    local address=$1
    local suffix=$2

    # Check if the address contains a protocol
    if [[ ! $address =~ ^(ws://|wss://) ]]; then
        # Add ws:// prefix if missing
        address="wss://$address"
    fi

    # Add specified suffix if missing
    if [[ ! $address =~ ${suffix}$ ]]; then
        address="$address$suffix"
    fi

    echo "$address"
}

# Function to ensure URL starts with http:// and ends with suffix (endpoint) provided
format_url_address() {
    local address=$1
    local suffix=$2

    # Return empty if the address is empty
    if [[ -z $address ]]; then
        echo ""
        return
    fi

    # Check if the address contains a port
    if [[ $address =~ :([0-9]+) ]]; then
        port=${BASH_REMATCH[1]}
        if [[ $port -eq 443 ]]; then
            # Add https:// prefix if missing
            if [[ ! $address =~ ^https:// ]]; then
                address="https://$address"
            fi
        else
            # Add http:// prefix if missing
            if [[ ! $address =~ ^http:// ]] && [[ ! $address =~ ^https:// ]]; then
                address="http://$address"
            fi
        fi
    else
        # Add http:// prefix if missing
        if [[ ! $address =~ ^http:// ]] && [[ ! $address =~ ^https:// ]]; then
            address="http://$address"
        fi
    fi

    # Add specified suffix if missing
    if [[ ! $address =~ ${suffix}$ ]]; then
        address="$address$suffix"
    fi

    echo "$address"
}

check_cloud_services() {
    local dhop_address=$1
    local dhop_ps_address=$2

    log_section "Check Cloud Service Accessibility"

    # Check if the DHOP address is reachable
    check_wss_service "$dhop_address"

    # Check if the DHOP pixel streaming address is reachable
    check_wss_service "$dhop_ps_address"
}

# Function to prompt for TTS provider selection
select_tts_provider() {
    log_section "Text-to-Speech Provider Selection"
    
    echo "Select your preferred text-to-speech provider:"
    echo "1) Azure (Microsoft TTS)"
    echo "2) Eleven Labs"
    echo "3) RIME"
    read -p "Enter choice [1-3]: " tts_choice
    
    case "$tts_choice" in
        1)
            TTS_PROVIDER="azure"
            echo "azure" > "$PROJECT_ROOT/.miniprem_tts_provider"
            info "Azure TTS selected"
            ;;
        2)
            TTS_PROVIDER="elevenlabs"
            echo "elevenlabs" > "$PROJECT_ROOT/.miniprem_tts_provider"
            info "Eleven Labs TTS selected"
            ;;
        3)
            TTS_PROVIDER="rime"
            echo "rime" > "$PROJECT_ROOT/.miniprem_tts_provider"
            info "RIME TTS selected"
            ;;
        *)
            warning "Invalid choice, defaulting to Azure TTS"
            TTS_PROVIDER="azure"
            echo "azure" > "$PROJECT_ROOT/.miniprem_tts_provider"
            ;;
    esac
}

# Modified function to configure Azure TTS
configure_azure_tts() {
    if [ "$TTS_PROVIDER" != "azure" ]; then
        # Clear Azure environment variables if not using Azure
        update_env_variable "AZURE_REGION" "\"\""
        update_env_variable "AZURE_SPEECH" "\"\""
        update_env_variable "AZURE_SPEECH_KEY" "\"\""
        return 0
    fi
    
    log_section "Configure Azure TTS"
    
    # Check if Azure region is already set
    local AZURE_REGION_VAL=$(read_env_variable "AZURE_REGION")
    if [ -z "$AZURE_REGION_VAL" ]; then
        read -p "Enter your Azure region (e.g., eastus): " AZURE_REGION
        if [ -z "$AZURE_REGION" ]; then
            warning "No Azure region provided. Azure TTS may not function correctly."
        else
            update_env_variable "AZURE_REGION" "\"$AZURE_REGION\""
            success "$CHECKMARK Azure region configured"
        fi
    else
        AZURE_REGION="$AZURE_REGION_VAL"
        success "$CHECKMARK Azure region already configured"
    fi

    # Check if Azure speech key is already set
    local AZURE_SPEECH_KEY_VAL=$(read_env_variable "AZURE_SPEECH_KEY")
    if [ -z "$AZURE_SPEECH_KEY_VAL" ]; then
        read -p "Enter your Azure speech key: " AZURE_SPEECH_KEY
        if [ -z "$AZURE_SPEECH_KEY" ]; then
            warning "No Azure speech key provided. Azure TTS may not function correctly."
        else
            update_env_variable "AZURE_SPEECH_KEY" "\"$AZURE_SPEECH_KEY\""
            update_env_variable "AZURE_SPEECH" "\"$AZURE_SPEECH_KEY\""
            success "$CHECKMARK Azure speech key configured"
        fi
    else
        AZURE_SPEECH_KEY="$AZURE_SPEECH_KEY_VAL"
        success "$CHECKMARK Azure speech key already configured"
    fi
}

# Modified function to configure Eleven Labs
configure_eleven_labs() {
    if [ "$TTS_PROVIDER" != "elevenlabs" ]; then
        # Clear Eleven Labs environment variables if not using Eleven Labs
        update_env_variable "ELEVEN_LABS_API_KEY" "\"\""
        update_env_variable "ELEVEN_LABS_MODEL_ID" "\"\""
        update_env_variable "ELEVEN_LABS_OPTIMIZE_LATENCY_LEVEL" "\"\""
        update_env_variable "ELEVEN_LABS_SIMILARITY_BOOST" "\"\""
        update_env_variable "ELEVEN_LABS_STABILITY" "\"\""
        return 0
    fi
    
    log_section "Configure Eleven Labs TTS"
    
    # Check if Eleven Labs API key is already set
    local ELEVEN_LABS_API_KEY_VAL=$(read_env_variable "ELEVEN_LABS_API_KEY")
    if [ -z "$ELEVEN_LABS_API_KEY_VAL" ]; then
        read -p "Enter your Eleven Labs API key: " ELEVEN_LABS_API_KEY
        if [ -z "$ELEVEN_LABS_API_KEY" ]; then
            warning "No Eleven Labs API key provided. Eleven Labs services may not function correctly."
        else
            # Update the environment variable
            update_env_variable "ELEVEN_LABS_API_KEY" "\"$ELEVEN_LABS_API_KEY\""
            # Set default values for other Eleven Labs parameters
            update_env_variable "ELEVEN_LABS_MODEL_ID" "\"eleven_flash_v2_5\""
            update_env_variable "ELEVEN_LABS_OPTIMIZE_LATENCY_LEVEL" "1"
            update_env_variable "ELEVEN_LABS_SIMILARITY_BOOST" "0.5"
            update_env_variable "ELEVEN_LABS_STABILITY" "0.5"
            success "$CHECKMARK Eleven Labs API key configured"
        fi
    else
        ELEVEN_LABS_API_KEY="$ELEVEN_LABS_API_KEY_VAL"
        success "$CHECKMARK Eleven Labs API key already configured"
    fi
}

# Modified function to setup RIME credentials
setup_rime_credentials() {

    DOCKER_CMD="sudo docker"

    if [ "$TTS_PROVIDER" != "rime" ]; then
        # Clear RIME environment variables if not using RIME
        update_env_variable "RIME_API_KEY" "\"\""
        return 0
    fi
    
    log_section "Setting up RIME credentials"

    # Check if RIME_API_KEY is already set
    local RIME_API_KEY_VAL=$(read_env_variable "RIME_API_KEY")

    if [ -z "$RIME_API_KEY_VAL" ]; then
        read -p "Enter your RIME API key: " RIME_API_KEY
        if [ -z "$RIME_API_KEY" ]; then
            warning "No RIME API key provided. RIME services may not function correctly."
        else
            update_env_variable "RIME_API_KEY" "\"$RIME_API_KEY\""
            success "$CHECKMARK RIME API key configured"
        fi
    else
        RIME_API_KEY="$RIME_API_KEY_VAL"
        success "$CHECKMARK RIME API key already configured"
    fi

    # Only pull RIME images if we're using RIME
    if [ "$TTS_PROVIDER" == "rime" ]; then
        # Check if we've already authenticated with quay.io
        if $DOCKER_CMD images | grep -q "quay.io/rimelabs/api" && $DOCKER_CMD images | grep -q "quay.io/rimelabs/mistv2"; then
            success "$CHECKMARK Already have RIME Docker images, skipping quay.io login"
            return 0
        fi

        # Prompt for quay.io password for RIME images
        local RIME_QUAY_PASSWORD=""
        while [ -z "$RIME_QUAY_PASSWORD" ]; do
            read -s -p "Enter the quay.io password for RIME (rimelabs+uneeq): " RIME_QUAY_PASSWORD
            echo
            if [ -z "$RIME_QUAY_PASSWORD" ]; then
                warning "No password entered. Please provide the quay.io password for RIME."
            fi
        done

        # Login to quay.io for RIME images
        info "Logging in to quay.io for RIME images..."
        $DOCKER_CMD login -u="rimelabs+uneeq" -p="$RIME_QUAY_PASSWORD" quay.io
        $DOCKER_CMD pull quay.io/rimelabs/api:v0.0.2-20250407
        $DOCKER_CMD pull quay.io/rimelabs/mistv2:v0.0.1-20250403

        info "RIME credential setup complete"
    fi
}

# Function to update docker-compose.yml based on the selected TTS provider
update_docker_compose_for_tts() {
    local compose_file="$PROJECT_ROOT/docker/docker-compose.yml"

    # Only proceed if docker-compose.yml exists
    if [ ! -f "$compose_file" ]; then
        warning "docker-compose.yml not found, skipping TTS configuration"
        return 1
    fi
    
    # Make a backup of the original file
    cp "$compose_file" "${compose_file}.bak"
    
    info "Updating docker-compose.yml for selected TTS provider: $TTS_PROVIDER"
    
    # Handle RIME services based on selection
    if [ "$TTS_PROVIDER" = "rime" ]; then
        # Uncomment RIME services if RIME is selected
        sed -i '/^### RIME BEGIN ###/,/^### RIME END ###/s/^  # /  /' "$compose_file"
    else
        # Comment out RIME services if not selected
        sed -i '/^### RIME BEGIN ###/,/^### RIME END ###/s/^  /  # /' "$compose_file"
    fi
    
    success "$CHECKMARK docker-compose.yml updated for TTS provider: $TTS_PROVIDER"
}

# Function to update docker-compose.yml based on the selected STT backend
update_docker_compose_for_stt() {
    local compose_file="$PROJECT_ROOT/docker/docker-compose.yml"
    local stt_choice=$1

    # Only proceed if docker-compose.yml exists
    if [ ! -f "$compose_file" ]; then
        warning "docker-compose.yml not found, skipping STT configuration"
        return 1
    fi
    
    info "Updating docker-compose.yml for selected STT backend..."
    
    if [ "$stt_choice" = "1" ]; then
        # Enable Whisper, disable FastWhisper
        sed -i '/^### WHISPER BEGIN ###/,/^### WHISPER END ###/s/^  # /  /' "$compose_file"
        sed -i '/^### FASTWHISPER BEGIN ###/,/^### FASTWHISPER END ###/s/^  /  # /' "$compose_file"
    elif [ "$stt_choice" = "2" ]; then
        # Enable FastWhisper, disable Whisper
        sed -i '/^### FASTWHISPER BEGIN ###/,/^### FASTWHISPER END ###/s/^  # /  /' "$compose_file"
        sed -i '/^### WHISPER BEGIN ###/,/^### WHISPER END ###/s/^  /  # /' "$compose_file"
    elif [ "$stt_choice" = "3" ]; then
        # Disable both Whisper and FastWhisper (use UneeQ default STT)
        sed -i '/^### WHISPER BEGIN ###/,/^### WHISPER END ###/s/^  /  # /' "$compose_file"
        sed -i '/^### FASTWHISPER BEGIN ###/,/^### FASTWHISPER END ###/s/^  /  # /' "$compose_file"
    fi
    
    success "$CHECKMARK docker-compose.yml updated for STT backend"
}

# Function to get required variables from the env file based on selected provider
get_required_env_vars_from_example() {
    local example_file="$PROJECT_ROOT/docker/docker-compose.env.example"
    local all_vars=""
    
    # Get variables based on the selected TTS provider
    case "$TTS_PROVIDER" in
        "azure")
            all_vars=$(grep -E '^(AZURE_REGION|AZURE_SPEECH|AZURE_SPEECH_KEY)=$' "$example_file" | cut -d= -f1)
            ;;
        "elevenlabs")
            all_vars=$(grep -E '^ELEVEN_LABS_API_KEY=$' "$example_file" | cut -d= -f1)
            ;;
        "rime")
            all_vars=$(grep -E '^RIME_API_KEY=$' "$example_file" | cut -d= -f1)
            ;;
        *)
            # Get common variables (not related to TTS)
            all_vars=$(grep -E '^[A-Z0-9_]+=$' "$example_file" | grep -v -E '^(AZURE_|ELEVEN_LABS_|RIME_)' | cut -d= -f1)
            ;;
    esac
    
    # Add common required variables
    common_vars=$(grep -E '^(DHOP_APIKEY|DHOP_TENANTID)=$' "$example_file" | cut -d= -f1)
    echo "$all_vars"$'\n'"$common_vars" | sort | uniq
}

# Function to check and prompt for required env variables dynamically based on selected provider
check_and_prompt_required_env_vars() {
    local env_file="$PROJECT_ROOT/docker/docker-compose.env"
    local required_vars=( $(get_required_env_vars_from_example) )
    
    for var in "${required_vars[@]}"; do
        local value=$(read_env_variable "$var")
        if [[ -z "$value" ]]; then
            warning "$var is missing or empty in $env_file."
            read -p "Enter value for $var: " value
            if [[ -z "$value" ]]; then
                fatal "$var is required. Exiting."
            fi
            # Store the value in a variable instead of writing directly
            case "$var" in
                "DHOP_APIKEY") PLATFORM_KEY="$value" ;;
                "DHOP_TENANTID") TENANT_ID="$value" ;;
                "AZURE_REGION") AZURE_REGION="$value" ;;
                "AZURE_SPEECH_KEY"|"AZURE_SPEECH") AZURE_SPEECH_KEY="$value" ;;
                "ELEVEN_LABS_API_KEY") ELEVEN_LABS_API_KEY="$value" ;;
                "RIME_API_KEY") RIME_API_KEY="$value" ;;
                *) update_env_variable "$var" "$value" ;; # Only use for non-main vars
            esac
        fi
    done
    
    # Update all main variables at once using update_env_file
    update_env_file
}

# Function to update environment variables in docker-compose.env
update_env_file() {
    local env_file="$PROJECT_ROOT/docker/docker-compose.env"
    
    # Only update variables if they have values
    if [ -n "$PLATFORM_KEY" ]; then
        # Check if variable exists in file before updating
        if grep -q "^DHOP_APIKEY=" "$env_file"; then
            sed -i "s|^DHOP_APIKEY=.*|DHOP_APIKEY=$PLATFORM_KEY|" "$env_file"
        fi
    fi
    
    if [ -n "$TENANT_ID" ]; then
        if grep -q "^DHOP_TENANTID=" "$env_file"; then
            sed -i "s|^DHOP_TENANTID=.*|DHOP_TENANTID=$TENANT_ID|" "$env_file"
        fi
    fi
    
    # Only update TTS-related variables based on selected provider
    if [ "$TTS_PROVIDER" = "azure" ]; then
        if [ -n "$AZURE_REGION" ]; then
            if grep -q "^AZURE_REGION=" "$env_file"; then
                sed -i "s|^AZURE_REGION=.*|AZURE_REGION=$AZURE_REGION|" "$env_file"
            fi
        fi
        
        if [ -n "$AZURE_SPEECH_KEY" ]; then
            if grep -q "^AZURE_SPEECH_KEY=" "$env_file"; then
                sed -i "s|^AZURE_SPEECH_KEY=.*|AZURE_SPEECH_KEY=$AZURE_SPEECH_KEY|" "$env_file"
            fi
            if grep -q "^AZURE_SPEECH=" "$env_file"; then
                sed -i "s|^AZURE_SPEECH=.*|AZURE_SPEECH=$AZURE_SPEECH_KEY|" "$env_file"
            fi
        fi
    elif [ "$TTS_PROVIDER" = "elevenlabs" ]; then
        # If we have Eleven Labs credentials, update those
        if [ -n "$ELEVEN_LABS_API_KEY" ]; then
            if grep -q "^ELEVEN_LABS_API_KEY=" "$env_file"; then
                sed -i "s|^ELEVEN_LABS_API_KEY=.*|ELEVEN_LABS_API_KEY=$ELEVEN_LABS_API_KEY|" "$env_file"
            fi
        fi
    elif [ "$TTS_PROVIDER" = "rime" ]; then
        # If we have RIME credentials, update those
        if [ -n "$RIME_API_KEY" ]; then
            if grep -q "^RIME_API_KEY=" "$env_file"; then
                sed -i "s|^RIME_API_KEY=.*|RIME_API_KEY=$RIME_API_KEY|" "$env_file"
            fi
        fi
    fi
}

# Function to ensure docker-compose.env exists by copying from example if needed
ensure_env_file_exists() {
    local env_file="$PROJECT_ROOT/docker/docker-compose.env"
    local example_file="$PROJECT_ROOT/docker/docker-compose.env.example"

    # Use stat for more reliable file existence checking
    if ! stat "$env_file" > /dev/null 2>&1; then
        # Example file must exist
        if [ -f "$example_file" ]; then
            info "Environment file not found, creating from example."

            # Attempt to copy with error handling
            if ! cp "$example_file" "$env_file"; then
                error "Failed to copy $example_file to $env_file"
                fatal "Check disk space and permissions in $PROJECT_ROOT/docker/"
            fi

            # Verify the copied file is readable and non-empty
            if [ ! -r "$env_file" ] || [ ! -s "$env_file" ]; then
                error "Created $env_file is not readable or empty"
                rm -f "$env_file"  # Clean up invalid file
                fatal "File creation verification failed. Check permissions and disk space."
            fi

            success "$CHECKMARK Created $env_file from $example_file"
        else
            fatal "Example environment file $example_file not found."
        fi
    else
        info "Environment file already exists at $env_file"
    fi
}

# Function to check if all required values are provided
check_all_values_provided() {
    local missing=0

    # Debug information
    info "Checking configuration values..."
    info "PLATFORM_ADDRESS: ${PLATFORM_ADDRESS:-'Not set'}"
    info "PLATFORM_KEY: ${PLATFORM_KEY:+'Set (value hidden)'}"
    info "TENANT_ID: ${TENANT_ID:-'Not set'}"
    info "RENNY_IMAGE: ${RENNY_IMAGE:-'Not set'}"
    
    # Check TTS-specific variables based on provider
    if [ "$TTS_PROVIDER" = "azure" ]; then
        info "AZURE_REGION: ${AZURE_REGION:-'Not set'}"
        info "AZURE_SPEECH_KEY: ${AZURE_SPEECH_KEY:+'Set (value hidden)'}"
    elif [ "$TTS_PROVIDER" = "elevenlabs" ]; then
        ELEVEN_LABS_API_KEY=$(read_env_variable "ELEVEN_LABS_API_KEY")
        info "ELEVEN_LABS_API_KEY: ${ELEVEN_LABS_API_KEY:+'Set (value hidden)'}"
    elif [ "$TTS_PROVIDER" = "rime" ]; then
        RIME_API_KEY=$(read_env_variable "RIME_API_KEY")
        info "RIME_API_KEY: ${RIME_API_KEY:+'Set (value hidden)'}"
    fi

    if [ -z "$PLATFORM_KEY" ]; then
        warning "UneeQ platform API key is missing"
        missing=1
    fi

    if [ -z "$TENANT_ID" ]; then
        warning "Tenant ID is missing"
        missing=1
    fi
    
    # Check TTS-specific requirements
    if [ "$TTS_PROVIDER" = "azure" ]; then
        if [ -z "$AZURE_REGION" ]; then
            warning "Azure region is missing"
            missing=1
        fi

        if [ -z "$AZURE_SPEECH_KEY" ]; then
            warning "Azure speech key is missing"
            missing=1
        fi
    elif [ "$TTS_PROVIDER" = "elevenlabs" ]; then
        ELEVEN_LABS_API_KEY=$(read_env_variable "ELEVEN_LABS_API_KEY")
        if [ -z "$ELEVEN_LABS_API_KEY" ]; then
            warning "Eleven Labs API key is missing"
            missing=1
        fi
    elif [ "$TTS_PROVIDER" = "rime" ]; then
        RIME_API_KEY=$(read_env_variable "RIME_API_KEY")
        if [ -z "$RIME_API_KEY" ]; then
            warning "RIME API key is missing"
            missing=1
        fi
    fi

    if [ -z "$RENNY_IMAGE" ]; then
        warning "Renny image name is missing"
        missing=1
    fi
        
    if [ $missing -eq 0 ]; then
        return 0  # All values are present
    else
        return 1  # Some values are missing
    fi
}

start_miniprem() {
    log_section "Starting Miniprem"

    # Enable cleanup tracking before starting any services
    enable_cleanup

    DOCKER_CMD="sudo docker compose"

    if [ "$INSTALL_TYPE" = "full" ]; then
        # Stop any local Redis instances that might be running
        info "Checking for local Redis instances..."
        if command -v lsof >/dev/null 2>&1; then
            REDIS_PROCESS=$(lsof -i :6379 -sTCP:LISTEN 2>/dev/null)
        else
            REDIS_PROCESS=$(ss -ltnp "sport = :6379" 2>/dev/null)
        fi

        if [ -n "$REDIS_PROCESS" ]; then
            info "Found Redis running on port 6379, attempting to stop it..."
            
            # Check for systemd service
            if systemctl is-active --quiet redis-server 2>/dev/null; then
                info "Stopping redis-server.service..."
                sudo systemctl stop redis-server >/dev/null 2>&1
            elif systemctl is-active --quiet redis 2>/dev/null; then
                info "Stopping redis.service..."
                sudo systemctl stop redis >/dev/null 2>&1
            else
                warning "Redis is running but not managed by systemd, please stop it manually if you encounter port conflicts"
            fi
        else
            info "No local Redis instances found running on port 6379"
        fi

        # Only start vLLM for full installation
        # First, ensure vLLM volume directory exists and has correct permissions
        info "Preparing vLLM volume directory..."
        if [ ! -d "$PROJECT_ROOT/docker/vllm_data" ]; then
            mkdir -p "$PROJECT_ROOT/docker/vllm_data"

            # Set secure permissions: rwxr-xr-x (755)
            # Owner: full access, Group/Others: read and execute only
            chmod 755 "$PROJECT_ROOT/docker/vllm_data"

            # Verify permissions were set correctly (cross-platform compatible)
            if command -v stat >/dev/null 2>&1; then
                local actual_perms=$(stat -f '%A' "$PROJECT_ROOT/docker/vllm_data" 2>/dev/null || stat -c '%a' "$PROJECT_ROOT/docker/vllm_data" 2>/dev/null)
                if [ "$actual_perms" != "755" ]; then
                    warning "Failed to set secure permissions on vLLM data directory (got $actual_perms instead of 755)"
                fi
            fi

            info "vLLM data directory created with secure permissions (755)"
        fi

        # First, start just vLLM since it needs significant GPU memory
        info "Starting vLLM service first..."
        info "Note: Initial startup may fail as the model needs to be downloaded. This is expected."
        $DOCKER_CMD $COMPOSE_FILES up -d vllm
        if [ $? -ne 0 ]; then
            warning "vLLM service failed to start - this is expected as the model needs to be downloaded"
        fi
        
        # Prepare the model while GPU is clean
        prepare_vllm_model
        
        # Now start other services EXCEPT A2F and TTS-specific ones
        info "Starting other services..."
        # Use the correct whisper service based on user's choice
        local whisper_service="whisper"
        if [[ "$stt_choice" == "2" ]]; then
            whisper_service="fastwhisper"
        fi
        
        # Define services to start based on TTS provider
        local tts_services=""
        if [ "$TTS_PROVIDER" = "rime" ]; then
            tts_services="rime-model rime-api"
        fi
        
        $DOCKER_CMD $COMPOSE_FILES up -d \
            miniprem-monitor redis grafana prometheus \
            $tts_services flowise $whisper_service
        if [ $? -ne 0 ]; then
            fatal "Failed to start support services"
        fi
    else
        # Default install: start monitor for container monitoring
        info "Starting MiniPrem Monitor for container monitoring..."
        $DOCKER_CMD $COMPOSE_FILES up -d miniprem-monitor
        if [ $? -ne 0 ]; then
            warning "Failed to start MiniPrem Monitor"
        fi

        # If using RIME in default install, start the RIME services
        if [ "$TTS_PROVIDER" = "rime" ]; then
            info "Starting RIME services..."
            $DOCKER_CMD $COMPOSE_FILES up -d rime-model rime-api
            if [ $? -ne 0 ]; then
                warning "Failed to start RIME services"
            fi
        fi
    fi

    # Start Renny with internal speech processing (required for both installation types)
    info "Starting Renny digital human service with internal speech processing..."
    $DOCKER_CMD $COMPOSE_FILES up -d renny
    if [ $? -ne 0 ]; then
        fatal "Failed to start Renny service"
    fi

    success "$CHECKMARK MiniPrem services started successfully"
}

# Function to check GPU memory usage periodically for monitoring progress
check_gpu_usage() {
    if command_exists nvidia-smi; then
        nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader
    else
        echo "GPU monitoring not available (nvidia-smi not found)"
    fi
}

# Function to display spinner with progress message
show_progress_spinner() {
    local message=$1
    local pid=$2
    local delay=0.5
    local spinner="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    local i=0
    local status_update_interval=15 # Show status update every 15 seconds
    local counter=0

    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) % ${#spinner} ))
        printf "\r${message} ${spinner:$i:1} "

        # Every 15 seconds, show GPU status
        if [ $counter -eq $status_update_interval ]; then
            printf "\n"
            date "+%H:%M:%S - Checking GPU status..."
            check_gpu_usage
            printf "\n${message} ${spinner:$i:1} "
            counter=0
        fi

        sleep $delay
        counter=$((counter+1))
    done
    printf "\r"
}

prepare_vllm_model() {
    log_section "Preparing vLLM LLM"

    DOCKER_CMD="sudo docker"

    info "Step 1: Waiting for vLLM container to become ready..."
    local max_attempts=30  # 5 minutes (30 * 10s)
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if $DOCKER_CMD inspect vllm >/dev/null 2>&1; then
            success "$CHECKMARK vLLM container exists"
            break
        fi
        
        info "Waiting for vLLM container to start... ($attempt/$max_attempts)"
        sleep 10
        attempt=$((attempt+1))
    done

    if [ $attempt -gt $max_attempts ]; then
        fatal "vLLM container failed to start within timeout"
    fi

    info "Step 2: Waiting for vLLM API to become available..."
    
    # Wait for API to become available
    local api_max_attempts=60  # 5 minutes (60 * 5s)
    local api_attempt=1
    
    while [ $api_attempt -le $api_max_attempts ]; do
        if curl --output /dev/null --silent --fail --max-time 2 http://localhost:8000/v1/models; then
            success "$CHECKMARK vLLM API is responding"
            break
        fi
        
        # Show progress every 6 attempts (30 seconds)
        if [ $((api_attempt % 6)) -eq 0 ]; then
            info "Still waiting for vLLM API... ($api_attempt/$api_max_attempts)"
            # Show GPU usage
            info "Current GPU memory usage:"
            $DOCKER_CMD exec vllm nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader
            # Show recent logs
            info "Recent container logs:"
            $DOCKER_CMD logs --tail 5 vllm
        else
            printf '.'
        fi
        
        sleep 5
        api_attempt=$((api_attempt+1))
    done
    
    if [ $api_attempt -gt $api_max_attempts ]; then
        warning "vLLM API did not become available within the expected timeframe."
        warning "Will attempt to continue anyway, but LLM services might not work properly."
        return 1
    fi
    
    # Do a final validation test using chat completions endpoint
    info "Step 3: Validating chat completions functionality..."
    
    local response=$(curl -s -X POST http://localhost:8000/v1/chat/completions \
        -H "Content-Type: application/json" \
        -d '{
            "model": "HuggingFaceH4/zephyr-7b-beta",
            "messages": [
                {"role": "system", "content": "You are a helpful AI assistant."},
                {"role": "user", "content": "Hello! Are you working?"}
            ],
            "max_tokens": 50,
            "temperature": 0.7
        }')
    
    if echo "$response" | grep -q 'error'; then
        error_msg=$(echo "$response" | jq -r '.error.message' 2>/dev/null || echo "$response")
        warning "Chat completions validation failed: $error_msg"
        warning "LLM services may not work correctly with Flowise."
        # Show the full response for debugging
        info "Full response:"
        echo "$response" | jq '.'
        return 1
    else
        success "$CHECKMARK Chat completions validated successfully"
        # Show a snippet of the response
        info "Sample response:"
        echo "$response" | jq -r '.choices[0].message.content' | head -n 1
        
        # Show final GPU memory usage
        info "Final GPU memory usage:"
        docker exec vllm nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader
    fi
    
    info "vLLM is ready for use with Flowise (use /v1/chat/completions endpoint)"
    return 0
}

# Function to setup Flowise chatflow
setup_flowise_chatflow() {
    log_section "Setting up Flowise Chatflow"

    # Save current directory
    local current_dir=$(pwd)

    # Create logs directory in project root
    mkdir -p "$PROJECT_ROOT/logs"

    # Define the log file path using the project root
    local log_file="$PROJECT_ROOT/logs/flowise_setup_error.log"
    
    # Wait for Flowise to be ready
    info "Waiting for Flowise to be ready..."
    info "This may take several minutes as Flowise needs to start up and connect to vLLM"

    # Instead of relying on the health endpoint, check if the web UI is accessible
    local max_attempts=60  # 5 minutes (60 * 5s)
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        # Try to access the root page (the UI) instead of a health endpoint
        if curl --output /dev/null --silent --fail http://localhost:3000/; then
            success "$CHECKMARK Flowise UI is up and running!"
            break
        fi

        # Show more verbose progress every 12 attempts (1 minute)
        if [ $((attempt % 12)) -eq 0 ]; then
            info "Still waiting for Flowise to become ready... ($attempt/$max_attempts, ~$((attempt/12)) minutes)"
            # Show the container status
            docker ps --filter "name=flowise" --format "{{.Status}}"
        else
            printf '.'
        fi

        sleep 5
        attempt=$((attempt+1))

        if [ $attempt -gt $max_attempts ]; then
            warning "Flowise service did not become available within the expected timeframe."
            warning "However, the container might still be starting up properly."
            read -p "Do you want to proceed with creating the chatflow anyway? (y/n): " continue_anyway
            if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
                warning "Chatflow setup skipped. You can run it manually later with: setup-chatflow-post-deployment.sh"
                cd "$current_dir"  # Return to original directory
                return 1
            fi
            break
        fi
    done

    # Run the chatflow setup script
    info "Creating Chatflow with Ollama integration..."
    
    # Initialize setup_result to error by default
    local setup_result=1
    
    # Determine location of setup script
    local setup_script="$PROJECT_ROOT/setup-chatflow-post-deployment.sh"

    if [ ! -f "$setup_script" ]; then
        setup_script=""
    fi
    
    # Run the setup script if found
    if [ -n "$setup_script" ]; then
        bash "$setup_script"
        setup_result=$?
    else
        # Log the error with details about what was searched
        echo "Error: setup-chatflow-post-deployment.sh script not found." > "$log_file"
        echo "Current directory: $current_dir" >> "$log_file"
        echo "Files in current directory:" >> "$log_file"
        ls -la "$current_dir" >> "$log_file"
        
        if [[ "$(basename "$current_dir")" == "docker" ]]; then
            echo "Files in parent directory:" >> "$log_file"
            ls -la "$(dirname "$current_dir")" >> "$log_file"
        fi
    fi

    if [ $setup_result -ne 0 ]; then
        warning "Failed to setup Flowise chatflow automatically."
        # Update the log file with additional details
        echo "Setup script exited with status code: $setup_result" >> "$log_file"
        warning "Check logs/flowise_setup_error.log for details on what went wrong."
        warning "You may need to run 'setup-chatflow-post-deployment.sh' manually later."
        cd "$current_dir"  # Return to original directory
        return 1
    else
        success "$CHECKMARK Flowise chatflow setup completed"
        info "Please visit http://localhost:3000 to configure the chatflow as described in README_FLOWISE_SETUP.md"
    fi

    # Return to original directory
    cd "$current_dir"
}

# UneeQ ASCII Logo
print_logo() {
    echo ""
    echo -e "\e[38;5;208m  #     #  #    #  #######  #######  #######   "
    echo -e "\e[38;5;209m  #     #  ##   #  #        #        #     #   "
    echo -e "\e[38;5;210m  #     #  # #  #  #######  #######  #     #   "
    echo -e "\e[38;5;211m  #     #  #  # #  #        #        #     #   "
    echo -e "\e[38;5;212m  #     #  #   ##  #        #        #   # #   "
    echo -e "\e[38;5;213m   #####   #    #  #######  #######  #######   "
    echo ""
    echo -e "\e[38;5;208m  ################################################  "
    echo -e "\e[38;5;255m               DIGITALHUMANS.COM                    "
    echo -e "\e[0m"
    echo ""
}

# Function to check if required ports are in use and stop existing containers
check_environment() {
    log_section "Checking Environment"

    DOCKER_CMD="sudo docker compose"
    
    # First, stop any existing miniprem containers
    info "Stopping any existing Miniprem containers..."

    if [ -f "$PROJECT_ROOT/miniprem.sh" ]; then
        "$PROJECT_ROOT/miniprem.sh" stop >/dev/null 2>&1
        success "$CHECKMARK Existing Miniprem containers stopped using miniprem.sh"
    elif [ -d "$PROJECT_ROOT/docker" ]; then
        (cd "$PROJECT_ROOT/docker" && $DOCKER_CMD down) >/dev/null 2>&1
        success "$CHECKMARK Existing Miniprem containers stopped using docker compose"
    else
        info "No existing Miniprem containers found"
    fi
    
    if [ "$INSTALL_TYPE" = "full" ]; then 

        # Only check for common local daemon ports that might conflict
        local port_map=(
            "6379:Redis"
        )
        local found=0
        local box_width=65  # Fixed width for the box
        
        for port_entry in "${port_map[@]}"; do
            # Split entry into port and service name
            local port="${port_entry%%:*}"
            local service="${port_entry#*:}"
            
            # Try lsof first, fallback to ss
            if command -v lsof >/dev/null 2>&1; then
                proc_info=$(lsof -i :$port -sTCP:LISTEN -nP | awk 'NR>1 {print $1, $2}' | head -n1)
            else
                proc_info=$(ss -ltnp "sport = :$port" 2>/dev/null | awk 'NR>1 {gsub(/users:\(\(","",$NF); split($NF,a,","); print a[1], a[2]}' | head -n1)
            fi
            if [ ! -z "$proc_info" ]; then
                proc_name=$(echo $proc_info | awk '{print $1}')
                proc_pid=$(echo $proc_info | awk '{print $2}')
                # Special handling for redis-server on 6379
                if [ "$port" = "6379" ] && [ "$proc_name" = "redis-server" ]; then
                    echo -e "\nRedis appears to be running locally on port 6379."
                    read -p "Would you like to try stopping it automatically? [y/N]: " stop_redis
                    if [[ "$stop_redis" =~ ^[Yy]$ ]]; then
                        sudo service redis-server stop || true
                        sudo systemctl stop redis || true
                        # Re-check if port is still in use
                        if command -v lsof >/dev/null 2>&1; then
                            proc_info=$(lsof -i :$port -sTCP:LISTEN -nP | awk 'NR>1 {print $1, $2}' | head -n1)
                        else
                            proc_info=$(ss -ltnp "sport = :$port" 2>/dev/null | awk 'NR>1 {gsub(/users:\(\(","",$NF); split($NF,a,","); print a[1], a[2]}' | head -n1)
                        fi
                        if [ -z "$proc_info" ]; then
                            success "$CHECKMARK Successfully stopped redis-server on port 6379."
                            continue
                        else
                            warning "redis-server is still running on port 6379. Please stop it manually."
                        fi
                    fi
                fi

                found=1
                # Create horizontal border line with consistent width
                local border=$(printf "%${box_width}s" | tr ' ' '-')
                
                echo -e "\n+${border}+"
                printf "| %-${box_width}s |\n" "⚠️  LOCAL SERVICE CONFLICT DETECTED"
                echo "+${border}+"
                
                # Format each line with proper right alignment
                printf "| Port %-5s is in use by local process '%-12s' (PID %-6s) |\n" "$port" "$proc_name" "$proc_pid"
                printf "| %-${box_width}s |\n" ""
                printf "| %-${box_width}s |\n" "This will prevent the $service service from starting"
                printf "| %-${box_width}s |\n" "correctly. You appear to have a local instance of $service"
                printf "| %-${box_width}s |\n" "running on your system."
                printf "| %-${box_width}s |\n" ""
                printf "| %-${box_width}s |\n" "To resolve:"
                printf "| %-${box_width}s |\n" "    sudo kill $proc_pid"
                printf "| %-${box_width}s |\n" "Then re-run this installer."
                echo "+${border}+"
            fi
        done
        if [ $found -eq 1 ]; then
            echo -e "\n\e[1;33m[WARNING] Local service conflicts detected.\e[0m"
            read -p "\nPress Enter to exit and resolve the conflict(s)..." _
            exit 1
        fi
    fi
}

# Function to check for duplicate installations of MiniPrem
check_duplicate_installations() {
    log_section "Checking for Duplicate Installations"

    # Create a marker file if it doesn't exist yet
    local marker_file="$PROJECT_ROOT/.miniprem_installation_marker"
    if [ ! -f "$marker_file" ]; then
        touch "$marker_file"
        info "Created installation marker file: $marker_file"
    fi

    # Get the absolute path of the current directory
    local current_dir="$PROJECT_ROOT"

    info "Searching for duplicate MiniPrem installations in common locations..."

    # Define likely installation locations (much faster, safer search)
    local search_paths=(
        "$HOME"
        "/opt"
        "/usr/local"
        "/var/lib"
    )

    # Search only likely locations with depth limit
    local miniprem_dirs=""
    for search_path in "${search_paths[@]}"; do
        if [ -d "$search_path" ]; then
            # maxdepth 4: prevents deep recursion, finds most installations
            # timeout 30s: prevents hanging on network mounts
            local found=$(timeout 30s find "$search_path" -maxdepth 4 -type d -iname "*miniprem*" \
                -not -path "*/\.git/*" \
                -not -path "*/node_modules/*" \
                -not -path "$PROJECT_ROOT" \
                -not -path "$PROJECT_ROOT/*" \
                2>/dev/null || true)

            if [ -n "$found" ]; then
                miniprem_dirs="$miniprem_dirs"$'\n'"$found"
            fi
        fi
    done

    # Remove leading/trailing newlines and get count
    miniprem_dirs=$(echo "$miniprem_dirs" | sed '/^$/d')
    local dir_count=$(echo "$miniprem_dirs" | grep -c "^" 2>/dev/null || echo 0)

    if [ "$dir_count" -gt 0 ] && [ -n "$miniprem_dirs" ]; then
        local box_width=75  # Fixed width for the box
        local border=$(printf "%${box_width}s" | tr ' ' '-')

        echo -e "\n+${border}+"
        printf "| %-${box_width}s |\n" "⚠️  MULTIPLE MINIPREM INSTALLATIONS DETECTED"
        echo "+${border}+"

        printf "| %-${box_width}s |\n" "Found $dir_count other directories with 'miniprem' in their name:"

        echo "$miniprem_dirs" | while read -r dir; do
            if [ -n "$dir" ]; then
                # Truncate path if too long
                local display_path="$dir"
                if [ ${#display_path} -gt $((box_width-4)) ]; then
                    display_path="...${display_path:$((${#display_path}-$box_width+7))}"
                fi
                printf "| %-${box_width}s |\n" "  - $display_path"
            fi
        done

        printf "| %-${box_width}s |\n" ""
        printf "| %-${box_width}s |\n" "Having multiple installations may cause conflicts and unexpected behavior."
        printf "| %-${box_width}s |\n" "It's recommended to use only one installation of MiniPrem."
        echo "+${border}+"

        read -p "Do you want to continue with this installation? (y/N): " continue_install
        if [[ ! "$continue_install" =~ ^[Yy]$ ]]; then
            fatal "Installation aborted due to multiple MiniPrem installations detected."
        fi

        warning "Continuing with installation despite duplicate installations detected."
    else
        success "$CHECKMARK No duplicate MiniPrem installations detected."
    fi
}

# Function to build the fast-whisper image locally
build_fast_whisper_image() {
    log_section "Building Fast Whisper Docker Image"
    
    DOCKER_CMD="sudo docker"

    info "Building fast-whisper image from Dockerfile..."

    # Check if required directories exist
    if [ ! -d "$PROJECT_ROOT/docker/fast-whisper" ]; then
        fatal "Fast Whisper directory not found at $PROJECT_ROOT/docker/fast-whisper"
    fi

    if [ ! -f "$PROJECT_ROOT/docker/fast-whisper/Dockerfile" ]; then
        fatal "Fast Whisper Dockerfile not found at $PROJECT_ROOT/docker/fast-whisper/Dockerfile"
    fi

    # Create the requirements.txt file if it doesn't exist
    if [ ! -f "$PROJECT_ROOT/docker/fast-whisper/requirements.txt" ]; then
        echo "Creating requirements.txt for fast-whisper..."
        cat > "$PROJECT_ROOT/docker/fast-whisper/requirements.txt" << EOF
faster-whisper==0.10.0
fastapi==0.103.1
uvicorn==0.23.2
python-multipart==0.0.6
pydantic==2.4.2
pyaudio==0.2.13
pyclip==0.7.0
python-dotenv==1.0.0
torch>=2.0.0
EOF
    fi

    # Create start.sh if it doesn't exist
    if [ ! -f "$PROJECT_ROOT/docker/fast-whisper/start.sh" ]; then
        echo "Creating start.sh for fast-whisper..."
        cat > "$PROJECT_ROOT/docker/fast-whisper/start.sh" << EOF
#!/bin/bash
cd /app/app
python3 -m uvicorn main:app --host 0.0.0.0 --port 9000
EOF
        chmod +x "$PROJECT_ROOT/docker/fast-whisper/start.sh"
    fi

    # Create app directory and main.py if they don't exist
    mkdir -p "$PROJECT_ROOT/docker/fast-whisper/app"
    if [ ! -f "$PROJECT_ROOT/docker/fast-whisper/app/main.py" ]; then
        echo "Creating main.py for fast-whisper..."
        cat > "$PROJECT_ROOT/docker/fast-whisper/app/main.py" << EOF
from fastapi import FastAPI, File, UploadFile, Form, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
import os
import time
from faster_whisper import WhisperModel
import tempfile

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Specify path to model files
models_path = '/app/models'

# Initialize model (will be loaded when needed)
model = None

def get_model():
    global model
    if model is None:
        # Check if models directory exists
        if not os.path.exists(models_path):
            os.makedirs(models_path, exist_ok=True)
        
        # Initialize the model
        model = WhisperModel("large-v2", device="cuda", compute_type="float16", download_root=models_path)
    return model

@app.get("/health")
async def health_check():
    return {"status": "healthy"}

@app.post("/v1/audio/transcriptions")
async def transcribe(file: UploadFile = File(...), model: str = Form("large-v2")):
    try:
        start_time = time.time()
        
        # Save uploaded file to a temporary file
        with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as temp_file:
            temp_file_path = temp_file.name
            content = await file.read()
            temp_file.write(content)
        
        # Get the model
        whisper_model = get_model()
        
        # Transcribe the audio
        segments, info = whisper_model.transcribe(temp_file_path, beam_size=5)
        
        # Collect all segments of transcription
        full_text = ""
        for segment in segments:
            full_text += segment.text + " "
        
        # Clean up temporary file
        os.unlink(temp_file_path)
        
        process_time = time.time() - start_time
        
        return {
            "text": full_text.strip(),
            "processing_time": process_time,
            "language": info.language,
            "language_probability": info.language_probability
        }
    
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=9000)
EOF
    fi

    # Build the Docker image
    (cd "$PROJECT_ROOT/docker" && $DOCKER_CMD build -t fast-whisper-optimized -f fast-whisper/Dockerfile ./fast-whisper)
    
    if [ $? -ne 0 ]; then
        fatal "Failed to build fast-whisper Docker image"
    else
        success "$CHECKMARK Fast Whisper Docker image built successfully"
    fi
}

# Add this function after the `pull_required_images` function
# Wrapper function around the pull_docker_images function in scripts/docker.sh
# that passes the TTS_PROVIDER as an environment variable
pull_docker_with_tts_provider() {
    # Export our TTS_PROVIDER so that the docker.sh script can access it
    export TTS_PROVIDER
    # Call the pull_docker_images function from scripts/docker.sh
    pull_docker_images
}

main() {
    print_logo

    check_environment

    check_duplicate_installations
    
    # Install type
    prompt_for_install_type

    # Parse command line arguments using getopt
    OPTIONS=$(getopt -o '' --long platform-address:,platform-key:,tenant-id:,tts-address:,tts-key:,azure-region:,azure-speech-key:,renny-image: -- "$@")
    if [ $? -ne 0 ]; then
        usage
    fi

    # Ensure docker-compose.env exists
    ensure_env_file_exists
    
    # Select TTS provider before configuring
    select_tts_provider

    # Configure TTS provider based on selection
    if [ "$TTS_PROVIDER" = "azure" ]; then
        configure_azure_tts
    elif [ "$TTS_PROVIDER" = "elevenlabs" ]; then
        configure_eleven_labs
    elif [ "$TTS_PROVIDER" = "rime" ]; then
        setup_rime_credentials
    fi

    # In all docker compose commands, use the correct compose files
    if [ "$INSTALL_TYPE" = "default" ]; then
        COMPOSE_FILES="-f $PROJECT_ROOT/docker/docker-compose.default.yml"
    else
        COMPOSE_FILES="-f $PROJECT_ROOT/docker/docker-compose.yml"
    fi

    # Update docker-compose.yml based on TTS provider
    update_docker_compose_for_tts
    
    # Check if the required software prerequisites are installed so installer can run
    check_installer_prequisites

    # check driver prerequisites
    check_driver_prerequisites

    # check software prerequisites
    check_software_prequisites

    # check hardware prerequisites
    check_hardware_prerequisites

    # check docker installation
    check_docker_installation

    eval set -- "$OPTIONS"

    # Initialize variables with existing values from .env file
    PLATFORM_ADDRESS=$(read_env_variable "DHOP_ADDRESS")
    PLATFORM_KEY=$(read_env_variable "DHOP_APIKEY")
    TENANT_ID=$(read_env_variable "DHOP_TENANTID")
    AZURE_REGION=$(read_env_variable "AZURE_REGION")

    # Try both AZURE_SPEECH and AZURE_SPEECH_KEY to handle both possibilities
    AZURE_SPEECH_KEY=$(read_env_variable "AZURE_SPEECH")
    if [ -z "$AZURE_SPEECH_KEY" ]; then
        AZURE_SPEECH_KEY=$(read_env_variable "AZURE_SPEECH_KEY")
    fi

    RENNY_IMAGE=$(read_docker_compose_value "image")

    # Debug output - strip quotes from values
    PLATFORM_ADDRESS=$(echo "$PLATFORM_ADDRESS" | sed 's/^"//;s/"$//')
    PLATFORM_KEY=$(echo "$PLATFORM_KEY" | sed 's/^"//;s/"$//')
    TENANT_ID=$(echo "$TENANT_ID" | sed 's/^"//;s/"$//')
    AZURE_REGION=$(echo "$AZURE_REGION" | sed 's/^"//;s/"$//')
    AZURE_SPEECH_KEY=$(echo "$AZURE_SPEECH_KEY" | sed 's/^"//;s/"$//')
    RENNY_IMAGE=$(echo "$RENNY_IMAGE" | sed 's/^"//;s/"$//')

    # Extract options and their arguments into variables
    while true; do
        case "$1" in
            --platform-address)
                PLATFORM_ADDRESS="$2"
                shift 2
                ;;
            --platform-key)
                PLATFORM_KEY="$2"
                shift 2
                ;;
            --tenant-id)
                TENANT_ID="$2"
                shift 2
                ;;
            --azure-region)
                AZURE_REGION="$2"
                shift 2
                ;;
            --azure-speech-key)
                AZURE_SPEECH_KEY="$2"
                shift 2
                ;;
            --renny-image)
                RENNY_IMAGE="$2"
                shift 2
                ;;
            --)
                shift
                break
                ;;
            *)
                usage
                ;;
        esac
    done

    # Check if all required values are already provided
    if check_all_values_provided; then
        # All values are provided, show summary and confirm
        log_section "Configuration Summary"
        info "UneeQ platform address: $PLATFORM_ADDRESS"
        info "UneeQ platform API key: ${PLATFORM_KEY:0:8}****${PLATFORM_KEY: -8}"
        info "Tenant ID: $TENANT_ID"
        info "Renny image name: $RENNY_IMAGE"
        
        # Display TTS provider-specific information
        info "TTS Provider: $TTS_PROVIDER"
        if [ "$TTS_PROVIDER" = "azure" ]; then
            info "Azure region: $AZURE_REGION"
            info "Azure speech key: ${AZURE_SPEECH_KEY:0:8}****${AZURE_SPEECH_KEY: -8}"
        elif [ "$TTS_PROVIDER" = "elevenlabs" ]; then
            ELEVEN_LABS_API_KEY=$(read_env_variable "ELEVEN_LABS_API_KEY")
            ELEVEN_LABS_API_KEY=$(echo "$ELEVEN_LABS_API_KEY" | sed 's/^"//;s/"$//')
            info "Eleven Labs API key: ${ELEVEN_LABS_API_KEY:0:8}****${ELEVEN_LABS_API_KEY: -8}"
        elif [ "$TTS_PROVIDER" = "rime" ]; then
            RIME_API_KEY=$(read_env_variable "RIME_API_KEY")
            RIME_API_KEY=$(echo "$RIME_API_KEY" | sed 's/^"//;s/"$//')
            info "RIME API key: ${RIME_API_KEY:0:8}****${RIME_API_KEY: -8}"
        fi

        while true; do
            read -p "All configuration values are already set. Proceed with installation? (Y/n): " confirm
            case "${confirm,,}" in
                y|yes)
                    break
                    ;;
                n|no)
                    info "Installation aborted by user."
                    exit 0
                    ;;
                *)
                    echo "Please enter 'y' or 'n'."
                    ;;
            esac
        done
    else
        PLATFORM_KEY=$(check_and_prompt_for_value "Enter the UneeQ platform API key" "$PLATFORM_KEY")
        TENANT_ID=$(check_and_prompt_for_value "Enter the Tenant ID" "$TENANT_ID")
        
        # Only prompt for Azure credentials if Azure TTS is selected
        if [ "$TTS_PROVIDER" = "azure" ]; then
            AZURE_REGION=$(check_and_prompt_for_value "Enter the Azure region" "$AZURE_REGION")
            AZURE_SPEECH_KEY=$(check_and_prompt_for_value "Enter the Azure speech key" "$AZURE_SPEECH_KEY")
        fi
        
        RENNY_IMAGE=$(check_and_prompt_for_value "Enter the Renny image name" "$RENNY_IMAGE")

        # Check if required arguments are provided
        if [ -z "$PLATFORM_KEY" ] || [ -z "$TENANT_ID" ] || [ -z "$RENNY_IMAGE" ]; then
            usage
            fatal "Missing required arguments. Please provide the required arguments."
        fi
        
        # Check if Azure credentials are provided when Azure TTS is selected
        if [ "$TTS_PROVIDER" = "azure" ] && ([ -z "$AZURE_REGION" ] || [ -z "$AZURE_SPEECH_KEY" ]); then
            usage
            fatal "Azure TTS selected but Azure credentials are missing."
        fi
    fi

    # Update the environment file with collected values
    update_env_file

    # Make sure PLATFORM_ADDRESS has a default value if it's empty
    if [ -z "$PLATFORM_ADDRESS" ]; then
        PLATFORM_ADDRESS="wss://api.enterprise.uneeq.io/signalling-service/v1/ws/renderer"
        # Also update it in the env file
        if grep -q "^DHOP_ADDRESS=" "$PROJECT_ROOT/docker/docker-compose.env"; then
            sed -i "s|^DHOP_ADDRESS=.*|DHOP_ADDRESS=$PLATFORM_ADDRESS|" "$PROJECT_ROOT/docker/docker-compose.env"
        fi
    fi

    # check to make sure the cloud services are reachable
    check_cloud_services "$PLATFORM_ADDRESS" "$PLATFORM_ADDRESS"

    # No need to setup RIME credentials here as we did it earlier based on TTS_PROVIDER selection
    
    if [ "$INSTALL_TYPE" = "full" ]; then
        echo -e "\nChoose your speech-to-text backend (only one will be enabled):"
        echo "1) Whisper (OpenAI, onerahmet/openai-whisper-asr-webservice)"
        echo "2) FastWhisper (GPU-optimized, locally built)"
        echo "3) Do not use local STT (UneeQ default STT will be used)"
        read -p "Enter choice [1-3]: " stt_choice
        if [[ "$stt_choice" == "1" ]] || [[ "$stt_choice" == "2" ]] || [[ "$stt_choice" == "3" ]]; then
            # Update docker-compose.yml for the selected STT backend
            update_docker_compose_for_stt "$stt_choice"
            
            # If FastWhisper is selected, build the image
            if [[ "$stt_choice" == "2" ]]; then
                build_fast_whisper_image
            fi
        else
            echo "Invalid choice, exiting."
            exit 1
        fi
    fi

    # pull the images down with TTS provider information
    pull_docker_with_tts_provider

    # Start the Miniprem system
    start_miniprem

    # Setup Flowise chatflow
    if [ "$INSTALL_TYPE" = "full" ]; then
        setup_flowise_chatflow
    fi

    success "$CHECKMARK Installation and configuration complete."
    info "Miniprem is now running. You can access:"
    info "- MiniPrem Monitor at http://localhost:3001 (container/Kubernetes monitoring)"
    if [ "$INSTALL_TYPE" = "full" ]; then
        info "- Flowise at http://localhost:3000 (workflow automation)"
        info "- Grafana at http://localhost:3002 (metrics dashboard)"
    fi
    info "- Renny service health at http://localhost:8081/health"
    info ""
    info "To stop the services, use: cd docker && docker compose down"
}

main "$@"