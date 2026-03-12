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
        # Unescape $$ back to $ (Docker Compose escaping for literal $)
        value="${value//\$\$/\$}"
    fi

    echo "$value"
}

# Function to update an environment variable in the .env file
# Escapes $ as $$ for Docker Compose compatibility (literal $ characters)
update_env_variable() {
    local var_name="$1"
    local new_value="$2"
    local env_file="docker/docker-compose.env"

    # Escape $ as $$ for Docker Compose .env file compatibility
    # Harbor robot usernames contain $ (e.g., robot$customer-name)
    local escaped_value="${new_value//\$/\$\$}"

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
        sed -i "s|^${var_name}=.*|${var_name}=${escaped_value}|" "$env_file"
    else
        # Add the variable if it does not exist
        echo "${var_name}=${escaped_value}" >> "$env_file"
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

# =============================================================================
# Harbor Registry Credential Management
# =============================================================================

# Check if Harbor credentials are configured and valid
check_harbor_credentials() {
    local username=$(read_env_variable "HARBOR_USERNAME")
    local password=$(read_env_variable "HARBOR_PASSWORD")

    # Return 1 if credentials are missing or placeholder values
    if [ -z "$username" ] || [ -z "$password" ]; then
        return 1
    fi
    if [ "$username" = "robot\$your-customer-name" ]; then
        return 1
    fi
    return 0
}

# Prompt for and save Harbor credentials
prompt_harbor_credentials() {
    info "Harbor registry credentials required for cr.uneeq.io"
    info "If you don't have Harbor credentials:"
    info "  - Contact: help@uneeq.com"
    info "  - Or ask your UneeQ representative"
    echo

    read -p "Enter Harbor robot username (e.g., robot\$customer-name): " harbor_user
    read -s -p "Enter Harbor robot password: " harbor_pass
    echo

    # Save credentials to env file
    update_env_variable "HARBOR_USERNAME" "$harbor_user"
    update_env_variable "HARBOR_PASSWORD" "$harbor_pass"
    success "$CHECKMARK Harbor credentials saved to docker/docker-compose.env"
}

# Login to Harbor using saved credentials
login_harbor_registry() {
    local username=$(read_env_variable "HARBOR_USERNAME")
    local password=$(read_env_variable "HARBOR_PASSWORD")
    DOCKER_CMD=$(get_docker_command)

    echo "$password" | eval "$DOCKER_CMD" login https://cr.uneeq.io -u \'"$username"\' --password-stdin
    return $?
}

# Full flow: check credentials, prompt if needed, login
# Call this before starting services to ensure Harbor authentication is valid
ensure_harbor_credentials() {
    # Quick check: do saved credentials exist in env file?
    if check_harbor_credentials; then
        info "Found Harbor credentials in docker/docker-compose.env, logging in..."
        if login_harbor_registry; then
            success "$CHECKMARK Harbor login successful"
            return 0
        fi
        warning "Saved Harbor credentials failed - may be expired or invalid"
    fi

    # Credentials missing or invalid - prompt user
    prompt_harbor_credentials
    if login_harbor_registry; then
        success "$CHECKMARK Harbor login successful"
        return 0
    else
        error "Harbor login failed with provided credentials"
        return 1
    fi
}

# Get the DHOP API hostname for the selected region
get_dhop_api_hostname() {
    case "${UNEEQ_REGION:-us}" in
        eu) echo "api-eu.enterprise.uneeq.io" ;;
        *)  echo "api.enterprise.uneeq.io" ;;
    esac
}

# Get the CDN hostname for the selected region
get_cdn_hostname() {
    case "${UNEEQ_REGION:-us}" in
        eu) echo "cdn-eu.enterprise.uneeq.io" ;;
        *)  echo "cdn.enterprise.uneeq.io" ;;
    esac
}

# Configure region-specific endpoints in the env file
configure_region_endpoints() {
    local api_host
    api_host=$(get_dhop_api_hostname)

    update_env_variable "DHOP_ADDRESS" "wss://${api_host}/signalling-service/v2/ws/renderer"
    update_env_variable "DHOP_PIXELSTREAMING_ADDRESS" "wss://${api_host}:443/signalling-service/v1/ws/pixelstreaming"
    info "Configured endpoints for region: ${UNEEQ_REGION:-us} (${api_host})"
}