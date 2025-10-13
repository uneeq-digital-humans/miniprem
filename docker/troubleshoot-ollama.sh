#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Ollama container exists
check_ollama_container() {
    log_info "Checking if Ollama container exists..."
    
    if docker ps -a --format '{{.Names}}' | grep -q "^ollama$"; then
        log_success "Ollama container found."
        return 0
    else
        log_error "Ollama container not found."
        return 1
    fi
}

# Check Ollama container status
check_ollama_status() {
    log_info "Checking Ollama container status..."
    
    if docker ps --format '{{.Names}}' | grep -q "^ollama$"; then
        status=$(docker inspect --format='{{.State.Status}}' ollama)
        health_status=$(docker inspect --format='{{.State.Health.Status}}' ollama 2>/dev/null || echo "No health check")
        
        log_success "Ollama container is $status (Health: $health_status)"
        return 0
    else
        log_error "Ollama container is not running."
        return 1
    fi
}

# Check NVIDIA Docker setup
check_nvidia_docker() {
    log_info "Checking NVIDIA Docker setup..."

    if command -v nvidia-smi >/dev/null 2>&1; then
        log_success "NVIDIA drivers are installed."

        # Get GPU count
        local gpu_count=$(nvidia-smi --query-gpu=count --format=csv,noheader,nounits | head -1)
        log_info "Detected ${gpu_count} GPU(s)"

        # Query all GPUs and display with index
        local gpu_stats=$(nvidia-smi --query-gpu=driver_version,name,temperature.gpu,utilization.gpu,utilization.memory,memory.used,memory.total --format=csv,noheader)
        local gpu_index=0

        echo "GPU Stats:"
        while IFS= read -r line; do
            gpu_index=$((gpu_index + 1))
            echo "  GPU ${gpu_index}: ${line}"
        done <<< "$gpu_stats"
    else
        log_error "NVIDIA drivers not found. Make sure they are installed."
        return 1
    fi
    
    log_info "Testing NVIDIA Docker runtime..."
    if docker run --rm --gpus=all nvidia/cuda:11.6.2-base-ubuntu20.04 nvidia-smi >/dev/null 2>&1; then
        log_success "NVIDIA Docker runtime is working correctly."
        return 0
    else
        log_error "NVIDIA Docker runtime test failed. Please check your NVIDIA Container Toolkit installation."
        log_info "You may need to run: sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker"
        return 1
    fi
}

# View Ollama logs
view_ollama_logs() {
    log_info "Last 50 lines of Ollama container logs:"
    echo "----------------------------------------------"
    docker logs --tail 50 ollama
    echo "----------------------------------------------"
}

# Try to run Ollama with an explicit test
test_ollama_manually() {
    log_info "Attempting to run a small model for testing..."
    
    # Stop the existing ollama container if running
    if docker ps --format '{{.Names}}' | grep -q "^ollama$"; then
        log_info "Stopping existing Ollama container..."
        docker stop ollama
        docker rm ollama
    fi
    
    log_info "Starting Ollama with explicit GPU settings for testing..."
    docker run -d --gpus=all --name ollama-test -p 11434:11434 -v ollama_test_data:/root/.ollama ollama/ollama
    
    # Wait for it to start
    sleep 10
    
    if docker ps --format '{{.Names}}' | grep -q "^ollama-test$"; then
        log_success "Ollama test container started successfully."
        
        log_info "Testing model pull with 'tinyllama'..."
        docker exec ollama-test ollama pull tinyllama
        
        log_info "If successful, this shows that GPU acceleration is working."
        log_info "You should update your docker-compose.yml to match this configuration."
        
        # Clean up
        log_info "Stopping test container..."
        docker stop ollama-test
        docker rm ollama-test
    else
        log_error "Failed to start test Ollama container."
    fi
}

# Restart Ollama with standard command
restart_ollama() {
    log_info "Restarting Ollama container..."
    
    docker stop ollama 2>/dev/null
    docker rm ollama 2>/dev/null
    
    log_info "Starting fresh Ollama container with GPU support..."
    docker run -d --gpus=all -v ollama_data:/root/.ollama -p 11434:11434 --name ollama ollama/ollama
    
    sleep 5
    
    if docker ps --format '{{.Names}}' | grep -q "^ollama$"; then
        log_success "Ollama container restarted successfully."
        log_info "Monitor logs with: docker logs -f ollama"
        log_info "Try pulling a model with: docker exec ollama ollama pull tinyllama"
    else
        log_error "Failed to restart Ollama container."
    fi
}

# Main menu
main_menu() {
    echo -e "\n${BLUE}=== Ollama GPU Troubleshooting Tool ===${NC}"
    echo "1. Check Ollama container status"
    echo "2. Check NVIDIA Docker setup"
    echo "3. View Ollama logs"
    echo "4. Run Ollama test with explicit GPU settings"
    echo "5. Restart Ollama container with standard command"
    echo "6. Exit"
    
    read -p "Select an option (1-6): " choice
    
    case $choice in
        1) check_ollama_container && check_ollama_status ;;
        2) check_nvidia_docker ;;
        3) view_ollama_logs ;;
        4) test_ollama_manually ;;
        5) restart_ollama ;;
        6) exit 0 ;;
        *) log_error "Invalid option. Please try again." ;;
    esac
    
    read -p "Press Enter to continue..."
    main_menu
}

# Start the script
echo -e "${BLUE}Ollama GPU Troubleshooting Tool${NC}"
echo "This tool will help diagnose issues with Ollama and GPU support"
echo "------------------------------------------------------------"

main_menu