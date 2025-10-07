# Bash Script Validation Report: install_miniprem.sh

**Script Path:** `/Users/tyler/Software_Development/miniprem-2025/docker/scripts/install_miniprem.sh`
**Analysis Date:** 2025-10-07
**Overall Risk Score:** 6.5/10 - Moderate Risk
**Recommendation:** Requires fixes before production use

---

## Executive Summary

The installation script is functional but has several critical security and reliability issues that should be addressed before production deployment. The main concerns are command injection vulnerabilities, missing error handling, and race conditions.

---

## Critical Errors (5)

### 1. Command Injection Risk - Line 40
**Severity:** 🔴 Critical
**Location:** `validate_cloud_service()` function

**Issue:**
```bash
response=$(curl -s -o /dev/null -w "%{http_code}" http://$address:$port)
```

**Problem:** User-supplied `$address` and `$port` are used in curl without proper validation or quoting. This creates command injection vulnerability.

**Fix:**
```bash
# Add input validation
if [[ ! "$address" =~ ^[a-zA-Z0-9.-]+$ ]]; then
    fatal "Invalid address format: $address"
fi
if [[ ! "$port" =~ ^[0-9]+$ ]]; then
    fatal "Invalid port format: $port"
fi
response=$(curl -s -o /dev/null -w "%{http_code}" "http://${address}:${port}")
```

---

### 2. Missing Error Handling - Line 621
**Severity:** 🔴 Critical
**Location:** `ensure_env_file_exists()` function

**Issue:**
```bash
if ! stat "$env_file" > /dev/null 2>&1; then
    if [ -f "$example_file" ]; then
        info "Environment file not found, creating from example."
        cp "$example_file" "$env_file"
```

**Problem:** The `cp` command can fail (permissions, disk space) but there's no check if the copy succeeded before proceeding.

**Fix:**
```bash
if ! cp "$example_file" "$env_file"; then
    fatal "Failed to copy example file to $env_file. Check permissions and disk space."
fi
# Verify the file exists and is readable
if [ ! -r "$env_file" ]; then
    fatal "Created $env_file but cannot read it. Check permissions."
fi
```

---

### 3. Insecure File Permissions - Line 747
**Severity:** 🔴 Critical
**Location:** `start_miniprem()` function

**Issue:**
```bash
mkdir -p "$PROJECT_ROOT/docker/vllm_data"
chmod 777 "$PROJECT_ROOT/docker/vllm_data"
```

**Problem:** `chmod 777` grants full read/write/execute permissions to all users. This is a security risk.

**Fix:**
```bash
mkdir -p "$PROJECT_ROOT/docker/vllm_data"
# Use restrictive permissions and adjust if Docker needs specific ownership
chmod 755 "$PROJECT_ROOT/docker/vllm_data"
# If Docker needs write access, use specific user/group
chown "${USER}:docker" "$PROJECT_ROOT/docker/vllm_data" 2>/dev/null || true
chmod 775 "$PROJECT_ROOT/docker/vllm_data"
```

---

### 4. Race Condition - Lines 1171-1192
**Severity:** 🟡 High
**Location:** `check_duplicate_installations()` function

**Issue:**
```bash
local miniprem_dirs=$(sudo find / -type d -iname "*miniprem*" \
    -not -path "*/\.*" \
    -not -path "*/proc/*" \
    # ... many exclusions
    2>/dev/null | sort)
```

**Problem:** Using `sudo find /` is extremely slow, can fail with permission errors, and creates a race condition if files change during the scan.

**Fix:**
```bash
# Instead of scanning the entire filesystem, search in likely locations only
local search_paths=("/opt" "/usr/local" "$HOME" "/home")
local miniprem_dirs=""

for path in "${search_paths[@]}"; do
    if [ -d "$path" ]; then
        miniprem_dirs+=$(find "$path" -maxdepth 3 -type d -iname "*miniprem*" 2>/dev/null)
        miniprem_dirs+=$'\n'
    fi
done

# Remove duplicates and sort
miniprem_dirs=$(echo "$miniprem_dirs" | grep -v "^$" | sort -u)
```

---

### 5. No Cleanup on Failure - Throughout Script
**Severity:** 🟡 High
**Location:** Global

**Problem:** If the script fails mid-execution, there's no cleanup mechanism to remove partially created files, stop partially started containers, or restore the previous state.

