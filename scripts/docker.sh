#!/bin/bash

# NOT TO BE RUN DIRECTLY, PLEASE RUN THE MAIN SCRIPT CALLED "install_miniprem.sh"

# Function to check if the user is in the Docker group and return the appropriate command
get_docker_command() {
        # Command about to be run using sudo, prompt for sudo password now (outside of the spinner)
        sudo -v

        echo "sudo docker"
}

check_docker_installed() {
    # Check if Docker is installed
    if ! command_exists docker; then
        warning 'Docker is not installed. Installing Docker...'

        # Prompt for sudo password
        sudo -v

        # Run commands with spinner
        {
            curl https://get.docker.com | sh && sudo systemctl --now enable docker
        } &
        show_spinner $!
        success "$CHECKMARK Docker & compose installed successfully."
    fi

    docker_version=$(docker --version | awk '{print $3}' | sed 's/,//')
    success "$CHECKMARK Docker version: $docker_version"

    # Check for docker-compose (v1) or docker compose (v2)
    if ! command_exists docker-compose && ! docker compose version >/dev/null 2>&1; then
        fatal "docker-compose is not installed. Please install Docker Compose."
        fatal "Visit https://docs.docker.com/compose/install/ for installation instructions."
    fi

    # Determine which docker-compose command to use
    if command_exists docker-compose; then
        DOCKER_COMPOSE_CMD="docker-compose"
        compose_version=$(docker-compose --version | awk '{print $3}' | sed 's/,//')
        success "$CHECKMARK Docker Compose (v1) version: $compose_version"
    else
        DOCKER_COMPOSE_CMD="docker compose"
        compose_version=$(docker compose version | awk '{print $4}')
        success "$CHECKMARK Docker Compose (v2) version: $compose_version"
    fi

    # Export for use in other functions
    export DOCKER_COMPOSE_CMD
}

check_nvidia_toolkit() {
    # Check if Nvidia Container Toolkit is installed
    if ! dpkg-query -W -f='${Status}' nvidia-container-toolkit 2>/dev/null | grep -q "ok installed"; then
        info "Nvidia Container Toolkit is not installed. Installing Nvidia Container Toolkit..."

        # Prompt for sudo password
        sudo -v

        # Run apt-get commands with spinner.
        # See this page for more information: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html
        {
            if [[ -f /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg ]]; then
                sudo rm /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
            fi
            curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg > /dev/null 2>&1 \
                && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
                sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
                sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null 2>&1
            if [ $? -ne 0 ]; then
                fatal "$CROSS Failed to add Nvidia Docker GPG key so that Nvidia docker runtime can be installed."
            fi

            sudo apt-get update > /dev/null 2>&1
            sudo apt-get install -y nvidia-container-toolkit > /dev/null 2>&1
            sudo systemctl restart docker > /dev/null 2>&1
            sudo nvidia-ctk runtime configure --runtime=docker > /dev/null 2>&1
            sudo systemctl restart docker > /dev/null 2>&1
        } &
        show_spinner $!
        success "$CHECKMARK Nvidia Docker runtime installed successfully."
    fi

    nvidia_toolkit_version=$(dpkg-query -W -f='${Version}' nvidia-container-toolkit)
    success "$CHECKMARK Nvidia Container Toolkit version: $nvidia_toolkit_version"
}

