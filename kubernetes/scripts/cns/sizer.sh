#!/bin/bash

################################################################################
# MiniPrem CNS Deployment Sizer
#
# Calculates optimal Renny configuration based on:
#   - GPU model and VRAM
#   - Resolution (1080p, 4K)
#   - Quality mode (web, miniprem)
#
# Usage:
#   ./sizer.sh                    # Interactive mode
#   ./sizer.sh --gpu "A100 80GB"  # Direct specification
#   ./sizer.sh --detect           # Auto-detect GPU
#
################################################################################

set -eo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_color() { echo -e "${1}${2}${NC}"; }

################################################################################
# GPU Database - VRAM requirements per Renny instance (in GB)
################################################################################

# VRAM requirements (GB)
VRAM_RENNY_BASE=2.5      # Base Renny renderer
VRAM_VLLM_7B=6.0         # 7B parameter LLM (Mistral, Zephyr)
VRAM_VLLM_13B=10.0       # 13B parameter LLM
VRAM_VLLM_70B=35.0       # 70B parameter LLM (needs A100 80GB+)
VRAM_RIVA=4.0            # NVIDIA Riva TTS+ASR

# Resolution overhead (GB)
VRAM_720P=0.5
VRAM_1080P=1.0
VRAM_1440P=1.5
VRAM_4K=3.0

# Quality multipliers
QUALITY_WEB=1.0
QUALITY_MINIPREM=1.3

# Get GPU VRAM by name
get_gpu_vram() {
    local gpu="$1"
    case "$gpu" in
        "H100 80GB"|"H100 SXM"|"A100 80GB"|"A100X") echo 78 ;;
        "A100 40GB") echo 38 ;;
        "L40"|"L40S"|"RTX 6000 Ada"|"RTX A6000") echo 46 ;;
        "RTX 5000 Ada") echo 30 ;;
        "A30"|"A10"|"A10G"|"L4"|"RTX A5000"|"RTX 4090"|"RTX 3090") echo 22 ;;
        "T4"|"A16"|"RTX A4000"|"RTX 4080") echo 14 ;;
        "RTX 4070 Ti"|"RTX 3080 Ti") echo 10 ;;
        "RTX 3080") echo 8 ;;
        *) echo 0 ;;
    esac
}

################################################################################
# Functions
################################################################################

detect_gpu() {
    if ! command -v nvidia-smi &> /dev/null; then
        echo ""
        return
    fi

    # Get GPU name and memory
    local gpu_info=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits 2>/dev/null | head -1)
    if [[ -z "$gpu_info" ]]; then
        echo ""
        return
    fi

    local gpu_name=$(echo "$gpu_info" | cut -d',' -f1 | xargs)
    local gpu_mem=$(echo "$gpu_info" | cut -d',' -f2 | xargs)

    # Convert MiB to GB
    local gpu_mem_gb=$((gpu_mem / 1024))

    echo "${gpu_name}|${gpu_mem_gb}"
}

get_gpu_count() {
    if ! command -v nvidia-smi &> /dev/null; then
        echo "1"
        return
    fi
    nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | wc -l | xargs
}

calculate_renny_capacity() {
    local vram_gb=$1
    local resolution=$2
    local quality=$3
    local include_vllm=${4:-"7b"}
    local include_riva=${5:-"false"}

    # Get resolution overhead
    local res_overhead=1.0
    case "$resolution" in
        "720p")  res_overhead=$VRAM_720P ;;
        "1080p") res_overhead=$VRAM_1080P ;;
        "1440p") res_overhead=$VRAM_1440P ;;
        "4k")    res_overhead=$VRAM_4K ;;
    esac

    # Get quality multiplier
    local quality_mult=$QUALITY_MINIPREM
    if [[ "$quality" == "web" ]]; then
        quality_mult=$QUALITY_WEB
    fi

    # Calculate VRAM per Renny instance
    local per_renny=$(echo "$VRAM_RENNY_BASE + ($res_overhead * $quality_mult)" | bc)

    # Calculate shared services VRAM
    local shared_vram=0
    case "$include_vllm" in
        "7b")  shared_vram=$(echo "$shared_vram + $VRAM_VLLM_7B" | bc) ;;
        "13b") shared_vram=$(echo "$shared_vram + $VRAM_VLLM_13B" | bc) ;;
        "70b") shared_vram=$(echo "$shared_vram + $VRAM_VLLM_70B" | bc) ;;
        "none") ;;
    esac

    if [[ "$include_riva" == "true" ]]; then
        shared_vram=$(echo "$shared_vram + $VRAM_RIVA" | bc)
    fi

    # Available VRAM for Renny after shared services
    local available=$(echo "$vram_gb - $shared_vram" | bc)

    if (( $(echo "$available <= 0" | bc -l) )); then
        echo "0|$per_renny|$shared_vram"
        return
    fi

    # Calculate max Renny instances
    local max_rennys=$(echo "$available / $per_renny" | bc)

    echo "${max_rennys}|${per_renny}|${shared_vram}"
}

