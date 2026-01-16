#!/bin/bash
set -e

# Run all tests
# Usage: ./test/run_all.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Make scripts executable
chmod +x scripts/*
chmod +x test/*.sh

echo "========================================"
echo "RUNNING ALL TESTS"
echo "========================================"

FAILED_TESTS=()

run_test() {
    local test_script=$1
    echo ""
    echo "----------------------------------------"
    echo "Running: $test_script"
    echo "----------------------------------------"
    
    if "$test_script"; then
        echo "✅ PASS: $test_script"
    else
        echo "❌ FAIL: $test_script"
        FAILED_TESTS+=("$test_script")
    fi
}

# 1. Validation Logic Tests (No AWS required)
run_test "$SCRIPT_DIR/test_strict_usage.sh"
run_test "$SCRIPT_DIR/test_wheel_validation.sh"

# 2. Functional/Integration Tests (AWS required for full coverage, but graceful skip implemented)
run_test "$SCRIPT_DIR/test_nodejs.sh"
# run_test "$SCRIPT_DIR/test_cli_integration.sh" 
# run_test "$SCRIPT_DIR/test_python_arch.sh"
# run_test "$SCRIPT_DIR/test_python_versions.sh"

# Note: Some tests like test_cli_integration.sh might overlap.
# Let's run the main ones.
run_test "$SCRIPT_DIR/test_cli_integration.sh"

if [ ${#FAILED_TESTS[@]} -eq 0 ]; then
    echo ""
    echo "========================================"
    echo "✅ ALL TESTS PASSED"
    echo "========================================"
    exit 0
else
    echo ""
    echo "========================================"
    echo "❌ SOME TESTS FAILED"
    echo "========================================"
    for t in "${FAILED_TESTS[@]}"; do
        echo "  - $t"
    done
    exit 1
fi