**Fix:**
```bash
# Add at the top of main() function
setup_cleanup_handler() {
    trap 'cleanup_on_error' ERR EXIT
}

cleanup_on_error() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        warning "Installation failed with exit code $exit_code"
        warning "Attempting to clean up..."

        # Stop any partially started containers
        if [ -d "$PROJECT_ROOT/docker" ]; then
            (cd "$PROJECT_ROOT/docker" && sudo docker compose down) 2>/dev/null || true
        fi

        # Remove installation marker if it was just created
        if [ -f "$PROJECT_ROOT/.miniprem_installation_marker" ]; then
            local marker_age=$(stat -f %B "$PROJECT_ROOT/.miniprem_installation_marker" 2>/dev/null)
            local current_time=$(date +%s)
            if [ $((current_time - marker_age)) -lt 300 ]; then
                rm -f "$PROJECT_ROOT/.miniprem_installation_marker"
            fi
        fi

        error "Cleanup complete. Please review errors above before retrying."
    fi
}

# Call in main()
setup_cleanup_handler
```

---

## Warnings (6)

### 1. Incomplete Input Validation - Lines 191-205
**Severity:** 🟡 Medium
**Location:** `check_and_prompt_for_value()` function

**Issue:** Function only checks if value is empty, doesn't validate format or content.

**Fix:**
```bash
check_and_prompt_for_value() {
    local prompt_message=$1
    local current_value=$2
    local validation_regex=$3  # Add optional validation
    local input_value=$current_value

    if [ -z "$current_value" ]; then
        read -p "$prompt_message: " input_value
        if [ -z "$input_value" ]; then
            echo ""
            return 1
        fi

        # Validate if regex provided
        if [ -n "$validation_regex" ] && [[ ! "$input_value" =~ $validation_regex ]]; then
            warning "Invalid input format for $prompt_message"
            return 1
        fi
    fi

    echo "$input_value"
}
```

---

### 2. Missing DOCKER_CMD Export - Lines 128, 396, 714, etc.
**Severity:** 🟡 Medium
**Location:** Multiple functions

**Issue:** `DOCKER_CMD` is set locally in functions but not exported, leading to inconsistent usage.

**Fix:**
```bash
# At the top of the script, after sourcing other scripts
declare -g DOCKER_CMD="sudo docker"
declare -g DOCKER_COMPOSE_CMD="sudo docker compose"

# Then use consistently:
pull_required_images() {
    # Just use $DOCKER_CMD and $DOCKER_COMPOSE_CMD directly
}
```

---

### 3. Unsafe sed Operations - Lines 468, 571-573
**Severity:** 🟡 Medium
**Location:** Multiple file editing operations

**Issue:** Using `sed -i` without backup can corrupt files if the operation fails mid-way.

**Fix:**
```bash
# Create backup before editing
local backup_file="${compose_file}.bak.$(date +%s)"
cp "$compose_file" "$backup_file"

# Perform sed operations
if sed -i '/^### RIME BEGIN ###/,/^### RIME END ###/s/^  # /  /' "$compose_file"; then
    success "$CHECKMARK docker-compose.yml updated"
    # Remove backup on success
    rm -f "$backup_file"
else
    # Restore from backup on failure
    error "Failed to update docker-compose.yml, restoring backup"
    mv "$backup_file" "$compose_file"
    return 1
fi
```

---

### 4. No Timeout on User Input - Lines 72, 91, 987
**Severity:** 🟠 Low
**Location:** Multiple `read -p` statements

**Issue:** Script can hang indefinitely waiting for user input.

**Fix:**
```bash
# Add timeout to all read statements
read -t 300 -p "Enter choice [1-2]: " install_choice || {
    warning "Input timeout after 5 minutes. Exiting."
    exit 1
}
```

---

### 5. Hardcoded Paths - Lines 452, 479, 509
**Severity:** 🟠 Low
**Location:** Multiple functions

**Issue:** Paths are hardcoded, making the script less portable.

**Fix:**
```bash
# Define path constants at the top
readonly DOCKER_DIR="$PROJECT_ROOT/docker"
readonly COMPOSE_FILE="$DOCKER_DIR/docker-compose.yml"
readonly COMPOSE_DEFAULT_FILE="$DOCKER_DIR/docker-compose.default.yml"
readonly ENV_FILE="$DOCKER_DIR/docker-compose.env"
readonly ENV_EXAMPLE_FILE="$DOCKER_DIR/docker-compose.env.example"

# Use throughout script
update_docker_compose_for_tts() {
    local compose_file="$COMPOSE_FILE"
    # ...
}
```

---

### 6. Port Conflict Detection Incomplete - Lines 1082-1144
**Severity:** 🟡 Medium
**Location:** `check_environment()` function

**Issue:** Only checks port 6379 (Redis), but script uses many other ports that could conflict (3000, 3001, 8000, 8081, 9090, etc.).

**Fix:**
```bash
# Extend port_map to include all used ports
local port_map=(
    "3000:Flowise"
    "3001:MiniPrem Monitor"
    "3002:Grafana"
    "6379:Redis"
    "8000:vLLM/Backend"
    "8081:Renny"
    "8100:RIME"
    "9000:Whisper"
    "9090:Prometheus"
)
```