print_header() {
    echo ""
    print_color "$BOLD" "╔═══════════════════════════════════════════════════════════════╗"
    print_color "$BOLD" "║         MiniPrem CNS Deployment Sizer                         ║"
    print_color "$BOLD" "╚═══════════════════════════════════════════════════════════════╝"
    echo ""
}

print_config_table() {
    local gpu_name=$1
    local vram_gb=$2
    local gpu_count=$3

    echo ""
    print_color "$CYAN" "GPU Configuration:"
    echo "  Model: $gpu_name"
    echo "  VRAM per GPU: ${vram_gb}GB"
    echo "  GPU Count: $gpu_count"
    echo "  Total VRAM: $((vram_gb * gpu_count))GB"
    echo ""

    print_color "$BOLD" "┌─────────────┬──────────┬──────────────────┬──────────────────┐"
    print_color "$BOLD" "│ Resolution  │ Quality  │ Rennys (no LLM)  │ Rennys (+ 7B)    │"
    print_color "$BOLD" "├─────────────┼──────────┼──────────────────┼──────────────────┤"

    for res in "1080p" "4k"; do
        for qual in "web" "miniprem"; do
            local result_no_llm=$(calculate_renny_capacity "$vram_gb" "$res" "$qual" "none" "false")
            local result_with_llm=$(calculate_renny_capacity "$vram_gb" "$res" "$qual" "7b" "false")

            local rennys_no_llm=$(echo "$result_no_llm" | cut -d'|' -f1)
            local rennys_with_llm=$(echo "$result_with_llm" | cut -d'|' -f1)

            # Multiply by GPU count
            rennys_no_llm=$((rennys_no_llm * gpu_count))
            rennys_with_llm=$((rennys_with_llm * gpu_count))

            printf "│ %-11s │ %-8s │ %-16s │ %-16s │\n" \
                "$res" "$qual" "$rennys_no_llm instances" "$rennys_with_llm instances"
        done
    done

    print_color "$BOLD" "└─────────────┴──────────┴──────────────────┴──────────────────┘"
    echo ""
}

generate_config() {
    local gpu_name=$1
    local vram_gb=$2
    local resolution=$3
    local quality=$4
    local renny_count=$5
    local gpu_count=$6

    local rennys_per_gpu=$((renny_count / gpu_count))

    echo ""
    print_color "$GREEN" "Recommended Configuration:"
    echo ""
    echo "# Add to your environment or values file:"
    echo "RENNY_REPLICAS=$renny_count"
    echo "RENNY_QUALITY_LEVEL=$quality"
    echo "GPU_TIMESLICE_REPLICAS=$rennys_per_gpu"
    echo ""
    echo "# Renny command args for $resolution:"
    case "$resolution" in
        "720p")  echo 'RENNY_ARGS="/Game/Live_Levels/BlankScene -RenderOffScreen -ResX=1280 -ResY=720 -NoTextureStreaming"' ;;
        "1080p") echo 'RENNY_ARGS="/Game/Live_Levels/BlankScene -RenderOffScreen -ResX=1920 -ResY=1080 -NoTextureStreaming"' ;;
        "1440p") echo 'RENNY_ARGS="/Game/Live_Levels/BlankScene -RenderOffScreen -ResX=2560 -ResY=1440 -NoTextureStreaming"' ;;
        "4k")    echo 'RENNY_ARGS="/Game/Live_Levels/BlankScene -RenderOffScreen -ResX=3840 -ResY=2160 -NoTextureStreaming"' ;;
    esac
    echo ""

    print_color "$YELLOW" "To deploy with these settings:"
    echo "  RENNY_REPLICAS=$renny_count ./deploy.sh"
    echo ""
}

