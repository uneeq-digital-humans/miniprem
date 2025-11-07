#!/bin/bash
set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOCKER_DIR="$PROJECT_ROOT/docker"

# Source required scripts
source "$PROJECT_ROOT/scripts/logging.sh"

# Color codes (already defined in logging.sh, but ensuring we have them)
WHITE='\033[1;37m'

# Global state
COMPOSE_FILE=""
INSTALL_TYPE=""
NUM_INSTANCES=0
BASE_RENNY_CONFIG=""
BACKUP_FILE=""
DEBUG_MODE=false

# Ordinal names for instances
declare -a ORDINALS=(
    "first"
    "second"
    "third"
    "fourth"
    "fifth"
    "sixth"
    "seventh"
    "eighth"
    "ninth"
    "tenth"
    "eleventh"
    "twelfth"
    "thirteenth"
    "fourteenth"
    "fifteenth"
    "sixteenth"
    "seventeenth"
    "eighteenth"
    "nineteenth"
    "twentieth"
    "twenty-first"
    "twenty-second"
    "twenty-third"
    "twenty-fourth"
    "twenty-fifth"
    "twenty-sixth"
    "twenty-seventh"
    "twenty-eighth"
    "twenty-ninth"
    "thirtieth"
)

################################################################################
# Function: display_usage
# Description: Show usage information
# Arguments: None
# Returns: None
################################################################################
display_usage() {
    echo -e $WHITE
    cat <<EOF
$(basename "$0") - Configure multiple Renny containers for Docker deployment

Usage:
    $(basename "$0") [OPTIONS]

Options:
    -n, --number <count>    Number of Renny instances (2-30, default: interactive prompt)
    --debug                 Skip Docker operations (for testing file creation only)
    -h, --help              Display this help message

Examples:
    # Interactive mode (prompts for count)
    $(basename "$0")

    # Specify instance count directly
    $(basename "$0") -n 4

Description:
    This script configures multiple Renny containers to run in parallel on the same
    Docker host. It handles port allocation, environment variable configuration, and
    service definition management.

    Port Allocation:
        Instance 1 (renny):        Health: 8081, Metrics: 8080
        Instance 2 (renny-second): Health: 8091, Metrics: 8090
        Instance 3 (renny-third):  Health: 8101, Metrics: 8100
        Pattern: base_port + (instance_num - 1) * 10

Requirements:
    - Docker installation completed (requires .miniprem_install_type file)
    - docker-compose.env must exist in docker/ directory
    - Docker daemon running
    - Minimum 2 instances, maximum 30

EOF
    echo -e $NC
}

################################################################################
# Function: parse_arguments
# Description: Parse command-line arguments
# Arguments:
#   $@ - All command-line arguments
# Returns: 0 on success, 1 on error
################################################################################
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--number)
                if [[ -z "${2:-}" ]]; then
                    error "Option $1 requires an argument"
                    return 1
                fi
                NUM_INSTANCES="$2"
                shift 2
                ;;
            --debug)
                DEBUG_MODE=true
                info "Debug mode enabled - Docker operations will be skipped"
                shift
                ;;
            -h|--help)
                display_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                display_usage
                return 1
                ;;
        esac
    done
    return 0
}

################################################################################
# Function: validate_installation
# Description: Verify MiniPrem installation is complete
# Arguments: None
# Returns: 0 on success, exits on failure
################################################################################
validate_installation() {
    log_section "Validating MiniPrem Installation"

    # Check if installation type file exists
    if [ ! -f "$PROJECT_ROOT/.miniprem_install_type" ]; then
        fatal "MiniPrem installation not completed. Please run: ./docker/scripts/install_miniprem.sh"
    fi

    # Read installation type
    INSTALL_TYPE=$(cat "$PROJECT_ROOT/.miniprem_install_type")
    success "Installation type: $INSTALL_TYPE"

    # Select appropriate compose file
    if [ "$INSTALL_TYPE" = "default" ]; then
        COMPOSE_FILE="$DOCKER_DIR/docker-compose.yml"
    else
        COMPOSE_FILE="$DOCKER_DIR/docker-compose.full.yml"
    fi

    if [ ! -f "$COMPOSE_FILE" ]; then
        fatal "Docker compose file not found: $COMPOSE_FILE"
    fi
    success "Compose file: $(basename "$COMPOSE_FILE")"

    # Check for base environment file
    if [ ! -f "$DOCKER_DIR/docker-compose.env" ]; then
        fatal "Environment file not found: $DOCKER_DIR/docker-compose.env"
    fi
    success "Environment file: docker-compose.env"
}