perform_nvidia_runtime_test() {
    info "Performing test to ensure Nvidia docker runtime is operational..."

    DOCKER_CMD=$(get_docker_command)

    # Pull the test image first (might take a while on first run)
    info "Pulling NVIDIA CUDA test image (if not already cached)..."

    # Temporarily disable exit-on-error for this pull command
    set +e
    local pull_output
    pull_output=$(eval $DOCKER_CMD pull nvidia/cuda:11.6.2-base-ubuntu20.04 2>&1)
    local pull_exit=$?
    set -e  # Re-enable exit-on-error

    if [ $pull_exit -ne 0 ]; then
        warning "Failed to pull NVIDIA CUDA test image (exit code: $pull_exit)"
        info "Will attempt to use cached version. Pull output:"
        echo "$pull_output" | head -5  # Show first 5 lines of error
    else
        success "$CHECKMARK NVIDIA CUDA test image ready"
    fi

    # Create a temp file to capture output from background process
    local temp_output=$(mktemp)

    {
        # Perform a test to make sure Nvidia runtime is working
        # Store both stdout and stderr for better debugging
        nvidia_smi_output=$(eval $DOCKER_CMD run --rm --privileged --gpus all nvidia/cuda:11.6.2-base-ubuntu20.04 nvidia-smi 2>&1)
        exit_code=$?

        if [ $exit_code -ne 0 ]; then
            echo "ERROR: Docker NVIDIA runtime test failed with exit code $exit_code" > "$temp_output"
            echo "Output: $nvidia_smi_output" >> "$temp_output"
            exit 1
        fi

        if ! echo "$nvidia_smi_output" | grep -q "NVIDIA-SMI"; then
            echo "ERROR: nvidia-smi output does not contain expected 'NVIDIA-SMI' string" > "$temp_output"
            echo "Output: $nvidia_smi_output" >> "$temp_output"
            exit 1
        fi

        rm -f "$temp_output"
    } &

    local bg_pid=$!
    show_spinner $bg_pid
    local spinner_exit=$?

    if [ $spinner_exit -ne 0 ]; then
        # Show the error output if it exists
        if [ -f "$temp_output" ]; then
            error "NVIDIA Docker runtime test failed:"
            cat "$temp_output"
            rm -f "$temp_output"
        fi
        fatal "$CROSS Nvidia runtime test failed. Check Docker GPU support."
    fi

    rm -f "$temp_output"
    success "$CHECKMARK Nvidia runtime is working correctly."
}

check_docker_installation() {
    log_section "Docker Prerequisites"

    check_docker_installed

    check_nvidia_toolkit

    perform_nvidia_runtime_test
}

pull_docker_images() {
    log_section "Pulling Docker Images"

    # Store the current directory
    local current_dir=$(pwd)
    
    # Check INSTALL_TYPE from environment or argument
    local install_type="${INSTALL_TYPE:-$1}"
    local compose_file=""
    
    # Use the correct path for the docker-compose file
    if [ "$install_type" = "full" ]; then
        compose_file="-f $current_dir/docker/docker-compose.full.yml"
    else
        compose_file="-f $current_dir/docker/docker-compose.yml"
    fi

    DOCKER_CMD=$(get_docker_command)

    if [ "$install_type" = "full" ]; then
        # First, pull public images (Grafana, Prometheus, Redis)
        info "Pulling public images (Grafana, Prometheus, Redis)..."
        {
            eval $DOCKER_CMD pull grafana/grafana:latest
            eval $DOCKER_CMD pull prom/prometheus:latest
            eval $DOCKER_CMD pull redis:latest
        } &
        show_spinner $!
        success "$CHECKMARK Public Docker images pulled successfully."
        
        # Pull TTS-specific images if needed
        if [ "$TTS_PROVIDER" = "rime" ]; then
            info "Pulling RIME-specific images..."
            # RIME images are handled through setup_rime_credentials via quay.io authentication
        fi
    else
        # For default installation, pull TTS-specific images if needed
        if [ "$TTS_PROVIDER" = "rime" ]; then
            info "Pulling RIME-specific images for default installation..."
            # RIME images are handled through setup_rime_credentials via quay.io authentication
        fi
    fi

    # Docker login for Harbor registry
    info "Logging in to Harbor registry (cr.uneeq.io) for Renny images..."
    info "If you don't have Harbor credentials:"
    info "  - Contact: help@uneeq.com"
    info "  - Or ask your UneeQ representative"
    echo

    read -p "Enter Harbor robot username (e.g., robot\$customer-name): " HARBOR_USERNAME
    read -s -p "Enter Harbor robot password: " HARBOR_PASSWORD
    echo

    # Test network connectivity to Harbor
    info "Testing connectivity to cr.uneeq.io..."
    if ! curl --max-time 10 --silent --fail --output /dev/null "https://cr.uneeq.io" 2>/dev/null; then
        warning "Cannot reach cr.uneeq.io"
        warning "Please ensure:"
        warning "  1. You have internet connectivity"
        warning "  2. Your firewall allows HTTPS to cr.uneeq.io (port 443)"
        warning "  3. Corporate networks: cr.uneeq.io is whitelisted"
        fatal "Network connectivity test failed"
    fi
    success "$CHECKMARK Network connectivity to Harbor verified"

    # Log in to Harbor registry using stdin to provide credentials
    # Note: eval is needed for DOCKER_CMD expansion, single quotes prevent $HARBOR_USERNAME expansion
    echo "$HARBOR_PASSWORD" | eval "$DOCKER_CMD" login https://cr.uneeq.io -u \'"$HARBOR_USERNAME"\' --password-stdin
    if [ $? -ne 0 ]; then
        error "Failed to authenticate with Harbor registry"
        error "Please verify:"
        error "  1. Username format is correct (robot\$customer-name)"
        error "  2. Password is correct"
        error "  3. Robot account has 'Pull Repository' permission"
        fatal "$CROSS Harbor authentication failed. Contact help@uneeq.com for assistance."
    fi
    success "$CHECKMARK Successfully logged in to Harbor registry."
    
    # Pull images for the selected install type
    info "Pulling Docker images for selected install type..."
    {
        # Change to the directory containing the docker-compose file
        cd $current_dir
        eval $DOCKER_CMD compose $compose_file pull
    } &
    show_spinner $!
    success "$CHECKMARK Docker images pulled successfully for selected install type."
}

