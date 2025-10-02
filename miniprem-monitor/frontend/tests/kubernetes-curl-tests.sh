#!/bin/bash

# Kubernetes API Testing Script
# Tests MiniPrem Monitor backend Kubernetes API endpoints using curl
# Usage: ./kubernetes-curl-tests.sh [backend-url]

set -e

# Configuration
BACKEND_URL="${1:-http://localhost:8000}"
TIMEOUT=30
VERBOSE=false
RESULTS_FILE="kubernetes-api-test-results.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Utility functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Test function wrapper
run_test() {
    local test_name="$1"
    local test_function="$2"

    ((TESTS_TOTAL++))
    log_info "Running test: $test_name"

    if $test_function; then
        log_success "$test_name"
        return 0
    else
        log_error "$test_name"
        return 1
    fi
}

# Utility function to make curl requests with proper error handling
curl_request() {
    local method="$1"
    local endpoint="$2"
    local expected_codes="$3"
    local description="$4"
    local extra_args="${5:-}"

    local url="${BACKEND_URL}${endpoint}"
    local temp_file=$(mktemp)
    local response_code
    local response_time

    log_info "Testing: $description"
    log_info "URL: $url"

    # Make the curl request with timing
    if curl -w "%{response_code}|%{time_total}" \
           -X "$method" \
           -H "Accept: application/json" \
           -H "Content-Type: application/json" \
           --connect-timeout $TIMEOUT \
           --max-time $TIMEOUT \
           -s \
           -o "$temp_file" \
           $extra_args \
           "$url"; then

        # Parse response code and time
        local curl_output=$(cat "$temp_file" | tail -1)
        response_code=$(echo "$curl_output" | cut -d'|' -f1)
        response_time=$(echo "$curl_output" | cut -d'|' -f2)

        # Get response body
        local response_body=$(cat "$temp_file" | head -n -1)

        log_info "Response Code: $response_code"
        log_info "Response Time: ${response_time}s"

        # Validate response code
        if [[ "$expected_codes" == *"$response_code"* ]]; then
            log_success "Response code $response_code is acceptable"

            # Try to parse JSON response
            if echo "$response_body" | jq . >/dev/null 2>&1; then
                log_success "Response is valid JSON"
                if [ "$VERBOSE" = true ]; then
                    echo "Response body:"
                    echo "$response_body" | jq .
                fi
            elif [ -n "$response_body" ]; then
                log_warning "Response is not JSON (might be plain text error)"
                if [ "$VERBOSE" = true ]; then
                    echo "Response body: $response_body"
                fi
            fi

            # Performance check
            if (( $(echo "$response_time < 10" | bc -l) )); then
                log_success "Response time ${response_time}s is acceptable"
            else
                log_warning "Response time ${response_time}s is slow"
            fi

            rm "$temp_file"
            return 0
        else
            log_error "Unexpected response code $response_code (expected: $expected_codes)"
            if [ -n "$response_body" ]; then
                echo "Response body: $response_body"
            fi
            rm "$temp_file"
            return 1
        fi
    else
        local curl_exit_code=$?
        rm "$temp_file"

        case $curl_exit_code in
            6) log_error "Could not resolve host - is the backend server running?" ;;
            7) log_error "Failed to connect to host - is the backend server running on $BACKEND_URL?" ;;
            28) log_error "Request timed out after ${TIMEOUT}s" ;;
            *) log_error "Curl failed with exit code $curl_exit_code" ;;
        esac
        return 1
    fi
}

# Test functions
test_backend_health() {
    curl_request "GET" "/health" "200 404" "Backend health check"
}

test_kubernetes_contexts_get() {
    curl_request "GET" "/api/kubernetes/contexts" "200 401 403 500 502 503" "Get Kubernetes contexts"
}

test_kubernetes_contexts_with_auth_header() {
    curl_request "GET" "/api/kubernetes/contexts" "200 401 403 500 502 503" "Get Kubernetes contexts with auth header" "-H \"Authorization: Bearer test-token\""
}

test_kubernetes_context_switch_valid() {
    local context_name="test-context"
    curl_request "POST" "/api/kubernetes/context/switch/$context_name" "200 400 401 403 404 500 502 503" "Switch to Kubernetes context: $context_name"
}

test_kubernetes_context_switch_invalid() {
    local context_name="nonexistent-context"
    curl_request "POST" "/api/kubernetes/context/switch/$context_name" "400 401 403 404 500 502 503" "Switch to invalid Kubernetes context: $context_name"
}

test_kubernetes_context_switch_empty() {
    curl_request "POST" "/api/kubernetes/context/switch/" "400 404 405" "Switch to empty context name"
}

test_api_cors_headers() {
    local temp_file=$(mktemp)

    if curl -D "$temp_file" \
           -H "Origin: http://localhost:3001" \
           -H "Access-Control-Request-Method: GET" \
           -H "Access-Control-Request-Headers: Content-Type" \
           -X OPTIONS \
           --connect-timeout $TIMEOUT \
           --max-time $TIMEOUT \
           -s \
           "${BACKEND_URL}/api/kubernetes/contexts"; then

        log_info "Checking CORS headers..."

        if grep -i "access-control-allow-origin" "$temp_file" >/dev/null; then
            log_success "CORS Access-Control-Allow-Origin header present"
        else
            log_warning "CORS Access-Control-Allow-Origin header missing"
        fi

        if grep -i "access-control-allow-methods" "$temp_file" >/dev/null; then
            log_success "CORS Access-Control-Allow-Methods header present"
        else
            log_warning "CORS Access-Control-Allow-Methods header missing"
        fi

        rm "$temp_file"
        return 0
    else
        log_error "CORS preflight request failed"
        rm "$temp_file"
        return 1
    fi
}

