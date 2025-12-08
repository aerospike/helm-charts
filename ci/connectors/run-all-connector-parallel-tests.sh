#!/bin/bash

# Parallel Integration Test Runner Script
# Runs integration tests for all connectors in parallel:
# Phase 1: Install Kind + Run Integration Test for all connectors in parallel
# Phase 2: Once all tests complete, Uninstall Kind for all connectors in parallel
# Continues regardless of pass/fail for each connector
# Prints summary metrics at the end
# Exits with success only if all connectors pass

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
        RED='\033[0;31m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    NC='\033[0m' # No Color
else
    # Disable colors - use empty strings
        GREEN=''
        RED=''
    BLUE=''
    CYAN=''
    NC=''
fi

# Connectors to test
CONNECTORS=(
#    "aerospike-esp-outbound"
 #   "aerospike-jms-inbound"
    "aerospike-jms-outbound"
    "aerospike-kafka-outbound"
 #   "aerospike-pulsar-outbound"
 #   "aerospike-xdr-proxy"
)

# Results tracking (using indexed arrays for bash 3.2 compatibility)
# Format: CONNECTOR_NAME:RESULT
TEST_RESULTS=()
TEST_ERRORS=()
TEST_DURATIONS=()
INSTALL_PIDS=()  # Track background process PIDs

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

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_failure() {
    echo -e "${RED}[FAILURE]${NC} $1"
}

# Function to detect connector status from log files
detect_connector_status() {
    local connector=$1
    local status="Starting..."
    
    # Check log files to determine current status
    if [ -f "/tmp/${connector}-test.log" ]; then
        # Test log exists - check if test passed
        if grep -q "^INTEGRATION_TEST_PASSED$" "/tmp/${connector}-test.log" 2>/dev/null; then
            status="Testing (passed)"
        elif grep -q "^INTEGRATION_TEST_FAILED$" "/tmp/${connector}-test.log" 2>/dev/null; then
            status="Testing (failed)"
        else
            status="Running tests..."
        fi
    elif [ -f "/tmp/${connector}-install.log" ]; then
        # Install log exists - check if install completed
        if grep -q "Kind cluster setup complete" "/tmp/${connector}-install.log" 2>/dev/null || \
           grep -q "Kind cluster installed successfully" "/tmp/${connector}-parallel.log" 2>/dev/null; then
            status="Installing (cluster ready)"
        else
            status="Installing Kind..."
        fi
    fi
    
    echo "$status"
}

# Function to show progress summary
show_progress() {
    local elapsed=$1
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "Progress Update (Elapsed: ${elapsed}s)"
    echo "════════════════════════════════════════════════════════════════"
    for connector in "${CONNECTORS[@]}"; do
        local result
        result=$(get_result "$connector")
        local duration
        duration=$(get_duration "$connector")
        
        if [ "$result" != "UNKNOWN" ]; then
            # Test completed
            if [ "$result" = "PASSED" ]; then
                printf "  %-30s ${GREEN}%-20s${NC} (${duration}s)\n" "$connector" "✓ COMPLETED"
            else
                printf "  %-30s ${RED}%-20s${NC} (${duration}s)\n" "$connector" "✗ FAILED"
            fi
        else
            # Test still running - detect status from logs
            local detected_status
            detected_status=$(detect_connector_status "$connector")
            printf "  %-30s ${CYAN}%-20s${NC}\n" "$connector" "$detected_status"
        fi
    done
    echo "════════════════════════════════════════════════════════════════"
    echo ""
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

print_header "Starting Parallel Integration Tests for All Connectors"
print_info "Total connectors to test: ${#CONNECTORS[@]}"
print_info "Mode: PARALLEL (install+test phase, then cleanup phase)"
echo ""

# Function to run install+test for a single connector (runs in background)
run_connector_install_and_test() {
    local connector=$1
    local start_time
	start_time=$(date +%s)
    local result="FAILED"
    local error_msg=""
    
    # Create a log file for this connector's output
    local connector_log="/tmp/${connector}-parallel.log"
    
    {
        echo "=========================================="
        echo "Testing Connector: ${connector}"
        echo "Started at: $(date)"
        echo "=========================================="
        echo ""
        
        # Paths (connectors are at repo root level)
        local connector_dir="${REPO_ROOT}/${connector}"
        local install_script="${connector_dir}/kind/install-kind.sh"
        local test_script="${connector_dir}/tests/integration-test/run-integration-test.sh"
        
        # Verify scripts exist
        if [ ! -f "$install_script" ]; then
            error_msg="install-kind.sh not found at ${install_script}"
            echo "[ERROR] $error_msg"
            set_result "$connector" "FAILED"
            set_error "$connector" "$error_msg"
            return 1
        fi
        
        if [ ! -f "$test_script" ]; then
            error_msg="run-integration-test.sh not found at ${test_script}"
            echo "[ERROR] $error_msg"
            set_result "$connector" "FAILED"
            set_error "$connector" "$error_msg"
            return 1
        fi
        
        # Track if install succeeded (needed for cleanup)
        local install_succeeded=false
        
        # Step 1: Install Kind cluster
        echo "[INFO] Step 1: Installing Kind cluster..."
        # Always write to file only during parallel execution to avoid interleaving
        bash "$install_script" > "/tmp/${connector}-install.log" 2>&1
        local install_exit_code=$?
        
        if [ "$install_exit_code" -eq 0 ]; then
            echo "[SUCCESS] Kind cluster installed successfully"
            install_succeeded=true
        else
            error_msg="Failed to install Kind cluster (exit code: $install_exit_code). Check /tmp/${connector}-install.log"
            echo "[ERROR] $error_msg"
            set_result "$connector" "FAILED"
            set_error "$connector" "$error_msg"
            install_succeeded=false
        fi
        
        # Step 2: Run integration test (only if install succeeded)
        if [ "$install_succeeded" = true ]; then
            echo "[INFO] Step 2: Running integration test..."
            local test_output="/tmp/${connector}-test.log"
            # Always write to file only during parallel execution to avoid interleaving
            bash "$test_script" > "$test_output" 2>&1
            local test_exit_code=$?
            
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
                    echo "[WARN] Exit code indicates pass, but INTEGRATION_TEST_FAILED marker found in log"
                    result="FAILED"
                    error_msg="Integration test failed (INTEGRATION_TEST_FAILED marker found). Check ${test_output}"
                elif [ "$has_pass_marker" = true ]; then
                    echo "[SUCCESS] Integration test passed (exit code: 0, INTEGRATION_TEST_PASSED marker found)"
                    result="PASSED"
                else
                    echo "[SUCCESS] Integration test passed (exit code: 0)"
                    result="PASSED"
                fi
            else
                if [ "$has_pass_marker" = true ] && [ "$has_fail_marker" = false ]; then
                    # Exit code says fail but marker says pass - trust the marker (may be cleanup error)
                    echo "[WARN] Exit code indicates failure, but INTEGRATION_TEST_PASSED marker found in log"
                    echo "[INFO] Treating as PASSED (failure may be from cleanup)"
                    result="PASSED"
                else
                    error_msg="Integration test failed (exit code: $test_exit_code). Check ${test_output}"
                    echo "[ERROR] $error_msg"
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
            echo "[WARN] Skipping integration test due to install failure"
            result="FAILED"
        fi
        
        # Record results
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))
        set_result "$connector" "$result"
        set_duration "$connector" "$duration"
        
        echo ""
        echo "=========================================="
        if [ "$result" = "PASSED" ]; then
            echo "[SUCCESS] ✅ ${connector} test completed successfully (Duration: ${duration}s)"
        else
            echo "[FAILURE] ❌ ${connector} test failed (Duration: ${duration}s)"
        fi
        echo "Completed at: $(date)"
        echo "=========================================="
        
    } > "$connector_log" 2>&1
    
    return 0
}

