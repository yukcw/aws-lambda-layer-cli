#!/bin/bash

# Test: Python Architecture (x86_64 vs arm64) using NumPy
# Covers:
# - Installing binary packages with different architecture targets
# - Verifying metadata on published layers
# - Invoking on specific architecture functions

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

setup_common

# Numpy needs to be compatible with Python 3.12 (NumPy >= 1.26.0)
NUMPY_VER="numpy==1.26.4"

echo -e "\n${BLUE}=== Test: Python Architecture (NumPy) ===${NC}"

test_arch() {
    local arch=$1
    local aws_arch=$2
    
    if ! ensure_test_role; then
         echo -e "${YELLOW}Skipping test (Role issue)${NC}"
         return 0
    fi
    local role_arn="$TEST_ROLE_ARN"

    local layer_name="test-numpy-$arch-$RUN_ID"
    local func_name="test-numpy-$arch-$RUN_ID"
    
    echo -e "\n${BLUE}[Test]${NC} Python NumPy on $arch..."
    
    cd "$TEST_DIR"
    echo "Publishing layer ($arch)..."
    
    output=$(yes | "$CLI_TOOL" publish --python "$NUMPY_VER" \
        --name "$layer_name" \
        --python-version 3.12 \
        --architecture "$arch" | strip_ansi)
    
    layer_arn=$(echo "$output" | grep "Layer ARN:" | awk '{print $3}' | tr -d '\r')
    if [ -z "$layer_arn" ]; then
        echo -e "${RED}FAIL:${NC} Could not extract Layer ARN"
        echo "$output"
        return 1
    fi
     local layer_ver=$(echo "$layer_arn" | awk -F: '{print $NF}')
    add_cleanup "aws lambda delete-layer-version --layer-name $layer_name --version-number $layer_ver"
    
    # Verify metadata in AWS
    local layer_meta=$(aws lambda get-layer-version --layer-name "$layer_name" --version-number "$layer_ver" --output json)
    if echo "$layer_meta" | grep -q "$aws_arch"; then
         echo -e "${GREEN}PASS:${NC} Layer metadata contains $aws_arch."
    else
         echo -e "${RED}FAIL:${NC} Layer metadata missing $aws_arch."
         echo "$layer_meta"
         return 1
    fi

    # Create Lambda Function
    echo "Creating lambda..."
    cat > lambda_function.py <<EOF
import numpy
def lambda_handler(event, context): return numpy.__version__
EOF
    zip function.zip lambda_function.py > /dev/null
    
    aws lambda create-function \
        --function-name "$func_name" \
        --runtime "python3.12" \
        --role "$role_arn" \
        --handler "lambda_function.lambda_handler" \
        --zip-file "fileb://function.zip" \
        --layers "$layer_arn" \
        --architectures "$aws_arch" > /dev/null
        
    add_cleanup "aws lambda delete-function --function-name $func_name"

    echo "Waiting for active..."
    sleep 5
    
    echo "Invoking..."
    # Retry once
    if ! aws lambda invoke --function-name "$func_name" response.json > /dev/null; then
        sleep 5
        aws lambda invoke --function-name "$func_name" response.json > /dev/null
    fi
    
    if grep -q "1.26" response.json; then
        echo -e "${GREEN}PASS:${NC} NumPy Load Success on $arch."
    else
        echo -e "${RED}FAIL:${NC} NumPy Load Failed on $arch."
        cat response.json
        return 1
    fi
}

if should_run_aws_tests; then
    # Test x86_64
    test_arch "x86_64" "x86_64"
    
    # Test arm64
    test_arch "arm64" "arm64"
fi
