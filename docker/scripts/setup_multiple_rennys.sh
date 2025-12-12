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
NUM_INSTANCES=""
BASE_RENNY_CONFIG=""
BACKUP_FILE=""
DEBUG_MODE=false

# Constants
readonly MIN_INSTANCES=2
readonly MAX_INSTANCES=30
readonly BASE_HEALTH_PORT=8081
readonly BASE_METRICS_PORT=8080
readonly PORT_INCREMENT=10

# Ordinal names for instances
declare -a ORDINALS=(
    "first" "second" "third" "fourth" "fifth"
    "sixth" "seventh" "eighth" "ninth" "tenth"
    "eleventh" "twelfth" "thirteenth" "fourteenth" "fifteenth"
    "sixteenth" "seventeenth" "eighteenth" "nineteenth" "twentieth"
    "twenty-first" "twenty-second" "twenty-third" "twenty-fourth" "twenty-fifth"
    "twenty-sixth" "twenty-seventh" "twenty-eighth" "twenty-ninth" "thirtieth"
)

################################################################################
# Function: display_usage
# Description: Show usage information
################################################################################
function display_usage() {
    echo -e $WHITE
    cat <<EOF
$(basename "$0") - Configure multiple Renny containers for Docker deployment

Usage:
    $(basename "$0") [OPTIONS]

Options:
    -n, --number <count>    Number of Renny instances ($MIN_INSTANCES-$MAX_INSTANCES, default: interactive prompt)
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
        Instance 1 (renny):        Health: $BASE_HEALTH_PORT, Metrics: $BASE_METRICS_PORT
        Instance 2 (renny-second): Health: 8091, Metrics: 8090
        Instance 3 (renny-third):  Health: 8101, Metrics: 8100
        Pattern: base_port + (instance_num - 1) * $PORT_INCREMENT

Requirements:
    - Docker installation completed (requires .miniprem_install_type file)
    - docker-compose.env must exist in docker/ directory
    - Docker daemon running
    - Minimum $MIN_INSTANCES instances, maximum $MAX_INSTANCES

EOF
    echo -e $NC
}

################################################################################
# Function: parse_arguments
# Description: Parse command-line arguments
################################################################################
function parse_arguments() {
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
################################################################################
function validate_installation() {
    log_section "Validating MiniPrem Installation"

    # Check if installation type file exists
    if [ ! -f "$PROJECT_ROOT/.miniprem_install_type" ]; then
        fatal "MiniPrem installation not completed. Please run: ./docker/scripts/install_miniprem.sh"
    fi

    # Read installation type
    INSTALL_TYPE=$(cat "$PROJECT_ROOT/.miniprem_install_type")
    success "Installation type: $INSTALL_TYPE"

    # Select appropriate compose file
    case "$INSTALL_TYPE" in
        default)
            COMPOSE_FILE="$DOCKER_DIR/docker-compose.yml"
            ;;
        *)
            COMPOSE_FILE="$DOCKER_DIR/docker-compose.full.yml"
            ;;
    esac

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
# Note: This script requires Docker access. On systems without docker group
#       privileges, run with sudo: sudo ./setup_multiple_rennys.sh
################################################################################
function validate_docker() {
    info "Checking Docker daemon..."

    if ! sudo docker ps > /dev/null 2>&1; then
        error "Docker daemon is not accessible."
        echo ""
        echo "This may be because:"
        echo "  1. Docker is not running (start Docker and retry)"
        exit 1
    fi

    success "$CHECKMARK Docker daemon is running"
}

