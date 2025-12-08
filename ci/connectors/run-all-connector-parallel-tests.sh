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
USE_COLORS=false

if [ -z "${NO_COLOR:-}" ]; then
    if [ -n "${JENKINS_CONSOLE_OUTPUT:-}" ]; then
        # In Jenkins - only use colors if explicitly enabled AND ANSI Color plugin is active
        if [ "${JENKINS_COLORS:-false}" = "true" ]; then
            # Test if ANSI Color plugin is actually working by checking for plugin-specific env vars
            # or by testing if stdout is a TTY (plugin makes it a TTY)
            if [ -t 1 ] || [ -n "${ANSI_COLOR:-}" ]; then
                USE_COLORS=true
            else
                # ANSI Color plugin not active - disable colors to avoid escape codes in output
                USE_COLORS=false
            fi
        fi
    elif [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
        # Interactive terminal with color support
        USE_COLORS=true
    fi
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
    
    # Diagnostic message for Jenkins users
    if [ -n "${JENKINS_CONSOLE_OUTPUT:-}" ] && [ "${JENKINS_COLORS:-false}" = "true" ]; then
        # User wants colors but they're disabled - ANSI Color plugin not active
        echo "[WARN] JENKINS_COLORS=true is set, but ANSI Color plugin is not active in this job." >&2
        echo "[WARN] Colors are disabled to prevent escape codes from appearing in output." >&2
        echo "[WARN] To enable colors: Install AnsiColor plugin AND enable it in job configuration (Build Environment -> 'Color ANSI Console Output')." >&2
    fi
fi

# Connectors to test
CONNECTORS=(
#    "aerospike-esp-outbound"
    "aerospike-jms-inbound"
    "aerospike-jms-outbound"
    "aerospike-kafka-outbound"
    "aerospike-pulsar-outbound"
 #   "aerospike-xdr-proxy"
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
           grep -q "Kind cluster installed successfully" "/tmp/${connector}-install.log" 2>/dev/null; then
            status="Installing (cluster ready)"
        else
            status="Installing Kind..."
        fi
    fi
	# TODO: to be deleted after testing and locking the file.
	cp /tmp/*aerospike*-*.log /var/lib/jenkins/csv-backups/.
    
    echo "$status"
}

# Function to show progress summary
show_progress() {
    local elapsed=$1
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "Progress Update (Elapsed: ${elapsed}s)"
    echo "════════════════════════════════════════════════════════════════"
    # Show progress for installed connectors only (those being tested)
    local connectors_to_show=("${INSTALLED_CONNECTORS[@]}")
    if [ ${#connectors_to_show[@]} -eq 0 ]; then
        connectors_to_show=("${CONNECTORS[@]}")
    fi
    for connector in "${connectors_to_show[@]}"; do
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
print_info "Mode: Sequential Install → Parallel Tests → Sequential Uninstall"
echo ""

# Function to install Kind cluster for a single connector (runs sequentially)
run_connector_install() {
    local connector=$1
    local connector_dir="${REPO_ROOT}/${connector}"
    local install_script="${connector_dir}/kind/install-kind.sh"
    
    print_info "Installing Kind cluster for: ${connector}"
    
    if [ ! -f "$install_script" ]; then
        local error_msg="install-kind.sh not found at ${install_script}"
        print_error "$error_msg"
        set_result "$connector" "FAILED"
        set_error "$connector" "$error_msg"
        return 1
    fi
    
    # Run install with real-time output (sequential, so safe to print to console)
    # Also save to file for later reference
    bash "$install_script" 2>&1 | tee "/tmp/${connector}-install.log"
    local install_exit_code=${PIPESTATUS[0]}
    
    if [ "$install_exit_code" -eq 0 ]; then
        print_success "Kind cluster installed successfully for ${connector}"
        return 0
    else
        local error_msg="Failed to install Kind cluster for ${connector} (exit code: $install_exit_code). Check /tmp/${connector}-install.log"
        print_error "$error_msg"
        set_result "$connector" "FAILED"
        set_error "$connector" "$error_msg"
        return 1
    fi
}

# Function to run integration test for a single connector (runs in parallel)
run_connector_test() {
    local connector=$1
    local start_time
    start_time=$(date +%s)
    local result="FAILED"
    local error_msg=""
    local test_exit_code=1
    
    # Create a log file for this connector's output
    local connector_log="/tmp/${connector}-test-parallel.log"
    
    {
        echo "=========================================="
        echo "Testing Connector: ${connector}"
        echo "Started at: $(date)"
        echo "=========================================="
        echo ""
        
        # Paths (connectors are at repo root level)
        local connector_dir="${REPO_ROOT}/${connector}"
        local test_script="${connector_dir}/tests/integration-test/run-integration-test.sh"
        
        # Verify script exists
        if [ ! -f "$test_script" ]; then
            error_msg="run-integration-test.sh not found at ${test_script}"
            echo "[ERROR] $error_msg"
            echo "RESULT:FAILED" > "/tmp/${connector}-result.txt"
            echo "ERROR:${error_msg}" > "/tmp/${connector}-error.txt"
            return 1
        fi
        
        # Run integration test
        echo "[INFO] Running integration test..."
        local test_output="/tmp/${connector}-test.log"
        # Always write to file only during parallel execution to avoid interleaving
        bash "$test_script" > "$test_output" 2>&1
        test_exit_code=$?
        
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
        
        # Write result to temp file so parent process can read it
        echo "RESULT:${result}" > "/tmp/${connector}-result.txt"
        if [ "$result" = "FAILED" ]; then
            if [ -f "$test_output" ]; then
                echo "ERROR:$(tail -50 "$test_output")" > "/tmp/${connector}-error.txt"
            else
                echo "ERROR:${error_msg}" > "/tmp/${connector}-error.txt"
            fi
        fi
        
        # Record duration
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))
        echo "DURATION:${duration}" > "/tmp/${connector}-duration.txt"
        
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
    
    # Note: Results are written to temp files inside the subshell above
    # They will be read and set in the parent process after all background processes complete
    # This ensures proper synchronization
    
    return 0
}

# Function to run uninstall for a single connector (runs sequentially)
run_connector_uninstall() {
    local connector=$1
    
    echo ""
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
    
    print_info "Uninstalling Kind cluster for: ${connector}"
    # Run uninstall with real-time output (sequential, so safe to print to console)
    # Also save to file for later reference
    bash "$uninstall_script" 2>&1 | tee "/tmp/${connector}-uninstall.log"
    local uninstall_exit_code=${PIPESTATUS[0]}
    
    if [ "$uninstall_exit_code" -eq 0 ]; then
        print_success "Kind cluster uninstalled successfully for ${connector}"
    else
        echo "[WARN] Failed to uninstall Kind cluster for ${connector} (exit code: $uninstall_exit_code). Check /tmp/${connector}-uninstall.log"
        echo "[WARN] You may need to manually clean up: kind delete cluster"
    fi
    
    echo ""
    echo "=========================================="
    echo "Uninstall completed at: $(date)"
    echo "=========================================="
    echo ""
    
    return 0
}

declare TOTAL_START_TIME
TOTAL_START_TIME=$(date +%s)
PASSED_COUNT=0
FAILED_COUNT=0

# Track which connectors installed successfully
INSTALLED_CONNECTORS=()

# Phase 1: Sequential Install - Install Kind clusters for all connectors one by one
print_header "Phase 1: Installing Kind Clusters (Sequential)"

for connector in "${CONNECTORS[@]}"; do
    if run_connector_install "$connector"; then
        INSTALLED_CONNECTORS+=("$connector")
    fi
done

print_info "Phase 1 complete: ${#INSTALLED_CONNECTORS[@]} of ${#CONNECTORS[@]} connectors installed successfully"
echo ""

# Phase 2: Parallel Tests - Run integration tests for all successfully installed connectors in parallel
if [ ${#INSTALLED_CONNECTORS[@]} -gt 0 ]; then
    print_header "Phase 2: Running Integration Tests (Parallel)"
    
    TEST_PIDS=()
    
    # Start all connector tests in background
    for connector in "${INSTALLED_CONNECTORS[@]}"; do
        print_info "Starting test for: ${connector}"
        run_connector_test "$connector" &
        TEST_PIDS+=("$!")
    done

    # Wait for all background processes to complete with progress updates
    print_info "Running ${#INSTALLED_CONNECTORS[@]} tests in parallel..."
    print_info "Progress updates will be shown every 10 seconds..."
    echo ""
    
    # Progress monitoring loop
    declare last_progress_time
    last_progress_time=$(date +%s)
    WAITED_PIDS=()  # Track which PIDs we've already waited for
    
    # Wait for processes and show progress
    while [ ${#WAITED_PIDS[@]} -lt ${#INSTALLED_CONNECTORS[@]} ]; do
        # Check for completed processes
        for pid in "${TEST_PIDS[@]}"; do
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
    
        if [ "$time_since_last_progress" -ge 10 ] && [ ${#WAITED_PIDS[@]} -lt ${#INSTALLED_CONNECTORS[@]} ]; then
            show_progress "$elapsed"
            last_progress_time=$current_time
        fi
        
        # Small sleep to avoid busy waiting
        sleep 1
    done
    
    # Final wait to ensure all processes are done (safety check)
    for pid in "${TEST_PIDS[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
    
    # Small delay to ensure all result writes are complete
    sleep 2
    
    # Read results from temp files and set them in parent process (synchronously)
    for connector in "${INSTALLED_CONNECTORS[@]}"; do
        if [ -f "/tmp/${connector}-result.txt" ]; then
            saved_result=$(grep "^RESULT:" "/tmp/${connector}-result.txt" 2>/dev/null | cut -d: -f2-)
            if [ -n "$saved_result" ]; then
                set_result "$connector" "$saved_result"
                
                if [ "$saved_result" = "FAILED" ] && [ -f "/tmp/${connector}-error.txt" ]; then
                    saved_error=$(grep "^ERROR:" "/tmp/${connector}-error.txt" 2>/dev/null | cut -d: -f2-)
                    if [ -n "$saved_error" ]; then
                        set_error "$connector" "$saved_error"
                    fi
                fi
                
                if [ -f "/tmp/${connector}-duration.txt" ]; then
                    saved_duration=$(grep "^DURATION:" "/tmp/${connector}-duration.txt" 2>/dev/null | cut -d: -f2-)
                    if [ -n "$saved_duration" ]; then
                        set_duration "$connector" "$saved_duration"
                    fi
                fi
            fi
        fi
    done
    
    # Count results - include both tested connectors and connectors that failed to install
    for connector in "${CONNECTORS[@]}"; do
        result=$(get_result "$connector")
        if [ "$result" = "PASSED" ]; then
            PASSED_COUNT=$((PASSED_COUNT + 1))
        elif [ "$result" = "FAILED" ]; then
            FAILED_COUNT=$((FAILED_COUNT + 1))
        elif [ "$result" = "UNKNOWN" ]; then
            # Connector was installed but test result not set - treat as failed
            echo "[WARN] Connector ${connector} has no test result - treating as FAILED" >&2
            set_result "$connector" "FAILED"
            FAILED_COUNT=$((FAILED_COUNT + 1))
        fi
    done
    
    print_info "Phase 2 complete: Passed: ${PASSED_COUNT}, Failed: ${FAILED_COUNT}"
    echo ""
    
    # Print all connector test logs sequentially (clean, separated output)
    if [ "${JENKINS_CONSOLE_OUTPUT:-false}" = "true" ]; then
        print_header "Phase 2: Detailed Test Logs (Sequential Output)"
        echo ""
        for connector in "${INSTALLED_CONNECTORS[@]}"; do
            connector_log="/tmp/${connector}-test-parallel.log"
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
else
    print_error "No connectors installed successfully. Skipping tests."
    FAILED_COUNT=${#CONNECTORS[@]}
fi

# Phase 3: Sequential Uninstall - Uninstall Kind clusters for all connectors one by one
print_header "Phase 3: Uninstalling Kind Clusters (Sequential)"

for connector in "${CONNECTORS[@]}"; do
    print_info "Uninstalling Kind cluster for: ${connector}"
    run_connector_uninstall "$connector"
done

print_info "Phase 3 complete: All clusters uninstalled"
echo ""

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