# Function to run uninstall for a single connector (runs in background)
run_connector_uninstall() {
    local connector=$1
    
    {
        echo "=========================================="
        echo "Uninstalling Connector: ${connector}"
        echo "Started at: $(date)"
        echo "=========================================="
        echo ""
        
        local connector_dir="${REPO_ROOT}/${connector}"
        local uninstall_script="${connector_dir}/kind/uninstall-kind.sh"
        
        if [ ! -f "$uninstall_script" ]; then
            echo "[WARN] uninstall-kind.sh not found at ${uninstall_script}"
            return 1
        fi
        
        echo "[INFO] Uninstalling Kind cluster..."
        # Always write to file only during parallel execution to avoid interleaving
        bash "$uninstall_script" > "/tmp/${connector}-uninstall.log" 2>&1
        local uninstall_exit_code=$?
        
        if [ "$uninstall_exit_code" -eq 0 ]; then
            echo "[SUCCESS] Kind cluster uninstalled successfully"
        else
            echo "[WARN] Failed to uninstall Kind cluster (exit code: $uninstall_exit_code). Check /tmp/${connector}-uninstall.log"
            echo "[WARN] You may need to manually clean up: kind delete cluster"
        fi
        
        echo ""
        echo "=========================================="
        echo "Uninstall completed at: $(date)"
        echo "=========================================="
        
    } > "/tmp/${connector}-uninstall-parallel.log" 2>&1
    
    # Don't print log here - will be printed sequentially if needed
    
    return 0
}