show_gpu_menu() {
    echo "Select your GPU model:"
    echo ""
    print_color "$BLUE" "  Datacenter GPUs (Recommended):"
    echo "    1) NVIDIA H100 80GB"
    echo "    2) NVIDIA A100 80GB"
    echo "    3) NVIDIA A100 40GB"
    echo "    4) NVIDIA L40/L40S (48GB)"
    echo "    5) NVIDIA A10/A10G (24GB)"
    echo "    6) NVIDIA T4 (16GB)"
    echo ""
    print_color "$BLUE" "  Workstation GPUs:"
    echo "    7) NVIDIA RTX 6000 Ada / A6000 (48GB)"
    echo "    8) NVIDIA RTX 5000 Ada (32GB)"
    echo "    9) NVIDIA RTX A5000 (24GB)"
    echo ""
    print_color "$BLUE" "  Other:"
    echo "    10) Custom (enter VRAM manually)"
    echo "    11) Auto-detect from system"
    echo ""
}

interactive_mode() {
    print_header

    # Check for auto-detect
    local detected=$(detect_gpu)
    if [[ -n "$detected" ]]; then
        local det_name=$(echo "$detected" | cut -d'|' -f1)
        local det_vram=$(echo "$detected" | cut -d'|' -f2)
        local det_count=$(get_gpu_count)

        print_color "$GREEN" "Detected GPU: $det_name (${det_vram}GB) x $det_count"
        echo ""
        read -p "Use detected GPU? [Y/n]: " use_detected

        if [[ "${use_detected,,}" != "n" ]]; then
            print_config_table "$det_name" "$det_vram" "$det_count"

            echo ""
            read -p "Enter desired resolution (1080p/4k) [1080p]: " resolution
            resolution=${resolution:-1080p}

            read -p "Enter quality mode (web/miniprem) [miniprem]: " quality
            quality=${quality:-miniprem}

            local result=$(calculate_renny_capacity "$det_vram" "$resolution" "$quality" "7b" "false")
            local max_rennys=$(echo "$result" | cut -d'|' -f1)
            max_rennys=$((max_rennys * det_count))

            read -p "Enter number of Renny instances [max: $max_rennys]: " renny_count
            renny_count=${renny_count:-$max_rennys}

            generate_config "$det_name" "$det_vram" "$resolution" "$quality" "$renny_count" "$det_count"
            return
        fi
    fi

    # Manual selection
    show_gpu_menu
    read -p "Select GPU [1-11]: " gpu_choice

    local gpu_name=""
    local vram_gb=0

    case "$gpu_choice" in
        1) gpu_name="H100 80GB"; vram_gb=78 ;;
        2) gpu_name="A100 80GB"; vram_gb=78 ;;
        3) gpu_name="A100 40GB"; vram_gb=38 ;;
        4) gpu_name="L40/L40S"; vram_gb=46 ;;
        5) gpu_name="A10/A10G"; vram_gb=22 ;;
        6) gpu_name="T4"; vram_gb=14 ;;
        7) gpu_name="RTX 6000 Ada"; vram_gb=46 ;;
        8) gpu_name="RTX 5000 Ada"; vram_gb=30 ;;
        9) gpu_name="RTX A5000"; vram_gb=22 ;;
        10)
            read -p "Enter GPU name: " gpu_name
            read -p "Enter usable VRAM (GB): " vram_gb
            ;;
        11)
            detected=$(detect_gpu)
            if [[ -z "$detected" ]]; then
                print_color "$RED" "No NVIDIA GPU detected"
                exit 1
            fi
            gpu_name=$(echo "$detected" | cut -d'|' -f1)
            vram_gb=$(echo "$detected" | cut -d'|' -f2)
            ;;
        *)
            print_color "$RED" "Invalid selection"
            exit 1
            ;;
    esac

    read -p "How many GPUs? [1]: " gpu_count
    gpu_count=${gpu_count:-1}

    print_config_table "$gpu_name" "$vram_gb" "$gpu_count"

    echo ""
    read -p "Enter desired resolution (1080p/4k) [1080p]: " resolution
    resolution=${resolution:-1080p}

    read -p "Enter quality mode (web/miniprem) [miniprem]: " quality
    quality=${quality:-miniprem}

    local result=$(calculate_renny_capacity "$vram_gb" "$resolution" "$quality" "7b" "false")
    local max_rennys=$(echo "$result" | cut -d'|' -f1)
    max_rennys=$((max_rennys * gpu_count))

    read -p "Enter number of Renny instances [max: $max_rennys]: " renny_count
    renny_count=${renny_count:-$max_rennys}

    generate_config "$gpu_name" "$vram_gb" "$resolution" "$quality" "$renny_count" "$gpu_count"
}

