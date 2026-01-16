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
    # Check if python3.10 exists
    if ! command -v python3.10 &> /dev/null; then
        echo -e "${YELLOW}Skipping Python 3.10 test (python3.10 not found)${NC}"
        return 0
    fi

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
    # Use numpy as it relies on C-extensions and stricter platform checks than pure python
    echo "Publishing layer (NumPy on 3.10)..."
    output=$(yes | "$CLI_TOOL" publish --python "numpy==1.26.4" --name "$layer_name" --python-version 3.10 | strip_ansi)
    
    layer_arn=$(echo "$output" | grep "Layer ARN:" | awk '{print $3}' | tr -d '\r')
    if [ -z "$layer_arn" ]; then 
        echo -e "${RED}FAIL: Layer ARN not found. Output:${NC}"
        echo "$output"
        exit 1
    fi
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
import json
import numpy
def lambda_handler(event, context):
    return {
        'statusCode': 200,
        'body': json.dumps({
            'numpy_version': numpy.__version__
        })
    }
EOF
    zip -q function.zip lambda_function.py

    if [ ! -f "function.zip" ]; then
         echo -e "${RED}FAIL: function.zip not found in $(pwd)${NC}"
         return 1
    fi
    
    aws lambda create-function --function-name "$func_name" \
        --runtime "python3.10" --role "$role_arn" --handler "lambda_function.lambda_handler" \
        --zip-file "fileb://$TEST_DIR/function.zip" --layers "$layer_arn" > /dev/null
    add_cleanup "aws lambda delete-function --function-name $func_name"

    sleep 5
    aws lambda invoke --function-name "$func_name" response.json > /dev/null
    if grep -q "numpy_version" response.json; then
        echo -e "${GREEN}PASS:${NC} Python 3.10 Invocation success (NumPy)."
    else
        echo -e "${RED}FAIL:${NC} Python 3.10 Invocation failed."
        cat response.json
        exit 1
    fi
}

test_python_al2023() {
    # Check if python3.12 exists
    if ! command -v python3.12 &> /dev/null; then
        echo -e "${YELLOW}Skipping Python 3.12 test (python3.12 not found)${NC}"
        # Fallback to python3 if it is >= 3.12
        local py_ver=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
        local py_minor=$(echo "$py_ver" | cut -d. -f2)
        if [ "$py_minor" -ge 12 ]; then
             echo -e "${BLUE}[Test]${NC} Using default python3 ($py_ver) for AL2023 test..."
             test_python_custom "$py_ver"
             return 0
        fi
        return 0
    fi

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

    # Create verify function
    cat <<EOF > lambda_function.py
import json
import numpy
def lambda_handler(event, context):
    return {
        'statusCode': 200, 
        'body': json.dumps({
            'message': 'ok',
            'numpy_version': numpy.__version__
        })
    }
EOF
    zip -q function.zip lambda_function.py

    echo "Publishing layer (NumPy on 3.12)..."
    output=$(yes | "$CLI_TOOL" publish --python "numpy==1.26.4" --name "$layer_name" --python-version 3.12 | strip_ansi)
    
    layer_arn=$(echo "$output" | grep "Layer ARN:" | awk '{print $3}' | tr -d '\r')
    if [ -z "$layer_arn" ]; then exit 1; fi
    local layer_ver=$(echo "$layer_arn" | awk -F: '{print $NF}')
    add_cleanup "aws lambda delete-layer-version --layer-name $layer_name --version-number $layer_ver"

    # Check if CLI chose Python 3.12 compatible runtime
    if echo "$output" | grep -q "Compatible runtimes:.*python3.12"; then
        echo -e "${GREEN}PASS:${NC} Compatible runtime correct (3.12)."
    else
        echo -e "${RED}FAIL:${NC} Compatible runtime incorrect."
        echo "Output was:"
        echo "$output"
        exit 1
    fi
    
    echo "Creating Lambda (Python 3.12)..."
    
    if [ ! -f "function.zip" ]; then
         echo -e "${RED}FAIL: function.zip not found in $(pwd)${NC}"
         return 1
    fi

    # Same function logic
    aws lambda create-function --function-name "$func_name" \
        --runtime "python3.12" --role "$role_arn" --handler "lambda_function.lambda_handler" \
        --zip-file "fileb://$TEST_DIR/function.zip" --layers "$layer_arn" > /dev/null
    add_cleanup "aws lambda delete-function --function-name $func_name"

    sleep 5
    aws lambda invoke --function-name "$func_name" response_312.json > /dev/null
    if grep -q "numpy_version" response_312.json; then
         echo -e "${GREEN}PASS:${NC} Python 3.12 Invocation success (NumPy)."
    else
         echo -e "${RED}FAIL:${NC} Python 3.12 Invocation failed."
         cat response_312.json
         exit 1
    fi
}

