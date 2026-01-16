#!/bin/bash

# Test: Wheel Validation Logic (Feature Coverage)
# 
# Features Tested:
# 1. Check if wheel compat to Amazon Linux
# 2. Check if wheel compat to given architecture
# 3. Tool detect architecture if passed test
# 4. Reject by filename (Implicit via standard file rejection)
# 5. Reject by meta-data in wheel (Renamed file checks)

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# OVERRIDE CLI_TOOL to point to the specific script we are testing
CLI_TOOL="$REPO_ROOT/scripts/create_wheel_layer.sh"

setup_common

WHEEL_DIR="$TEST_DIR/wheels"
# Update JSON Path to match the previously identified location
JSON_FILE="$REPO_ROOT/test/numpy_wheel_list.json"
mkdir -p "$WHEEL_DIR"

# Ensure pip is available (Mock or Real)
if ! command -v pip &> /dev/null; then
    if command -v pip3 &> /dev/null; then
        pip() { python3 -m pip "$@"; }
        export -f pip
    else
        echo "Error: pip not found. Test needs pip to simulate installation."
        exit 1
    fi
fi
export PATH="$PATH:$HOME/.local/bin"

# ------------------------------------------------------------------
# Helper: Create Dummy Wheel with specific metadata
# ------------------------------------------------------------------
create_dummy_wheel() {
    local name=$1
    local tag=$2
    local filename="$WHEEL_DIR/$name"
    
    # Create temp structure
    local tmp_wheel_dir="$WHEEL_DIR/temp_$(echo "$name" | tr -cd 'a-zA-Z0-9')"
    mkdir -p "$tmp_wheel_dir/dummy_pkg-${name%%-*}.dist-info"
    
    # Create WHEEL metadata
    cat > "$tmp_wheel_dir/dummy_pkg-${name%%-*}.dist-info/WHEEL" <<END
Wheel-Version: 1.0
Generator: test
Root-Is-Purelib: false
Tag: $tag
END

    # Create dummy module
    touch "$tmp_wheel_dir/dummy_pkg.py"
    
    # Zip it
    cwd=$(pwd)
    cd "$tmp_wheel_dir"
    zip -q -r "$filename" .
    cd "$cwd"
    rm -rf "$tmp_wheel_dir"
}

# ------------------------------------------------------------------
# Main Test Function
# ------------------------------------------------------------------
run_test_case() {
    local filename=$1
    local target_arch=$2
    local expected=$3 # PASS or FAIL
    local extracted_tag=$4
    local case_description=$5
    local py_ver=${6:-"3.12"}

    # Generate dummy wheel if not exists
    if [ ! -f "$WHEEL_DIR/$filename" ]; then
        create_dummy_wheel "$filename" "$extracted_tag"
    fi

    local output_file="$TEST_DIR/output_${filename}_${target_arch}.log"
    
    # Run CLI (Dry run / Validation only via create_wheel_layer)
    set +e
    bash "$CLI_TOOL" \
        -w "$WHEEL_DIR/$filename" \
        -a "$target_arch" \
        --python-version "$py_ver" > "$output_file" 2>&1
    local exit_code=$?
    set -e

    # Analyze result logic
    local valid_failed=0
    local failure_reason=""
    
    if grep -q "Error: Wheel is not compatible with Linux" "$output_file"; then 
        valid_failed=1
        failure_reason="OS_INCOMPATIBLE"
    fi
    if grep -q "Error: Wheel architecture mismatch" "$output_file"; then 
        valid_failed=1
        failure_reason="ARCH_MISMATCH"
    fi
    if grep -q "Error: Wheel is for .* but you requested" "$output_file"; then
        valid_failed=1
        failure_reason="STRICT_ARCH_MISMATCH"
    fi

    local feature_note=""
    local color_start=""
    local color_end=""
    local result_text=""

    if [ "$expected" == "FAIL" ]; then
        if [ $valid_failed -eq 1 ]; then
            color_start="${GREEN}"
            color_end="${NC}"
            result_text="PASS (Rejected)"
            if [ "$failure_reason" == "OS_INCOMPATIBLE" ]; then feature_note="F1, F4"; fi
            if [ "$failure_reason" == "ARCH_MISMATCH" ]; then feature_note="F2"; fi
            if [ "$failure_reason" == "STRICT_ARCH_MISMATCH" ]; then feature_note="F2"; fi
        else
            color_start="${RED}"
            color_end="${NC}"
            result_text="FAIL (Accepted)"
            echo ""
            echo "--- LOG for $filename ($target_arch) ---"
            cat "$output_file"
            echo "--- END LOG ---"
        fi
    else
        # EXPECT PASS
        if [ $valid_failed -eq 0 ]; then
            color_start="${GREEN}"
            color_end="${NC}"
            result_text="PASS (Accepted)"
            feature_note="F3 (Verified)" 
        else
            color_start="${RED}"
            color_end="${NC}"
            result_text="FAIL (Rejected)"
        fi
    fi
    
    # Use %b for colors so they don't interfere with column width calculation and are interpreted correctly
    printf "| %-55s | %-8s | %b%-25s%b | %-15s |\n" "${filename:0:55}" "$target_arch" "$color_start" "$result_text" "$color_end" "$feature_note"
}

