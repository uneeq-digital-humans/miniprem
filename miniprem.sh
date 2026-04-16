#!/bin/bash

# Change to the script's directory
cd "$(dirname "$0")" || { echo "Failed to change directory to script location"; exit 1; }

# Add this line after changing to the script's directory
PROJECT_ROOT=$(pwd)

################################################################################
# Detect Installation Type: Docker or CNS (Kubernetes)
################################################################################

# Check for CNS installation marker
CNS_CONFIG_FILE="$PROJECT_ROOT/kubernetes/scripts/cns/.cns_config"
CNS_INSTALLED=false

if [ -f "$CNS_CONFIG_FILE" ]; then
    CNS_INSTALLED=true
fi

# Also check if MicroK8s is running with Renny deployed
if command -v microk8s &> /dev/null; then
    if microk8s kubectl get deployment renny -n uneeq &>/dev/null 2>&1; then
        CNS_INSTALLED=true
    fi
fi

# For CNS installations, check permissions and route to CNS scripts
if [ "$CNS_INSTALLED" = true ]; then
    # Check if user has microk8s permissions
    if command -v microk8s &> /dev/null; then
        if ! microk8s status &>/dev/null 2>&1; then
            echo ""
            echo "⚠️  MicroK8s permission denied."
            echo ""
            echo "You need to run this command with sudo OR be in the microk8s group:"
            echo ""
            echo "  Option 1: Run with sudo"
            echo "    sudo ./miniprem.sh ${1:-}"
            echo ""
            echo "  Option 2: Add yourself to microk8s group (recommended)"
            echo "    sudo usermod -a -G microk8s \$USER"
            echo "    newgrp microk8s  # Or logout and login again"
            echo ""
            exit 1
        fi
    fi
    CNS_SCRIPTS_DIR="$PROJECT_ROOT/kubernetes/scripts/cns"

    # Route commands to CNS scripts
    case "${1:-}" in
        start)
            exec "$CNS_SCRIPTS_DIR/restart.sh" "${@:2}"
            ;;
        stop)
            exec "$CNS_SCRIPTS_DIR/stop.sh" "${@:2}"
            ;;
        restart)
            "$CNS_SCRIPTS_DIR/stop.sh"
            exec "$CNS_SCRIPTS_DIR/restart.sh" "${@:2}"
            ;;
        status)
            exec "$CNS_SCRIPTS_DIR/status.sh" "${@:2}"
            ;;
        scale)
            # Use sizer.sh --apply for full configuration (GPU time-slicing + replicas + quality)
            # This ensures GPU resources are properly allocated when scaling
            exec "$CNS_SCRIPTS_DIR/sizer.sh" --apply
            ;;
        scale-quick)
            # Quick scale without GPU reconfiguration (use if you know what you're doing)
            exec "$CNS_SCRIPTS_DIR/scale.sh" "${@:2}"
            ;;
        sizer)
            # GPU capacity calculator and configurator
            exec "$CNS_SCRIPTS_DIR/sizer.sh" "${@:2}"
            ;;
        logs)
            # For CNS, show Renny pod logs with pod selection
            if command -v microk8s &> /dev/null; then
                KUBECTL="microk8s kubectl"
            else
                KUBECTL="kubectl"
            fi

            # Get list of Renny pods
            PODS=($($KUBECTL get pods -n uneeq -l app=renny -o jsonpath='{.items[*].metadata.name}' 2>/dev/null))

            if [[ ${#PODS[@]} -eq 0 ]]; then
                echo "No Renny pods found in uneeq namespace"
                exit 1
            fi

            POD_ARG="${2:-}"

            # If "all" specified, follow all pods
            if [[ "$POD_ARG" == "all" ]]; then
                echo "Following logs from ALL ${#PODS[@]} Renny pods (Ctrl+C to stop)..."
                exec $KUBECTL logs -f -l app=renny -n uneeq --all-containers=true --max-log-requests=${#PODS[@]}
            fi

            # If specific pod name/number provided
            if [[ -n "$POD_ARG" ]]; then
                if [[ "$POD_ARG" =~ ^[0-9]+$ ]]; then
                    # It's a number - use as index (1-based)
                    IDX=$((POD_ARG - 1))
                    if [[ $IDX -ge 0 && $IDX -lt ${#PODS[@]} ]]; then
                        exec $KUBECTL logs -f "${PODS[$IDX]}" -n uneeq --all-containers=true
                    else
                        echo "Invalid pod number: $POD_ARG (have ${#PODS[@]} pods)"
                        exit 1
                    fi
                else
                    # It's a pod name
                    exec $KUBECTL logs -f "$POD_ARG" -n uneeq --all-containers=true
                fi
            fi

            # No argument - show menu
            echo ""
            echo "Select a Renny pod to view logs:"
            echo ""
            for i in "${!PODS[@]}"; do
                STATUS=$($KUBECTL get pod "${PODS[$i]}" -n uneeq -o jsonpath='{.status.phase}' 2>/dev/null)
                printf "  %d) %s (%s)\n" $((i+1)) "${PODS[$i]}" "$STATUS"
            done
            echo ""
            echo "  all) Follow ALL pods"
            echo ""
            read -p "Enter selection [1-${#PODS[@]} or 'all']: " selection

            if [[ "$selection" == "all" ]]; then
                exec $KUBECTL logs -f -l app=renny -n uneeq --all-containers=true --max-log-requests=${#PODS[@]}
            elif [[ "$selection" =~ ^[0-9]+$ && $selection -ge 1 && $selection -le ${#PODS[@]} ]]; then
                exec $KUBECTL logs -f "${PODS[$((selection-1))]}" -n uneeq --all-containers=true
            else
                echo "Invalid selection"
                exit 1
            fi
            ;;
        deploy)
            exec "$CNS_SCRIPTS_DIR/deploy-local.sh" "${@:2}"
            ;;
        upgrade|update)
            exec "$CNS_SCRIPTS_DIR/upgrade.sh" "${@:2}"
            ;;
        destroy)
            exec "$CNS_SCRIPTS_DIR/destroy.sh" "${@:2}"
            ;;
        -h|--help|help)
            echo ""
            echo "MiniPrem CNS (Kubernetes) Management"
            echo ""
            echo "CNS installation detected. Available commands:"
            echo ""
            echo "  start       - Start the CNS deployment (scale up Renny pods)"
            echo "  stop        - Stop the CNS deployment (scale down to 0)"
            echo "  restart     - Restart the CNS deployment"
            echo "  status      - Check CNS deployment status"
            echo "  logs [N|all]- View Renny pod logs (select pod or 'all')"
            echo ""
            echo "Configuration & Scaling:"
            echo "  upgrade             - Interactive upgrade menu"
            echo "  upgrade --full      - Full upgrade (git + helm + new Renny)"
            echo "  upgrade --config-only - Just apply values file changes"
            echo "  upgrade --restart   - Just restart pods"
            echo "  scale             - Interactive scaling with GPU config"
            echo "  scale-quick N     - Quick scale to N replicas"
            echo "  sizer             - GPU capacity calculator"
            echo ""
            echo "Deployment:"
            echo "  deploy      - Run full CNS deployment (interactive)"
            echo "  destroy     - Destroy CNS deployment"
            echo ""
            echo "Examples:"
            echo "  ./miniprem.sh upgrade             # Apply renny-values-cns.yaml changes"
            echo "  ./miniprem.sh upgrade --replicas 3 # Change replica count"
            echo "  ./miniprem.sh upgrade --clear-secrets # Clear TTS/LLM secrets"
            echo "  ./miniprem.sh scale               # Interactive GPU-aware scaling"
            echo ""
            echo "CNS Configuration: $CNS_CONFIG_FILE"
            echo ""
            exit 0
            ;;
        *)
            echo "MiniPrem CNS installation detected."
            echo "Run './miniprem.sh --help' for available commands."
            echo ""
            echo "Quick commands:"
            echo "  ./miniprem.sh status   - Check deployment status"
            echo "  ./miniprem.sh upgrade  - Full upgrade (git + helm + image)"
            echo "  ./miniprem.sh scale    - Scale Renny (with GPU config)"
            echo "  ./miniprem.sh logs     - View Renny logs"
            exit 0
            ;;
    esac
fi

################################################################################
# Docker Installation (Original behavior)
################################################################################

# Source the scripts for Docker mode
source scripts/logging.sh
source scripts/docker.sh
source scripts/environment.sh

# Load the install type from the file
if [ -f .miniprem_install_type ]; then
    INSTALL_TYPE=$(cat .miniprem_install_type)
else
    INSTALL_TYPE="default"  # Default to basic if file doesn't exist
fi

# Set the compose file based on install type
if [ "$INSTALL_TYPE" = "default" ]; then
    COMPOSE_FILE="-f $PROJECT_ROOT/docker/docker-compose.yml"
else
    COMPOSE_FILE="-f $PROJECT_ROOT/docker/docker-compose.full.yml"
fi

# Function to display usage
usage() {
    echo -e $WHITE
    cat <<EOF
`basename $0` [start|stop|status|restart|logs|upgrade|setup|pull|validate|config|custom]
Control the MiniPrem services

Commands:
    start:              Start the MiniPrem services
    stop:               Stop the MiniPrem services
    status:             Check the status of the MiniPrem services
    restart:            Restart the MiniPrem services
    logs:               View the logs of the MiniPrem services
    upgrade:            Full upgrade (git pull + docker pull + rebuild)
    setup:              Run the Flowise chatflow setup
    pull [--regenerate]: Pull latest code from git only (no docker pull)
    validate:           Validate custom services configuration
    config [--custom]:  Show final merged Docker Compose config
    custom list:        List all custom services
    custom add [name]:  Add a new custom service interactively

Upgrade:
    The 'upgrade' command performs a complete MiniPrem update:
    1. Backs up your config files (credentials, terraform vars, etc.)
    2. Pulls latest code from git
    3. Restores your config files
    4. Pulls latest Renny image from Harbor
    5. Rebuilds MiniPrem Monitor locally

    After upgrade, run './miniprem.sh restart' to apply changes.

Options:
    -h, --help: Show this usage information
EOF
    echo -e $NC
    exit 1
}

start_services() {
    log_section "Starting MiniPrem Services"

    # Ensure Harbor credentials are available (will prompt if needed)
    if ! ensure_harbor_credentials; then
        fatal "Cannot start services without valid Harbor credentials"
    fi

    start_docker_compose "$COMPOSE_FILE"
}

stop_services() {
    log_section "Stopping MiniPrem Services"
    stop_docker_compose "$COMPOSE_FILE"
}

restart_services() {
    log_section "Restarting MiniPrem Services"
    stop_services
    start_services
}

check_status() {
    log_section "MiniPrem Services Status"
    DOCKER_CMD=$(get_docker_command)
    $DOCKER_CMD compose $COMPOSE_FILE ps
}

view_logs() {
    log_section "MiniPrem Services Logs"
    DOCKER_CMD=$(get_docker_command)
    $DOCKER_CMD compose $COMPOSE_FILE logs -f
}

setup_flowise() {
    log_section "Setting up Flowise Chatflow"

    # Check if Flowise is running
    if ! curl --output /dev/null --silent --head --fail http://localhost:3000/; then
        warning "Flowise service is not running. Starting services first..."
        start_services

        # Wait for Flowise to be ready
        info "Waiting for Flowise to be ready..."
        local max_attempts=60
        local attempt=1

        while [ $attempt -le $max_attempts ]; do
            if curl --output /dev/null --silent --head --fail http://localhost:3000/; then
                success "$CHECKMARK Flowise is up and running!"
                break
            fi

            printf '.'
            sleep 5
            attempt=$((attempt+1))

            if [ $attempt -gt $max_attempts ]; then
                fatal "Flowise service did not become available within the expected timeframe."
            fi
        done
    fi

    # Run the chatflow setup script
    bash "$PROJECT_ROOT/docker/setup-chatflow-post-deployment.sh"
}

pull_updates() {
    log_section "Pulling Latest MiniPrem Updates"

    local regenerate=false
    if [[ "$1" == "--regenerate" ]]; then
        regenerate=true
    fi

    # Check if we're in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        fatal "Not a git repository. Cannot pull updates."
    fi

    # Check for uncommitted changes
    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        warning "You have uncommitted changes. Please commit or stash them first."
        info "Current changes:"
        git status --short
        fatal "Aborting pull to avoid conflicts."
    fi

    # Pull latest changes
    info "Pulling latest changes from git..."
    git pull
    if [ $? -ne 0 ]; then
        fatal "$CROSS Failed to pull updates from git."
    fi
    success "$CHECKMARK Successfully pulled latest updates."

    # Check if custom services file exists
    if [ -f "$PROJECT_ROOT/docker/docker-compose.custom.yml" ]; then
        info "Custom services file detected."

        if [ "$regenerate" = true ]; then
            info "Regenerating merge with custom services..."
            bash "$PROJECT_ROOT/docker/scripts/merge-compose.sh"
            if [ $? -eq 0 ] || [ $? -eq 2 ]; then
                success "$CHECKMARK Merge regenerated successfully."
            else
                fatal "$CROSS Failed to regenerate merge."
            fi
        else
            warning "Custom services exist. Run 'pull --regenerate' to update merge."
        fi
    fi

    # Show summary of changes
    info "Recent changes:"
    git log --oneline -5
}

################################################################################
# Upgrade - Full upgrade with git pull + docker pull + rebuild
################################################################################

# Files that contain user credentials/config and must be preserved during git pull
CONFIG_FILES_TO_PRESERVE=(
    "docker/configuration.dat"
    ".env"
    "docker/.env"
    "docker/docker-compose.custom.yml"
    ".miniprem_install_type"
    "kubernetes/scripts/cns/.cns_config"
    "kubernetes/values/renny-values-cns.yaml"
    "kubernetes/terraform/eks/terraform.tfvars"
    "kubernetes/terraform/aks/terraform.tfvars"
    "kubernetes/terraform/gke/terraform.tfvars"
)

backup_config_files() {
    local backup_dir="$PROJECT_ROOT/.config_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"

    local backed_up=0
    for file in "${CONFIG_FILES_TO_PRESERVE[@]}"; do
        local full_path="$PROJECT_ROOT/$file"
        if [ -f "$full_path" ]; then
            local dir=$(dirname "$file")
            mkdir -p "$backup_dir/$dir"
            cp "$full_path" "$backup_dir/$file"
            ((backed_up++))
        fi
    done

    if [ $backed_up -gt 0 ]; then
        info "Backed up $backed_up config file(s) to $backup_dir"
    fi
    echo "$backup_dir"
}

restore_config_files() {
    local backup_dir="$1"

    if [ ! -d "$backup_dir" ]; then
        warning "Backup directory not found: $backup_dir"
        return 1
    fi

    local restored=0
    for file in "${CONFIG_FILES_TO_PRESERVE[@]}"; do
        local backup_file="$backup_dir/$file"
        local target_file="$PROJECT_ROOT/$file"
        if [ -f "$backup_file" ]; then
            local dir=$(dirname "$target_file")
            mkdir -p "$dir"
            cp "$backup_file" "$target_file"
            ((restored++))
        fi
    done

    if [ $restored -gt 0 ]; then
        success "$CHECKMARK Restored $restored config file(s)"
    fi

    # Clean up backup directory
    rm -rf "$backup_dir"
}

upgrade_services() {
    log_section "Upgrading MiniPrem (Docker)"

    echo ""
    info "This will:"
    echo "  1. Backup your config files (credentials, etc.)"
    echo "  2. Pull latest code from git"
    echo "  3. Restore your config files"
    echo "  4. Pull latest Renny image from Harbor"
    echo "  5. Rebuild MiniPrem Monitor"
    echo ""
    echo "After upgrade, run './miniprem.sh restart' to apply changes."
    echo ""

    # Check if we're in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        fatal "Not a git repository. Cannot upgrade."
    fi

    # Step 1: Backup config files
    info "Step 1/5: Backing up config files..."
    local backup_dir
    backup_dir=$(backup_config_files)

    # Step 2: Git pull (stash any other changes first)
    info "Step 2/5: Pulling latest code from git..."

    # Stash any uncommitted changes (except our preserved files)
    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        warning "Stashing uncommitted changes..."
        git stash push -m "miniprem-upgrade-$(date +%Y%m%d_%H%M%S)" || true
    fi

    git pull
    if [ $? -ne 0 ]; then
        warning "Git pull failed. Restoring config files..."
        restore_config_files "$backup_dir"
        fatal "$CROSS Failed to pull updates from git."
    fi
    success "$CHECKMARK Git pull successful"

    # Step 3: Restore config files
    info "Step 3/5: Restoring config files..."
    restore_config_files "$backup_dir"

    # Step 4: Validate Harbor credentials and pull Renny
    info "Step 4/5: Pulling latest Renny image..."

    if ! ensure_harbor_credentials; then
        fatal "Cannot pull Renny image without valid Harbor credentials"
    fi

    DOCKER_CMD=$(get_docker_command)

    # Pull Renny image
    info "Pulling cr.uneeq.io/uneeq/renny-renderer:enterprise-latest..."
    if $DOCKER_CMD pull cr.uneeq.io/uneeq/renny-renderer:enterprise-latest; then
        success "$CHECKMARK Renny image updated"
    else
        warning "Failed to pull Renny image. Check Harbor credentials."
    fi

    # Step 5: Rebuild MiniPrem Monitor (it's built locally, not pulled)
    info "Step 5/5: Rebuilding MiniPrem Monitor..."

    cd "$PROJECT_ROOT/docker"
    if $DOCKER_CMD compose $COMPOSE_FILE build --no-cache --pull miniprem-monitor 2>/dev/null; then
        success "$CHECKMARK MiniPrem Monitor rebuilt"
    else
        # Try without --pull flag (older docker-compose)
        if $DOCKER_CMD compose $COMPOSE_FILE build --no-cache miniprem-monitor 2>/dev/null; then
            success "$CHECKMARK MiniPrem Monitor rebuilt"
        else
            warning "Could not rebuild MiniPrem Monitor automatically."
            echo "  Try manually: cd docker && docker compose build --no-cache miniprem-monitor"
        fi
    fi
    cd "$PROJECT_ROOT"

    # Show summary
    echo ""
    success "═══════════════════════════════════════════════════════════════"
    success "  Upgrade Complete!"
    success "═══════════════════════════════════════════════════════════════"
    echo ""
    info "Recent changes pulled:"
    git log --oneline -5
    echo ""
    info "Next steps:"
    echo "  1. Review the changes above"
    echo "  2. Restart services: ./miniprem.sh restart"
    echo ""
    info "To verify after restart:"
    echo "  ./miniprem.sh status"
    echo "  docker exec miniprem-monitor docker version  # Should show API 1.46+"
    echo ""
}

validate_custom_services() {
    log_section "Validating Custom Services Configuration"

    # Check if custom services file exists
    if [ ! -f "$PROJECT_ROOT/docker/docker-compose.custom.yml" ]; then
        info "No custom services file found at docker/docker-compose.custom.yml"
        success "$CHECKMARK No validation needed."
        exit 0
    fi

    info "Validating custom services configuration..."

    # Run merge-compose in check-only mode
    bash "$PROJECT_ROOT/docker/scripts/merge-compose.sh" --check --verbose
    local exit_code=$?

    case $exit_code in
        0)
            success "$CHECKMARK Custom services configuration is valid. No conflicts detected."
            exit 0
            ;;
        1)
            error "$CROSS Validation failed. Please fix errors in docker-compose.custom.yml"
            exit 1
            ;;
        2)
            warning "Validation completed with warnings. Conflicts detected but can be resolved."
            exit 2
            ;;
        *)
            error "$CROSS Unknown validation error."
            exit 1
            ;;
    esac
}

show_config() {
    log_section "Docker Compose Configuration"

    local show_custom_only=false
    if [[ "$1" == "--custom" ]]; then
        show_custom_only=true
    fi

    DOCKER_CMD=$(get_docker_command)

    if [ "$show_custom_only" = true ]; then
        # Show only custom services
        if [ ! -f "$PROJECT_ROOT/docker/docker-compose.custom.yml" ]; then
            info "No custom services file found."
            exit 0
        fi

        info "Custom services configuration:"
        cat "$PROJECT_ROOT/docker/docker-compose.custom.yml"
    else
        # Show final merged configuration
        info "Final merged Docker Compose configuration:"

        # Check if override file exists
        if [ -f "$PROJECT_ROOT/docker/docker-compose.override.yml" ]; then
            $DOCKER_CMD compose $COMPOSE_FILE -f "$PROJECT_ROOT/docker/docker-compose.override.yml" config
        else
            $DOCKER_CMD compose $COMPOSE_FILE config
        fi
    fi
}

list_custom_services() {
    log_section "Custom Services"

    # Check if custom services file exists
    if [ ! -f "$PROJECT_ROOT/docker/docker-compose.custom.yml" ]; then
        info "No custom services defined yet."
        info "Use './miniprem.sh custom add [SERVICE_NAME]' to add a custom service."
        exit 0
    fi

    # Get list of custom services
    local services=$(yq eval '.services | keys | .[]' "$PROJECT_ROOT/docker/docker-compose.custom.yml" 2>/dev/null)

    if [ -z "$services" ]; then
        info "No custom services defined in docker-compose.custom.yml"
        exit 0
    fi

    info "Custom services defined:"
    echo ""

    DOCKER_CMD=$(get_docker_command)

    # Get running containers
    local running_containers=$($DOCKER_CMD ps --format "{{.Names}}")

    while IFS= read -r service; do
        # Check if service is running
        local status="stopped"
        local status_color=$RED

        if echo "$running_containers" | grep -q "^${service}$\|^.*[-_]${service}[-_].*$"; then
            status="running"
            status_color=$GREEN
        fi

        # Get service details
        local image=$(yq eval ".services.${service}.image // \"N/A\"" "$PROJECT_ROOT/docker/docker-compose.custom.yml")
        local ports=$(yq eval ".services.${service}.ports[]? // \"N/A\"" "$PROJECT_ROOT/docker/docker-compose.custom.yml" | tr '\n' ', ' | sed 's/,$//')

        echo -e "  ${BOLD}${service}${NC}"
        echo -e "    Status: ${status_color}${status}${NC}"
        echo -e "    Image:  ${image}"
        if [ "$ports" != "N/A" ] && [ -n "$ports" ]; then
            echo -e "    Ports:  ${ports}"
        fi
        echo ""
    done <<< "$services"
}

add_custom_service() {
    log_section "Add Custom Service"

    local service_name="$1"

    # Interactive mode if no service name provided
    if [ -z "$service_name" ]; then
        echo -e "${BOLD}Available service templates:${NC}"
        echo "  1) postgres   - PostgreSQL database"
        echo "  2) redis      - Redis cache"
        echo "  3) mongodb    - MongoDB database"
        echo "  4) mysql      - MySQL database"
        echo "  5) nginx      - Nginx web server"
        echo "  6) custom     - Custom service (manual configuration)"
        echo ""
        read -p "Select a template (1-6) or press Enter to cancel: " template_choice

        case $template_choice in
            1) service_name="postgres" ;;
            2) service_name="redis" ;;
            3) service_name="mongodb" ;;
            4) service_name="mysql" ;;
            5) service_name="nginx" ;;
            6) service_name="custom" ;;
            *)
                info "Cancelled."
                exit 0
                ;;
        esac

        # Get custom name if not using template name
        if [ "$service_name" != "custom" ]; then
            read -p "Service name [${service_name}]: " custom_name
            if [ -n "$custom_name" ]; then
                service_name="$custom_name"
            fi
        else
            read -p "Enter service name: " service_name
            if [ -z "$service_name" ]; then
                fatal "Service name cannot be empty."
            fi
        fi
    fi

    # Create docker-compose.custom.yml if it doesn't exist
    if [ ! -f "$PROJECT_ROOT/docker/docker-compose.custom.yml" ]; then
        info "Creating new docker-compose.custom.yml..."
        cat > "$PROJECT_ROOT/docker/docker-compose.custom.yml" << 'EOF'