################################################################################
# Function: validate_docker
# Description: Verify Docker daemon is running
# Arguments: None
# Returns: 0 on success, exits on failure
################################################################################
validate_docker() {
    info "Checking Docker daemon..."

    if ! docker ps > /dev/null 2>&1; then
        fatal "Docker daemon is not running. Please start Docker and retry."
    fi

    success "$CHECKMARK Docker daemon is running"
}

################################################################################
# Function: prompt_for_instance_count
# Description: Interactively ask user for number of instances
# Arguments: None
# Returns: Sets NUM_INSTANCES variable
################################################################################
prompt_for_instance_count() {
    log_section "Configuration - Number of Renny Instances"

    echo -e $LIGHTGRAY
    cat <<EOF
Recommendations:
  - 2 instances: Basic redundancy and failover capability
  - 3-4 instances: Balanced performance and resource usage (RECOMMENDED)
  - 5+ instances: High-capacity deployments requiring multiple GPUs

System requirements per instance:
  - GPU VRAM: 2-3 GB per instance
  - CPU: 1-2 cores per instance
  - RAM: 2-4 GB per instance

EOF
    echo -e $NC

    local valid_input=false
    while [ "$valid_input" = false ]; do
        echo -n "Enter number of Renny instances (2-30): "
        read -r user_input

        # Validate integer
        if ! [[ "$user_input" =~ ^[0-9]+$ ]]; then
            warning "Please enter a valid integer"
            continue
        fi

        # Validate range
        if [ "$user_input" -lt 2 ] || [ "$user_input" -gt 30 ]; then
            warning "Number must be between 2 and 30 (you entered: $user_input)"
            continue
        fi

        NUM_INSTANCES="$user_input"
        valid_input=true
    done

    echo ""
    success "$CHECKMARK You selected $NUM_INSTANCES Renny instances"
    info "Instances will use ports: 8080-$((8080 + (NUM_INSTANCES - 1) * 10)) (metrics)"
    info "Health checks on ports: 8081-$((8081 + (NUM_INSTANCES - 1) * 10))"
}

################################################################################
# Function: validate_instance_count
# Description: Validate user-provided instance count
# Arguments: None
# Returns: 0 on success, exits on failure
################################################################################
validate_instance_count() {
    log_section "Validating Instance Count"

    # Validate integer
    if ! [[ "$NUM_INSTANCES" =~ ^[0-9]+$ ]]; then
        fatal "Instance count must be an integer (you provided: $NUM_INSTANCES)"
    fi

    # Validate range
    if [ "$NUM_INSTANCES" -lt 2 ] || [ "$NUM_INSTANCES" -gt 30 ]; then
        fatal "Instance count must be between 2 and 30 (you provided: $NUM_INSTANCES)"
    fi

    success "$CHECKMARK Valid instance count: $NUM_INSTANCES"
}

