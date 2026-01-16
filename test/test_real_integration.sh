#!/bin/bash

# Integration Test: Real Wheels & AWS Usage
# This test downloads REAL wheels from the provided JSON list and runs the full lifecycle:
# 1. Validation Logic (F1, F4, F5)
# 2. Layer Creation (Success Case)
# 3. AWS Publication (If credentials exist)
# 4. Lambda Invocation (If credentials exist)

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

CLI_TOOL="$REPO_ROOT/scripts/create_wheel_layer.sh"
JSON_FILE="$REPO_ROOT/test/numpy_wheel_list.json"
WHEEL_DIR="$TEST_DIR/real_wheels"

setup_common # Creates TEST_DIR

mkdir -p "$WHEEL_DIR"

# ------------------------------------------------------------------
# Helper: Get URL from JSON
# ------------------------------------------------------------------
get_url() {
    local platform_keyword=$1
    local arch_keyword=$2
    python3 -c "
import json
with open('$JSON_FILE') as f:
    wheels = json.load(f)
for w in wheels:
    u = w['url']
    if '$platform_keyword' in u and '$arch_keyword' in u:
        print(u)
        break
"
}

download_wheel() {
    local url=$1
    local dest_name=${url##*/}
    if [ ! -f "$WHEEL_DIR/$dest_name" ]; then
        >&2 echo -e "${BLUE}Downloading $dest_name...${NC}"
        if command -v curl &> /dev/null; then
            if ! curl -L -s -o "$WHEEL_DIR/$dest_name" "$url"; then
                >&2 echo "Error downloading $url"
                return 1
            fi
        else
            if ! wget -q -O "$WHEEL_DIR/$dest_name" "$url"; then
                >&2 echo "Error downloading $url"
                return 1
            fi
        fi
    fi
    echo "$WHEEL_DIR/$dest_name"
}

# ------------------------------------------------------------------
# 1. Prepare Wheels
# ------------------------------------------------------------------
echo "=== Phase 1: Preparation ==="
echo "Identifying wheels from JSON..."

# MAC WHEEL (for Failure testing)
MAC_URL=$(get_url "macosx" "x86_64")
if [ -z "$MAC_URL" ]; then echo "Error: No Mac wheel found in JSON"; exit 1; fi
MAC_WHEEL=$(download_wheel "$MAC_URL")

# LINUX WHEEL (for Success testing)
LINUX_URL=$(get_url "manylinux" "x86_64")
if [ -z "$LINUX_URL" ]; then echo "Error: No Linux wheel found in JSON"; exit 1; fi
LINUX_WHEEL=$(download_wheel "$LINUX_URL")

echo "Using Wheels:"
echo "  Mac:   $(basename "$MAC_WHEEL")"
echo "  Linux: $(basename "$LINUX_WHEEL")"

# ------------------------------------------------------------------
# 2. Validation Tests
# ------------------------------------------------------------------
echo ""
echo "=== Phase 2: Validation Features (F1, F4, F5) ==="

# F1/F4: Check Mac Wheel rejection
echo -n "Test [F1/F4] Mac Wheel Rejection... "
set +e
bash "$CLI_TOOL" -w "$MAC_WHEEL" -a x86_64 --python-version 3.13 > "$TEST_DIR/f1_out.log" 2>&1
res=$?
set -e
if [ $res -ne 0 ]; then
    echo -e "${GREEN}PASS${NC} (Rejected as expected)"
elif grep -q "Warning: Filename suggests non-Linux" "$TEST_DIR/f1_out.log"; then
    # If python validation fails silent, it might fallback to warning.
    # But strict mode should exit 1.
    echo -e "${RED}FAIL${NC} (Was accepted but should have failed)"
else
    echo -e "${RED}FAIL${NC} (Was accepted)"
    cat "$TEST_DIR/f1_out.log"
fi

# F5: Renaming Attack
echo -n "Test [F5] Renamed Metadata Rejection... "
RENAMED_WHEEL="$WHEEL_DIR/numpy-2.4.1-cp313-cp313-manylinux_2_17_x86_64.whl"
cp "$MAC_WHEEL" "$RENAMED_WHEEL"

set +e
bash "$CLI_TOOL" -w "$RENAMED_WHEEL" -a x86_64 --python-version 3.13 > "$TEST_DIR/f5_out.log" 2>&1
res=$?
set -e
if [ $res -ne 0 ] && grep -q "Error: Wheel is not compatible with Linux" "$TEST_DIR/f5_out.log"; then
    echo -e "${GREEN}PASS${NC} (Caught metadata mismatch)"
else
    echo -e "${RED}FAIL${NC}"
    echo "Output:"
    cat "$TEST_DIR/f5_out.log"
fi

# ------------------------------------------------------------------
# 3. Layer Creation (Success)
# ------------------------------------------------------------------
echo ""
echo "=== Phase 3: Layer Creation (F3) ==="
LAYER_ZIP="$TEST_DIR/numpy_layer.zip"
echo -n "Building Valid Layer... "

set +e
bash "$CLI_TOOL" -w "$LINUX_WHEEL" -n "$LAYER_ZIP" -a x86_64 --python-version 3.13 --platform manylinux_2_27_x86_64 > "$TEST_DIR/build_out.log" 2>&1
res=$?
set -e

if [ $res -eq 0 ] && [ -f "$LAYER_ZIP" ]; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC}"
    cat "$TEST_DIR/build_out.log"
    exit 1
