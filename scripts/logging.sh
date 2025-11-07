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
CHECKMARK="✓"
CROSS="✗"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Function to rotate logs
rotate_logs() {
    if [ -f "$LOG_FILE" ]; then
        # Extract timestamp using POSIX ERE (grep -oE) for macOS/BSD compatibility
        local timestamp
        local grep_output

        grep_output=$(head -n 1 "$LOG_FILE" 2>/dev/null | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}' 2>&1)
        local grep_exit=$?

        if [ -n "$grep_output" ]; then
            timestamp="$grep_output"
        else
            # Fallback to current timestamp
            timestamp=$(date +"%Y-%m-%d_%H-%M-%S")

            # Log why we're using fallback (only if grep actually failed, not just no match)
            if [ $grep_exit -ne 0 ] && [ $grep_exit -ne 1 ]; then
                echo "WARNING: Failed to extract timestamp from log file (grep exit: $grep_exit), using current time" >&2
            fi
        fi

        local target_file="$LOG_DIR/install_miniprem_$timestamp.log"

        # Check if mv succeeds
        if ! mv "$LOG_FILE" "$target_file" 2>/dev/null; then
            echo "ERROR: Failed to rotate log file from $LOG_FILE to $target_file" >&2
            echo "  - Check disk space: df -h" >&2
            echo "  - Check permissions: ls -la $LOG_DIR" >&2
            # Don't exit - rotation failure shouldn't kill the script
        fi
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

    # Log to console (stderr to avoid capture in redirects)
    echo -e "${color}${level}: ${symbol} ${message}${NC}" >&2

    # Log to file
    echo -e "${timestamp} ${level}: ${symbol} ${message}" >> "$LOG_FILE"
}

# Function to log section headers
log_section() {
    local section_name=$1
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local box_width=65  # Same width as in the port conflict warnings
    
    # Create horizontal border line with consistent width
    local border=$(printf "%${box_width}s" | tr ' ' '=')
    
    # Log to console (stderr to avoid capture in redirects)
    echo -e "\n${BLUE}${BOLD}+${border}+${NC}" >&2
    printf "${BLUE}${BOLD}| %-${box_width}s |${NC}\n" "$section_name" >&2
    echo -e "${BLUE}${BOLD}+${border}+${NC}\n" >&2
    
    # Log to file
    echo -e "\n${timestamp} +${border}+" >> "$LOG_FILE"
    printf "${timestamp} | %-${box_width}s |\n" "$section_name" >> "$LOG_FILE"
    echo -e "${timestamp} +${border}+\n" >> "$LOG_FILE"
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
        printf "    \b\b\b\b"
        # Log error with context before exiting
        error "Background process (PID: $pid) failed with exit code: $exit_status"
        error "Check the log file for details: $LOG_FILE"
        exit 1
    fi
    printf "    \b\b\b\b"
}