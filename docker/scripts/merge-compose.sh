#!/usr/bin/env bash
################################################################################
# merge-compose.sh - Intelligent Docker Compose File Merger
#
# Merges official docker-compose.yml with custom docker-compose.custom.yml
# Handles YAML parsing, conflict detection, and generates override files.
#
# Usage: ./merge-compose.sh [OPTIONS]
#
# Exit Codes:
#   0 - Success
#   1 - Error (validation failed, missing tools, etc.)
#   2 - Conflicts detected (informational, may still succeed based on strategy)
################################################################################

set -euo pipefail

# Script directory and Docker root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Default configuration
DEFAULT_OFFICIAL_FILE="${DOCKER_ROOT}/docker-compose.yml"
DEFAULT_CUSTOM_FILE="${DOCKER_ROOT}/docker-compose.custom.yml"
DEFAULT_OUTPUT_FILE="${DOCKER_ROOT}/docker-compose.override.yml"

# CLI options
OFFICIAL_FILE="${DEFAULT_OFFICIAL_FILE}"
CUSTOM_FILE="${DEFAULT_CUSTOM_FILE}"
OUTPUT_FILE="${DEFAULT_OUTPUT_FILE}"
CHECK_ONLY=false
PREFER_CUSTOM=true
RENAME_CUSTOM_PREFIX=""
VERBOSE=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# Helper Functions
################################################################################

log() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_verbose() {
    if [[ "${VERBOSE}" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $*"
    fi
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

show_help() {
    cat << EOF
Usage: ${0##*/} [OPTIONS]

Intelligently merge official and custom Docker Compose files.

OPTIONS:
    --file FILE              Input custom compose file
                             (default: docker-compose.custom.yml)
    --output FILE            Output file
                             (default: docker-compose.override.yml)
    --check                  Check compatibility without writing
    --prefer-custom          Keep custom when conflicts exist (DEFAULT)
    --prefer-official        Use official when conflicts exist
    --rename-custom PREFIX   Rename conflicting custom services with PREFIX
    --verbose                Enable debug output
    -h, --help               Show this help message

EXAMPLES:
    # Basic merge with defaults
    ${0##*/}

    # Check for conflicts without writing
    ${0##*/} --check

    # Prefer official services when conflicts exist
    ${0##*/} --prefer-official

    # Rename conflicting custom services
    ${0##*/} --rename-custom "custom-"

    # Custom input and output files
    ${0##*/} --file my-custom.yml --output my-override.yml

EXIT CODES:
    0 - Success
    1 - Error (validation failed, missing tools, etc.)
    2 - Conflicts detected (informational, depends on strategy)

EOF
}

################################################################################
# Validation Functions
################################################################################

check_dependencies() {
    local missing_tools=()

    # Check for required tools
    if ! command -v yq &> /dev/null; then
        missing_tools+=("yq")
    fi

    if ! command -v docker &> /dev/null && ! command -v docker-compose &> /dev/null; then
        missing_tools+=("docker or docker-compose")
    fi

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please install missing dependencies:"
        log_error "  - yq: brew install yq (macOS) or https://github.com/mikefarah/yq"
        return 1
    fi

    log_verbose "All required dependencies found"
    return 0
}

validate_yaml_syntax() {
    local file="$1"
    local label="${2:-file}"

    log_verbose "Validating YAML syntax for ${label}: ${file}"

    if [[ ! -f "${file}" ]]; then
        log_error "${label} does not exist: ${file}"
        return 1
    fi

    # Use yq to validate YAML syntax
    if ! yq eval '.' "${file}" > /dev/null 2>&1; then
        log_error "Invalid YAML syntax in ${label}: ${file}"
        return 1
    fi

    log_verbose "${label} has valid YAML syntax"
    return 0
}

validate_compose_file() {
    local file="$1"
    local label="${2:-file}"

    log_verbose "Validating Docker Compose structure for ${label}: ${file}"

    # Check for required top-level keys
    if ! yq eval 'has("services")' "${file}" | grep -q "true"; then
        log_error "${label} missing required 'services' key: ${file}"
        return 1
    fi

    log_verbose "${label} has valid Docker Compose structure"
    return 0
}

################################################################################
# Conflict Detection
################################################################################

detect_service_conflicts() {
    local official_file="$1"
    local custom_file="$2"

    log_verbose "Detecting service name conflicts..."

    local official_services
    local custom_services
    local conflicts=()

    # Get service lists
    official_services=$(yq eval '.services | keys | .[]' "${official_file}" 2>/dev/null || echo "")
    custom_services=$(yq eval '.services | keys | .[]' "${custom_file}" 2>/dev/null || echo "")

    # Find duplicates
    while IFS= read -r service; do
        if echo "${official_services}" | grep -q "^${service}$"; then
            conflicts+=("${service}")
        fi
    done <<< "${custom_services}"

    if [[ ${#conflicts[@]} -gt 0 ]]; then
        log_warn "Found ${#conflicts[@]} service name conflict(s):"
        for service in "${conflicts[@]}"; do
            log_warn "  - ${service}"
        done
        echo "${conflicts[@]}"
        return 2
    fi

    log_verbose "No service name conflicts detected"
    return 0
}

################################################################################
# Merging Functions
################################################################################

merge_services() {
    local official_file="$1"
    local custom_file="$2"
    local output_file="$3"
    shift 3
    local conflicts=("$@")

    log "Merging services..."

    # Start with the full official file structure (including name, etc.)
    yq eval '.' "${official_file}" > "${output_file}.tmp.merged"

    # Process custom services
    local custom_services
    custom_services=$(yq eval '.services | keys | .[]' "${custom_file}" 2>/dev/null || echo "")

    while IFS= read -r service; do
        [[ -z "${service}" ]] && continue

        local is_conflict=false
        if [[ ${#conflicts[@]} -gt 0 ]]; then
            for conflict in "${conflicts[@]}"; do
                if [[ "${service}" == "${conflict}" ]]; then
                    is_conflict=true
                    break
                fi
            done
        fi

        if [[ "${is_conflict}" == "true" ]]; then
            # Handle conflict based on strategy
            if [[ "${PREFER_CUSTOM}" == "true" ]]; then
                log_verbose "Overwriting service '${service}' with custom version (prefer-custom)"
                yq eval-all --inplace \
                    "select(fileIndex == 0).services.${service} = select(fileIndex == 1).services.${service} | select(fileIndex == 0)" \
                    "${output_file}.tmp.merged" "${custom_file}"
            elif [[ -n "${RENAME_CUSTOM_PREFIX}" ]]; then
                local new_name="${RENAME_CUSTOM_PREFIX}${service}"
                log_verbose "Renaming custom service '${service}' to '${new_name}'"
                yq eval-all --inplace \
                    "select(fileIndex == 0).services.${new_name} = select(fileIndex == 1).services.${service} | select(fileIndex == 0)" \
                    "${output_file}.tmp.merged" "${custom_file}"
            else
                log_verbose "Keeping official service '${service}' (prefer-official)"
            fi
        else
            # No conflict, add custom service
            log_verbose "Adding custom service '${service}'"
            yq eval-all --inplace \
                "select(fileIndex == 0).services.${service} = select(fileIndex == 1).services.${service} | select(fileIndex == 0)" \
                "${output_file}.tmp.merged" "${custom_file}"
        fi
    done <<< "${custom_services}"
}

merge_volumes() {
    local official_file="$1"
    local custom_file="$2"
    local output_file="$3"

    log_verbose "Merging volumes..."

    # Get custom volumes
    local custom_volumes
    custom_volumes=$(yq eval '.volumes // {}' "${custom_file}")

    # If custom file has volumes, merge them
    if [[ "${custom_volumes}" != "{}" ]]; then
        # Merge volumes into the main merged file (custom takes precedence)
        yq eval-all --inplace \
            'select(fileIndex == 0).volumes = (select(fileIndex == 0).volumes // {}) * select(fileIndex == 1).volumes | select(fileIndex == 0)' \
            "${output_file}.tmp.merged" "${custom_file}"
    fi
}

merge_networks() {
    local official_file="$1"
    local custom_file="$2"
    local output_file="$3"

    log_verbose "Merging networks..."

    # Get custom networks
    local custom_networks
    custom_networks=$(yq eval '.networks // {}' "${custom_file}")

    # If custom file has networks, merge them
    if [[ "${custom_networks}" != "{}" ]]; then
        # Merge networks into the main merged file (custom takes precedence)
        yq eval-all --inplace \
            'select(fileIndex == 0).networks = (select(fileIndex == 0).networks // {}) * select(fileIndex == 1).networks | select(fileIndex == 0)' \
            "${output_file}.tmp.merged" "${custom_file}"
    fi
}

add_metadata_header() {
    local output_file="$1"
    shift
    local conflicts=("$@")

    local timestamp
    timestamp=$(date -u +"%Y-%m-%d %H:%M:%S UTC")

    cat > "${output_file}.header" << EOF
# Docker Compose Override File
# Generated by merge-compose.sh on ${timestamp}
#
# This file was created by merging:
#   Official: ${OFFICIAL_FILE}
#   Custom:   ${CUSTOM_FILE}
#
# Merge Strategy: $(if [[ "${PREFER_CUSTOM}" == "true" ]]; then echo "prefer-custom"; elif [[ -n "${RENAME_CUSTOM_PREFIX}" ]]; then echo "rename-custom (${RENAME_CUSTOM_PREFIX})"; else echo "prefer-official"; fi)
EOF

    if [[ ${#conflicts[@]} -gt 0 ]]; then
        echo "#" >> "${output_file}.header"
        echo "# Conflicts Resolved: ${#conflicts[@]}" >> "${output_file}.header"
        for conflict in "${conflicts[@]}"; do
            echo "#   - ${conflict}" >> "${output_file}.header"
        done
    fi

    echo "#" >> "${output_file}.header"
    echo "" >> "${output_file}.header"

    # Prepend header to merged file
    cat "${output_file}.header" "${output_file}.tmp.merged" > "${output_file}"
    rm -f "${output_file}.header" "${output_file}.tmp.merged"
}

validate_merged_output() {
    local output_file="$1"

    log "Validating merged output..."

    # Validate YAML syntax
    if ! validate_yaml_syntax "${output_file}" "merged output"; then
        return 1
    fi

    # Validate with docker-compose config (if docker-compose is available)
    if command -v docker-compose &> /dev/null; then
        log_verbose "Running docker-compose config validation..."

        local temp_dir
        temp_dir=$(mktemp -d)
        cp "${output_file}" "${temp_dir}/docker-compose.yml"

        if (cd "${temp_dir}" && docker-compose config > /dev/null 2>&1); then
            log_verbose "docker-compose config validation passed"
            rm -rf "${temp_dir}"
            return 0
        else
            log_error "docker-compose config validation failed"
            rm -rf "${temp_dir}"
            return 1
        fi
    fi

    log_verbose "Merged output validation passed"
    return 0
}

################################################################################
# Main Merge Function
################################################################################

perform_merge() {
    local official_file="$1"
    local custom_file="$2"
    local output_file="$3"

    log "Starting merge process..."
    log "  Official: ${official_file}"
    log "  Custom:   ${custom_file}"
    log "  Output:   ${output_file}"

    # Validate input files
    validate_yaml_syntax "${official_file}" "official file" || return 1
    validate_yaml_syntax "${custom_file}" "custom file" || return 1
    validate_compose_file "${official_file}" "official file" || return 1
    validate_compose_file "${custom_file}" "custom file" || return 1

    # Detect conflicts
    local conflicts_str
    local conflicts=()
    local exit_code=0

    if conflicts_str=$(detect_service_conflicts "${official_file}" "${custom_file}" 2>&1 >&2); then
        log_verbose "No conflicts detected"
    else
        exit_code=$?
        if [[ ${exit_code} -eq 2 ]]; then
            # Capture the echoed conflicts (last line of stderr output)
            conflicts_str=$(detect_service_conflicts "${official_file}" "${custom_file}" 2>/dev/null | tail -1)
            read -ra conflicts <<< "${conflicts_str}"
            log_verbose "Detected conflicts: ${conflicts[*]}"
            log_warn "Conflicts will be resolved using merge strategy"
        fi
    fi

    # Check-only mode
    if [[ "${CHECK_ONLY}" == "true" ]]; then
        log "Check-only mode: No output file written"
        if [[ ${#conflicts[@]} -gt 0 ]]; then
            log_warn "Conflicts detected (see above)"
            return 2
        fi
        log_success "No conflicts detected"
        return 0
    fi

    # Perform merge
    if [[ ${#conflicts[@]} -gt 0 ]]; then
        merge_services "${official_file}" "${custom_file}" "${output_file}" "${conflicts[@]}"
    else
        merge_services "${official_file}" "${custom_file}" "${output_file}"
    fi
    merge_volumes "${official_file}" "${custom_file}" "${output_file}"
    merge_networks "${official_file}" "${custom_file}" "${output_file}"

    # Add metadata header
    if [[ ${#conflicts[@]} -gt 0 ]]; then
        add_metadata_header "${output_file}" "${conflicts[@]}"
    else
        add_metadata_header "${output_file}"
    fi

    # Validate merged output
    if ! validate_merged_output "${output_file}"; then
        log_error "Merged output validation failed"
        return 1
    fi

    log_success "Merge completed successfully"
    log_success "Output written to: ${output_file}"

    if [[ ${#conflicts[@]} -gt 0 ]]; then
        log_warn "Resolved ${#conflicts[@]} conflict(s) - review output file"
        return 2
    fi

    return 0
}

################################################################################
# Argument Parsing
################################################################################

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --file)
                CUSTOM_FILE="$2"
                shift 2
                ;;
            --output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            --check)
                CHECK_ONLY=true
                shift
                ;;
            --prefer-custom)
                PREFER_CUSTOM=true
                RENAME_CUSTOM_PREFIX=""
                shift
                ;;
            --prefer-official)
                PREFER_CUSTOM=false
                RENAME_CUSTOM_PREFIX=""
                shift
                ;;
            --rename-custom)
                RENAME_CUSTOM_PREFIX="$2"
                PREFER_CUSTOM=false
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo ""
                show_help
                exit 1
                ;;
        esac
    done

    # Convert relative paths to absolute
    if [[ ! "${CUSTOM_FILE}" =~ ^/ ]]; then
        CUSTOM_FILE="${DOCKER_ROOT}/${CUSTOM_FILE}"
    fi

    if [[ ! "${OUTPUT_FILE}" =~ ^/ ]]; then
        OUTPUT_FILE="${DOCKER_ROOT}/${OUTPUT_FILE}"
    fi
}

################################################################################
# Main Execution
################################################################################

main() {
    parse_arguments "$@"

    log "Docker Compose Merge Utility"
    log "=============================="

    # Check dependencies
    if ! check_dependencies; then
        exit 1
    fi

    # Check if custom file exists
    if [[ ! -f "${CUSTOM_FILE}" ]]; then
        log_error "Custom file does not exist: ${CUSTOM_FILE}"
        exit 1
    fi

    # Perform merge
    if perform_merge "${OFFICIAL_FILE}" "${CUSTOM_FILE}" "${OUTPUT_FILE}"; then
        exit 0
    else
        exit_code=$?
        if [[ ${exit_code} -eq 2 ]]; then
            # Conflicts detected but merge succeeded
            exit 2
        else
            # Merge failed
            exit 1
        fi
    fi
}

# Run main function
main "$@"
