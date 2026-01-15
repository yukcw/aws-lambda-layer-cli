#!/bin/bash

# Python Lambda Layer Creator from Wheel
# Usage:
#   ./create_wheel_layer.sh -w mypackage.whl
#   ./create_wheel_layer.sh -w mypackage.whl -i "pandas,boto3" -n my-layer.zip

set -e
set -u

# Default values
WHEEL_FILE=""
PACKAGES=""
LAYER_NAME=""
PYTHON_VERSION="3.12"
PLATFORM="manylinux2014_x86_64"
IMPLEMENTATION="cp"
ABI="cp312"  # Default ABI tag

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -w|--wheel)
            if [[ -n "${2:-}" && "${2:-}" != -* ]]; then
                WHEEL_FILE="$2"
                shift 2
            else
                printf "${RED}Error: $1 requires an argument${NC}\n"
                exit 1
            fi
            ;;
        --wheel=*)
            WHEEL_FILE="${1#*=}"
            shift
            ;;
        -i|--packages)
            if [[ -n "${2:-}" && "${2:-}" != -* ]]; then
                PACKAGES="$2"
                shift 2
            else
                printf "${RED}Error: $1 requires an argument${NC}\n"
                exit 1
            fi
            ;;
        --packages=*)
            PACKAGES="${1#*=}"
            shift
            ;;
        -n|--name)
            if [[ -n "${2:-}" && "${2:-}" != -* ]]; then
                LAYER_NAME="$2"
                shift 2
            else
                printf "${RED}Error: $1 requires an argument${NC}\n"
                exit 1
            fi
            ;;
        --name=*)
            LAYER_NAME="${1#*=}"
            shift
            ;;
        --python-version)
            if [[ -n "${2:-}" && "${2:-}" != -* ]]; then
                PYTHON_VERSION="$2"
                shift 2
            else
                printf "${RED}Error: $1 requires an argument${NC}\n"
                exit 1
            fi
            ;;
        --python-version=*)
            PYTHON_VERSION="${1#*=}"
            shift
            ;;
        --platform)
            if [[ -n "${2:-}" && "${2:-}" != -* ]]; then
                PLATFORM="$2"
                shift 2
            else
                printf "${RED}Error: $1 requires an argument${NC}\n"
                exit 1
            fi
            ;;
        --platform=*)
            PLATFORM="${1#*=}"
            shift
            ;;
        -h|--help)
            cat << 'EOF'
Usage: ./create_wheel_layer.sh -w <wheel_file> [-i <packages>] [-n <zip_name>]

Options:
  -w, --wheel          Path to .whl file
  -i, --packages       Additional packages (comma or space separated)
  -n, --name           Output zip filename
  --python-version     Target Python version (default: 3.12)
  --platform           Target platform (default: manylinux2014_x86_64)

Supported Platforms:
  manylinux2014_x86_64    # Amazon Linux 2, RHEL 7+ (older)
  manylinux2014_aarch64   # ARM64 architecture
  manylinux_2_28_x86_64   # Amazon Linux 2023, RHEL 8+ (newer)
  manylinux_2_28_aarch64  # ARM64 with newer glibc
  linux_x86_64            # Generic Linux
  linux_aarch64           # Generic ARM64 Linux

Python Version Support:
  3.8, 3.9, 3.10, 3.11, 3.12, 3.13, 3.14

Examples:
  # Build for Amazon Linux 2 (Python 3.12)
  ./create_wheel_layer.sh -w mypackage.whl --python-version=3.12 --platform=manylinux2014_x86_64

  # Build for Amazon Linux 2023 (Python 3.13)
  ./create_wheel_layer.sh -w mypackage.whl --python-version=3.13 --platform=manylinux_2_28_x86_64

  # Build with additional packages for ARM64
  ./create_wheel_layer.sh -w mypackage.whl -i "numpy,pandas" --platform=manylinux_2_28_aarch64
EOF
            exit 0
            ;;
        *)
            printf "${RED}Unknown option: $1${NC}\n"
            exit 1
            ;;
    esac
done

# Validation
if [ -z "$WHEEL_FILE" ]; then
    printf "${RED}Error: Wheel file is required (-w)${NC}\n"
    exit 1
fi

if [ ! -f "$WHEEL_FILE" ]; then
    printf "${RED}Error: File $WHEEL_FILE not found${NC}\n"
    exit 1
fi

# Determine ABI tag based on Python version
PY_MAJOR_MINOR=$(echo "$PYTHON_VERSION" | sed 's/\([0-9]\+\)\.\([0-9]\+\).*/\1\2/')
ABI="cp${PY_MAJOR_MINOR}"

if [ -z "$LAYER_NAME" ]; then
    BASENAME=$(basename "$WHEEL_FILE" .whl)
    LAYER_NAME="${BASENAME}_layer.zip"
fi

# Setup workspace
LAYER_DIR="layer_build_$(date +%s)"
ORIGINAL_DIR=$(pwd)

# Convert relative paths to absolute
if [[ "$WHEEL_FILE" != /* ]]; then
    WHEEL_FILE="$ORIGINAL_DIR/$WHEEL_FILE"
fi

printf "${GREEN}Creating Lambda layer from wheel...${NC}\n"
printf "Wheel: $WHEEL_FILE\n"
if [ -n "$PACKAGES" ]; then
    printf "Extra Packages: $PACKAGES\n"
fi
printf "Platform: $PLATFORM\n"
printf "Python: $PYTHON_VERSION\n"

mkdir -p "$LAYER_DIR/python"

# Install
printf "${GREEN}Installing packages...${NC}\n"
CMD=("pip" "install" "$WHEEL_FILE")

if [ -n "$PACKAGES" ]; then
    # Replace commas with spaces
    PKG_SPACE=$(echo "$PACKAGES" | tr ',' ' ')
    # Split into array
    read -ra PKG_ARRAY <<< "$PKG_SPACE"
    CMD+=("${PKG_ARRAY[@]}")
fi

CMD+=("--target" "$LAYER_DIR/python")
CMD+=("--platform" "$PLATFORM")
CMD+=("--implementation" "$IMPLEMENTATION")
CMD+=("--python-version" "$PYTHON_VERSION")
CMD+=("--abi" "$ABI")
CMD+=("--only-binary=:all:")
CMD+=("--upgrade")

echo "Running: ${CMD[*]}"
if ! "${CMD[@]}"; then
    printf "${RED}Installation failed${NC}\n"
    rm -rf "$LAYER_DIR"
    exit 1
fi

# Cleanup
printf "${GREEN}Removing cache and metadata...${NC}\n"
find "$LAYER_DIR" -type d -name "__pycache__" -exec rm -rf {} +
# Removing dist-info might break some packages (entry points, metadata), but user requested space saving
# Making it optional or just following user's script. Following user script:
find "$LAYER_DIR" -type d -name "*.dist-info" -exec rm -rf {} +

# Zip
printf "${GREEN}Zipping to $LAYER_NAME...${NC}\n"
cd "$LAYER_DIR"
if zip -r "$ORIGINAL_DIR/$LAYER_NAME" python > /dev/null; then
    printf "${GREEN}✅ Done! Created $LAYER_NAME${NC}\n"
else
    printf "${RED}Error creating zip file${NC}\n"
    cd "$ORIGINAL_DIR"
    rm -rf "$LAYER_DIR"
    exit 1
fi

cd "$ORIGINAL_DIR"
rm -rf "$LAYER_DIR"