fi

# ------------------------------------------------------------------
# 4. AWS Publish & Test (If Env Var Set)
# ------------------------------------------------------------------
if ! should_run_aws_tests; then
    echo "AWS credentials not found. Skipping usage test."
    exit 0
fi

echo ""
echo "=== Phase 4: AWS Publish & Usage Test ==="
echo "Note: This requires 'aws' CLI and permissions."

# Ensure Role
ensure_test_role

# Publish Layer
LAYER_NAME="test-numpy-layer-$RUN_ID"
echo "Publishing Layer ($LAYER_NAME)..."
LAYER_ARN=$(aws lambda publish-layer-version \
    --layer-name "$LAYER_NAME" \
    --zip-file "fileb://$LAYER_ZIP" \
    --compatible-runtimes python3.13 \
    --compatible-architectures x86_64 \
    --query "LayerVersionArn" --output text)

echo "Layer ARN: $LAYER_ARN"
add_cleanup "aws lambda delete-layer-version --layer-name $LAYER_NAME --version-number ${LAYER_ARN##*:}"

# Create Function
FUNC_NAME="test-func-$RUN_ID"
echo "Creating Test Function ($FUNC_NAME)..."

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

# Need to wait for role propagation sometimes, ensure_test_role does standard sleep, but sometimes more is needed
sleep 2

aws lambda create-function \
    --function-name "$FUNC_NAME" \
    --runtime python3.13 \
    --role "$TEST_ROLE_ARN" \
    --handler lambda_function.lambda_handler \
    --zip-file "fileb://$TEST_DIR/function.zip" \
    --layers "$LAYER_ARN" \
    --architectures x86_64 \
    --query "FunctionArn" --output text > /dev/null

add_cleanup "aws lambda delete-function --function-name $FUNC_NAME"

# Wait for function active
echo "Waiting for function to be active..."
sleep 5

# Invoke
echo "Invoking function..."
aws lambda invoke \
    --function-name "$FUNC_NAME" \
    --cli-binary-format raw-in-base64-out \
    --payload '{}' \
    "$TEST_DIR/invoke_out.json" > /dev/null

echo "Response:"
cat "$TEST_DIR/invoke_out.json"
echo ""

if grep -q "Numpy Version" "$TEST_DIR/invoke_out.json"; then
    echo -e "${GREEN}SUCCESS: Lambda Function ran and imported Numpy!${NC}"
else
    echo -e "${RED}FAILURE: Function output unexpected.${NC}"
    exit 1
fi
