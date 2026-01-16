#!/bin/bash

# Integration Test: Main CLI Wrapper (aws-lambda-layer-cli)
# Scenarios:
# 1. Publish from Wheel (Success case)
# 2. Deploy to Mismatched Runtime (Failure case)
# 3. Deploy to Mismatched Architecture (Failure case)
# 4. Publish from Pip (Success case - Standard Package Name)

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
# Override CLI_TOOL to point to the script we are editing
CLI_TOOL="$REPO_ROOT/scripts/aws-lambda-layer-cli"
JSON_FILE="$REPO_ROOT/test/numpy_wheel_list.json"
WHEEL_DIR="$TEST_DIR/real_wheels_cli"

# Ensure we have a clean state
setup_common
mkdir -p "$WHEEL_DIR"

# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------
get_url() {
    local k1=$1
    local k2=$2
    local k3=${3:-""}
    python3 -c "
import json
with open('$JSON_FILE') as f:
    wheels = json.load(f)
for w in wheels:
    u = w['url']
    if '$k1' in u and '$k2' in u and '$k3' in u:
        print(u)
        break
"
}

download_wheel() {
    local url=$1
    local dest_name=${url##*/}
    
    # Check cache first
    local cache_path="$REPO_ROOT/test/wheels/$dest_name"
    if [ -f "$cache_path" ]; then
        cp "$cache_path" "$WHEEL_DIR/$dest_name"
    fi

    if [ ! -f "$WHEEL_DIR/$dest_name" ]; then
        >&2 echo "Downloading $dest_name..."
        curl -L -s -o "$WHEEL_DIR/$dest_name" "$url"
    fi
    echo "$WHEEL_DIR/$dest_name"
}

if ! should_run_aws_tests; then
    echo "AWS credentials not found. Skipping usage test."
    exit 0
fi

ensure_test_role

# ------------------------------------------------------------------
# Preparation
# ------------------------------------------------------------------
echo "=== Phase 1: Preparation ==="
# Get a Python 3.13 Wheel for x86_64
LINUX_URL=$(get_url "manylinux" "x86_64" "cp313")
if [ -z "$LINUX_URL" ]; then echo "Error: No Linux python 3.13 wheel found in JSON"; exit 1; fi
LINUX_WHEEL=$(download_wheel "$LINUX_URL")
echo "Using Wheel: $(basename "$LINUX_WHEEL")"

# ------------------------------------------------------------------
# Scenario 1: Publish from Wheel & Deploy to Matching Runtime
# ------------------------------------------------------------------
echo ""
echo "=== Scenario 1: Publish Wheel & Deploy Matching Runtime (Python 3.13) ==="
LAYER_NAME_1="test-cli-wheel-$RUN_ID"

# We must accept prompts "Do you want to proceed?" and "Do you want to publish?"
# Using 'yes' to feed 'y' to prompts
echo "Publishing Layer..."
yes | "$CLI_TOOL" publish \
    --python --wheel "$LINUX_WHEEL" \
    --name "$LAYER_NAME_1" \
    --description "Test Layer from Wheel" > "$TEST_DIR/pub1.log" 2>&1

res=$?
if [ $res -ne 0 ]; then
    echo -e "${RED}Publish Failed${NC}"
    cat "$TEST_DIR/pub1.log"
    exit 1
fi

LAYER_ARN_1=$(grep -o "arn:aws:lambda:[^:]*:[0-9]*:layer:$LAYER_NAME_1:[0-9]*" "$TEST_DIR/pub1.log" | tail -1)
echo "Layer ARN: $LAYER_ARN_1"
add_cleanup "aws lambda delete-layer-version --layer-name $LAYER_NAME_1 --version-number ${LAYER_ARN_1##*:}"

# Verify Layer Metadata
echo "Verifying Layer Metadata..."
LAYER_VER="${LAYER_ARN_1##*:}"
aws lambda get-layer-version --layer-name "$LAYER_NAME_1" --version-number "$LAYER_VER" > "$TEST_DIR/layer_info.json"

if grep -q "python3.13" "$TEST_DIR/layer_info.json" && grep -q "CompatibleRuntimes" "$TEST_DIR/layer_info.json"; then
    echo -e "${GREEN}METADATA CHECK: CompatibleRuntimes includes python3.13${NC}"
else
    echo -e "${RED}METADATA FAILURE: CompatibleRuntimes missing python3.13${NC}"
    cat "$TEST_DIR/layer_info.json"
    exit 1
fi

if grep -q "x86_64" "$TEST_DIR/layer_info.json" && grep -q "CompatibleArchitectures" "$TEST_DIR/layer_info.json"; then
    echo -e "${GREEN}METADATA CHECK: CompatibleArchitectures includes x86_64${NC}"
else
    echo -e "${RED}METADATA FAILURE: CompatibleArchitectures missing x86_64${NC}"
    cat "$TEST_DIR/layer_info.json"
    exit 1
fi

# Create Function (Python 3.13)
FUNC_NAME_1="test-func-match-$RUN_ID"
echo "Creating Function (Python 3.13)..."

cat > "$TEST_DIR/lambda_function.py" <<EOF
import json
import numpy

def lambda_handler(event, context):
    return {
        'statusCode': 200,
        'body': f"Numpy Version: {numpy.__version__}"
    }
EOF
zip -j "$TEST_DIR/function.zip" "$TEST_DIR/lambda_function.py" >/dev/null

aws lambda create-function \
    --function-name "$FUNC_NAME_1" \
    --runtime python3.13 \
    --role "$TEST_ROLE_ARN" \
    --handler lambda_function.lambda_handler \
    --zip-file "fileb://$TEST_DIR/function.zip" \
    --layers "$LAYER_ARN_1" \
    --architectures x86_64 > /dev/null

add_cleanup "aws lambda delete-function --function-name $FUNC_NAME_1"

# Invoke
echo "Waiting for function active..."
sleep 5
echo "Invoking..."
aws lambda invoke \
    --function-name "$FUNC_NAME_1" \
    --cli-binary-format raw-in-base64-out \
    --payload '{}' \
    "$TEST_DIR/invoke1.json" > /dev/null

if grep -q "Numpy Version" "$TEST_DIR/invoke1.json"; then
    echo -e "${GREEN}SUCCESS: Scenario 1 passed (Imported Numpy)${NC}"
else
    echo -e "${RED}FAILURE: Scenario 1 failed${NC}"
    cat "$TEST_DIR/invoke1.json"
    exit 1
fi

# ------------------------------------------------------------------
# Scenario 2: Deploy Same Layer to Mismatched Runtime (Python 3.12)
# ------------------------------------------------------------------
echo ""
echo "=== Scenario 2: Deploy Same Layer to Mismapped Runtime (Python 3.12) ==="
# Note: numpy cp313 wheel should fail on cp312

FUNC_NAME_2="test-func-mismatch-$RUN_ID"
echo "Creating Function (Python 3.12)..."

aws lambda create-function \
    --function-name "$FUNC_NAME_2" \
    --runtime python3.12 \
    --role "$TEST_ROLE_ARN" \
    --handler lambda_function.lambda_handler \
    --zip-file "fileb://$TEST_DIR/function.zip" \
    --layers "$LAYER_ARN_1" \
    --architectures x86_64 > /dev/null

add_cleanup "aws lambda delete-function --function-name $FUNC_NAME_2"

echo "Waiting for function active..."
sleep 5
echo "Invoking..."
aws lambda invoke \
    --function-name "$FUNC_NAME_2" \
    --cli-binary-format raw-in-base64-out \
    --payload '{}' \
    "$TEST_DIR/invoke2.json" > /dev/null

# We expect an error in the response (e.g. "errorMessage")
if grep -q "errorMessage" "$TEST_DIR/invoke2.json"; then
    echo -e "${GREEN}SUCCESS: Scenario 2 passed (Function failed as expected)${NC}"
    echo "Error was: $(grep -o '"errorMessage": "[^"]*"' "$TEST_DIR/invoke2.json")"
else
    echo -e "${RED}FAILURE: Scenario 2 (Function unexpectedly succeeded or returned invalid response)${NC}"
    cat "$TEST_DIR/invoke2.json"
    # Don't exit, continue to next scenario
fi

# ------------------------------------------------------------------
# Scenario 3: Deploy Same Layer to Mismatched Architecture (arm64)
# ------------------------------------------------------------------
echo ""
echo "=== Scenario 3: Deploy Same Layer (x86_64) to Mismatched Arch (arm64) ==="
# Note: numpy x86_64 wheel should fail on arm64

FUNC_NAME_3="test-func-arch-fail-$RUN_ID"
echo "Creating Function (Python 3.13, arm64)..."

# Ensure we log the command
printf "${BLUE}Running: aws lambda create-function --function-name $FUNC_NAME_3 --runtime python3.13 --role ... --layers $LAYER_ARN_1 --architectures arm64${NC}\n"

aws lambda create-function \
    --function-name "$FUNC_NAME_3" \
    --runtime python3.13 \
    --role "$TEST_ROLE_ARN" \
    --handler lambda_function.lambda_handler \
    --zip-file "fileb://$TEST_DIR/function.zip" \
    --layers "$LAYER_ARN_1" \
    --architectures arm64 > /dev/null

add_cleanup "aws lambda delete-function --function-name $FUNC_NAME_3"

echo "Waiting for function active..."
sleep 5
echo "Invoking..."
printf "${BLUE}Running: aws lambda invoke --function-name $FUNC_NAME_3 ...${NC}\n"

aws lambda invoke \
    --function-name "$FUNC_NAME_3" \
    --cli-binary-format raw-in-base64-out \
    --payload '{}' \
    "$TEST_DIR/invoke3.json" > /dev/null

# We expect an error in the response
if grep -q "errorMessage" "$TEST_DIR/invoke3.json"; then
    echo -e "${GREEN}SUCCESS: Scenario 3 passed (Function failed as expected)${NC}"
    echo "Error was: $(grep -o '"errorMessage": "[^"]*"' "$TEST_DIR/invoke3.json")"
else
    echo -e "${RED}FAILURE: Scenario 3 (Function unexpectedly succeeded or returned invalid response)${NC}"
    cat "$TEST_DIR/invoke3.json"
fi

# ------------------------------------------------------------------
# Scenario 4: Publish from Pip (Standard Package Name)
# ------------------------------------------------------------------
echo ""
echo "=== Scenario 4: Publish from Pip (numpy==2.4.1) ==="
LAYER_NAME_4="test-cli-pip-$RUN_ID"

echo "Publishing Layer..."
yes | "$CLI_TOOL" publish \
    --python "numpy==2.4.1" \
    --name "$LAYER_NAME_4" \
    --description "Test Layer from Pip" \
    --python-version 3.12 \
    --architecture x86_64 > "$TEST_DIR/pub4.log" 2>&1

res=$?
if [ $res -ne 0 ]; then
    echo -e "${RED}Publish Failed${NC}"
    cat "$TEST_DIR/pub4.log"
    exit 1
fi

LAYER_ARN_4=$(grep -o "arn:aws:lambda:[^:]*:[0-9]*:layer:$LAYER_NAME_4:[0-9]*" "$TEST_DIR/pub4.log" | tail -1)
echo "Layer ARN: $LAYER_ARN_4"
add_cleanup "aws lambda delete-layer-version --layer-name $LAYER_NAME_4 --version-number ${LAYER_ARN_4##*:}"

# Create Function (Python 3.12)
FUNC_NAME_4="test-func-pip-$RUN_ID"
echo "Creating Function (Python 3.12)..."

aws lambda create-function \
    --function-name "$FUNC_NAME_4" \
    --runtime python3.12 \
    --role "$TEST_ROLE_ARN" \
    --handler lambda_function.lambda_handler \
    --zip-file "fileb://$TEST_DIR/function.zip" \
    --layers "$LAYER_ARN_4" \
    --architectures x86_64 > /dev/null

add_cleanup "aws lambda delete-function --function-name $FUNC_NAME_4"

echo "Waiting for function active..."
sleep 5
echo "Invoking..."
aws lambda invoke \
    --function-name "$FUNC_NAME_4" \
    --cli-binary-format raw-in-base64-out \
    --payload '{}' \
    "$TEST_DIR/invoke4.json" > /dev/null

if grep -q "Numpy Version: 2.4.1" "$TEST_DIR/invoke4.json"; then
    echo -e "${GREEN}SUCCESS: Scenario 4 passed (Imported Numpy 2.4.1)${NC}"
else
    echo -e "${RED}FAILURE: Scenario 4 failed${NC}"
    cat "$TEST_DIR/invoke4.json"
    exit 1
fi

echo ""
echo -e "${GREEN}ALL SCENARIOS COMPLETED${NC}"
