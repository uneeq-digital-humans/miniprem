#!/bin/bash

# NOT TO BE RUN DIRECTLY, PLEASE RUN THE MAIN SCRIPT CALLED "install_miniprem.sh"

# variables which define the system requirements

# Function to validate Docker daemon is running and responsive
validate_docker_daemon() {
    log_section "Docker Daemon Validation"

    if ! timeout 5 sudo docker info > /dev/null 2>&1; then
        fatal "$CROSS Docker daemon is not running or unreachable (timeout after 5 seconds)"
        fatal "Try starting Docker: sudo service docker start"
        return 1
    fi

    success "$CHECKMARK Docker daemon is running and responsive"
    return 0
}

# Define required total GPU memory (in MB)
MIN_GPU_MEMORY=6000

# Required NVIDIA driver major version (install fails below this)
MIN_NVIDIA_DRIVER_VERSION=580

# Supported NVIDIA driver version (only this version is supported; warns on mismatch)
SUPPORTED_NVIDIA_DRIVER_VERSION="580.82.09"

# Define required minimum CUDA version
MIN_CUDA_VERSION=12.0

# Define minimum number of CPU cores
MIN_CPU_CORES=8

# Define minimum amount of RAM (in MB)
MIN_RAM=6000

# Define minimum free SSD space (in GB)
MIN_FREE_SSD_SPACE=64

# Define minimum Ubuntu version
MIN_UBUNTU_VERSION="24.04"

# Define minimum kernel version
MIN_KERNEL_VERSION="5.15"

# Define minimum Chrome version
MIN_CHROME_MAJOR_VERSION="124"

check_driver_prerequisites() {
    # Check if Nvidia drivers are installed
    
    log_section "Nvidia Driver Prerequisites"

    if ! command_exists nvidia-smi; then
        fatal 'Nvidia drivers are not installed. Please install Nvidia drivers and try again.'
    else
        # Extract driver version and CUDA version
        if ! driver_version=$(timeout 5 nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits 2>/dev/null); then
            log_warn "Could not query NVIDIA driver (GPU may be unavailable)"
            return 0
        fi
        cuda_version=$(timeout 5 nvidia-smi 2>/dev/null | grep -oP 'CUDA Version: \K[0-9.]+' || echo "")

        # Validate driver version is not empty
        if [[ -z "$driver_version" ]]; then
            log_warn "Could not determine NVIDIA driver version"
            return 0
        fi

        # Extract major version, handle various formats
        local major_version
        major_version=$(echo "$driver_version" | sed -E 's/([0-9]+).*/\1/')

        # Validate numeric format before arithmetic
        if ! [[ "$major_version" =~ ^[0-9]+$ ]]; then
            log_warn "Could not parse NVIDIA driver version: $driver_version"
            return 0
        fi

        # Check if driver version is at least the minimum required version
        if (( major_version < MIN_NVIDIA_DRIVER_VERSION )); then
            fatal "$CROSS Nvidia driver version is less than $MIN_NVIDIA_DRIVER_VERSION. Please install Nvidia driver version $MIN_NVIDIA_DRIVER_VERSION or higher."
        else
            success "$CHECKMARK Nvidia driver version $driver_version is sufficient."
        fi

        # Warn if not on the supported driver version
        if [[ "$driver_version" != "$SUPPORTED_NVIDIA_DRIVER_VERSION" ]]; then
            warning "Nvidia driver $driver_version detected. MiniPrem only supports $SUPPORTED_NVIDIA_DRIVER_VERSION."
        fi

        # Check if CUDA version is at least the minimum required version
        if (( $(echo "$cuda_version < $MIN_CUDA_VERSION" | bc -l) )); then
            fatal "$CROSS CUDA version is less than $MIN_CUDA_VERSION. Please install CUDA version $MIN_CUDA_VERSION or higher."
        else
            success "$CHECKMARK CUDA version $cuda_version is sufficient."
        fi
    fi
}

# Function to check if a command exists and works correctly
command_exists_and_works() {
    local cmd=$1
    if command -v "$cmd" >/dev/null 2>&1; then
        # Check if the command runs successfully
        "$cmd" --version >/dev/null 2>&1
        return $?
    else
        return 1
    fi
}

