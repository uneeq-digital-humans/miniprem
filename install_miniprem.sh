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
`basename $0` --platform-address <UneeQ platform address> --platform-key <UneeQ platform API key> --tenant <Tenant ID> --renny-image <Docker image name for Renny> [--azure-region <Azure region>] [--azure-speech-key <Azure speech key>] --renny-image <Docker image name for Renny> [h]
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

# Function to ensure docker-compose.env exists
ensure_env_file_exists() {
    local env_file="docker/docker-compose.env"
    if [[ ! -f "$env_file" ]]; then
        touch "$env_file"
        info "Created new environment file at $env_file"
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

    # Save current directory
    local current_dir=$(pwd)

    # Build and start the services
    cd docker && docker compose -f docker-compose.yml up -d
    if [ $? -ne 0 ]; then
        # Return to original directory before exiting
        cd "$current_dir"
        fatal "Failed to start Miniprem services"
    else
        success "$CHECKMARK Miniprem services started successfully"
    fi

    # Check if log-streamer is running
    if ! docker ps | grep -q "log-streamer"; then
        warning "Log streamer service did not start properly. Container logs might not be available in documentation."
    else
        success "$CHECKMARK Log streamer service is running and accessible at http://localhost:8082/health"
    fi

    # Return to original directory
    cd "$current_dir"
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

# Function to pull the required Ollama model after the container is up
pull_ollama_model() {
    log_section "Preparing Ollama LLM"

    info "NOTE: This is a multi-step process that may take 5-15 minutes depending on your hardware."
    info "      - First, we need to wait for Ollama to start"
    info "      - Then, we'll download the Gemma3:4b model (if not already downloaded)"
    info "      - Finally, the model needs to load completely into GPU memory"
    info "Please be patient as we go through these steps."

    echo ""
    info "Step 1: Waiting for Ollama service to start..."

    local max_attempts=120 # Wait up to 10 minutes for service to start
    local attempt=1
    local ollama_started=0

    while [ $attempt -le $max_attempts ]; do
        # Check if ollama is running by querying the API version endpoint
        if curl --output /dev/null --silent --fail http://localhost:11434/api/version; then
            success "$CHECKMARK Ollama service is running (API accessible)"
            ollama_started=1
            break
        fi

        # Show progress every 10 attempts
        if [ $((attempt % 10)) -eq 0 ]; then
            info "Still waiting for Ollama to start... ($attempt/$max_attempts)"
            # Show the container status
            docker ps --filter "name=ollama" --format "{{.Status}}"
        else
            printf '.'
        fi

        sleep 5
        attempt=$((attempt+1))
    done

    if [ $ollama_started -eq 0 ]; then
        warning "Ollama service did not start within the expected timeframe (10 minutes)."
        warning "You may need to troubleshoot by checking: docker logs ollama"
        read -p "Do you want to continue anyway? (y/n): " continue_anyway
        if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
            fatal "Installation aborted due to Ollama startup issues."
        fi
    fi

    echo ""
    info "Step 2: Downloading and preparing the Gemma3:4b model..."
    info "(This is a large model and may take several minutes to download and prepare)"
    info "You can monitor progress by running 'docker logs -f ollama' in another terminal"
    echo ""

    DOCKER_CMD=$(get_docker_command) # Get docker or sudo docker

    # Check if model is already pulled
    model_exists=$($DOCKER_CMD exec ollama ollama list 2>/dev/null | grep -c "gemma3:4b")

    if [ "$model_exists" -gt 0 ]; then
        info "Model Gemma3:4b is already pulled, skipping download"
    else
        info "Starting model pull... (this may take 5-10 minutes)"

        # Run the pull command in background and capture PID
        ($DOCKER_CMD exec ollama ollama pull gemma3:4b) &
        pull_pid=$!

        # Show spinner with progress message
        show_progress_spinner "Downloading and preparing Gemma3:4b model" $pull_pid

        # Check if pull was successful
        wait $pull_pid
        pull_status=$?

        if [ $pull_status -ne 0 ]; then
            warning "Failed to pull Ollama model automatically."
            warning "You can try running 'docker exec ollama ollama pull gemma3:4b' manually later."
            read -p "Do you want to continue with the installation anyway? (y/n): " continue_anyway
            if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
                fatal "Installation aborted due to model pull failure."
            fi
        else
            success "$CHECKMARK Ollama model pulled successfully."
        fi
    fi

    echo ""
    info "Ollama with Gemma3:4b model is now ready to use"
    info "You can test it directly with:"
    info "  docker exec -it ollama ollama run gemma3:4b \"Tell me a joke\""
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

    # Login to quay.io for RIME images
    info "Logging in to quay.io for RIME images..."
    # This would need to be replaced with actual login credentials
    # docker login -u <username> -p <password> quay.io

    info "RIME credential setup complete"
}

main() {
    # Parse command line arguments using getopt
    OPTIONS=$(getopt -o '' --long platform-address:,platform-key:,tenant-id:,tts-address:,tts-key:,azure-region:,azure-speech-key:,renny-image: -- "$@")
    if [ $? -ne 0 ]; then
        usage
    fi

    # Ensure configuration.dat exists
    ensure_configuration_file_exists

    # Ensure docker-compose.env exists
    ensure_env_file_exists

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

        read -p "All configuration values are already set. Proceed with installation? (Y/n): " confirm
        if [[ "$confirm" =~ ^[Nn] ]]; then
            info "Installation aborted by user."
            exit 0
        fi
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

    # now use the platform address provided to form the DHOP address and pixelstreaming address
    DHOP_ADDRESS=$(format_dhop_address "$PLATFORM_ADDRESS" "/signalling-service/v1/ws/renderer")
    read protocol address port path < <(extract_url_components "$PLATFORM_ADDRESS")
    DHOP_PS_ADDRESS=$(format_dhop_address "$address" ":443/signalling-service/v1/ws/pixelstreaming") # form the pixel streaming address using the address part of the platform address

    info "DHOP address: $DHOP_ADDRESS"

    # update the .env file with the provided values
    update_env_variable "DHOP_ADDRESS" "$DHOP_ADDRESS"
    update_env_variable "DHOP_APIKEY" "\"$PLATFORM_KEY\""
    update_env_variable "DHOP_PIXELSTREAMING_ADDRESS" "$DHOP_PS_ADDRESS"
    update_env_variable "DHOP_TENANTID" "$TENANT_ID"
    update_env_variable "AZURE_REGION" "$AZURE_REGION"

    # Check which Azure speech key variable is used in the file
    if grep -q "AZURE_SPEECH=" "docker/docker-compose.env"; then
        update_env_variable "AZURE_SPEECH" "$AZURE_SPEECH_KEY"
    else
        update_env_variable "AZURE_SPEECH_KEY" "$AZURE_SPEECH_KEY"
    fi

    # Update the Docker image in docker-compose.yml if provided
    update_docker_compose_image "$RENNY_IMAGE"

    # Check and update configuration.dat
    check_and_update_configuration "$TENANT_ID" "$PLATFORM_KEY"

    # check to make sure the cloud services are reachable
    check_cloud_services "$DHOP_ADDRESS" "$DHOP_PS_ADDRESS"

    # Setup RIME credentials
    setup_rime_credentials

    # Build the log streamer service
    build_log_streamer

    # pull the images down
    pull_docker_images

    # Start the Miniprem system
    start_miniprem

    # Pull Gemma3:4b inside the Ollama container
    pull_ollama_model

    # Setup Flowise chatflow
    setup_flowise_chatflow

    success "$CHECKMARK Installation and configuration complete."
    info "Miniprem is now running. You can access:"
    info "- Flowise at http://localhost:3000"
    info "- Renny service health at http://localhost:8081/health"
    info "- Documentation with logs viewer at http://localhost:3000/docs/ (if you've set up the documentation server)"
    info "To stop the services, use: cd docker && docker compose down"
}

main "$@"