---

## Best Practice Recommendations (10)

### 1. Global Variable Management
**Issue:** Many variables are modified across multiple functions without clear scope.

**Recommendation:**
```bash
# At the top of the script
declare -g PLATFORM_ADDRESS=""
declare -g PLATFORM_KEY=""
declare -g TENANT_ID=""
declare -g TTS_PROVIDER=""
declare -g INSTALL_TYPE=""
declare -g AZURE_REGION=""
declare -g AZURE_SPEECH_KEY=""
declare -g ELEVEN_LABS_API_KEY=""
declare -g RIME_API_KEY=""
declare -g RENNY_IMAGE=""

# Use readonly for constants
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly SCRIPT_VERSION="1.0.0"
```

---

### 2. Function Decomposition
**Issue:** Functions like `main()` are too long (240+ lines) and do too many things.

**Recommendation:**
```bash
# Break down main() into smaller functions:
main() {
    print_logo
    validate_environment
    collect_configuration
    validate_configuration
    prepare_system
    install_services
    post_install_configuration
    print_success_message
}

validate_environment() {
    check_environment
    check_duplicate_installations
    check_installer_prequisites
    check_driver_prerequisites
    check_software_prequisites
    check_hardware_prerequisites
    check_docker_installation
}

collect_configuration() {
    prompt_for_install_type
    ensure_env_file_exists
    select_tts_provider
    configure_tts_provider
    collect_platform_credentials
}
```

---

### 3. Logging Improvements
**Issue:** Mix of `echo`, `info`, `warning`, `error`, and `fatal` makes it hard to filter logs.

**Recommendation:**
```bash
# Add log levels and timestamps
LOG_LEVEL=${LOG_LEVEL:-INFO}  # DEBUG, INFO, WARN, ERROR, FATAL

log_with_level() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$level" in
        DEBUG) [ "$LOG_LEVEL" = "DEBUG" ] && echo "[$timestamp] [DEBUG] $message" ;;
        INFO)  echo "[$timestamp] [INFO]  $message" ;;
        WARN)  echo "[$timestamp] [WARN]  $message" >&2 ;;
        ERROR) echo "[$timestamp] [ERROR] $message" >&2 ;;
        FATAL) echo "[$timestamp] [FATAL] $message" >&2; exit 1 ;;
    esac
}

# Use throughout script
log_with_level INFO "Starting installation..."
log_with_level DEBUG "PLATFORM_ADDRESS=$PLATFORM_ADDRESS"
```

---

### 4. Version Checking
**Issue:** No version tracking or compatibility checking.

**Recommendation:**
```bash
check_script_version() {
    local version_file="$PROJECT_ROOT/.miniprem_version"
    local current_version="1.0.0"

    if [ -f "$version_file" ]; then
        local installed_version=$(cat "$version_file")
        if [ "$installed_version" != "$current_version" ]; then
            warning "Installed version ($installed_version) differs from script version ($current_version)"
            read -p "Do you want to upgrade? (y/N): " upgrade_choice
            if [[ "$upgrade_choice" =~ ^[Yy]$ ]]; then
                perform_upgrade "$installed_version" "$current_version"
            fi
        fi
    fi

    echo "$current_version" > "$version_file"
}
```

---

### 5. DRY Violations
**Issue:** Code duplication in multiple places (e.g., TTS provider configuration, docker compose selection).

**Recommendation:**
```bash
# Consolidate TTS configuration
configure_tts_provider() {
    local provider=$1

    case "$provider" in
        azure)
            local required_vars=("AZURE_REGION" "AZURE_SPEECH_KEY")
            ;;
        elevenlabs)
            local required_vars=("ELEVEN_LABS_API_KEY")
            ;;
        rime)
            local required_vars=("RIME_API_KEY")
            ;;
    esac

    for var in "${required_vars[@]}"; do
        prompt_and_validate_var "$var"
    done
}
```

---

### 6. Error Recovery
**Issue:** No way to resume installation after failure.

**Recommendation:**
```bash
# Save progress state
save_progress() {
    local step=$1
    echo "$step" > "$PROJECT_ROOT/.miniprem_install_progress"
}

# Check and resume
check_previous_installation() {
    local progress_file="$PROJECT_ROOT/.miniprem_install_progress"
    if [ -f "$progress_file" ]; then
        local last_step=$(cat "$progress_file")
        warning "Found incomplete installation (last step: $last_step)"
        read -p "Resume from last step? (Y/n): " resume
        if [[ ! "$resume" =~ ^[Nn]$ ]]; then
            return_to_step "$last_step"
        fi
    fi
}
```

---