check_installer_prequisites() {
    log_section "Software Prerequisites"

    # check if jq is installed, if not install it
    if ! command_exists jq; then
        info "jq is not installed. Installing jq..."

        # Prompt for sudo password
        sudo -v

        # Run apt-get commands with spinner
        {
            sudo apt-get update > /dev/null 2>&1
            sudo apt-get install -y jq > /dev/null 2>&1
        } &
        show_spinner $!
        success "$CHECKMARK jq installed successfully."
    fi

    # Check if snap is installed, if not install it
    if ! command_exists snap; then
        info "snap is not installed. Installing snap..."

        # Prompt for sudo password
        sudo -v

        {
            # Install snapd
            sudo apt update
            sudo apt install -y snapd

            # Enable and start snapd service
            sudo systemctl enable --now snapd
        } &
        show_spinner $!
        success "$CHECKMARK snap installed successfully."
    fi

    # Check if yq is installed, if not install it using snap
    if ! command_exists_and_works yq; then
        info "yq is not installed or not working correctly. Installing yq using snap..."

        # Prompt for sudo password
        sudo -v

        {
            # Install yq using snap
            sudo snap install yq
        } &
        show_spinner $!
        success "$CHECKMARK yq installed successfully."
    fi

    success "$CHECKMARK installer software prerequisites are met."
}

check_software_prequisites() {
    # pull the OS version and kernel version
    log_section "Software Prerequisites"

    # Check if OS is Ubuntu and version is at least the minimum required
    os_version=$(lsb_release -rs)
    if [[ $(lsb_release -is) != "Ubuntu" ]] || (( $(echo "$os_version < $MIN_UBUNTU_VERSION" | bc -l) )); then
        fatal "$CROSS OS is not Ubuntu or version is less than $MIN_UBUNTU_VERSION. Please use Ubuntu version $MIN_UBUNTU_VERSION or higher."
    else
        success "$CHECKMARK OS is Ubuntu and version $os_version is sufficient."
    fi

    # Check if kernel version is at least the minimum required
    kernel_version=$(uname -r | cut -d '-' -f 1 | awk -F. '{print $1"."$2}')
    if (( $(echo "$kernel_version < $MIN_KERNEL_VERSION" | bc -l) )); then
        fatal "$CROSS Kernel version is less than $MIN_KERNEL_VERSION. Please use kernel version $MIN_KERNEL_VERSION or higher."
    else
        success "$CHECKMARK Kernel version $kernel_version is sufficient."
    fi

    # Check if Chrome is installed and version is at least the minimum required
    if ! command_exists google-chrome; then
        fatal "$CROSS Google Chrome is not installed. Please install Google Chrome and try again."
    else
        chrome_version=$(google-chrome --version | cut -d ' ' -f 3 | cut -d '.' -f 1)
        if (( $chrome_version < $MIN_CHROME_MAJOR_VERSION )); then
            fatal "$CROSS Google Chrome version is less than $MIN_CHROME_MAJOR_VERSION. Please install Google Chrome version $MIN_CHROME_MAJOR_VERSION or higher."
        else
            success "$CHECKMARK Google Chrome version $chrome_version is sufficient."
        fi
    fi

    # Check if pactl is installed, if not install it
    if ! command_exists pactl; then
        info "pactl is not installed. This is required for audio checks. Installing pulseaudio-utils..."

        # Prompt for sudo password
        sudo -v

        # Run apt-get commands with spinner
        {
            sudo apt-get update > /dev/null 2>&1
            sudo apt-get install -y pulseaudio-utils > /dev/null 2>&1
        } &
        show_spinner $!
        success "$CHECKMARK pactl installed successfully."
    fi

    # Check if curl is installed, if not install it
    if ! command_exists curl; then
        info "curl is not installed. Installing curl..."

        # Prompt for sudo password
        sudo -v

        # Run apt-get commands with spinner
        {
            sudo apt-get update > /dev/null 2>&1
            sudo apt-get install -y curl > /dev/null 2>&1
        } &
        show_spinner $!
        success "$CHECKMARK curl installed successfully."
    fi

    # Check if curl is installed, if not install it
    if ! command_exists socat; then
        info "socat is not installed. Installing socat..."

        # Prompt for sudo password
        sudo -v

        # Run apt-get commands with spinner
        {
            sudo apt-get update > /dev/null 2>&1
            sudo apt-get install -y socat > /dev/null 2>&1
        } &
        show_spinner $!
        success "$CHECKMARK socat installed successfully."
    fi
}