start_docker_compose() {
    log_section "Starting Docker Compose Services"
    DOCKER_CMD=$(get_docker_command)
    local compose_file="${1:-"-f docker/docker-compose.yml"}"
    info "Starting Docker Compose services..."
    eval $DOCKER_CMD compose $compose_file up -d
    if [ $? -ne 0 ]; then
        fatal "$CROSS Failed to start Docker Compose services."
    fi
    success "$CHECKMARK Docker Compose services started successfully."
}

stop_docker_compose() {
    log_section "Stopping Docker Compose Services"
    DOCKER_CMD=$(get_docker_command)
    local compose_file="${1:-"-f docker/docker-compose.yml"}"
    info "Stopping Docker Compose services..."
    eval $DOCKER_CMD compose $compose_file down
    if [ $? -ne 0 ]; then
        fatal "$CROSS Failed to stop Docker Compose services."
    fi
    success "$CHECKMARK Docker Compose services stopped successfully."
}

update_docker_compose_image() {
    local image_name=$1
    local install_type=$(cat "$PROJECT_ROOT/.miniprem_install_type" 2>/dev/null || echo "default")
    local compose_file="docker/docker-compose.yml"

    if [ "$install_type" = "full" ]; then
        compose_file="docker/docker-compose.full.yml"
    fi

    if [[ -f "$compose_file" ]]; then
        if yq eval ".services.renny.image = \"$image_name\"" -i "$compose_file"; then
            success "$CHECKMARK Updated Docker image in $compose_file to $image_name"
        else
            fatal "$CROSS Failed to update Docker image in $compose_file"
        fi
    else
        fatal "$CROSS Docker compose file $compose_file not found."
    fi
}

# Function to read the current image value from the docker-compose.yml file
read_docker_compose_value() {
    local key=$1
    local install_type=$(cat "$PROJECT_ROOT/.miniprem_install_type" 2>/dev/null || echo "default")
    local compose_file="docker/docker-compose.yml"

    if [ "$install_type" = "full" ]; then
        compose_file="docker/docker-compose.full.yml"
    fi

    if [[ -f "$compose_file" ]]; then
        yq eval ".services.renny.$key" "$compose_file"
    else
        warning "Docker compose file $compose_file not found. Trying fallback options."
        # Try miniprem services file as fallback
        compose_file="docker/docker-compose.miniprem.services.yml"
        if [[ -f "$compose_file" ]]; then
            yq eval ".services.renny.$key" "$compose_file"
        else
            fatal "$CROSS No valid Docker compose file found."
        fi
    fi
}