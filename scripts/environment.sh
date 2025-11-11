#!/bin/bash

# NOT TO BE RUN DIRECTLY, PLEASE RUN THE MAIN SCRIPT CALLED "install_miniprem.sh"

# Function to read existing values from the .env file
read_env_variable() {
    local var_name="$1"
    local env_file="docker/docker-compose.env"
    local value=""

    if [ -f "$env_file" ]; then
        value=$(grep "^${var_name}=" "$env_file" | cut -d '=' -f 2-)
        value=$(echo "$value" | sed 's/^"//;s/"$//') # Remove surrounding quotes if any
    fi

    echo "$value"
}

# Function to update an environment variable in the .env file
update_env_variable() {
    local var_name="$1"
    local new_value="$2"
    local env_file="docker/docker-compose.env"

    # Ensure the file exists
    if [[ ! -f "$env_file" ]]; then
        touch "$env_file"
    fi

    # Check if file is empty or doesn't end with newline
    if [[ ! -s "$env_file" ]] || [[ $(tail -c 1 "$env_file" | wc -l) -eq 0 ]]; then
        # File is empty or doesn't end with newline, no need to add one
        :
    else
        # Ensure there's a newline at the end of the file
        echo "" >> "$env_file"
    fi

    if grep -q "^${var_name}=" "$env_file"; then
        # Update the existing variable
        sed -i "s|^${var_name}=.*|${var_name}=${new_value}|" "$env_file"
    else
        # Add the variable if it does not exist
        echo "${var_name}=${new_value}" >> "$env_file"
    fi
}

# Function to configure Renny quality level based on deployment target
configure_renny_quality() {
    # Validate that deployment target was set by caller
    if [ -z "$DEPLOYMENT_TARGET" ]; then
        fatal "DEPLOYMENT_TARGET not set. prompt_deployment_target() must be called first."
    fi

    local quality_level=""

    # Map deployment target to quality level (RENNY_QUALITY_LEVEL env var)
    # These values are consumed by the Renny renderer to control rendering behavior:
    #   - "miniprem": High-fidelity rendering optimized for dedicated hardware with direct GPU access
    #   - "web": Performance-optimized rendering for cloud platforms with shared GPU resources
    case "$DEPLOYMENT_TARGET" in
        "hardware")
            quality_level="miniprem"  # High-fidelity rendering for local/on-premise installations
            info "Configuring for dedicated hardware: Higher rendering quality (RENNY_QUALITY_LEVEL=miniprem)"
            ;;
        "cloud")
            quality_level="web"  # Performance-optimized rendering for cloud platforms
            info "Configuring for cloud platform: Optimized performance (RENNY_QUALITY_LEVEL=web)"
            ;;
        *)
            fatal "Invalid deployment target: $DEPLOYMENT_TARGET"
            ;;
    esac

    # Update the environment variable and capture result immediately
    if update_env_variable "RENNY_QUALITY_LEVEL" "$quality_level"; then
        success "$CHECKMARK Renny quality level configured: RENNY_QUALITY_LEVEL=$quality_level"
        info "You can change this later by editing docker/docker-compose.env and restarting Renny"
    else
        warning "Failed to update RENNY_QUALITY_LEVEL, but continuing..."
    fi
}