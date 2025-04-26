#!/bin/bash

# NOT TO BE RUN DIRECTLY, PLEASE RUN THE MAIN SCRIPT CALLED "install_miniprem.sh"

# Log file path
LOG_FILE="install_miniprem.log"
LOG_DIR="logs"

# Define ANSI color codes
LIGHTGRAY='\033[0;37m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Unicode characters for checkmark and cross
CHECKMARK="\u2714"
CROSS="\u2716"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Function to rotate logs
rotate_logs() {
    if [ -f "$LOG_FILE" ]; then
        # Read the timestamp from the log file
        local timestamp=$(head -n 1 "$LOG_FILE" | grep -oP '\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}')
        if [ -z "$timestamp" ]; then
            # If no timestamp is found, use the current time
            timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
        fi
        mv "$LOG_FILE" "$LOG_DIR/install_miniprem_$timestamp.log"
    fi
}

# Rotate logs at the start
rotate_logs

# Function to log messages to the console and log file
log_message() {
    local level=$1
    local color=$2
    local symbol=$3
    shift 3
    local message="$@"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    # Log to console
    echo -e "${color}${level}: ${symbol} ${message}${NC}"

    # Log to file
    echo -e "${timestamp} ${level}: ${symbol} ${message}" >> "$LOG_FILE"
}

# Function to log section headers
log_section() {
    local section_name=$1
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    # Log to console
    echo -e "\n${BLUE}${BOLD}========== ${section_name} ==========${NC}\n"

    # Log to file
    echo -e "\n${timestamp} ========== ${section_name} ==========\n" >> "$LOG_FILE"
}

# Function to initialize the log file with a timestamp
initialize_log() {
    local timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
    echo "Log start time: $timestamp" > "$LOG_FILE"
}

# Initialize the log file at the start
initialize_log

info() {
    local symbol=${1:-""}
    shift
    log_message "INFO" "$LIGHTGRAY" "$symbol" "$@"
}

success() {
    local symbol=${1:-$CHECKMARK}
    shift
    log_message "SUCCESS" "$GREEN" "$symbol" "$@"
}

warning() {
    local symbol=${1:-""}
    shift
    log_message "WARNING" "$ORANGE" "$symbol" "$@"
}

error() {
    local symbol=${1:-$CROSS}
    shift
    log_message "ERROR" "$RED" "$symbol" "$@"
}

fatal() {
    local symbol=${1:-$CROSS}
    shift
    log_message "FATAL" "$RED" "$symbol" "$@"
    exit 1
}

# Function to show a spinner
show_spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    wait $pid
    local exit_status=$?
    if [ $exit_status -ne 0 ]; then
        exit 1
    fi
    printf "    \b\b\b\b"
}