# ------------------------------------------------------------------
# Execution
# ------------------------------------------------------------------

echo "=== Wheel Validation Feature Test Suite ==="
echo "Features:"
echo "  [F1] Compat to Amazon Linux"
echo "  [F2] Compat to Architecture"
echo "  [F3] Detect Architecture/Validity"
echo "  [F4] Filename check (Implicit)"
echo "  [F5] Metadata check (Deep validation)"
echo ""

printf "| %-55s | %-8s | %-25s | %-15s |\n" "Wheel File" "Target" "Result" "Features"
printf "|-%-55s-|-%-8s-|-%-25s-|-%-15s-|\n" "-------------------------------------------------------" "--------" "-------------------------" "---------------"

# 1. Bulk JSON Test
python3 -c "
import json
import sys

try:
    with open('$JSON_FILE', 'r') as f:
        wheels = json.load(f)
    
    for w in wheels:
        url = w['url']
        filename = url.split('/')[-1]
        
        # Tag parsing
        parts = filename[:-4].split('-')
        if len(parts) < 5: 
            tag = 'py3-none-any'
            py_ver = '3.12'
        else: 
            tag = '-'.join(parts[-3:])
            py_tag = parts[-3]
            py_ver = '3.12'
            if py_tag.startswith('cp') and py_tag[2:].isdigit():
                 ver_str = py_tag[2:]
                 if len(ver_str) == 2: py_ver = f'{ver_str[0]}.{ver_str[1]}' # 39 -> 3.9
                 elif len(ver_str) >= 3: py_ver = f'{ver_str[0]}.{ver_str[1:]}' # 313 -> 3.13
        
        is_linux = 'manylinux' in filename or 'musllinux' in filename or 'linux' in filename
        is_x86 = 'x86_64' in filename or 'amd64' in filename
        is_arm = 'aarch64' in filename or 'arm64' in filename
        
        # Test Case 1: Target x86_64
        expect_x86 = 'PASS' if (is_linux and is_x86) else 'FAIL'
        print(f'{filename}|x86_64|{expect_x86}|{tag}|Standard validity check|{py_ver}')

        # Test Case 2: Target arm64
        expect_arm = 'PASS' if (is_linux and is_arm) else 'FAIL'
        print(f'{filename}|arm64|{expect_arm}|{tag}|Standard validity check|{py_ver}')

except Exception as e:
    sys.exit(1)
" | while IFS='|' read -r filename target expected tag desc py_ver; do
    if [ -z "$filename" ]; then continue; fi
    run_test_case "$filename" "$target" "$expected" "$tag" "$desc" "$py_ver"
done

echo ""
echo "=== Feature 5: Reject by Metadata (Renaming Attack) ==="
MAC_WHEEL_NAME="numpy-2.4.1-cp313-cp313-macosx_10_13_x86_64.whl"
FAKE_LINUX_NAME="numpy-2.4.1-cp313-cp313-manylinux_2_27_x86_64.whl"
MAC_TAG="cp313-cp313-macosx_10_13_x86_64"

printf "| %-55s | %-8s | %-25s | %-15s |\n" "Renamed 'checks' (Mac->Linux Name)" "x86_64" "..." "F5"
create_dummy_wheel "$FAKE_LINUX_NAME" "$MAC_TAG"
run_test_case "$FAKE_LINUX_NAME" "x86_64" "FAIL" "$MAC_TAG" "Renamed Metadata Check" "3.13"

echo ""
echo "=== Feature 3: Tool Detect Architecture ==="
VALID_WHEEL="numpy-2.4.1-cp313-cp313-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl"
TAG="cp313-cp313-manylinux_2_27_x86_64.manylinux_2_28_x86_64"

create_dummy_wheel "$VALID_WHEEL" "$TAG"
OUT_LOG="$TEST_DIR/detect_test.log"
set +e
bash "$CLI_TOOL" -w "$WHEEL_DIR/$VALID_WHEEL" -a "x86_64" --python-version 3.13 > "$OUT_LOG" 2>&1
set -e

if grep -q "Detected platforms:" "$OUT_LOG" || grep -q "Platform Tag:" "$OUT_LOG"; then
    echo -e "${GREEN}PASS${NC}: Tool output confirms detection/processing."
else
    echo -e "${RED}FAIL${NC}: Tool did not output detection details."
    cat "$OUT_LOG"
fi