quick_estimate() {
    local gpu=$1
    local vram=$(get_gpu_vram "$gpu")

    if [[ $vram -eq 0 ]]; then
        print_color "$RED" "Unknown GPU: $gpu"
        echo "Available GPUs: H100 80GB, A100 80GB, A100 40GB, L40, A10G, T4, RTX 6000 Ada, RTX A6000, RTX 4090"
        exit 1
    fi

    print_header
    print_config_table "$gpu" "$vram" "1"
}

################################################################################
# Apply Configuration
################################################################################

detect_kubectl() {
    if command -v microk8s &> /dev/null; then
        echo "microk8s kubectl"
    elif command -v kubectl &> /dev/null; then
        echo "kubectl"
    else
        echo ""
    fi
}

detect_helm() {
    if command -v microk8s &> /dev/null; then
        echo "microk8s helm3"
    elif command -v helm &> /dev/null; then
        echo "helm"
    else
        echo ""
    fi
}

apply_configuration() {
    local renny_count=$1
    local rennys_per_gpu=$2
    local quality=$3
    local resolution=$4

    local KUBECTL=$(detect_kubectl)
    local HELM=$(detect_helm)

    if [[ -z "$KUBECTL" ]]; then
        print_color "$RED" "Error: kubectl not found. Is Kubernetes installed?"
        exit 1
    fi

    print_color "$BOLD" ""
    print_color "$BOLD" "Applying Configuration..."
    print_color "$BOLD" "========================="
    echo ""
    echo "  Renny Replicas: $renny_count"
    echo "  GPU Time-Slice: $rennys_per_gpu per GPU"
    echo "  Quality Mode:   $quality"
    echo "  Resolution:     $resolution"
    echo ""

    # Confirm before applying
    read -p "Apply this configuration? [y/N]: " confirm
    if [[ "${confirm,,}" != "y" ]]; then
        print_color "$YELLOW" "Aborted."
        exit 0
    fi

    echo ""

    # Step 1: Update GPU time-slicing ConfigMap
    print_color "$BLUE" "Step 1/4: Updating GPU time-slicing ConfigMap..."
    cat <<EOF | $KUBECTL apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: time-slicing-config
  namespace: gpu-operator
data:
  any: |-
    version: v1
    flags:
      migStrategy: none
    sharing:
      timeSlicing:
        renameByDefault: false
        failRequestsGreaterThanOne: false
        resources:
          - name: nvidia.com/gpu
            replicas: $rennys_per_gpu
EOF
    if [[ $? -eq 0 ]]; then
        print_color "$GREEN" "  ✓ Time-slicing ConfigMap updated"
    else
        print_color "$YELLOW" "  ⚠ ConfigMap update failed (may not exist yet)"
    fi

    # Step 2: Patch cluster policy (if exists)
    print_color "$BLUE" "Step 2/4: Patching GPU Operator cluster policy..."
    $KUBECTL patch clusterpolicies.nvidia.com/cluster-policy \
        -n gpu-operator \
        --type merge \
        -p '{"spec": {"devicePlugin": {"config": {"name": "time-slicing-config", "default": "any"}}}}' 2>/dev/null
    if [[ $? -eq 0 ]]; then
        print_color "$GREEN" "  ✓ Cluster policy patched"
    else
        print_color "$YELLOW" "  ⚠ Cluster policy patch skipped (may not exist)"
    fi

    # Step 3: Scale Renny deployment
    print_color "$BLUE" "Step 3/4: Scaling Renny deployment to $renny_count replicas..."

    # Try to find Renny deployment
    local RENNY_DEPLOY=$($KUBECTL get deployment -n uneeq -o name 2>/dev/null | grep -E "renny|renderer" | head -1)

    if [[ -n "$RENNY_DEPLOY" ]]; then
        $KUBECTL scale "$RENNY_DEPLOY" -n uneeq --replicas="$renny_count"
        print_color "$GREEN" "  ✓ Scaled $RENNY_DEPLOY to $renny_count replicas"
    else
        print_color "$YELLOW" "  ⚠ No Renny deployment found in 'uneeq' namespace"
        print_color "$YELLOW" "    Run deploy script first, or set RENNY_REPLICAS=$renny_count"
    fi

    # Step 4: Update environment variable (quality mode)
    print_color "$BLUE" "Step 4/4: Updating quality mode to '$quality'..."

    if [[ -n "$RENNY_DEPLOY" ]]; then
        $KUBECTL set env "$RENNY_DEPLOY" -n uneeq RENNY_QUALITY_LEVEL="$quality" 2>/dev/null
        if [[ $? -eq 0 ]]; then
            print_color "$GREEN" "  ✓ Quality mode set to '$quality'"
        else
            print_color "$YELLOW" "  ⚠ Could not set quality mode"
        fi
    fi

    echo ""
    print_color "$GREEN" "Configuration applied!"
    echo ""

    # Show current status
    print_color "$BOLD" "Current Status:"
    echo ""

    if [[ -n "$RENNY_DEPLOY" ]]; then
        $KUBECTL get pods -n uneeq -l app=renderer 2>/dev/null || \
        $KUBECTL get pods -n uneeq 2>/dev/null | head -10
    fi

    echo ""
    print_color "$CYAN" "Monitor rollout with:"
    echo "  $KUBECTL rollout status $RENNY_DEPLOY -n uneeq"
    echo ""
    print_color "$CYAN" "Watch pods:"
    echo "  $KUBECTL get pods -n uneeq -w"
    echo ""
    print_color "$CYAN" "Check GPU usage:"
    echo "  nvidia-smi -l 1"
}

