#!/bin/bash
# Test for strict argument handling with wheel auto-detection

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
CLI_TOOL="$REPO_ROOT/scripts/create_wheel_layer.sh"
setup_common

echo "=== Strict Usage Test ==="

# Create a dummy wheel with specific tag
create_dummy_wheel() {
    local name=$1
    local tag=$2
    local dir="$TEST_DIR/wheels"
    mkdir -p "$dir"
    local filename="$dir/$name"
    
    # Simple zip creation (empty content ok for this test as we test arg parsing/filename detection primarily)
    # But script does check .dist-info/WHEEL for tag validation too.
    # We will just rely on filename detection for the 'arg parsing' phase, 
    # but the script later validates content. 
    # To pass "validation", we need consistent content.
    
    local tmp_wheel_dir="$dir/temp_$(echo "$name" | tr -cd 'a-zA-Z0-9')"
    mkdir -p "$tmp_wheel_dir/pkg-1.0.dist-info"
    # Create WHEEL file
    echo "Wheel-Version: 1.0" > "$tmp_wheel_dir/pkg-1.0.dist-info/WHEEL"
    echo "Generator: test" >> "$tmp_wheel_dir/pkg-1.0.dist-info/WHEEL"
    echo "Root-Is-Purelib: true" >> "$tmp_wheel_dir/pkg-1.0.dist-info/WHEEL"
    echo "Tag: $tag" >> "$tmp_wheel_dir/pkg-1.0.dist-info/WHEEL"
    
    # Create METADATA file (Required by modern Pip)
    echo "Metadata-Version: 2.1" > "$tmp_wheel_dir/pkg-1.0.dist-info/METADATA"
    echo "Name: pkg" >> "$tmp_wheel_dir/pkg-1.0.dist-info/METADATA"
    echo "Version: 1.0" >> "$tmp_wheel_dir/pkg-1.0.dist-info/METADATA"

    # Create RECORD file
    touch "$tmp_wheel_dir/pkg-1.0.dist-info/RECORD"
    
    cwd=$(pwd)
    cd "$tmp_wheel_dir"
    zip -q -r "$filename" .
    cd "$cwd"
    rm -rf "$tmp_wheel_dir"
}

# Wheel: Python 3.9, x86_64
WHEEL_NAME="pkg-1.0-cp39-cp39-manylinux2014_x86_64.whl"
TAG="cp39-cp39-manylinux2014_x86_64"
create_dummy_wheel "$WHEEL_NAME" "$TAG"
WHEEL_PATH="$TEST_DIR/wheels/$WHEEL_NAME"

echo "Test 1: Conflict (Wheel=3.9, Arg=3.12)"
set +e
OUT=$("$CLI_TOOL" -w "$WHEEL_PATH" --python-version 3.12 2>&1)
RES=$?
set -e

if [ $RES -ne 0 ] && echo "$OUT" | grep -q "Error: Wheel is for Python 3.9"; then
    echo -e "${GREEN}PASS${NC}: Correctly rejected conflicting version."
else
    echo -e "${RED}FAIL${NC}: Should have rejected conflicting version."
    echo "$OUT"
fi

echo "Test 2: Implicit (No Args)"
set +e
# We expect it to auto-detect 3.9 and x86_64 and try to install.
# Installation will fail because we don't have python 3.9 pip/env setup or dummy wheel is empty.
# But we check the log for "Auto-detected".
OUT=$("$CLI_TOOL" -w "$WHEEL_PATH" -n out.zip 2>&1)
set -e

if echo "$OUT" | grep -q "Detected Python: 3.9"; then
    echo -e "${GREEN}PASS${NC}: Auto-detected Python 3.9"
else
    echo -e "${RED}FAIL${NC}: Failed to detect."
    echo "$OUT"
fi

echo "Test 3: Redundant but Correct Arg"
set +e
OUT=$("$CLI_TOOL" -w "$WHEEL_PATH" --python-version 3.9 --architecture x86_64 2>&1)
RES=$?
set -e

# Checking valid usage doesn't crash on arg check
if [ $RES -eq 0 ]; then
    echo -e "${GREEN}PASS${NC}: Accepted matching argument."
else
    echo -e "${RED}FAIL${NC}: Should have accepted matching argument."
    echo "$OUT"
fi
