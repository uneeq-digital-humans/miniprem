#!/bin/bash

source scripts/logging.sh
source scripts/docker.sh

# Function to display usage
usage() {
    echo -e $WHITE
    cat <<EOF
`basename $0` [start|stop|status|restart|logs|setup]
Control the MiniPrem services

Commands:
    start:   Start the MiniPrem services
    stop:    Stop the MiniPrem services
    status:  Check the status of the MiniPrem services
    restart: Restart the MiniPrem services
    logs:    View the logs of the MiniPrem services
    setup:   Run the Flowise chatflow setup

Options:
    -h: usage
EOF
    echo -e $NC
    exit 1
}

start_services() {
    log_section "Starting MiniPrem Services"
    cd docker && docker compose -f docker-compose.yml up -d
    if [ $? -eq 0 ]; then
        success "$CHECKMARK MiniPrem services started successfully"
    else
        fatal "$CROSS Failed to start MiniPrem services"
    fi
}

stop_services() {
    log_section "Stopping MiniPrem Services"
    cd docker && docker compose -f docker-compose.yml down
    if [ $? -eq 0 ]; then
        success "$CHECKMARK MiniPrem services stopped successfully"
    else
        fatal "$CROSS Failed to stop MiniPrem services"
    fi
}

restart_services() {
    log_section "Restarting MiniPrem Services"
    stop_services
    start_services
}

check_status() {
    log_section "MiniPrem Services Status"
    cd docker && docker compose -f docker-compose.yml ps
}

view_logs() {
    log_section "MiniPrem Services Logs"
    cd docker && docker compose -f docker-compose.yml logs -f
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
    bash docker/setup-chatflow-post-deployment.sh
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
    -h|--help)
        usage
        ;;
    *)
        usage
        ;;
esac