################################################################################
# Function: extract_renny_service
# Description: Extract base Renny service definition from compose file
# Arguments: None
# Returns: Sets BASE_RENNY_CONFIG variable
################################################################################
extract_renny_service() {
    log_section "Extracting Renny Service Configuration"

    # Find the renny service block
    local in_renny_service=false
    local service_lines=()
    local line_num=0

    while IFS= read -r line; do
        line_num=$((line_num + 1))

        # Start of renny service
        if [[ "$line" =~ ^[[:space:]]*renny:[[:space:]]*$ ]]; then
            in_renny_service=true
            service_lines=("$line")
            continue
        fi

        # Skip non-renny services
        if [ "$in_renny_service" = false ]; then
            continue
        fi

        # Check if we've reached another service (at same indentation level as 'renny:')
        if [[ "$line" =~ ^[a-zA-Z0-9_-]+:[[:space:]]*$ ]] && [ ! -z "$line" ]; then
            # We've hit the next service, stop collecting
            break
        fi

        # End of file
        if [ -z "$line" ]; then
            # Empty line might be end of service, but continue to be sure
            if [ "${#service_lines[@]}" -gt 1 ]; then
                break
            fi
            continue
        fi

        # Collect service lines
        if [ "$in_renny_service" = true ]; then
            service_lines+=("$line")
        fi
    done < "$COMPOSE_FILE"

    if [ ${#service_lines[@]} -eq 0 ]; then
        fatal "Could not find 'renny' service definition in $COMPOSE_FILE"
    fi

    # Store the base config
    BASE_RENNY_CONFIG=$(printf '%s\n' "${service_lines[@]}")
    success "$CHECKMARK Extracted renny service definition (${#service_lines[@]} lines)"
}

################################################################################
# Function: get_ordinal_name
# Description: Get ordinal name for instance number
# Arguments:
#   $1 - Instance number (1-based)
# Returns: Prints ordinal name to stdout
################################################################################
get_ordinal_name() {
    local index=$((($1 - 1)))
    if [ $index -ge 0 ] && [ $index -lt ${#ORDINALS[@]} ]; then
        echo "${ORDINALS[$index]}"
    else
        echo "instance-$1"
    fi
}

################################################################################
# Function: calculate_ports
# Description: Calculate health and metrics ports for an instance
# Arguments:
#   $1 - Instance number (1-based)
# Returns: Prints "health_port metrics_port" to stdout
################################################################################
calculate_ports() {
    local instance_num=$1
    local health_port=$((8081 + (instance_num - 1) * 10))
    local metrics_port=$((8080 + (instance_num - 1) * 10))
    echo "$health_port $metrics_port"
}

################################################################################
# Function: create_instance_env_file
# Description: Create environment file for a specific Renny instance
# Arguments:
#   $1 - Instance number (1-based)
#   $2 - Ordinal name
# Returns: 0 on success, 1 on error
################################################################################
create_instance_env_file() {
    local instance_num=$1
    local ordinal_name=$2
    local env_filename="renny-${ordinal_name}.env"
    local env_filepath="$DOCKER_DIR/$env_filename"

    # Calculate ports
    local ports=$(calculate_ports "$instance_num")
    local health_port=$(echo "$ports" | awk '{print $1}')
    local metrics_port=$(echo "$ports" | awk '{print $2}')

    # Copy base env file
    if ! cp "$DOCKER_DIR/docker-compose.env" "$env_filepath"; then
        error "Failed to create environment file: $env_filepath"
        return 1
    fi

    # Update HEALTH_URL and METRICS_PORT in the new env file
    if ! sed -i.tmp "s|HEALTH_URL=.*|HEALTH_URL=http://0.0.0.0:${health_port}/health|g" "$env_filepath"; then
        error "Failed to update HEALTH_URL in $env_filename"
        rm -f "$env_filepath" "$env_filepath.tmp"
        return 1
    fi

    if ! sed -i.tmp "s|METRICS_PORT=.*|METRICS_PORT=$metrics_port|g" "$env_filepath"; then
        error "Failed to update METRICS_PORT in $env_filename"
        rm -f "$env_filepath" "$env_filepath.tmp"
        return 1
    fi

    # Clean up sed temporary file
    rm -f "$env_filepath.tmp"

    info "Created environment file: $env_filename (Health: $health_port, Metrics: $metrics_port)"
    return 0
}

################################################################################
# Function: clean_existing_instances
# Description: Remove existing custom Renny service definitions from compose file
# Arguments: None
# Returns: 0 on success, 1 on error
################################################################################
clean_existing_instances() {
    log_section "Cleaning Existing Custom Renny Instances"

    local temp_file="${COMPOSE_FILE}.tmp"
    local in_custom_renny=false
    local skip_line=false

    # Check if there are any custom renny instances to remove
    if ! grep -q "renny-second:" "$COMPOSE_FILE" 2>/dev/null; then
        info "No existing custom instances found"
        return 0
    fi

    info "Removing existing custom renny instances..."

    # Create new compose file without custom instances
    {
        while IFS= read -r line; do
            # Check if this is a custom renny service (renny-second, renny-third, etc.)
            if [[ "$line" =~ ^[[:space:]]*renny-(second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth|eleventh|twelfth|thirteenth|fourteenth|fifteenth|sixteenth|seventeenth|eighteenth|nineteenth|twentieth|twenty-first|twenty-second|twenty-third|twenty-fourth|twenty-fifth|twenty-sixth|twenty-seventh|twenty-eighth|twenty-ninth|thirtieth|instance-):[[:space:]]*$ ]]; then
                in_custom_renny=true
                skip_line=true
                continue
            fi

            # Check if we've reached another service
            if [ "$in_custom_renny" = true ] && [[ "$line" =~ ^[a-zA-Z0-9_-]+:[[:space:]]*$ ]] && [ ! -z "$line" ]; then
                in_custom_renny=false
            fi

            # Skip lines that are part of custom renny service
            if [ "$in_custom_renny" = true ]; then
                continue
            fi

            echo "$line"
        done < "$COMPOSE_FILE"
    } > "$temp_file"

    # Replace original file with cleaned version
    if ! mv "$temp_file" "$COMPOSE_FILE"; then
        error "Failed to update compose file"
        rm -f "$temp_file"
        return 1
    fi

    success "$CHECKMARK Cleaned existing custom instances"
    return 0
}

################################################################################
# Function: append_renny_instances
# Description: Append new Renny service definitions to compose file
# Arguments: None
# Returns: 0 on success, 1 on error
################################################################################
append_renny_instances() {
    log_section "Configuring Renny Instances"

    # Skip the first instance (it already exists in the base compose file)
    for ((i = 2; i <= NUM_INSTANCES; i++)); do
        local ordinal_name=$(get_ordinal_name "$i")
        local service_name="renny-${ordinal_name}"
        local ports=$(calculate_ports "$i")
        local health_port=$(echo "$ports" | awk '{print $1}')
        local metrics_port=$(echo "$ports" | awk '{print $2}')

        # Create environment file
        if ! create_instance_env_file "$i" "$ordinal_name"; then
            error "Failed to create environment file for instance $i"
            return 1
        fi

        info "Configuring $service_name (Health: $health_port, Metrics: $metrics_port)"
    done

    # Now append all custom instances to compose file
    {
        echo ""  # Blank line separator

        for ((i = 2; i <= NUM_INSTANCES; i++)); do
            local ordinal_name=$(get_ordinal_name "$i")
            local service_name="renny-${ordinal_name}"
            local health_port=$(calculate_ports "$i" | awk '{print $1}')
            local metrics_port=$(calculate_ports "$i" | awk '{print $2}')

            # Create modified service definition
            echo "$BASE_RENNY_CONFIG" | sed \
                -e "s/container_name: renny$/container_name: $service_name/" \
                -e "s/renny-second:/renny-${ordinal_name}:/" \
                -e 's/env_file:$/env_file:/' \
                -e "s|docker-compose.env|renny-${ordinal_name}.env|g" \
                -e "s|http://localhost:8081/health|http://0.0.0.0:${health_port}/health|g" \
                -e "s/^  renny:/  ${service_name}:/" \
                | sed "s/^  renny:/  ${service_name}:/" \
                | sed "s/^    container_name: renny$/    container_name: ${service_name}/" \
                | sed "s|env_file:.*|- docker-compose.env|" \
                | sed "s|env_file|env_file|" \
                | sed "s|- docker-compose.env|- renny-${ordinal_name}.env|"

            # Add blank line between services
            if [ $i -lt $NUM_INSTANCES ]; then
                echo ""
            fi
        done
    } >> "$COMPOSE_FILE" 2>/dev/null || {
        error "Failed to append instances to compose file"
        return 1
    }

    success "$CHECKMARK Added $((NUM_INSTANCES - 1)) custom Renny instances to compose file"
    return 0
}

################################################################################
# Function: append_renny_instances_correct
# Description: Properly append new Renny service definitions to compose file
# Arguments: None
# Returns: 0 on success, 1 on error
################################################################################
append_renny_instances_correct() {
    log_section "Adding Custom Renny Instances to Compose File"

    # First, create all environment files
    for ((i = 2; i <= NUM_INSTANCES; i++)); do
        local ordinal_name=$(get_ordinal_name "$i")
        if ! create_instance_env_file "$i" "$ordinal_name"; then
            error "Failed to create environment file for instance $i"
            return 1
        fi
    done

    # Append new services to compose file
    {
        echo ""  # Blank line separator

        for ((i = 2; i <= NUM_INSTANCES; i++)); do
            local ordinal_name=$(get_ordinal_name "$i")
            local service_name="renny-${ordinal_name}"
            local health_port=$(calculate_ports "$i" | awk '{print $1}')

            # Create modified service definition with proper indentation
            echo "  $service_name:"

            echo "$BASE_RENNY_CONFIG" | tail -n +2 | while IFS= read -r line; do
                # Replace container_name
                if [[ "$line" =~ container_name: ]]; then
                    echo "    container_name: $service_name"
                # Replace env_file
                elif [[ "$line" =~ env_file: ]]; then
                    echo "    env_file:"
                    read -r next_line  # Read the next line (usually the env file path)
                    echo "      - renny-${ordinal_name}.env"
                # Replace healthcheck port
                elif [[ "$line" =~ "http://localhost:8081/health" ]]; then
                    echo "$line" | sed "s|8081|$health_port|g"
                else
                    echo "$line"
                fi
            done

            # Add blank line between services
            if [ $i -lt $NUM_INSTANCES ]; then
                echo ""
            fi
        done
    } >> "$COMPOSE_FILE" 2>/dev/null || {
        error "Failed to append instances to compose file"
        return 1
    }

    success "$CHECKMARK Added $((NUM_INSTANCES - 1)) custom Renny instances to compose file"
    return 0
}

################################################################################
# Function: create_service_definitions
# Description: Create complete service definitions for all additional instances
# Arguments: None
# Returns: 0 on success, 1 on error
################################################################################
create_service_definitions() {
    log_section "Creating Service Definitions"

    # Create environment files and collect service definitions
    local temp_services_file="/tmp/renny_services_$$.txt"

    {
        for ((i = 2; i <= NUM_INSTANCES; i++)); do
            local ordinal_name=$(get_ordinal_name "$i")
            local service_name="renny-${ordinal_name}"
            local health_port=$(calculate_ports "$i" | awk '{print $1}')

            # Create environment file for this instance
            if ! create_instance_env_file "$i" "$ordinal_name"; then
                error "Failed to create environment file for instance $i"
                rm -f "$temp_services_file"
                return 1
            fi

            # Generate service definition
            cat << EOF
  $service_name:
    container_name: $service_name
    command: ["/Game/Live_Levels/BlankScene", "-RenderOffScreen", "-ResX=1920", "-ResY=1080", "-NoTextureStreaming"]
    entrypoint: ["/opt/renny/renny-entrypoint.sh"]
    env_file:
      - renny-${ordinal_name}.env
    environment:
      - NEW_SPEECH_OVERRIDE=1
      - MINIPREM_TELEMETRY_DISABLED=\${MINIPREM_TELEMETRY_DISABLED:-0}
      - TELEMETRY_BACKEND_URL=https://renny.services.uneeq.io
      - HEARTBEAT_INTERVAL_SECONDS=900
      - PLATFORM=docker
      - INSTALLATION_ID_FILE=/app/data/installation_id
    image: "facemeproduction/renny:0.713-37d59"
    network_mode: "host"
    runtime: nvidia
    privileged: true
    tty: true
    volumes:
      - ./configuration.dat:/opt/renny/Renny/Binaries/Linux/configuration.dat
      - ./renny-entrypoint.sh:/opt/renny/renny-entrypoint.sh:ro
      - ./renny-telemetry-client.sh:/opt/renny/telemetry-client.sh:ro
      - /tmp/miniprem_installation_id:/app/data/installation_id
      - /tmp/miniprem_telemetry_state:/app/telemetry_state
    healthcheck:
      test: "curl -f http://localhost:${health_port}/health"
      interval: 10s
      timeout: 500ms
      start_interval: 15s
      start_period: 10s
      retries: 3
    restart: unless-stopped
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    security_opt:
      - no-new-privileges:true

EOF
        done
    } > "$temp_services_file"

    # Ensure newline before appending services (avoid concatenation with last line)
    echo "" >> "$COMPOSE_FILE"

    # Append all services to compose file
    if ! cat "$temp_services_file" >> "$COMPOSE_FILE"; then
        error "Failed to append services to compose file"
        rm -f "$temp_services_file"
        return 1
    fi

    rm -f "$temp_services_file"
    success "$CHECKMARK Created $((NUM_INSTANCES - 1)) service definitions"
    return 0
}

################################################################################
# Function: backup_compose_file
# Description: Create backup of compose file before modifications
# Arguments: None
# Returns: 0 on success, 1 on error
################################################################################
backup_compose_file() {
    log_section "Creating Backup"

    BACKUP_FILE="${COMPOSE_FILE}.backup.$(date +%s)"

    if ! cp "$COMPOSE_FILE" "$BACKUP_FILE"; then
        error "Failed to backup compose file"
        return 1
    fi

    success "$CHECKMARK Backup created: $(basename "$BACKUP_FILE")"
    return 0
}

################################################################################
# Function: restart_services
# Description: Stop and start services with new configuration
# Arguments: None
# Returns: 0 on success, 1 on error
################################################################################
restart_services() {
    log_section "Restarting Services"

    if [ "$DEBUG_MODE" = true ]; then
        info "[DEBUG MODE] Skipping Docker operations"
        info "[DEBUG MODE] Would run: $PROJECT_ROOT/miniprem.sh stop"
        info "[DEBUG MODE] Would run: $PROJECT_ROOT/miniprem.sh start"
        info "[DEBUG MODE] Files created successfully:"
        info "  - Compose file: $COMPOSE_FILE"
        for ((i = 2; i <= NUM_INSTANCES; i++)); do
            local ordinal_name=$(get_ordinal_name "$i")
            info "  - renny-${ordinal_name}.env"
        done
        return 0
    fi

    info "Stopping current services..."
    if ! docker compose -f "$COMPOSE_FILE" down > /dev/null 2>&1; then
        warning "Could not gracefully stop services (may not be running)"
    fi

    sleep 2

    info "Starting services with new configuration..."
    if ! docker compose -f "$COMPOSE_FILE" up -d; then
        error "Failed to start services"
        return 1
    fi

    return 0
}

################################################################################
# Function: verify_containers_healthy
# Description: Verify all Renny containers are running and healthy
# Arguments: None
# Returns: 0 if all healthy, 1 otherwise
################################################################################
verify_containers_healthy() {
    log_section "Verifying Container Health"

    if [ "$DEBUG_MODE" = true ]; then
        info "[DEBUG MODE] Skipping container health verification"
        return 0
    fi

    local max_attempts=30
    local attempt=1
    local failed_containers=()

    info "Waiting for containers to stabilize..."

    while [ $attempt -le $max_attempts ]; do
        local all_healthy=true
        local container_count=$(docker ps -f label!=com.docker.compose.project -q 2>/dev/null | wc -l)

        for ((i = 1; i <= NUM_INSTANCES; i++)); do
            local service_name="renny"
            if [ $i -gt 1 ]; then
                service_name="renny-$(get_ordinal_name "$i")"
            fi

            # Check if container exists
            local container_id=$(docker ps -a -f name="^${service_name}$" -q 2>/dev/null)
            if [ -z "$container_id" ]; then
                all_healthy=false
                if [ $attempt -eq $max_attempts ]; then
                    failed_containers+=("$service_name (not found)")
                fi
                continue
            fi

            # Check if container is running
            local container_status=$(docker inspect "$container_id" --format='{{.State.Running}}' 2>/dev/null)
            if [ "$container_status" != "true" ]; then
                all_healthy=false
                if [ $attempt -eq $max_attempts ]; then
                    failed_containers+=("$service_name (not running)")
                fi
                continue
            fi

            # Check health status if healthcheck is configured
            local health_status=$(docker inspect "$container_id" --format='{{.State.Health.Status}}' 2>/dev/null)
            if [ ! -z "$health_status" ] && [ "$health_status" != "healthy" ] && [ "$health_status" != "" ]; then
                if [ $attempt -lt $max_attempts ]; then
                    all_healthy=false
                else
                    failed_containers+=("$service_name (health: $health_status)")
                fi
            fi
        done

        if [ "$all_healthy" = true ]; then
            success "$CHECKMARK All containers are healthy and running"
            return 0
        fi

        if [ $attempt -lt $max_attempts ]; then
            printf '.'
            sleep 1
            attempt=$((attempt + 1))
        else
            break
        fi
    done

    echo ""

    if [ ${#failed_containers[@]} -gt 0 ]; then
        error "The following containers failed to start or are not healthy:"
        for container in "${failed_containers[@]}"; do
            echo "  - $container"
        done
        return 1
    fi

    return 0
}

################################################################################
# Function: display_summary
# Description: Display summary of configuration
# Arguments: None
# Returns: None
################################################################################
display_summary() {
    log_section "Configuration Summary"

    echo -e $LIGHTGRAY
    cat <<EOF
Installation completed successfully!

Total Renny instances configured: $NUM_INSTANCES
Installation type: $INSTALL_TYPE
Compose file: $(basename "$COMPOSE_FILE")

Port Allocation:
EOF
    echo -e $NC

    for ((i = 1; i <= NUM_INSTANCES; i++)); do
        local service_name="renny"
        if [ $i -gt 1 ]; then
            service_name="renny-$(get_ordinal_name "$i")"
        fi

        local ports=$(calculate_ports "$i")
        local health_port=$(echo "$ports" | awk '{print $1}')
        local metrics_port=$(echo "$ports" | awk '{print $2}')

        printf "  %-20s Health: %-6s Metrics: %-6s\n" "$service_name" "$health_port" "$metrics_port"
    done

    echo ""
    echo -e $LIGHTGRAY
    cat <<EOF
Management Commands:
  Start services:   ./miniprem.sh start
  Stop services:    ./miniprem.sh stop
  Check status:     ./miniprem.sh status
  View logs:        ./miniprem.sh logs
  Restart services: ./miniprem.sh restart

Monitor Status:
  Open in browser: http://localhost:3001/
  Or run: ./miniprem.sh logs

Backup Information:
  Compose file backup: $(basename "$BACKUP_FILE")

Next Steps:
  1. Verify all services are running: ./miniprem.sh status
  2. Access the monitoring dashboard at http://localhost:3001
  3. Configure Flowise chatflow (if needed): ./miniprem.sh setup

EOF
    echo -e $NC
}

################################################################################
# Function: main
# Description: Main entry point
# Arguments: $@ - All command-line arguments
# Returns: Exit code
################################################################################
main() {
    # Parse command-line arguments
    parse_arguments "$@" || exit 1

    # Set IFS after argument parsing to avoid issues with space-separated args
    IFS=$'\n\t'

    # Display header
    log_section "MiniPrem Multiple Renny Configuration"

    # Validate installation
    validate_installation || exit 1

    # Validate Docker
    validate_docker || exit 1

    # Get instance count from user if not provided
    if [ -z "$NUM_INSTANCES" ]; then
        prompt_for_instance_count
    else
        validate_instance_count
    fi

    # Extract base Renny configuration
    extract_renny_service || exit 1

    # Backup compose file
    backup_compose_file || exit 1

    # Clean existing instances (idempotent)
    clean_existing_instances || exit 1

    # Create service definitions for all instances
    create_service_definitions || {
        error "Failed to create service definitions. Restoring from backup..."
        if cp "$BACKUP_FILE" "$COMPOSE_FILE"; then
            success "Restored original compose file"
        fi
        exit 1
    }

    # Restart services
    restart_services || {
        error "Failed to start services. Restoring from backup..."
        if cp "$BACKUP_FILE" "$COMPOSE_FILE"; then
            success "Restored original compose file"
        fi
        exit 1
    }

    # Verify containers are healthy
    if ! verify_containers_healthy; then
        error "Some containers failed to start. Check logs with: ./miniprem.sh logs"
        warning "Backup of compose file: $(basename "$BACKUP_FILE")"
        exit 1
    fi

    # Display summary
    display_summary

    exit 0
}

# Execute main function
main "$@"
