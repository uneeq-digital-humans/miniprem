#!/bin/bash

# NOT TO BE RUN DIRECTLY, PLEASE RUN THE MAIN SCRIPT CALLED "install_miniprem.sh"

# Function to check if the user is in the Docker group and return the appropriate command
get_docker_command() {
    if systemctl --user is-active docker >/dev/null 2>&1; then
        echo "docker"
    else
        # Command about to be run using sudo, prompt for sudo password now (outside of the spinner)
        sudo -v

        echo "sudo docker"
    fi
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

    # Check if Docker rootless mode is installed
    if ! command_exists dockerd-rootless-setuptool.sh; then
        warning 'Docker rootless mode is not installed. Installing Docker rootless mode...'

        # Prompt for sudo password
        sudo -v

        # Install Docker rootless mode
        {
            sudo apt-get update
            sudo apt-get install -y uidmap
            curl -fsSL https://get.docker.com/rootless | sh
        } &
        show_spinner $!
        success "$CHECKMARK Docker rootless mode installed successfully."
    fi

    # Set up Docker rootless mode for the current user
    if ! systemctl --user is-active docker >/dev/null 2>&1; then
        warning 'Setting up Docker rootless mode for the current user...'

        # Add a small sleep before installing the uidmap package just to make sure apt-get has finished updating
        sleep 2

        # Ensure required packages are installed
        sudo apt-get install -y uidmap

        # Set up Docker rootless mode
        dockerd-rootless-setuptool.sh install
        if [ $? -ne 0 ]; then
            fatal "$CROSS Failed to set up Docker rootless mode. Please check the requirements and try again."
        fi

        # Enable and start the Docker daemon in rootless mode
        systemctl --user enable docker
        systemctl --user start docker

        success "$CHECKMARK Docker rootless mode set up for the current user"
    fi

    docker_version=$(docker --version | awk '{print $3}' | sed 's/,//')
    success "$CHECKMARK Docker version: $docker_version"
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

        # now configure so that in rootless mode the nvidia runtime can still be used
        nvidia-ctk runtime configure --runtime=docker --config=$HOME/.config/docker/daemon.json  > /dev/null 2>&1
        systemctl --user restart docker  > /dev/null 2>&1
        sudo nvidia-ctk config --set nvidia-container-cli.no-cgroups --in-place  > /dev/null 2>&1
    fi

    nvidia_toolkit_version=$(dpkg-query -W -f='${Version}' nvidia-container-toolkit)
    success "$CHECKMARK Nvidia Container Toolkit version: $nvidia_toolkit_version"
}

perform_nvidia_runtime_test() {
    info "Performing test to ensure Nvidia docker runtime is operational..."

    DOCKER_CMD=$(get_docker_command)

    {
        # Perform a test to make sure Nvidia runtime is working
        nvidia_smi_output=$($DOCKER_CMD run --rm --runtime=nvidia --gpus all nvidia/cuda:11.6.2-base-ubuntu20.04 nvidia-smi 2>/dev/null)
        if ! echo "$nvidia_smi_output" | grep -q "NVIDIA-SMI"; then
            fatal "$CROSS Nvidia runtime test failed. Please check your installation."
        fi
    } &
    show_spinner $!
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

    # Change to the project root (if not already there)
    cd "$(dirname "$0")/.." > /dev/null 2>&1 || { fatal "$CROSS Failed to change directory to project root"; }

    DOCKER_CMD=$(get_docker_command)

    # Check INSTALL_TYPE from environment or argument
    local install_type="${INSTALL_TYPE:-$1}"
    local compose_files="-f docker/docker-compose.base.yml"
    if [ "$install_type" = "full" ]; then
        compose_files="-f docker/docker-compose.base.yml -f docker/docker-compose.extras.yml"
    fi

    if [ "$install_type" = "full" ]; then
        # First, pull public images (Grafana, Prometheus, Redis)
        info "Pulling public images (Grafana, Prometheus, Redis)..."
        {
            $DOCKER_CMD pull grafana/grafana:latest
            $DOCKER_CMD pull prom/prometheus:latest
            $DOCKER_CMD pull redis:latest
        } &
        show_spinner $!
        success "$CHECKMARK Public Docker images pulled successfully."
    fi

    # Docker login for UneeQ images
    info "Logging in to UneeQ Docker registry for Renny and Audio2Face images..."
    read -p "Enter UneeQ Docker registry username: " UNEEQ_USERNAME
    read -s -p "Enter UneeQ personal access token (PAT): " UNEEQ_PAT
    echo

    # Log in to the UneeQ Docker registry using stdin to provide the PAT
    echo "$UNEEQ_PAT" | $DOCKER_CMD login -u "$UNEEQ_USERNAME" --password-stdin
    if [ $? -ne 0 ]; then
        fatal "$CROSS Failed to login to UneeQ Docker registry."
    fi
    success "$CHECKMARK Successfully logged in to UneeQ Docker registry."
    
    # Pull images for the selected install type
    info "Pulling Docker images for selected install type..."
    {
        $DOCKER_CMD compose $compose_files pull
    } &
    show_spinner $!
    success "$CHECKMARK Docker images pulled successfully for selected install type."

    cd - > /dev/null 2>&1 || { fatal "$CROSS Failed to change back to the original directory"; }
}

start_docker_compose() {
    log_section "Starting Docker Compose Services"
    DOCKER_CMD=$(get_docker_command)
    local compose_file="${1:-"-f docker/docker-compose.yml"}"
    info "Starting Docker Compose services..."
    $DOCKER_CMD compose $compose_file up -d
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
    $DOCKER_CMD compose $compose_file down
    if [ $? -ne 0 ]; then
        fatal "$CROSS Failed to stop Docker Compose services."
    fi
    success "$CHECKMARK Docker Compose services stopped successfully."
}

update_docker_compose_image() {
    local image_name=$1
    local compose_file="docker/docker-compose.yml"

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
    local compose_file="docker/docker-compose.yml"

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