################################################################################
# Function: validate_number_input
# Description: Validate if input is a valid number within range
################################################################################
function validate_number_input() {
    local input="$1"

    # Validate integer
    if ! [[ "$input" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    # Validate range
    if [ "$input" -lt "$MIN_INSTANCES" ] || [ "$input" -gt "$MAX_INSTANCES" ]; then
        return 1
    fi

    return 0
}

################################################################################
# Function: prompt_for_instance_count
# Description: Interactively ask user for number of instances
################################################################################
function prompt_for_instance_count() {
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

    while true; do
        echo -n "Enter number of Renny instances ($MIN_INSTANCES-$MAX_INSTANCES): "
        read -r user_input

        if validate_number_input "$user_input"; then
            NUM_INSTANCES="$user_input"
            break
        else
            warning "Please enter a valid integer between $MIN_INSTANCES and $MAX_INSTANCES"
        fi
    done

    echo ""
    success "$CHECKMARK You selected $NUM_INSTANCES Renny instances"

    local max_metrics_port=$((BASE_METRICS_PORT + (NUM_INSTANCES - 1) * PORT_INCREMENT))
    local max_health_port=$((BASE_HEALTH_PORT + (NUM_INSTANCES - 1) * PORT_INCREMENT))

    info "Instances will use ports: $BASE_METRICS_PORT-$max_metrics_port (metrics)"
    info "Health checks on ports: $BASE_HEALTH_PORT-$max_health_port"
}

################################################################################
# Function: validate_instance_count
# Description: Validate user-provided instance count
################################################################################
function validate_instance_count() {
    log_section "Validating Instance Count"

    if ! validate_number_input "$NUM_INSTANCES"; then
        error "Instance count must be an integer between $MIN_INSTANCES and $MAX_INSTANCES (you provided: $NUM_INSTANCES)"
        echo ""
        echo "Usage examples:"
        echo "  ./setup_multiple_rennys.sh -n 2    # Configure 2 instances"
        echo "  ./setup_multiple_rennys.sh -n 4    # Configure 4 instances"
        echo "  ./setup_multiple_rennys.sh         # Interactive mode (prompts for count)"
        exit 1
    fi

    success "$CHECKMARK Valid instance count: $NUM_INSTANCES"
}

################################################################################
# Function: extract_renny_service
# Description: Extract base Renny service definition from compose file
################################################################################
function extract_renny_service() {
    log_section "Extracting Renny Service Configuration"

    local service_lines=()
    local in_renny_service=false

    while IFS= read -r line; do
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
        if [[ "$line" =~ ^[a-zA-Z0-9_-]+:[[:space:]]*$ ]] && [ -n "$line" ]; then
            break
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
################################################################################
function get_ordinal_name() {
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
################################################################################
function calculate_ports() {
    local instance_num=$1
    local offset=$((instance_num - 1))
    local health_port=$((BASE_HEALTH_PORT + offset * PORT_INCREMENT))
    local metrics_port=$((BASE_METRICS_PORT + offset * PORT_INCREMENT))
    echo "$health_port $metrics_port"
}

################################################################################
# Function: create_instance_env_file
# Description: Create environment file for a specific Renny instance
################################################################################
function create_instance_env_file() {
    local instance_num=$1
    local ordinal_name=$2
    local env_filename="renny-${ordinal_name}.env"
    local env_filepath="$DOCKER_DIR/$env_filename"

    # Calculate ports
    local ports=$(calculate_ports "$instance_num")
    local health_port=$(echo "$ports" | awk '{print $1}')
    local metrics_port=$(echo "$ports" | awk '{print $2}')

    # Copy base env file
    local cp_error
    if ! cp_error=$(cp "$DOCKER_DIR/docker-compose.env" "$env_filepath" 2>&1); then
        error "Failed to create environment file: $env_filepath"
        error "Copy error: $cp_error"
        error "Source: $DOCKER_DIR/docker-compose.env"
        error "Check: ls -la $DOCKER_DIR/docker-compose.env"
        return 1
    fi

    # Update HEALTH_URL and METRICS_PORT in the new env file
    local temp_file="${env_filepath}.tmp"
    local sed_error

    if ! sed_error=$(sed "s|HEALTH_URL=.*|HEALTH_URL=http://0.0.0.0:${health_port}/health|g; \
              s|METRICS_PORT=.*|METRICS_PORT=$metrics_port|g" \
              "$env_filepath" 2>&1 > "$temp_file"); then
        error "Failed to update environment variables in $env_filename"
        error "Sed error: $sed_error"
        rm -f "$temp_file"
        return 1
    fi

    local mv_error
    if ! mv_error=$(mv "$temp_file" "$env_filepath" 2>&1); then
        error "Failed to move temporary file to $env_filepath"
        error "Move error: $mv_error"
        rm -f "$temp_file"
        return 1
    fi

    info "Created environment file: $env_filename (Health: $health_port, Metrics: $metrics_port)"
    return 0
}

################################################################################
# Function: is_custom_renny_service
# Description: Check if a line matches a custom renny service name
################################################################################
function is_custom_renny_service() {
    local line="$1"

    # Check against all possible ordinal names
    for ((i = 2; i <= MAX_INSTANCES; i++)); do
        local ordinal=$(get_ordinal_name "$i")
        if [[ "$line" =~ ^[[:space:]]*renny-${ordinal}:[[:space:]]*$ ]]; then
            return 0
        fi
    done

    return 1
}

################################################################################
# Function: clean_existing_instances
# Description: Remove existing custom Renny service definitions from compose file
################################################################################
function clean_existing_instances() {
    log_section "Cleaning Existing Custom Renny Instances"

    # Check if there are any custom renny instances to remove
    if ! grep -q "renny-second:" "$COMPOSE_FILE" 2>/dev/null; then
        info "No existing custom instances found"
        return 0
    fi

    info "Removing existing custom renny instances..."

    local temp_file="${COMPOSE_FILE}.tmp"
    local in_custom_renny=false

    # Create new compose file without custom instances
    {
        while IFS= read -r line; do
            # Check if this is a custom renny service
            if is_custom_renny_service "$line"; then
                in_custom_renny=true
                continue
            fi

            # Check if we've reached another service
            if [ "$in_custom_renny" = true ] && [[ "$line" =~ ^[a-zA-Z0-9_-]+:[[:space:]]*$ ]] && [ -n "$line" ]; then
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
# Function: generate_service_definition
# Description: Generate a complete service definition for one instance
################################################################################
function generate_service_definition() {
    local instance_num=$1
    local ordinal_name=$2
    local service_name="renny-${ordinal_name}"
    local health_port=$(calculate_ports "$instance_num" | awk '{print $1}')

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
    image: "cr.uneeq.io/uneeq/renny-renderer:enterprise-latest"
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
}

################################################################################
# Function: create_service_definitions
# Description: Create complete service definitions for all additional instances
################################################################################
function create_service_definitions() {
    log_section "Creating Service Definitions"

    # Create environment files for all additional instances
    for ((i = 2; i <= NUM_INSTANCES; i++)); do
        local ordinal_name=$(get_ordinal_name "$i")

        if ! create_instance_env_file "$i" "$ordinal_name"; then
            error "Failed to create environment file for instance $i"
            return 1
        fi
    done

    # Ensure newline before appending services
    echo "" >> "$COMPOSE_FILE"

    # Append all services to compose file
    for ((i = 2; i <= NUM_INSTANCES; i++)); do
        local ordinal_name=$(get_ordinal_name "$i")

        if ! generate_service_definition "$i" "$ordinal_name" >> "$COMPOSE_FILE"; then
            error "Failed to append service definition for instance $i"
            return 1
        fi
    done

    success "$CHECKMARK Created $((NUM_INSTANCES - 1)) service definitions"
    return 0
}

################################################################################
# Function: backup_compose_file
# Description: Create backup of compose file before modifications
################################################################################
function backup_compose_file() {
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
# Function: manage_docker_services
# Description: Stop and start services with new configuration
################################################################################
function manage_docker_services() {
    log_section "Restarting Services"

    if [ "$DEBUG_MODE" = true ]; then
        info "[DEBUG MODE] Skipping Docker operations"
        info "[DEBUG MODE] Files created successfully:"
        info "  - Compose file: $COMPOSE_FILE"

        for ((i = 2; i <= NUM_INSTANCES; i++)); do
            local ordinal_name=$(get_ordinal_name "$i")
            info "  - renny-${ordinal_name}.env"
        done
        return 0
    fi

    info "Stopping current services..."
    local down_error
    if ! down_error=$(sudo docker compose -f "$COMPOSE_FILE" down 2>&1); then
        # Check if failure is because services aren't running
        if echo "$down_error" | grep -q "no configuration file provided\|No such container"; then
            warning "No services were running (this is normal for first run)"
        else
            # Unexpected failure - log details but continue
            warning "Could not gracefully stop services"
            warning "Docker compose down error: $down_error"
            warning "Continuing anyway, but this might indicate a problem..."
        fi
    fi

    sleep 2

    info "Starting services with new configuration..."
    local up_error
    if ! up_error=$(sudo docker compose -f "$COMPOSE_FILE" up -d 2>&1); then
        error "Failed to start services"
        error "Docker compose up error: $up_error"
        error ""
        error "Common causes:"
        error "  - Port conflicts: Check if ports are already in use"
        error "  - Docker daemon: Verify Docker is running"
        error "  - Compose syntax: Check $COMPOSE_FILE for errors"
        error "  - Resources: Ensure sufficient CPU/memory/disk"
        error ""
        error "Troubleshooting:"
        error "  sudo docker ps -a                    # Check existing containers"
        error "  sudo docker compose -f $COMPOSE_FILE config  # Validate compose file"
        error "  sudo docker compose -f $COMPOSE_FILE logs    # View service logs"
        return 1
    fi

    return 0
}

################################################################################
# Function: check_container_health
# Description: Check health status of a single container
################################################################################
function check_container_health() {
    local service_name="$1"

    # Check if container exists
    local container_id=$(sudo docker ps -a -f name="^${service_name}$" -q 2>/dev/null)
    if [ -z "$container_id" ]; then
        echo "not found"
        return 1
    fi

    # Check if container is running
    local container_status=$(sudo docker inspect "$container_id" --format='{{.State.Running}}' 2>/dev/null)
    if [ "$container_status" != "true" ]; then
        echo "not running"
        return 1
    fi

    # Check health status if healthcheck is configured
    local health_status=$(sudo docker inspect "$container_id" --format='{{.State.Health.Status}}' 2>/dev/null)
    if [ -n "$health_status" ] && [ "$health_status" != "" ]; then
        echo "$health_status"
    else
        echo "healthy"  # No healthcheck configured, assume healthy if running
    fi

    return 0
}

################################################################################
# Function: verify_containers_healthy
# Description: Verify all Renny containers are running and healthy
################################################################################
function verify_containers_healthy() {
    log_section "Verifying Container Health"

    if [ "$DEBUG_MODE" = true ]; then
        info "[DEBUG MODE] Skipping container health verification"
        return 0
    fi

    local max_attempts=30
    local attempt=1
    local all_healthy=false

    info "Waiting for containers to stabilize..."

    while [ $attempt -le $max_attempts ] && [ "$all_healthy" = false ]; do
        all_healthy=true
        local failed_containers=()

        for ((i = 1; i <= NUM_INSTANCES; i++)); do
            local service_name="renny"
            if [ $i -gt 1 ]; then
                service_name="renny-$(get_ordinal_name "$i")"
            fi

            local health_status=$(check_container_health "$service_name")

            case "$health_status" in
                healthy)
                    # Container is healthy
                    ;;
                starting|unhealthy)
                    # Container is still starting or temporarily unhealthy
                    all_healthy=false
                    if [ $attempt -eq $max_attempts ]; then
                        failed_containers+=("$service_name (health: $health_status)")
                    fi
                    ;;
                *)
                    # Container not found or not running
                    all_healthy=false
                    if [ $attempt -eq $max_attempts ]; then
                        failed_containers+=("$service_name ($health_status)")
                    fi
                    ;;
            esac
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
            # Final attempt failed
            echo ""
            if [ ${#failed_containers[@]} -gt 0 ]; then
                error "The following containers failed to start or are not healthy:"
                for container in "${failed_containers[@]}"; do
                    echo "  - $container"
                done
                return 1
            fi
        fi
    done

    return 0
}

################################################################################
# Function: display_summary
# Description: Display summary of configuration
################################################################################
function display_summary() {
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
# Function: restore_on_error
# Description: Restore from backup if operation fails
################################################################################
function restore_on_error() {
    local message="$1"

    error "$message"

    if [ -n "$BACKUP_FILE" ] && [ -f "$BACKUP_FILE" ]; then
        info "Restoring from backup..."
        if cp "$BACKUP_FILE" "$COMPOSE_FILE"; then
            success "Restored original compose file"
        else
            error "Failed to restore from backup"
        fi
    fi
}

################################################################################
# Function: main
# Description: Main entry point
################################################################################
function main() {
    # Parse command-line arguments
    parse_arguments "$@" || exit 1

    # Set IFS after argument parsing to avoid issues with space-separated args
    IFS=$'\n\t'

    # Display header
    log_section "MiniPrem Multiple Renny Configuration"

    # Validate installation
    validate_installation || exit 1

    # Validate Docker (skip in debug mode)
    if [ "$DEBUG_MODE" != true ]; then
        validate_docker || exit 1
    fi

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
    clean_existing_instances || {
        restore_on_error "Failed to clean existing instances"
        exit 1
    }

    # Create service definitions for all instances
    create_service_definitions || {
        restore_on_error "Failed to create service definitions"
        exit 1
    }

    # Restart services
    manage_docker_services || {
        restore_on_error "Failed to manage Docker services"
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