# Phase 1: Run install+test for all connectors in parallel
print_header "Phase 1: Installing Kind Clusters and Running Integration Tests (Parallel)"

declare TOTAL_START_TIME
TOTAL_START_TIME=$(date +%s)
PASSED_COUNT=0
FAILED_COUNT=0

# Start all connector tests in background
for connector in "${CONNECTORS[@]}"; do
    print_info "Starting parallel test for: ${connector}"
    run_connector_install_and_test "$connector" &
    INSTALL_PIDS+=("$!")
done

# Wait for all background processes to complete with progress updates
print_info "Running ${#CONNECTORS[@]} tests in parallel..."
print_info "Progress updates will be shown every 10 seconds..."
echo ""

# Progress monitoring loop
last_progress_time=$(date +%s)
WAITED_PIDS=()  # Track which PIDs we've already waited for

# Wait for processes and show progress
while [ ${#WAITED_PIDS[@]} -lt ${#CONNECTORS[@]} ]; do
    # Check for completed processes
    for pid in "${INSTALL_PIDS[@]}"; do
        # Check if we've already waited for this PID
        already_waited=false
        for waited_pid in "${WAITED_PIDS[@]}"; do
            if [ "$waited_pid" = "$pid" ]; then
                already_waited=true
                break
            fi
        done
        
        if [ "$already_waited" = false ] && ! kill -0 "$pid" 2>/dev/null; then
            # Process completed - wait for it and mark as waited
            wait "$pid" 2>/dev/null || true
            WAITED_PIDS+=("$pid")
        fi
    done
    
    # Show progress every 10 seconds
    current_time=$(date +%s)
    elapsed=$((current_time - TOTAL_START_TIME))
    time_since_last_progress=$((current_time - last_progress_time))
    
    if [ "$time_since_last_progress" -ge 10 ] && [ ${#WAITED_PIDS[@]} -lt ${#CONNECTORS[@]} ]; then
        show_progress "$elapsed"
        last_progress_time=$current_time
    fi
    
    # Small sleep to avoid busy waiting
    sleep 1
done

# Final wait to ensure all processes are done (safety check)
for pid in "${INSTALL_PIDS[@]}"; do
    wait "$pid" 2>/dev/null || true
done

# Count results
for connector in "${CONNECTORS[@]}"; do
    result=$(get_result "$connector")
    if [ "$result" = "PASSED" ]; then
        PASSED_COUNT=$((PASSED_COUNT + 1))
    elif [ "$result" = "FAILED" ]; then
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
done

print_info "Phase 1 complete: Passed: ${PASSED_COUNT}, Failed: ${FAILED_COUNT}"
echo ""

# Print all connector logs sequentially (clean, separated output)
if [ "${JENKINS_CONSOLE_OUTPUT:-false}" = "true" ]; then
    print_header "Phase 1: Detailed Logs (Sequential Output)"
    echo ""
    for connector in "${CONNECTORS[@]}"; do
        connector_log="/tmp/${connector}-parallel.log"
        if [ -f "$connector_log" ]; then
            echo "════════════════════════════════════════════════════════════════"
            echo "Connector: ${connector}"
            echo "════════════════════════════════════════════════════════════════"
            cat "$connector_log"
            echo ""
            echo ""
        fi
    done
fi

# Phase 2: Run uninstall for all connectors in parallel
print_header "Phase 2: Uninstalling Kind Clusters (Parallel)"

UNINSTALL_PIDS=()
for connector in "${CONNECTORS[@]}"; do
    print_info "Starting uninstall for: ${connector}"
    run_connector_uninstall "$connector" &
    UNINSTALL_PIDS+=("$!")
done

# Wait for all uninstall processes to complete
print_info "Waiting for all uninstalls to complete..."

for pid in "${UNINSTALL_PIDS[@]}"; do
    wait "$pid"
done

print_info "Phase 2 complete: All clusters uninstalled"
echo ""

# Print uninstall logs sequentially if console output is enabled
if [ "${JENKINS_CONSOLE_OUTPUT:-false}" = "true" ]; then
    print_header "Phase 2: Uninstall Logs (Sequential Output)"
    echo ""
    for connector in "${CONNECTORS[@]}"; do
        uninstall_log="/tmp/${connector}-uninstall-parallel.log"
        if [ -f "$uninstall_log" ]; then
            echo "════════════════════════════════════════════════════════════════"
            echo "Uninstall: ${connector}"
            echo "════════════════════════════════════════════════════════════════"
            cat "$uninstall_log"
            echo ""
            echo ""
        fi
    done
fi

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
    echo "  - ${connector}-parallel.log (parallel execution log)"
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