apply_interactive() {
    print_header

    # Detect GPU
    local detected=$(detect_gpu)
    local gpu_name=""
    local vram_gb=""
    local gpu_count=""

    if [[ -n "$detected" ]]; then
        gpu_name=$(echo "$detected" | cut -d'|' -f1)
        vram_gb=$(echo "$detected" | cut -d'|' -f2)
        gpu_count=$(get_gpu_count)

        print_color "$GREEN" "Detected: $gpu_name (${vram_gb}GB) × $gpu_count"
        echo ""
    else
        print_color "$RED" "No GPU detected. Cannot auto-configure."
        echo ""
        read -p "Enter GPU VRAM in GB: " vram_gb
        gpu_count=1
        gpu_name="Manual"
    fi

    # Show capacity table
    print_config_table "$gpu_name" "$vram_gb" "$gpu_count"

    # Get user preferences
    echo ""
    read -p "Resolution (1080p/4k) [1080p]: " resolution
    resolution=${resolution:-1080p}

    read -p "Quality mode (web/miniprem) [miniprem]: " quality
    quality=${quality:-miniprem}

    read -p "Include local LLM? (y/n) [y]: " include_llm
    include_llm=${include_llm:-y}

    local llm_type="7b"
    if [[ "${include_llm,,}" != "y" ]]; then
        llm_type="none"
    fi

    # Calculate
    local result=$(calculate_renny_capacity "$vram_gb" "$resolution" "$quality" "$llm_type" "false")
    local max_per_gpu=$(echo "$result" | cut -d'|' -f1)
    local max_total=$((max_per_gpu * gpu_count))

    echo ""
    print_color "$CYAN" "Maximum Renny instances: $max_total"
    read -p "How many Rennys to deploy? [$max_total]: " renny_count
    renny_count=${renny_count:-$max_total}

    # Validate
    if [[ $renny_count -gt $max_total ]]; then
        print_color "$YELLOW" "Warning: $renny_count exceeds recommended max ($max_total)"
        read -p "Continue anyway? [y/N]: " force
        if [[ "${force,,}" != "y" ]]; then
            exit 1
        fi
    fi

    # Calculate per-GPU slicing
    local rennys_per_gpu=$(( (renny_count + gpu_count - 1) / gpu_count ))

    # Apply
    apply_configuration "$renny_count" "$rennys_per_gpu" "$quality" "$resolution"
}

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --detect           Auto-detect GPU and show capacity"
    echo "  --gpu \"MODEL\"      Specify GPU model (e.g., \"A100 80GB\")"
    echo "  --apply            Interactive mode with auto-apply to cluster"
    echo "  --apply-quick      Auto-detect GPU and apply recommended config"
    echo "  --list             List known GPU models"
    echo "  --help             Show this help"
    echo ""
    echo "Examples:"
    echo "  $0                          # Interactive calculator (no changes)"
    echo "  $0 --detect                 # Auto-detect and show capacity table"
    echo "  $0 --gpu \"A100 80GB\"        # Show capacity for specific GPU"
    echo "  $0 --apply                  # Interactive mode, then apply to cluster"
    echo "  $0 --apply-quick            # Auto-detect and apply recommended config"
    echo ""
}

