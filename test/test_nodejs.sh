#!/bin/bash

# Test: Node.js Layer Creation and Verification
# Covers:
# - Node.js layer creation (local zip)
# - Publishing (x86_64, arm64 compatibility)

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

setup_common

echo -e "\n${BLUE}=== Test: Node.js Basic ===${NC}"

test_local_node() {
    echo -e "\n${BLUE}[Test]${NC} Node.js Local Zip..."
    local pkg="lodash"
    local layer_name="test-node-local-$RUN_ID.zip"
    
    cd "$TEST_DIR"
    "$CLI_TOOL" zip --nodejs "$pkg" --name "$layer_name" > /dev/null
    
    if [ -f "output/$layer_name" ]; then
        echo -e "${GREEN}PASS:${NC} Zip created."
    else
        echo -e "${RED}FAIL:${NC} Zip not created."
        exit 1
    fi
    
    if check_zip_content "output/$layer_name" "nodejs/node_modules/lodash/package.json"; then
        echo -e "${GREEN}PASS:${NC} Content verified."
    else
        exit 1
    fi
}

test_publish_node() {
    echo -e "\n${BLUE}[Test]${NC} Node.js Publish (Multi-Arch)..."
    
    if ! ensure_test_role; then
         echo -e "${YELLOW}Skipping publish test (Role creation failed and no AWS_LAMBDA_ROLE_ARN provided)${NC}"
         return 0
    fi
    local role_arn="$TEST_ROLE_ARN"

    local layer_name="test-node-pub-$RUN_ID"
    local func_name_x86="test-node-x86-$RUN_ID"
    local func_name_arm="test-node-arm-$RUN_ID"
    
    echo "Publishing layer..."
    cd "$TEST_DIR"
    output=$(yes | "$CLI_TOOL" publish --nodejs "lodash" --name "$layer_name" --description "Nodejs Test" | strip_ansi)
    
    layer_arn=$(echo "$output" | grep "Layer ARN:" | awk '{print $3}' | tr -d '\r')
    if [ -z "$layer_arn" ]; then
        echo -e "${RED}FAIL:${NC} Could not extract Layer ARN"
        echo "$output"
        exit 1
    fi
    echo -e "${GREEN}PASS:${NC} Layer published: $layer_arn"
    
    local layer_ver=$(echo "$layer_arn" | awk -F: '{print $NF}')
    add_cleanup "aws lambda delete-layer-version --layer-name $layer_name --version-number $layer_ver"

    # Verify compatible architectures in output (should have both or be implicitly both)
    # AWS CLI 'get-layer-version' can verify this properly.
    echo "Verifying layer metadata..."
    layer_meta=$(aws lambda get-layer-version --layer-name "$layer_name" --version-number "$layer_ver" --output json)
    # Check if we can find both architectures? Default might not list them if it wasn't specified, OR we forced it.
    # Our CLI change forces "CompatibleArchitectures": ["x86_64", "arm64"]
    
    if echo "$layer_meta" | grep -q "x86_64" && echo "$layer_meta" | grep -q "arm64"; then
        echo -e "${GREEN}PASS:${NC} Layer marked compatible with x86_64 and arm64."
    else
        echo -e "${YELLOW}WARNING:${NC} Layer might not have explicit compatible architectures set in AWS console, checking functionality..."
        echo "$layer_meta"
    fi

    # Create Lambda Function (x86)
    echo "Creating lambda (x86_64)..."
    cat > index.js <<EOF
const _ = require('lodash');
exports.handler = async (event) => { return _.VERSION; };
EOF
    zip function.zip index.js > /dev/null
    
    aws lambda create-function --function-name "$func_name_x86" \
        --runtime "nodejs20.x" --role "$role_arn" --handler "index.handler" \
        --zip-file "fileb://function.zip" --layers "$layer_arn" \
        --architectures "x86_64" > /dev/null
    add_cleanup "aws lambda delete-function --function-name $func_name_x86"

    # Create Lambda Function (arm64)
    # Re-use zip
    aws lambda create-function --function-name "$func_name_arm" \
        --runtime "nodejs20.x" --role "$role_arn" --handler "index.handler" \
        --zip-file "fileb://function.zip" --layers "$layer_arn" \
        --architectures "arm64" > /dev/null
    add_cleanup "aws lambda delete-function --function-name $func_name_arm"

    echo "Waiting for functions active..."
    sleep 5
    
    echo "Invoking x86..."
    aws lambda invoke --function-name "$func_name_x86" response_x86.json > /dev/null
    if grep -q "4." response_x86.json; then
        echo -e "${GREEN}PASS:${NC} x86_64 Invocation success."
    else
        echo -e "${RED}FAIL:${NC} x86_64 Invocation failed."
        cat response_x86.json
        exit 1
    fi

    echo "Invoking arm64..."
    aws lambda invoke --function-name "$func_name_arm" response_arm.json > /dev/null
    if grep -q "4." response_arm.json; then
        echo -e "${GREEN}PASS:${NC} arm64 Invocation success."
    else
        echo -e "${RED}FAIL:${NC} arm64 Invocation failed."
        cat response_arm.json
        exit 1
    fi
}

test_local_node
if should_run_aws_tests; then
    test_publish_node
fi