### 7. Testing and Dry-Run Mode
**Issue:** No way to test the script without actually installing.

**Recommendation:**
```bash
# Add dry-run mode
DRY_RUN=${DRY_RUN:-false}

docker_exec() {
    if [ "$DRY_RUN" = "true" ]; then
        info "[DRY-RUN] Would execute: $@"
    else
        "$@"
    fi
}

# Use throughout script
docker_exec $DOCKER_CMD pull prom/prometheus:v2.45.0
docker_exec $DOCKER_COMPOSE_CMD up -d

# Run script with: DRY_RUN=true ./install_miniprem.sh
```

---

### 8. Configuration Validation
**Issue:** No validation of configuration values before proceeding.

**Recommendation:**
```bash
validate_configuration() {
    log_section "Validating Configuration"

    # Validate API key format
    if [ -n "$PLATFORM_KEY" ] && [ ${#PLATFORM_KEY} -lt 32 ]; then
        fatal "Platform API key appears too short. Expected at least 32 characters."
    fi

    # Validate tenant ID format
    if [ -n "$TENANT_ID" ] && [[ ! "$TENANT_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        warning "Tenant ID doesn't match UUID format. Proceeding anyway, but double-check."
    fi

    # Validate URLs
    if [ -n "$PLATFORM_ADDRESS" ] && [[ ! "$PLATFORM_ADDRESS" =~ ^wss?:// ]]; then
        fatal "Platform address must start with ws:// or wss://"
    fi

    success "$CHECKMARK Configuration validated"
}
```

---

### 9. Improved Progress Feedback
**Issue:** Long-running operations provide minimal feedback.

**Recommendation:**
```bash
# Add progress bars for long operations
show_progress() {
    local current=$1
    local total=$2
    local message=$3
    local percent=$((current * 100 / total))
    local filled=$((percent / 2))
    local empty=$((50 - filled))

    printf "\r%s [" "$message"
    printf "%${filled}s" | tr ' ' '='
    printf "%${empty}s" | tr ' ' ' '
    printf "] %d%%" "$percent"

    [ "$current" -eq "$total" ] && echo ""
}

# Use in loops
for i in $(seq 1 $max_attempts); do
    show_progress $i $max_attempts "Waiting for service"
    # ... check logic
done
```

---

### 10. Idempotency
**Issue:** Running script multiple times can cause issues.

**Recommendation:**
```bash
# Make operations idempotent
ensure_directory() {
    local dir=$1
    local mode=${2:-755}

    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        chmod "$mode" "$dir"
        info "Created directory: $dir"
    else
        info "Directory already exists: $dir"
    fi
}

# Use throughout
ensure_directory "$PROJECT_ROOT/docker/vllm_data" 755
ensure_directory "$PROJECT_ROOT/logs" 755
```

---

## Priority Action Items

1. **Immediate (Before Next Use):**
   - Fix command injection vulnerability (Critical Error #1)
   - Add error handling for file operations (Critical Error #2)
   - Fix insecure file permissions (Critical Error #3)

2. **Short Term (This Week):**
   - Implement cleanup handler (Critical Error #5)
   - Optimize duplicate installation check (Critical Error #4)
   - Add comprehensive port conflict detection (Warning #6)
   - Implement dry-run mode (Best Practice #7)

3. **Medium Term (This Month):**
   - Refactor main() function (Best Practice #2)
   - Implement error recovery (Best Practice #6)
   - Add configuration validation (Best Practice #8)
   - Improve logging (Best Practice #3)

4. **Long Term (Next Quarter):**
   - Full code refactoring for DRY violations (Best Practice #5)
   - Add comprehensive testing suite
   - Create automated CI/CD validation
   - Add version upgrade mechanism (Best Practice #4)

---

## Testing Recommendations

```bash
# Test the script with various scenarios:

# 1. Fresh installation
./install_miniprem.sh --platform-key="test" --tenant-id="test"

# 2. Dry-run mode
DRY_RUN=true ./install_miniprem.sh

# 3. Invalid inputs
./install_miniprem.sh --platform-key="" --tenant-id=""

# 4. Interrupted installation (kill mid-process)
./install_miniprem.sh &
kill -INT $!
./install_miniprem.sh  # Should resume or clean up

# 5. Multiple installations
./install_miniprem.sh  # First time
./install_miniprem.sh  # Second time - should detect duplicate
```

---

## Conclusion

The script is functional for its current use case but requires significant hardening before production deployment. The critical security issues (command injection, file permissions) should be addressed immediately, while the other improvements can be implemented incrementally based on priority.

**Estimated Effort:**
- Critical fixes: 4-8 hours
- Warning fixes: 8-16 hours
- Best practice improvements: 16-40 hours
- **Total: 28-64 hours of development time**

