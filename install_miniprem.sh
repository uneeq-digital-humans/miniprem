#!/bin/bash

source scripts/docker.sh
source scripts/logging.sh
source scripts/audio.sh
source scripts/hash.sh
source scripts/environment.sh
source scripts/prerequisites.sh

# Enable debugging
#set -x

usage() {
    echo -e $WHITE
    cat <<EOF
$(basename "$0") --platform-address <UneeQ platform address> --platform-key <UneeQ platform API key> --tenant <Tenant ID> --renny-image <Docker image name for Renny> [--azure-region <Azure region>] [--azure-speech-key <Azure speech key>] --renny-image <Docker image name for Renny> [h]
Install and configure Renny and A2F services on a laptop/kiosk

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

    # Perform a curl request to the given address and port
    response=$(curl -s -o /dev/null -w "%{http_code}" http://$address:$port)

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

# Function to check and update configuration.dat
check_and_update_configuration() {
    local tenant_id="$1"
    local jws_secret="$2"
    local config_file="docker/configuration.dat"
    local server="prod-global"

    if [[ -f "$config_file" ]]; then
        # Read the JSON values from the file, we won't replace the existing values for server
        server=$(jq -r 'if .Server == null then "" else .Server end' "$config_file")

        # If server is not set, default to "prod-global"
        if [[ -z "$server" ]]; then
            server="prod-global"
        fi
    fi

    # Update the configuration file with the new values
    jq -n --arg server "$server" --arg tenant_id "$tenant_id" --arg jws_secret "$jws_secret" \
        '{Server: $server, TenantId: $tenant_id, JWSSecret: $jws_secret}' > "$config_file"

    # Check the ownership of the file and make sure its not the root user that owns it
    file_owner=$(stat -c '%U' "$config_file")
    if [[ "$file_owner" != "$USER" ]]; then
        warning "$config_file is not owned by $USER, correcting this now."
        sudo chown "$USER:$USER" "$config_file"
    fi

    # make sure the file has correct permissions (and isn't a directory)
    if [[ -d "$config_file" ]]; then
        warning "$config_file is a directory rather than a file, correcting this now."
        chmod 644 "$config_file"
    fi
    
    success "$CHECKMARK Configuration updated in $config_file"
}

# Function to ensure configuration.dat exists
ensure_configuration_file_exists() {
    local config_file="docker/configuration.dat"
    if [[ ! -f "$config_file" ]]; then
        touch "$config_file"
        echo "{}" > "$config_file"  # Initialize with an empty JSON object
    fi
}

# Function to get required variables from the example env file (those with empty values)
get_required_env_vars_from_example() {
    local example_file="docker/docker-compose.env.example"
    grep -E '^[A-Z0-9_]+=$' "$example_file" | cut -d= -f1
}

# Function to ensure docker-compose.env exists by copying from example if needed
ensure_env_file_exists() {
    local env_file="docker/docker-compose.env"
    local example_file="docker/docker-compose.env.example"
    if [[ ! -f "$env_file" ]]; then
        cp "$example_file" "$env_file"
        info "Created $env_file from $example_file."
    fi
}

# Function to check and prompt for required env variables dynamically
check_and_prompt_required_env_vars() {
    local env_file="docker/docker-compose.env"
    local required_vars=( $(get_required_env_vars_from_example) )
    for var in "${required_vars[@]}"; do
        local value=$(read_env_variable "$var")
        if [[ -z "$value" ]]; then
            warning "$var is missing or empty in $env_file."
            read -p "Enter value for $var: " value
            if [[ -z "$value" ]]; then
                fatal "$var is required. Exiting."
            fi
            update_env_variable "$var" "$value"
        fi
    done
}

# Function to check if all required values are provided
check_all_values_provided() {
    local missing=0

    # Debug information
    info "Checking configuration values..."
    info "PLATFORM_ADDRESS: ${PLATFORM_ADDRESS:-'Not set'}"
    info "PLATFORM_KEY: ${PLATFORM_KEY:+'Set (value hidden)'}"
    info "TENANT_ID: ${TENANT_ID:-'Not set'}"
    info "AZURE_REGION: ${AZURE_REGION:-'Not set'}"
    info "AZURE_SPEECH_KEY: ${AZURE_SPEECH_KEY:+'Set (value hidden)'}"
    info "RENNY_IMAGE: ${RENNY_IMAGE:-'Not set'}"
    if [ -z "$PLATFORM_ADDRESS" ]; then
        warning "UneeQ platform address is missing"
        missing=1
    fi

    if [ -z "$PLATFORM_KEY" ]; then
        warning "UneeQ platform API key is missing"
        missing=1
    fi

    if [ -z "$TENANT_ID" ]; then
        warning "Tenant ID is missing"
        missing=1
    fi

    if [ -z "$AZURE_REGION" ]; then
        warning "Azure region is missing"
        missing=1
    fi

    if [ -z "$AZURE_SPEECH_KEY" ]; then
        warning "Azure speech key is missing"
        missing=1
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

# Function to build the log streamer service
build_log_streamer() {
    log_section "Building Log Streamer Service"

    # Save current directory
    local current_dir=$(pwd)

    # Check if the log-streamer directory exists in various possible locations
    if [ -d "docker/log-streamer" ]; then
        cd docker
    elif [ "$(basename $(pwd))" = "docker" ] && [ -d "log-streamer" ]; then
        # Already in docker directory
        :
    elif [ -d "../docker/log-streamer" ]; then
        cd ../docker
    else
        fatal "Log streamer directory not found. Expected at docker/log-streamer"
    fi

    info "Building log streamer Docker image..."

    # Check if we need to go into the log-streamer directory
    if [ -d "log-streamer" ]; then
        cd log-streamer
    fi

    # Check if package.json exists
    if [ ! -f "package.json" ]; then
        cd "$current_dir"  # Return to original directory before exiting
        fatal "package.json not found in log-streamer directory"
    fi

    # Check if Dockerfile exists
    if [ ! -f "Dockerfile" ]; then
        cd "$current_dir"  # Return to original directory before exiting
        fatal "Dockerfile not found in log-streamer directory"
    fi

    # Go back to the docker directory if we're in log-streamer
    if [ "$(basename $(pwd))" = "log-streamer" ]; then
        cd ..
    fi

    success "$CHECKMARK Log streamer service is ready to be built by docker-compose"

    # Return to original directory
    cd "$current_dir"
}

# Function to start the Miniprem system with docker compose
start_miniprem() {
    log_section "Starting Miniprem"
    docker compose $COMPOSE_FILES up -d
    if [ $? -ne 0 ]; then
        fatal "Failed to start Miniprem services"
    else
        success "$CHECKMARK Miniprem services started successfully"
    fi
    if [ "$INSTALL_TYPE" = "full" ]; then
        if ! docker ps | grep -q "log-streamer"; then
            warning "Log streamer service did not start properly. Container logs might not be available in documentation."
        else
            success "$CHECKMARK Log streamer service is running and accessible at http://localhost:8082/health"
        fi
    fi
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

# Function to prepare the required vLLM model after the container is up
prepare_vllm_model() {
    log_section "Preparing vLLM LLM"

    info "NOTE: This is a multi-step process that may take 5-15 minutes depending on your hardware."
    info "      - First, we need to wait for vLLM to start"
    info "      - Then, we'll trigger the download of the Gemma3:4b model (if not already downloaded)"
    info "      - Finally, the model needs to load completely into GPU memory"
    info "Please be patient as we go through these steps."

    echo ""
    info "Step 1: Waiting for vLLM service to start..."

    local max_attempts=120 # Wait up to 10 minutes for service to start
    local attempt=1
    local vllm_started=0

    while [ $attempt -le $max_attempts ]; do
        # Check if vLLM is running by querying the /v1/completions endpoint
        if curl --output /dev/null --silent --fail http://localhost:8000/v1/completions; then
            success "$CHECKMARK vLLM service is running (API accessible)"
            vllm_started=1
            break
        fi

        # Show progress every 10 attempts
        if [ $((attempt % 10)) -eq 0 ]; then
            info "Still waiting for vLLM to start... ($attempt/$max_attempts)"
            # Show the container status
            docker ps --filter "name=vllm" --format "{{.Status}}"
        else
            printf '.'
        fi

        sleep 5
        attempt=$((attempt+1))
    done

    if [ $vllm_started -eq 0 ]; then
        warning "vLLM service did not start within the expected timeframe (10 minutes)."
        warning "You may need to troubleshoot by checking: docker logs vllm"
        read -p "Do you want to continue anyway? (y/n): " continue_anyway
        if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
            fatal "Installation aborted due to vLLM startup issues."
        fi
    fi

    echo ""
    info "Step 2: Triggering download and preparation of the Gemma3:4b model..."
    info "(This is a large model and may take several minutes to download and prepare)"
    info "You can monitor progress by running 'docker logs -f vllm' in another terminal"
    echo ""

    # Poll until the model is fully loaded and ready
    info "Waiting for Gemma3:4b model to be fully loaded in vLLM..."
    local poll_attempt=1
    local poll_max_attempts=40  # Wait up to 10 minutes (40*15s)
    while [ $poll_attempt -le $poll_max_attempts ]; do
        response=$(curl -s -X POST http://localhost:8000/v1/chat/completions \
            -H 'Content-Type: application/json' \
            -d '{
                "model": "gemma-3-4b",
                "messages": [
                    { "role": "user", "content": "Hello!" }
                ]
            }')
        if ! echo "$response" | grep -q 'error'; then
            success "$CHECKMARK Gemma3:4b model is fully loaded and ready in vLLM."
            break
        else
            info "Model not ready yet, still waiting... ($poll_attempt/$poll_max_attempts)"
            sleep 15
            poll_attempt=$((poll_attempt+1))
        fi
    done
    if [ $poll_attempt -gt $poll_max_attempts ]; then
        warning "Timed out waiting for Gemma3:4b model to be ready in vLLM."
        warning "You may need to check the vLLM logs or try again later."
    fi
}

# Function to setup Flowise chatflow
setup_flowise_chatflow() {
    log_section "Setting up Flowise Chatflow"

    # Save current directory
    local current_dir=$(pwd)
    
    # Determine the project root directory
    local project_root=""
    if [[ "$(basename "$current_dir")" == "docker" ]]; then
        # We're in the docker directory, so project root is one level up
        project_root="$(dirname "$current_dir")"
        # Create logs directory in project root
        mkdir -p "$project_root/logs"
    else
        # We're probably already in the project root
        project_root="$current_dir"
        # Create logs directory in current directory
        mkdir -p "$project_root/logs"
    fi
    
    # Define the log file path using the project root
    local log_file="$project_root/logs/flowise_setup_error.log"
    
    # Wait for Flowise to be ready
    info "Waiting for Flowise to be ready..."
    info "This may take several minutes as Flowise needs to start up and connect to Ollama"

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
    
    # Determine location of setup script based on current directory
    local setup_script=""
    if [[ "$(basename "$current_dir")" == "docker" ]]; then
        # We're in the docker directory
        if [ -f "../setup-chatflow-post-deployment.sh" ]; then
            setup_script="../setup-chatflow-post-deployment.sh"
        fi
    else
        # We're in the project root
        if [ -f "./setup-chatflow-post-deployment.sh" ]; then
            setup_script="./setup-chatflow-post-deployment.sh"
        fi
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

# Function to install Rime login credentials
setup_rime_credentials() {
    log_section "Setting up RIME credentials"

    # Check if RIME_API_KEY is already set
    local RIME_API_KEY=$(read_env_variable "RIME_API_KEY")

    if [ -z "$RIME_API_KEY" ]; then
        read -p "Enter your RIME API key: " RIME_API_KEY
        if [ -z "$RIME_API_KEY" ]; then
            warning "No RIME API key provided. RIME services may not function correctly."
        else
            update_env_variable "RIME_API_KEY" "\"$RIME_API_KEY\""
            success "$CHECKMARK RIME API key configured"
        fi
    else
        success "$CHECKMARK RIME API key already configured"
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
    docker login -u="rimelabs+uneeq" -p="$RIME_QUAY_PASSWORD" quay.io
    docker pull quay.io/rimelabs/api:v0.0.2-20250407
    docker pull quay.io/rimelabs/mistv2:v0.0.1-20250403

    info "RIME credential setup complete"
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
    
    # First, stop any existing miniprem containers
    info "Stopping any existing Miniprem containers..."
    
    if [ -f "./miniprem.sh" ]; then
        ./miniprem.sh stop >/dev/null 2>&1
        success "$CHECKMARK Existing Miniprem containers stopped using miniprem.sh"
    elif [ -d "./docker" ]; then
        (cd docker && docker compose down) >/dev/null 2>&1
        success "$CHECKMARK Existing Miniprem containers stopped using docker compose"
    else
        info "No existing Miniprem containers found"
    fi
    
    # Only check for common local daemon ports that might conflict
    local port_map=(
        "6379:Redis" 
        "11434:Ollama"
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
            # Special handling for ollama on 11434
            if [ "$port" = "11434" ] && [[ "${proc_name,,}" == *ollama* ]]; then
                echo -e "\nOllama appears to be running locally on port 11434."
                read -p "Would you like to try stopping it automatically? [y/N]: " stop_ollama
                if [[ "$stop_ollama" =~ ^[Yy]$ ]]; then
                    sudo systemctl stop ollama || true
                    # Re-check if port is still in use
                    if command -v lsof >/dev/null 2>&1; then
                        proc_info=$(lsof -i :$port -sTCP:LISTEN -nP | awk 'NR>1 {print $1, $2}' | head -n1)
                    else
                        proc_info=$(ss -ltnp "sport = :$port" 2>/dev/null | awk 'NR>1 {gsub(/users:\(\(","",$NF); split($NF,a,","); print a[1], a[2]}' | head -n1)
                    fi
                    if [ -z "$proc_info" ]; then
                        success "$CHECKMARK Successfully stopped ollama on port 11434."
                        continue
                    else
                        warning "Ollama is still running on port 11434. Please stop it manually."
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
}

# Function to configure whisper service
configure_whisper_service() {
    local whisper_type
    echo "Please choose your preferred speech-to-text service:"
    echo "1. OpenAI Whisper (slower but more accurate)"
    echo "2. Faster Whisper (faster but slightly less accurate)"
    read -p "Enter your choice (1 or 2): " whisper_type

    case $whisper_type in
        1)
            echo "Configuring OpenAI Whisper..."
            sed -i '/^  # whisper:/s/^  # //' docker/docker-compose.yml
            ;;
        2)
            echo "Configuring Faster Whisper..."
            sed -i '/^  # fastwhisper:/s/^  # //' docker/docker-compose.yml
            # Create necessary directories
            mkdir -p docker/fast-whisper/app
            mkdir -p docker/fast-whisper/models
            ;;
        *)
            echo "Invalid choice. Defaulting to OpenAI Whisper."
            sed -i '/^  # whisper:/s/^  # //' docker/docker-compose.yml
            ;;
    esac
}

main() {
    print_logo
    check_environment
    # Parse command line arguments using getopt
    OPTIONS=$(getopt -o '' --long platform-address:,platform-key:,tenant-id:,tts-address:,tts-key:,azure-region:,azure-speech-key:,renny-image: -- "$@")
    if [ $? -ne 0 ]; then
        usage
    fi

    # Ensure configuration.dat exists
    ensure_configuration_file_exists

    # Ensure docker-compose.env exists
    ensure_env_file_exists

    # Check and prompt for required env variables
    check_and_prompt_required_env_vars

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
        info "Azure region: $AZURE_REGION"
        info "Azure speech key: ${AZURE_SPEECH_KEY:0:8}****${AZURE_SPEECH_KEY: -8}"
        info "Renny image name: $RENNY_IMAGE"

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
        # Prompt for missing values
        PLATFORM_ADDRESS=$(check_and_prompt_for_value "Enter the UneeQ platform address" "$PLATFORM_ADDRESS")
        PLATFORM_KEY=$(check_and_prompt_for_value "Enter the UneeQ platform API key" "$PLATFORM_KEY")
        TENANT_ID=$(check_and_prompt_for_value "Enter the Tenant ID" "$TENANT_ID")
        AZURE_REGION=$(check_and_prompt_for_value "Enter the Azure region" "$AZURE_REGION")
        AZURE_SPEECH_KEY=$(check_and_prompt_for_value "Enter the Azure speech key" "$AZURE_SPEECH_KEY")
        RENNY_IMAGE=$(check_and_prompt_for_value "Enter the Renny image name" "$RENNY_IMAGE")

        # Check if required arguments are provided
        if [ -z "$PLATFORM_ADDRESS" ] || [ -z "$PLATFORM_KEY" ] || [ -z "$TENANT_ID" ] || [ -z "$AZURE_REGION" ] || [ -z "$AZURE_SPEECH_KEY" ] || [ -z "$RENNY_IMAGE" ]; then
            usage
            fatal "Missing required arguments. Please provide the required arguments."
        fi
    fi

    # Check and update configuration.dat
    check_and_update_configuration "$TENANT_ID" "$PLATFORM_KEY"

    # check to make sure the cloud services are reachable
    check_cloud_services "$PLATFORM_ADDRESS" "$PLATFORM_ADDRESS"

    # Setup RIME credentials
    if [ "$INSTALL_TYPE" = "full" ]; then
        setup_rime_credentials
    fi

    # Build the log streamer service
    build_log_streamer

    # pull the images down
    pull_docker_images

    # Start the Miniprem system
    start_miniprem

    # Prepare Gemma3:4b inside the vLLM container
    if [ "$INSTALL_TYPE" = "full" ]; then
        prepare_vllm_model
    fi

    # Setup Flowise chatflow
    if [ "$INSTALL_TYPE" = "full" ]; then
        setup_flowise_chatflow
    fi

    # Configure whisper service
    configure_whisper_service

    success "$CHECKMARK Installation and configuration complete."
    info "Miniprem is now running. You can access:"
    info "- Flowise at http://localhost:3000"
    info "- Renny service health at http://localhost:8081/health"
    info "- Documentation with logs viewer at http://localhost:3000/docs/ (if you've set up the documentation server)"
    info "To stop the services, use: cd docker && docker compose down"
}

# Prompt for install type at the start
INSTALL_TYPE=""
echo "Select installation type:"
echo "1) Default Install (Renny + Audio2Face only)"
echo "2) Full Install (All services: Renny, Audio2Face, Flowise, vLLM, Grafana, Prometheus, RIME, Whisper etc.)"
read -p "Enter choice [1-2]: " install_choice
if [[ "$install_choice" == "1" ]]; then
    INSTALL_TYPE="default"
    echo "default" > .miniprem_install_type
elif [[ "$install_choice" == "2" ]]; then
    INSTALL_TYPE="full"
    echo "full" > .miniprem_install_type
else
    echo "Invalid choice, exiting."
    exit 1
fi

# In all docker compose commands, use the correct compose files (with docker/ prefix, run from project root)
if [ "$INSTALL_TYPE" = "default" ]; then
    COMPOSE_FILES="-f docker/docker-compose.default.yml"
else
    COMPOSE_FILES="-f docker/docker-compose.yml"
fi

# Only pull images and perform logins for selected services
if [ "$INSTALL_TYPE" = "full" ]; then
    # Pull all images and perform all logins (including RIME)
    setup_rime_credentials
else
    # Only pull images for Renny and Audio2Face
    info "Pulling Renny and Audio2Face images..."
    docker pull facemeproduction/renny:0.484-37235
    docker pull facemeproduction/audio2face_with_emotion:local-dev
    docker pull facemeproduction/audio2face_anim_controller:local-dev
fi

# After determining INSTALL_TYPE and before pulling images or starting services, add:
if [ "$INSTALL_TYPE" = "full" ]; then
    echo "\nChoose your speech-to-text backend (only one will be enabled):"
    echo "1) Whisper (OpenAI, onerahmet/openai-whisper-asr-webservice)"
    echo "2) FastWhisper (SYSTRAN, GPU-optimized, systran/faster-whisper)"
    read -p "Enter choice [1-2]: " stt_choice
    if [[ "$stt_choice" == "1" ]]; then
        info "Enabling Whisper backend in docker-compose.yml..."
        # Uncomment whisper, comment fastwhisper
        sed -i '/^# whisper:/,/^#   security_opt:/s/^# //' docker/docker-compose.yml
        sed -i '/^# fastwhisper:/,/^#   security_opt:/s/^# /#/' docker/docker-compose.yml
    elif [[ "$stt_choice" == "2" ]]; then
        info "Enabling FastWhisper backend in docker-compose.yml..."
        # Uncomment fastwhisper, comment whisper
        sed -i '/^# fastwhisper:/,/^#   security_opt:/s/^# //' docker/docker-compose.yml
        sed -i '/^# whisper:/,/^#   security_opt:/s/^# /#/' docker/docker-compose.yml
    else
        echo "Invalid choice, exiting."
        exit 1
    fi
fi

# Use $COMPOSE_FILES in all docker compose up/down commands
# Example:
# docker compose $COMPOSE_FILES up -d

main "$@"