version: '3.8'

services:
EOF
    fi

    # Check if service already exists
    if yq eval ".services.${service_name}" "$PROJECT_ROOT/docker/docker-compose.custom.yml" | grep -qv "null"; then
        fatal "Service '${service_name}' already exists in docker-compose.custom.yml"
    fi

    # Get service template
    local template=""
    case $template_choice in
        1)
            template=$(cat << 'EOF'
  postgres:
    image: postgres:15
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: miniprem
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - miniprem-network

volumes:
  postgres_data:
EOF
            )
            ;;
        2)
            template=$(cat << 'EOF'
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    networks:
      - miniprem-network

volumes:
  redis_data:
EOF
            )
            ;;
        3)
            template=$(cat << 'EOF'
  mongodb:
    image: mongo:6
    environment:
      MONGO_INITDB_ROOT_USERNAME: admin
      MONGO_INITDB_ROOT_PASSWORD: admin
    ports:
      - "27017:27017"
    volumes:
      - mongodb_data:/data/db
    networks:
      - miniprem-network

volumes:
  mongodb_data:
EOF
            )
            ;;
        4)
            template=$(cat << 'EOF'
  mysql:
    image: mysql:8
    environment:
      MYSQL_ROOT_PASSWORD: root
      MYSQL_DATABASE: miniprem
    ports:
      - "3306:3306"
    volumes:
      - mysql_data:/var/lib/mysql
    networks:
      - miniprem-network

volumes:
  mysql_data:
EOF
            )
            ;;
        5)
            template=$(cat << 'EOF'
  nginx:
    image: nginx:alpine
    ports:
      - "8080:80"
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d
      - ./nginx/html:/usr/share/nginx/html
    networks:
      - miniprem-network
EOF
            )
            ;;
        *)
            template=$(cat << EOF
  ${service_name}:
    image: # TODO: Specify image
    ports:
      - "8080:80"  # TODO: Configure ports
    environment:
      # TODO: Add environment variables
    networks:
      - miniprem-network
EOF
            )
            ;;
    esac

    # Replace template service name with actual service name
    template=$(echo "$template" | sed "s/^  [a-z]*:/  ${service_name}:/")

    # Append to custom file
    echo "$template" >> "$PROJECT_ROOT/docker/docker-compose.custom.yml"

    success "$CHECKMARK Service '${service_name}' added to docker-compose.custom.yml"

    # Run merge
    info "Merging custom services with official configuration..."
    bash "$PROJECT_ROOT/docker/scripts/merge-compose.sh"
    if [ $? -eq 0 ] || [ $? -eq 2 ]; then
        success "$CHECKMARK Merge completed successfully."
        info "You can now start the service with: ./miniprem.sh restart"
    else
        warning "Merge encountered issues. Please review docker-compose.custom.yml"
    fi
}

# Check if the user provided an argument
if [ -z "$1" ]; then
    usage
fi

# Handle the argument
case "$1" in
    start)
        start_services
        ;;
    stop)
        stop_services
        ;;
    restart)
        restart_services
        ;;
    status)
        check_status
        ;;
    logs)
        view_logs
        ;;
    setup)
        setup_flowise
        ;;
    upgrade|update)
        upgrade_services
        ;;
    pull)
        pull_updates "$2"
        ;;
    validate)
        validate_custom_services
        ;;
    config)
        show_config "$2"
        ;;
    custom)
        case "$2" in
            list)
                list_custom_services
                ;;
            add)
                add_custom_service "$3"
                ;;
            *)
                error "Unknown custom command: $2"
                echo ""
                echo "Usage: $0 custom [list|add]"
                echo ""
                echo "  list       - List all custom services"
                echo "  add [name] - Add a new custom service"
                exit 1
                ;;
        esac
        ;;
    -h|--help)
        usage
        ;;
    *)
        error "Unknown command: $1"
        echo ""
        usage
        ;;
esac