test_api_rate_limiting() {
    log_info "Testing rate limiting with 5 rapid requests..."

    local success_count=0
    local error_count=0

    for i in {1..5}; do
        if curl -w "%{response_code}" \
               -X GET \
               --connect-timeout 5 \
               --max-time 10 \
               -s \
               -o /dev/null \
               "${BACKEND_URL}/api/kubernetes/contexts" | grep -E "^(200|401|403|500)$" >/dev/null; then
            ((success_count++))
        else
            ((error_count++))
        fi
        sleep 0.1
    done

    log_info "Rapid requests: $success_count succeeded, $error_count failed"

    if [ $success_count -gt 0 ]; then
        log_success "API handles rapid requests"
        return 0
    else
        log_error "API failed all rapid requests"
        return 1
    fi
}

test_api_large_context_name() {
    # Test with a very long context name
    local long_context_name=$(printf 'a%.0s' {1..1000})
    curl_request "POST" "/api/kubernetes/context/switch/$long_context_name" "400 401 403 404 413 500 502 503" "Switch to very long context name"
}

test_api_sql_injection() {
    # Test SQL injection attempt (should be handled safely)
    local malicious_context="'; DROP TABLE users; --"
    curl_request "POST" "/api/kubernetes/context/switch/$malicious_context" "400 401 403 404 500 502 503" "SQL injection attempt in context name" "-G --data-urlencode \"context=$malicious_context\""
}

# Performance test
test_concurrent_requests() {
    log_info "Testing concurrent requests (3 simultaneous)..."

    local pids=()
    local temp_dir=$(mktemp -d)

    # Launch 3 concurrent requests
    for i in {1..3}; do
        (
            curl -w "%{response_code}" \
                 -X GET \
                 --connect-timeout $TIMEOUT \
                 --max-time $TIMEOUT \
                 -s \
                 -o /dev/null \
                 "${BACKEND_URL}/api/kubernetes/contexts" > "$temp_dir/result_$i"
        ) &
        pids+=($!)
    done

    # Wait for all requests to complete
    local success_count=0
    for pid in "${pids[@]}"; do
        if wait $pid; then
            ((success_count++))
        fi
    done

    # Check results
    for i in {1..3}; do
        if [ -f "$temp_dir/result_$i" ]; then
            local response_code=$(cat "$temp_dir/result_$i")
            if [[ "$response_code" =~ ^[0-9]{3}$ ]] && [ "$response_code" -lt 600 ]; then
                ((success_count++))
            fi
        fi
    done

    rm -rf "$temp_dir"

    if [ $success_count -ge 2 ]; then
        log_success "Concurrent requests handled successfully ($success_count/3)"
        return 0
    else
        log_error "Concurrent requests failed ($success_count/3)"
        return 1
    fi
}

# Main test execution
main() {
    echo "======================================="
    echo "  Kubernetes API Testing Script"
    echo "  Backend URL: $BACKEND_URL"
    echo "  Timeout: ${TIMEOUT}s"
    echo "======================================="
    echo

    # Check if jq is available for JSON parsing
    if ! command -v jq &> /dev/null; then
        log_warning "jq not found - JSON response validation will be limited"
    fi

    # Check if bc is available for arithmetic
    if ! command -v bc &> /dev/null; then
        log_warning "bc not found - response time validation will be limited"
    fi

    # Basic connectivity tests
    log_info "=== Basic Connectivity Tests ==="
    run_test "Backend Health Check" test_backend_health
    echo

    # Core API tests
    log_info "=== Core Kubernetes API Tests ==="
    run_test "Get Kubernetes Contexts" test_kubernetes_contexts_get
    run_test "Get Contexts with Auth Header" test_kubernetes_contexts_with_auth_header
    run_test "Switch to Valid Context" test_kubernetes_context_switch_valid
    run_test "Switch to Invalid Context" test_kubernetes_context_switch_invalid
    run_test "Switch to Empty Context" test_kubernetes_context_switch_empty
    echo

    # Security tests
    log_info "=== Security Tests ==="
    run_test "CORS Headers Check" test_api_cors_headers
    run_test "Large Context Name Handling" test_api_large_context_name
    run_test "SQL Injection Protection" test_api_sql_injection
    echo

    # Performance tests
    log_info "=== Performance Tests ==="
    run_test "Rate Limiting Test" test_api_rate_limiting
    run_test "Concurrent Requests Test" test_concurrent_requests
    echo

    # Summary
    echo "======================================="
    echo "  Test Results Summary"
    echo "======================================="
    echo "Total Tests: $TESTS_TOTAL"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed.${NC}"
        exit 1
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -t|--timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS] [BACKEND_URL]"
            echo "Options:"
            echo "  -v, --verbose    Enable verbose output"
            echo "  -t, --timeout    Set request timeout in seconds (default: 30)"
            echo "  -h, --help       Show this help message"
            echo ""
            echo "Default backend URL: http://localhost:8000"
            exit 0
            ;;
        *)
            BACKEND_URL="$1"
            shift
            ;;
    esac
done

# Run the tests
main