################################################################################
# Main
################################################################################

main() {
    case "${1:-}" in
        --detect)
            print_header
            local detected=$(detect_gpu)
            if [[ -z "$detected" ]]; then
                print_color "$RED" "No NVIDIA GPU detected"
                exit 1
            fi
            local gpu_name=$(echo "$detected" | cut -d'|' -f1)
            local vram_gb=$(echo "$detected" | cut -d'|' -f2)
            local gpu_count=$(get_gpu_count)
            print_config_table "$gpu_name" "$vram_gb" "$gpu_count"
            ;;
        --gpu)
            quick_estimate "${2:-}"
            ;;
        --apply)
            apply_interactive
            ;;
        --apply-quick)
            print_header
            local detected=$(detect_gpu)
            if [[ -z "$detected" ]]; then
                print_color "$RED" "No NVIDIA GPU detected"
                exit 1
            fi
            local gpu_name=$(echo "$detected" | cut -d'|' -f1)
            local vram_gb=$(echo "$detected" | cut -d'|' -f2)
            local gpu_count=$(get_gpu_count)

            print_color "$GREEN" "Detected: $gpu_name (${vram_gb}GB) × $gpu_count"
            print_config_table "$gpu_name" "$vram_gb" "$gpu_count"

            # Use defaults: 1080p, miniprem, with 7B LLM
            local result=$(calculate_renny_capacity "$vram_gb" "1080p" "miniprem" "7b" "false")
            local max_per_gpu=$(echo "$result" | cut -d'|' -f1)
            local max_total=$((max_per_gpu * gpu_count))
            local rennys_per_gpu=$max_per_gpu

            print_color "$CYAN" "Recommended config: $max_total Rennys @ 1080p miniprem (with 7B LLM)"
            echo ""

            apply_configuration "$max_total" "$rennys_per_gpu" "miniprem" "1080p"
            ;;
        --list)
            echo "Known GPU models:"
            echo "  Datacenter: H100 80GB, A100 80GB, A100 40GB, L40, L40S, A10, A10G, T4"
            echo "  Workstation: RTX 6000 Ada, RTX A6000, RTX A5000, RTX 5000 Ada"
            echo "  Consumer: RTX 4090, RTX 4080, RTX 3090"
            ;;
        --help|-h)
            usage
            ;;
        "")
            interactive_mode
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"