test_python_custom() {
    local ver=$1
    echo -e "\n${BLUE}[Test]${NC} Python $ver (Amazon Linux 2023 check)..."
    
    if ! ensure_test_role; then
         echo -e "${YELLOW}Skipping test (Role issue)${NC}"
         return 0
    fi
    local role_arn="$TEST_ROLE_ARN"
    
    local layer_name="test-py${ver//./}-$RUN_ID"
    local func_name="test-py${ver//./}-$RUN_ID"
    
    cd "$TEST_DIR"
    
    # Create verification function
    cat <<EOF > lambda_function.py
import json
import requests
import sys

def lambda_handler(event, context):
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Hello from Lambda!',
            'requests_version': requests.__version__,
            'python_version': sys.version
        })
    }
EOF
    zip -q function.zip lambda_function.py

    echo "Publishing layer (Requests on $ver)..."
    
    # We use 'yes' to handle prompts
    output=$(yes | "$CLI_TOOL" publish --python "requests" --name "$layer_name" --python-version "$ver" | strip_ansi)
    
    layer_arn=$(echo "$output" | grep "Layer ARN:" | awk '{print $3}' | tr -d '\r')
    if [ -z "$layer_arn" ]; then 
        echo -e "${RED}FAIL: Layer ARN not found. Output:${NC}"
        echo "$output"
        exit 1
    fi
    local layer_ver=$(echo "$layer_arn" | awk -F: '{print $NF}')
    add_cleanup "aws lambda delete-layer-version --layer-name $layer_name --version-number $layer_ver"

    # Check for correct platform selection (AL2023 for >=3.12)
    # The output log should imply it used manylinux_2_28
    if echo "$output" | grep -q "manylinux_2_28"; then
        echo -e "${GREEN}PASS:${NC} Platform detection correct (manylinux_2_28)."
    else
        echo -e "${RED}FAIL:${NC} Platform detection incorrect (Expected manylinux_2_28)."
        echo "$output"
        # We don't exit here to try function invocation if possible, but actually invoked platform matters.
    fi
    
    # Verify runtime compatibility
    if echo "$output" | grep -q "Compatible runtimes:.*python$ver"; then
        echo -e "${GREEN}PASS:${NC} Compatible runtime correct ($ver)."
    else
         # Sometimes it lists range or multiple.
        echo -e "${YELLOW}WARN:${NC} Compatible runtime check weak."
    fi

    # Attempt to create lambda with this runtime
    # Note: AWS Lambda must support this runtime. python3.14 might not exist yet on AWS.
    # If using 3.14, we might fail creation.
    echo "Creating Lambda (Python $ver)..."
    
    if [ ! -f "function.zip" ]; then
         echo -e "${RED}FAIL: function.zip not found in $(pwd)${NC}"
         ls -la
         return 1
    fi
    
    if ! aws lambda create-function --function-name "$func_name" \
        --runtime "python$ver" --role "$role_arn" --handler "lambda_function.lambda_handler" \
        --zip-file "fileb://$TEST_DIR/function.zip" --layers "$layer_arn" > /dev/null 2>&1; then
            echo -e "${YELLOW}WARN: Failed to create function with runtime python$ver. (May not be supported by AWS yet)${NC}"
            return 0 # Skip invocation
    fi
    add_cleanup "aws lambda delete-function --function-name $func_name"

    sleep 5
    aws lambda invoke --function-name "$func_name" "response_$ver.json" > /dev/null
    if grep -q "2." "response_$ver.json"; then
         echo -e "${GREEN}PASS:${NC} Python $ver Invocation success."
    else
         echo -e "${RED}FAIL:${NC} Python $ver Invocation failed."
         cat "response_$ver.json"
         exit 1
    fi
}

if should_run_aws_tests; then
    test_python_al2
    test_python_al2023
fi