# Function to check hardware prerequisites such as Nvidia GPU, num CPU cores, amount of RAM, free SSD space etc.
check_hardware_prerequisites() {
    # assumes driver prerequisites are met
    log_section "Hardware Prerequisites"

    # Check if Nvidia GPU is available
    if ! command_exists nvidia-smi; then
        # shouldn't reach here if check_driver_prerequisites has already apssed
        fatal "$CROSS Nvidia GPU is not available. Please install Nvidia GPU and try again"
    else
        # Get GPU count
        gpu_count=$(nvidia-smi --query-gpu=count --format=csv,noheader,nounits | head -1)
        info "\tDetected ${gpu_count} GPU(s)"

        # Extract GPU models and memory info for all GPUs
        gpu_models=$(nvidia-smi --query-gpu=name --format=csv,noheader,nounits)
        gpu_memory_info=$(nvidia-smi --query-gpu=memory.total,memory.used --format=csv,noheader,nounits)

        # Check each GPU and find at least one with sufficient memory
        gpu_index=0
        sufficient_gpu_found=false

        while IFS= read -r memory_line && IFS= read -r model_line <&3; do
            gpu_index=$((gpu_index + 1))

            # Parse total and used memory for this GPU
            total_memory=$(echo "$memory_line" | cut -d ',' -f 1 | xargs)
            used_memory=$(echo "$memory_line" | cut -d ',' -f 2 | xargs)
            free_memory=$((total_memory - used_memory))

            # Display info for this GPU
            info "\tGPU ${gpu_index}: ${model_line}"
            info "\t  Total: ${total_memory} MB, Used: ${used_memory} MB, Free: ${free_memory} MB"

            # Check if this GPU meets requirements
            if [ "$free_memory" -ge "$MIN_GPU_MEMORY" ]; then
                success "$CHECKMARK GPU ${gpu_index} has sufficient free memory (${free_memory} MB >= ${MIN_GPU_MEMORY} MB)"
                sufficient_gpu_found=true
            else
                warning "GPU ${gpu_index} does not have sufficient free memory (${free_memory} MB < ${MIN_GPU_MEMORY} MB)"
            fi
        done <<< "$gpu_memory_info" 3<<< "$gpu_models"

        # If no GPU with sufficient memory was found, fail
        if [ "$sufficient_gpu_found" = false ]; then
            fatal "$CROSS No GPU found with at least ${MIN_GPU_MEMORY} MB of free memory. Please free up GPU memory or use a system with more GPU resources."
        fi
    fi

    # check number of CPU cores and CPU model
    num_cores=$(nproc)
    cpu_model=$(lscpu | grep 'Model name' | cut -d ':' -f 2 | xargs)
    info "\tCPU Model: $cpu_model"
    # Check if number of CPU cores is sufficient
    if [ $num_cores -lt $MIN_CPU_CORES ]; then
        fatal "$CROSS Number of CPU cores is less than ${MIN_CPU_CORES}. Please use a system with at least ${MIN_CPU_CORES} CPU cores."
    else
        success "$CHECKMARK Number of CPU cores is sufficient. Total cores: ${num_cores}"
    fi

    # check amount of RAM is sufficient
    total_ram=$(free -m | grep Mem | awk '{print $2}')
    if [ $total_ram -lt $MIN_RAM ]; then
        fatal "$CROSS Total RAM is less than ${MIN_RAM} MB. Please use a system with at least ${MIN_RAM} MB of RAM."
    else
        success "$CHECKMARK Total RAM is sufficient. Total RAM: ${total_ram} MB"
    fi

    # check free SSD space is sufficient
    free_space=$(df -BG / | tail -1 | awk '{print $4}' | sed 's/G//')
    if [ $free_space -lt $MIN_FREE_SSD_SPACE ]; then
        fatal "$CROSS Free SSD space is less than ${MIN_FREE_SSD_SPACE} GB. Please ensure at least ${MIN_FREE_SSD_SPACE} GB of free SSD space."
    else
        success "$CHECKMARK Free SSD space is sufficient. Free space: ${free_space} GB"
    fi

    # check what speaker and microphone are available
    playback_device=$(get_audio_playback_device)
    recording_device=$(get_audio_recording_device)

    # Log the information
    info "\tDefault Speaker: $playback_device"
    info "\tDefault Microphone: $recording_device"
}
