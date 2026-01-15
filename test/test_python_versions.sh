#!/bin/bash

# Test: Python Versions (AL2 vs AL2023)
# Covers:
# - Python 3.10 (AL2)
# - Python 3.12 (AL2023)
# - Verifies platform string generation implicitly by function success

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

setup_common

echo -e "\n${BLUE}=== Test: Python Versions ===${NC}"

test_python_al2() {
    # Python 3.10 uses glibc 2.26 (AL2), matches manylinux2014
    echo -e "\n${BLUE}[Test]${NC} Python 3.10 (Amazon Linux 2)..."
    
    if ! ensure_test_role; then
         echo -e "${YELLOW}Skipping test (Role issue)${NC}"
         return 0
    fi
    local role_arn="$TEST_ROLE_ARN"

    local layer_name="test-py310-$RUN_ID"
    local func_name="test-py310-$RUN_ID"
    
    cd "$TEST_DIR"
    # requests is pure python but valid verification
    echo "Publishing layer (Requests on 3.10)..."
    output=$(yes | "$CLI_TOOL" publish --python "requests" --name "$layer_name" --python-version 3.10 | strip_ansi)
    
    layer_arn=$(echo "$output" | grep "Layer ARN:" | awk '{print $3}' | tr -d '\r')
    if [ -z "$layer_arn" ]; then exit 1; fi
    local layer_ver=$(echo "$layer_arn" | awk -F: '{print $NF}')
    add_cleanup "aws lambda delete-layer-version --layer-name $layer_name --version-number $layer_ver"
    
    # Check if CLI chose Python 3.10 compatible runtime
    if echo "$output" | grep -q "Compatible runtimes:.*python3.10"; then
        echo -e "${GREEN}PASS:${NC} Compatible runtime correct (3.10)."
    else
        echo -e "${RED}FAIL:${NC} Compatible runtime incorrect."
        exit 1
    fi

    echo "Creating Lambda (Python 3.10)..."
    cat > lambda_function.py <<EOF
import requests
def lambda_handler(event, context): return requests.__version__
EOF
    zip function.zip lambda_function.py > /dev/null
    
    aws lambda create-function --function-name "$func_name" \
        --runtime "python3.10" --role "$role_arn" --handler "lambda_function.lambda_handler" \
        --zip-file "fileb://function.zip" --layers "$layer_arn" > /dev/null
    add_cleanup "aws lambda delete-function --function-name $func_name"

    sleep 5
    aws lambda invoke --function-name "$func_name" response.json > /dev/null
    if grep -q "2." response.json; then
        echo -e "${GREEN}PASS:${NC} Python 3.10 Invocation success."
    else
        echo -e "${RED}FAIL:${NC} Python 3.10 Invocation failed."
        cat response.json
        exit 1
    fi
}

test_python_al2023() {
    # Python 3.12 uses glibc 2.34 (AL2023), matches manylinux_2_28
    echo -e "\n${BLUE}[Test]${NC} Python 3.12 (Amazon Linux 2023)..."
    
    if ! ensure_test_role; then
         echo -e "${YELLOW}Skipping test (Role issue)${NC}"
         return 0
    fi
    local role_arn="$TEST_ROLE_ARN"

    local layer_name="test-py312-$RUN_ID"
    local func_name="test-py312-$RUN_ID"
    
    cd "$TEST_DIR"
    echo "Publishing layer (Requests on 3.12)..."
    output=$(yes | "$CLI_TOOL" publish --python "requests" --name "$layer_name" --python-version 3.12 | strip_ansi)
    
    layer_arn=$(echo "$output" | grep "Layer ARN:" | awk '{print $3}' | tr -d '\r')
    if [ -z "$layer_arn" ]; then exit 1; fi
    local layer_ver=$(echo "$layer_arn" | awk -F: '{print $NF}')
    add_cleanup "aws lambda delete-layer-version --layer-name $layer_name --version-number $layer_ver"

    # Check if CLI chose Python 3.12 compatible runtime
    if echo "$output" | grep -q "Compatible runtimes:.*python3.12"; then
        echo -e "${GREEN}PASS:${NC} Compatible runtime correct (3.12)."
    else
        echo -e "${RED}FAIL:${NC} Compatible runtime incorrect."
        exit 1
    fi
    
    echo "Creating Lambda (Python 3.12)..."
    # Same function logic
    aws lambda create-function --function-name "$func_name" \
        --runtime "python3.12" --role "$role_arn" --handler "lambda_function.lambda_handler" \
        --zip-file "fileb://function.zip" --layers "$layer_arn" > /dev/null
    add_cleanup "aws lambda delete-function --function-name $func_name"

    sleep 5
    aws lambda invoke --function-name "$func_name" response_312.json > /dev/null
    if grep -q "2." response_312.json; then
         echo -e "${GREEN}PASS:${NC} Python 3.12 Invocation success."
    else
         echo -e "${RED}FAIL:${NC} Python 3.12 Invocation failed."
         cat response_312.json
         exit 1
    fi
}

if should_run_aws_tests; then
    test_python_al2
    test_python_al2023
fi
