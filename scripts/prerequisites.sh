#!/bin/bash

# NOT TO BE RUN DIRECTLY, PLEASE RUN THE MAIN SCRIPT CALLED "install_miniprem.sh"

# variables which define the system requirements

# Define required total GPU memory (in MB)
MIN_GPU_MEMORY=16000

# Define required minimum NVIDIA driver version
MIN_NVIDIA_DRIVER_VERSION=535

# Define required minimum CUDA version
MIN_CUDA_VERSION=12.0

# Define minimum number of CPU cores
MIN_CPU_CORES=8

# Define minimum amount of RAM (in MB)
MIN_RAM=16000

# Define minimum free SSD space (in GB)
MIN_FREE_SSD_SPACE=128

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
        driver_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits)
        cuda_version=$(nvidia-smi | grep -oP 'CUDA Version: \K[0-9.]+')
        # Check if driver version is at least the minimum required version
        if [ $(echo $driver_version | cut -d '.' -f 1) -lt $MIN_NVIDIA_DRIVER_VERSION ]; then
            fatal "$CROSS Nvidia driver version is less than $MIN_NVIDIA_DRIVER_VERSION. Please install Nvidia driver version $MIN_NVIDIA_DRIVER_VERSION or higher."
        else
            success "$CHECKMARK Nvidia driver version $driver_version is sufficient."
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
        # Extract GPU model
        gpu_model=$(nvidia-smi --query-gpu=name --format=csv,noheader,nounits)
        info "\tGPU Model: $gpu_model"

        # Extract GPU memory information
        gpu_memory_info=$(nvidia-smi --query-gpu=memory.total,memory.used --format=csv,noheader,nounits)
        total_memory=$(echo $gpu_memory_info | cut -d ',' -f 1)
        used_memory=$(echo $gpu_memory_info | cut -d ',' -f 2)

        # Check if GPU memory is sufficient
        if [ $total_memory -lt $MIN_GPU_MEMORY ]; then
            fatal "$CROSS GPU memory is less than ${MIN_GPU_MEMORY} MB. Please use a GPU with at least ${MIN_GPU_MEMORY} MB memory"
        else
            success "$CHECKMARK GPU memory is sufficient. Total memory: ${total_memory} MB, free memory: $((total_memory - used_memory)) MB"
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