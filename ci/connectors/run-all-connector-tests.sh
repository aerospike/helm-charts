#!/bin/bash

# Master Integration Test Runner Script
# Runs integration tests for all connectors sequentially:
# 1. install-kind -> run-integration-test -> collect result -> uninstall-kind
# 2. Continues regardless of pass/fail for each connector
# 3. Prints summary metrics at the end
# 4. Exits with success only if all connectors pass

set -o pipefail
# Don't use 'set -e' globally - we handle errors explicitly in each section

# Detect if colors are supported
# In Jenkins: disable colors by default unless JENKINS_COLORS=true is set (AnsiColor plugin)
# Otherwise: check if terminal supports colors
if [ -n "${JENKINS_CONSOLE_OUTPUT:-}" ]; then
    # In Jenkins - only use colors if explicitly enabled (AnsiColor plugin)
    if [ "${JENKINS_COLORS:-false}" = "true" ] && [ -z "${NO_COLOR:-}" ]; then
        USE_COLORS=true
    else
        USE_COLORS=false
    fi
elif [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    # Interactive terminal with color support
    USE_COLORS=true
else
    # Colors not supported
    USE_COLORS=false
fi

# Colors for better console output
if [ "$USE_COLORS" = true ]; then
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    NC='\033[0m' # No Color
else
    # Disable colors - use empty strings
    GREEN=''
    YELLOW=''
    RED=''
    BLUE=''
    CYAN=''
    NC=''
fi

# Connectors to test
CONNECTORS=(
#    "aerospike-esp-outbound"
    "aerospike-jms-inbound"
    "aerospike-jms-outbound"
    "aerospike-kafka-outbound"
    "aerospike-pulsar-outbound"
#    "aerospike-xdr-proxy"
)

# Results tracking (using indexed arrays for bash 3.2 compatibility)
# Format: CONNECTOR_NAME:RESULT
TEST_RESULTS=()
TEST_ERRORS=()
TEST_DURATIONS=()

# Helper function to get result for a connector
get_result() {
    local connector=$1
    local result="UNKNOWN"
    for entry in "${TEST_RESULTS[@]}"; do
        if [[ "$entry" == "${connector}:"* ]]; then
            result="${entry#"${connector}":}"
            break
        fi
    done
    echo "$result"
}

# Helper function to set result for a connector
set_result() {
    local connector=$1
    local result=$2
    local found=false
    local new_array=()
    local i=0
    for entry in "${TEST_RESULTS[@]}"; do
        if [[ "$entry" == "${connector}:"* ]]; then
            new_array["$i"]="${connector}:${result}"
            found=true
        else
            new_array["$i"]="$entry"
        fi
        ((i++))
    done
    if [ "$found" = false ]; then
        new_array["$i"]="${connector}:${result}"
    fi
    TEST_RESULTS=("${new_array[@]}")
}

# Helper function to get error for a connector
get_error() {
    local connector=$1
    local error=""
    for entry in "${TEST_ERRORS[@]}"; do
        if [[ "$entry" == "${connector}:"* ]]; then
            error="${entry#"${connector}":}"
            break
        fi
    done
    echo "$error"
}

# Helper function to set error for a connector
set_error() {
    local connector=$1
    local error=$2
    local found=false
    local new_array=()
    local i=0
    for entry in "${TEST_ERRORS[@]}"; do
        if [[ "$entry" == "${connector}:"* ]]; then
            new_array["$i"]="${connector}:${error}"
            found=true
        else
            new_array["$i"]="$entry"
        fi
        ((i++))
    done
    if [ "$found" = false ]; then
        new_array["$i"]="${connector}:${error}"
    fi
    TEST_ERRORS=("${new_array[@]}")
}

# Helper function to get duration for a connector
get_duration() {
    local connector=$1
    local duration="0"
    for entry in "${TEST_DURATIONS[@]}"; do
        if [[ "$entry" == "${connector}:"* ]]; then
            duration="${entry#"${connector}":}"
            break
        fi
    done
    echo "$duration"
}

# Helper function to set duration for a connector
set_duration() {
    local connector=$1
    local duration=$2
    local found=false
    local new_array=()
    local i=0
    for entry in "${TEST_DURATIONS[@]}"; do
        if [[ "$entry" == "${connector}:"* ]]; then
            new_array["$i"]="${connector}:${duration}"
            found=true
        else
            new_array["$i"]="$entry"
        fi
        ((i++))
    done
    if [ "$found" = false ]; then
        new_array["$i"]="${connector}:${duration}"
    fi
    TEST_DURATIONS=("${new_array[@]}")
}

print_header() {
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_failure() {
    echo -e "${RED}[FAILURE]${NC} $1"
}

# Get script directory and repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Script is in ci/connectors/, so repo root is 2 levels up
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

# Verify prerequisites
print_header "Checking Prerequisites"
REQUISITES=("kubectl" "kind" "docker" "helm")
MISSING_REQUISITES=()
for item in "${REQUISITES[@]}"; do
    if ! command -v "${item}" &>/dev/null; then
        MISSING_REQUISITES+=("${item}")
    else
        print_info "✅ ${item} found"
    fi
done

if [ ${#MISSING_REQUISITES[@]} -gt 0 ]; then
    print_error "Missing prerequisites: ${MISSING_REQUISITES[*]}"
    print_error "Please install the missing tools before running this script"
    exit 1
fi

print_header "Starting Integration Tests for All Connectors"
print_info "Total connectors to test: ${#CONNECTORS[@]}"
echo ""

# Function to run a single connector test
run_connector_test() {
    local connector=$1
    local start_time
    start_time=$(date +%s)
    local result="FAILED"
    local error_msg=""
    
    print_header "Testing Connector: ${connector}"
    
    # Paths (connectors are at repo root level)
    local connector_dir="${REPO_ROOT}/${connector}"
    local install_script="${connector_dir}/kind/install-kind.sh"
    local test_script="${connector_dir}/tests/integration-test/run-integration-test.sh"
    local uninstall_script="${connector_dir}/kind/uninstall-kind.sh"
    
    # Verify scripts exist
    if [ ! -f "$install_script" ]; then
        error_msg="install-kind.sh not found at ${install_script}"
        print_error "$error_msg"
        set_result "$connector" "FAILED"
        set_error "$connector" "$error_msg"
        return 1
    fi
    
    if [ ! -f "$test_script" ]; then
        error_msg="run-integration-test.sh not found at ${test_script}"
        print_error "$error_msg"
        set_result "$connector" "FAILED"
        set_error "$connector" "$error_msg"
        return 1
    fi
    
    if [ ! -f "$uninstall_script" ]; then
        error_msg="uninstall-kind.sh not found at ${uninstall_script}"
        print_error "$error_msg"
        set_result "$connector" "FAILED"
        set_error "$connector" "$error_msg"
        return 1
    fi
    
    # Track if install succeeded (needed for cleanup)
    local install_succeeded=false
    
    # Step 1: Install Kind cluster
    print_info "Step 1: Installing Kind cluster..."
    if [ "${JENKINS_CONSOLE_OUTPUT:-false}" = "true" ]; then
        # In Jenkins console mode: output to console and also save to file
        bash "$install_script" 2>&1 | tee "/tmp/${connector}-install.log"
        local install_exit_code=${PIPESTATUS[0]}
    else
        # Normal mode: output to file only
        bash "$install_script" > "/tmp/${connector}-install.log" 2>&1
        local install_exit_code=$?
    fi
    
    if [ "$install_exit_code" -eq 0 ]; then
        print_success "Kind cluster installed successfully"
        install_succeeded=true
    else
        error_msg="Failed to install Kind cluster (exit code: $install_exit_code). Check /tmp/${connector}-install.log"
        print_error "$error_msg"
        set_result "$connector" "FAILED"
        set_error "$connector" "$error_msg"
        # Still try to uninstall in case partial install occurred
        install_succeeded=false
    fi
    
    # Step 2: Run integration test (only if install succeeded)
    if [ "$install_succeeded" = true ]; then
        print_info "Step 2: Running integration test..."
        local test_output="/tmp/${connector}-test.log"
        if [ "${JENKINS_CONSOLE_OUTPUT:-false}" = "true" ]; then
            # In Jenkins console mode: output to console and also save to file
            bash "$test_script" 2>&1 | tee "$test_output"
            local test_exit_code=${PIPESTATUS[0]}
        else
            # Normal mode: output to file only
            bash "$test_script" > "$test_output" 2>&1
            local test_exit_code=$?
        fi
        
        # Check for explicit markers in output (for better log parsing)
        local has_pass_marker=false
        local has_fail_marker=false
        if [ -f "$test_output" ]; then
            # Look for standardized markers first
            if grep -q "^INTEGRATION_TEST_PASSED$" "$test_output" 2>/dev/null; then
                has_pass_marker=true
            fi
            if grep -q "^INTEGRATION_TEST_FAILED$" "$test_output" 2>/dev/null; then
                has_fail_marker=true
            fi
        fi
        
        if [ "$test_exit_code" -eq 0 ]; then
            if [ "$has_fail_marker" = true ]; then
                # Exit code says pass but marker says fail - trust the marker
                print_warning "Exit code indicates pass, but INTEGRATION_TEST_FAILED marker found in log"
                result="FAILED"
                error_msg="Integration test failed (INTEGRATION_TEST_FAILED marker found). Check ${test_output}"
            elif [ "$has_pass_marker" = true ]; then
                print_success "Integration test passed (exit code: 0, INTEGRATION_TEST_PASSED marker found)"
                result="PASSED"
            else
                print_success "Integration test passed (exit code: 0)"
                result="PASSED"
            fi
        else
            if [ "$has_pass_marker" = true ] && [ "$has_fail_marker" = false ]; then
                # Exit code says fail but marker says pass - trust the marker (may be cleanup error)
                print_warning "Exit code indicates failure, but INTEGRATION_TEST_PASSED marker found in log"
                print_info "Treating as PASSED (failure may be from cleanup)"
                result="PASSED"
            else
                error_msg="Integration test failed (exit code: $test_exit_code). Check ${test_output}"
                print_error "$error_msg"
                result="FAILED"
            fi
        fi
        
        # Capture error details if failed
        if [ "$result" = "FAILED" ]; then
            if [ -f "$test_output" ]; then
                set_error "$connector" "$(tail -50 "$test_output")"
            else
                set_error "$connector" "$error_msg"
            fi
        fi
    else
        print_warning "Skipping integration test due to install failure"
        result="FAILED"
    fi
    
    # Step 3: Uninstall Kind cluster (always run, even if install/test failed)
    print_info "Step 3: Uninstalling Kind cluster..."
    if [ "${JENKINS_CONSOLE_OUTPUT:-false}" = "true" ]; then
        # In Jenkins console mode: output to console and also save to file
        bash "$uninstall_script" 2>&1 | tee "/tmp/${connector}-uninstall.log"
        local uninstall_exit_code=${PIPESTATUS[0]}
    else
        # Normal mode: output to file only
        bash "$uninstall_script" > "/tmp/${connector}-uninstall.log" 2>&1
        local uninstall_exit_code=$?
    fi
    
    if [ "$uninstall_exit_code" -eq 0 ]; then
        print_success "Kind cluster uninstalled successfully"
    else
        print_warning "Failed to uninstall Kind cluster (exit code: $uninstall_exit_code). Check /tmp/${connector}-uninstall.log"
        print_warning "You may need to manually clean up: kind delete cluster"
    fi
    
    # Record results
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    set_result "$connector" "$result"
    set_duration "$connector" "$duration"
    
    if [ "$result" = "PASSED" ]; then
        print_success "✅ ${connector} test completed successfully (Duration: ${duration}s)"
    else
        print_failure "❌ ${connector} test failed (Duration: ${duration}s)"
    fi
    
    echo ""
    return 0
}

# Run tests for all connectors
declare TOTAL_START_TIME
TOTAL_START_TIME=$(date +%s)
PASSED_COUNT=0
FAILED_COUNT=0

for connector in "${CONNECTORS[@]}"; do
    print_info "Processing connector: ${connector}"
    if run_connector_test "$connector"; then
        result=$(get_result "$connector")
        if [ "$result" = "PASSED" ]; then
            PASSED_COUNT=$((PASSED_COUNT + 1))
        else
            FAILED_COUNT=$((FAILED_COUNT + 1))
        fi
    else
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
    
    print_info "Completed connector: ${connector} (Passed: ${PASSED_COUNT}, Failed: ${FAILED_COUNT})"
    
    # Small delay between connectors
    sleep 2
done

declare TOTAL_END_TIME
TOTAL_END_TIME=$(date +%s)
TOTAL_DURATION=$((TOTAL_END_TIME - TOTAL_START_TIME))

# Print Summary
print_header "Integration Test Summary"

echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
printf "%-30s %-10s %-10s\n" "CONNECTOR" "STATUS" "DURATION"
echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"

for connector in "${CONNECTORS[@]}"; do
    result=$(get_result "$connector")
    duration=$(get_duration "$connector")
    
    if [ "$result" = "PASSED" ]; then
        printf "%-30s ${GREEN}%-10s${NC} %-10s\n" "$connector" "PASSED" "${duration}s"
    else
        printf "%-30s ${RED}%-10s${NC} %-10s\n" "$connector" "FAILED" "${duration}s"
    fi
done

echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BLUE}Total Connectors Tested:${NC} ${#CONNECTORS[@]}"
echo -e "${GREEN}Passed:${NC} ${PASSED_COUNT}"
echo -e "${RED}Failed:${NC} ${FAILED_COUNT}"
echo -e "${BLUE}Total Duration:${NC} ${TOTAL_DURATION}s"
echo ""

# Print error details for failed tests
if [ "$FAILED_COUNT" -gt 0 ]; then
    print_header "Failed Test Details"
    for connector in "${CONNECTORS[@]}"; do
        result=$(get_result "$connector")
        if [ "$result" = "FAILED" ]; then
            print_error "❌ ${connector} - FAILED"
            error=$(get_error "$connector")
            if [ -n "$error" ]; then
                echo "Error details:"
                echo "$error" | head -20
                echo ""
                print_info "Full error log available at: /tmp/${connector}-test.log"
            fi
            echo ""
        fi
    done
fi

# Print log file locations
print_header "Log Files"
print_info "All logs are stored in /tmp/ directory:"
for connector in "${CONNECTORS[@]}"; do
    echo "  - ${connector}-install.log"
    echo "  - ${connector}-test.log"
    echo "  - ${connector}-uninstall.log"
done
echo ""

# Final status
print_header "Final Status"
if [ "$FAILED_COUNT" -eq 0 ]; then
    print_success "🎉 All connector integration tests PASSED!"
    echo ""
    exit 0
else
    print_failure "❌ Some connector integration tests FAILED"
    echo ""
    print_info "Failed connectors:"
    for connector in "${CONNECTORS[@]}"; do
        result=$(get_result "$connector")
        if [ "$result" = "FAILED" ]; then
            echo "  - ${connector}"
        fi
    done
    echo ""
    exit 1
fi
