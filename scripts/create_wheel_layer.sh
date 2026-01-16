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
# We now track user provided values separate from defaults
USER_PYTHON_VERSION=""
USER_ARCHITECTURE=""
USER_PLATFORM=""

DEFAULT_PYTHON_VERSION="3.12"
DEFAULT_ARCHITECTURE="x86_64"

PYTHON_VERSION="$DEFAULT_PYTHON_VERSION"
ARCHITECTURE="$DEFAULT_ARCHITECTURE"
PLATFORM=""
IMPLEMENTATION="cp"
ABI=""  # Will be calculated

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
                USER_PYTHON_VERSION="$2"
                PYTHON_VERSION="$2"
                shift 2
            else
                printf "${RED}Error: $1 requires an argument${NC}\n"
                exit 1
            fi
            ;;
        --python-version=*)
            USER_PYTHON_VERSION="${1#*=}"
            PYTHON_VERSION="${1#*=}"
            shift
            ;;
        --architecture|-a)
            if [[ -n "${2:-}" && "${2:-}" != -* ]]; then
                USER_ARCHITECTURE="$2"
                ARCHITECTURE="$2"
                shift 2
            else
                printf "${RED}Error: $1 requires an argument${NC}\n"
                exit 1
            fi
            ;;
        --architecture=*)
            USER_ARCHITECTURE="${1#*=}"
            ARCHITECTURE="${1#*=}"
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
  -a, --architecture   Target architecture (x86_64, arm64)

Supported Architectures:
  x86_64 (amd64)       # Standard Intel/AMD 64-bit
  arm64 (aarch64)      # AWS Graviton (ARM 64-bit)

Examples:
  # Build for Amazon Linux 2 (Python 3.12, x86_64)
  ./create_wheel_layer.sh -w mypackage.whl --python-version=3.12

  # Build for ARM64
  ./create_wheel_layer.sh -w mypackage.whl -a arm64
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
# Detect pip
PIP_EXE=""
if command -v pip &> /dev/null; then
    PIP_EXE="pip"
elif command -v pip3 &> /dev/null; then
    PIP_EXE="pip3"
else
    printf "${RED}Error: pip or pip3 not found. Please install Python and pip.${NC}\n"
    exit 1
fi
if [ ! -f "$WHEEL_FILE" ]; then
    printf "${RED}Error: File $WHEEL_FILE not found${NC}\n"
    exit 1
fi

# ------------------------------------------------------------------
# WHEEL METADATA AUTO-DETECTION
# ------------------------------------------------------------------
# Extract metadata directly from filename/wheel to enforce strictness
# Format: Name-Ver-PyTag-AbiTag-PlatTag.whl

DETECTED_PY="any"
DETECTED_ABI="none"
DETECTED_PLAT="any"
DETECTED_ARCH="any"

# Helper python script to parse filename strictly
META_OUT=$(python3 -c "
import sys
import os

filename = os.path.basename(sys.argv[1])
if filename.endswith('.whl'):
    filename = filename[:-4]
    
parts = filename.split('-')
# Minimal check: Name-Ver-Py-Abi-Plat
if len(parts) >= 5:
    plat = parts[-1]
    abi = parts[-2]
    py = parts[-3]
    
    # Arch mapping
    arch = 'any'
    if 'x86_64' in plat or 'amd64' in plat:
        arch = 'x86_64'
    elif 'aarch64' in plat or 'arm64' in plat:
        arch = 'aarch64'
        
    # Py Ver extraction (cp312->3.12)
    py_ver = 'any'
    if py.startswith('cp') and len(py) > 2 and py[2:].isdigit():
        pv_raw = py[2:]
        if len(pv_raw) == 2: # 39
             py_ver = f'{pv_raw[0]}.{pv_raw[1]}'
        elif len(pv_raw) >= 3: # 312
             major = pv_raw[0]
             minor = pv_raw[1:]
             py_ver = f'{major}.{minor}'
    
    print(f'{py_ver}|{arch}|{plat}|{abi}')
else:
    print('any|any|any|none')
" "$WHEEL_FILE")

IFS='|' read -r DET_PY DET_ARCH DET_PLAT DET_ABI <<< "$META_OUT"

# STRICT MODE ENFORCEMENT
# If the wheel is binary (specific architecture or python), we ENFORCE it.
# If the wheel is 'any', we allow defaults or user args.

if [ "$DET_PY" != "any" ]; then
    if [ -n "$USER_PYTHON_VERSION" ] && [ "$USER_PYTHON_VERSION" != "$DET_PY" ]; then
        printf "${RED}Error: Wheel is for Python $DET_PY, but you requested $USER_PYTHON_VERSION.${NC}\n"
        printf "Please remove the argument or use matching version.\n"
        exit 1
    fi
    # Auto-set
    PYTHON_VERSION="$DET_PY"
    printf "Detected Python: $PYTHON_VERSION\n"
fi

if [ "$DET_ARCH" != "any" ]; then
    if [ -n "$USER_ARCHITECTURE" ]; then
        # Normalize user input for comparison
        NORM_USER_ARCH="$USER_ARCHITECTURE"
        if [ "$USER_ARCHITECTURE" == "arm64" ]; then NORM_USER_ARCH="aarch64"; fi
        if [ "$USER_ARCHITECTURE" == "amd64" ]; then NORM_USER_ARCH="x86_64"; fi
        
        if [ "$NORM_USER_ARCH" != "$DET_ARCH" ]; then
             printf "${RED}Error: Wheel is for $DET_ARCH, but you requested $USER_ARCHITECTURE.${NC}\n"
             exit 1
        fi
    fi
    # Auto-set
    ARCHITECTURE="$DET_ARCH" 
    printf "Detected Architecture: $ARCHITECTURE\n"
fi

if [ "$DET_PLAT" != "any" ] && [ -z "$USER_PLATFORM" ]; then
    # Only override platform if user didn't specify one (pip might need specific one)
    # But usually filename platform is correct for install
    PLATFORM="$DET_PLAT"
fi

if [ "$DET_ABI" != "none" ]; then
    ABI="$DET_ABI"
fi

# Normalize Architecture
AWS_ARCH="$ARCHITECTURE"
if [ "$ARCHITECTURE" = "arm64" ] || [ "$ARCHITECTURE" = "aarch64" ]; then
    ARCHITECTURE="aarch64"
    AWS_ARCH="arm64"
elif [ "$ARCHITECTURE" = "amd64" ] || [ "$ARCHITECTURE" = "x86_64" ]; then
    ARCHITECTURE="x86_64"
    AWS_ARCH="x86_64"
fi

# Determine Platform if still empty
if [ -z "$PLATFORM" ]; then
    # Default to manylinux2014 as it is safe for both AL2 and AL2023
    PLATFORM="manylinux2014_${ARCHITECTURE}"
fi


# Validate Wheel Suitability for Lambda (Linux) using metadata
printf "Validating wheel compatibility...\n"

# Only run python validation if python is available (it should be, given pip is used)
PYTHON_EXE=""
if command -v python3 &> /dev/null; then
    PYTHON_EXE="python3"
elif command -v python &> /dev/null; then
    PYTHON_EXE="python"
fi

if [ -n "$PYTHON_EXE" ]; then
    # Use Python to inspect the WHEEL metadata for accurate tags
    $PYTHON_EXE -c "
import sys, zipfile, os

try:
    wheel_path = sys.argv[1]
    target_arch = sys.argv[2]
    
    # Define compatibility
    compatible_os = ['manylinux', 'linux', 'any']
    
    arch_map = {
        'x86_64': ['x86_64', 'amd64', 'any'],
        'arm64': ['aarch64', 'arm64', 'any'],
        'aarch64': ['aarch64', 'arm64', 'any']
    }
    
    with zipfile.ZipFile(wheel_path, 'r') as z:
        # Find .dist-info/WHEEL
        wheel_files = [f for f in z.namelist() if f.endswith('.dist-info/WHEEL')]
        if not wheel_files:
            # Fallback for old wheels without WHEEL metadata (rare)
            print('Warning: No .dist-info/WHEEL found, skipping strict validation.')
            sys.exit(0)
            
        content = z.read(wheel_files[0]).decode('utf-8')
        tags = []
        for line in content.splitlines():
            if line.startswith('Tag:'):
                tags.append(line.split(':', 1)[1].strip())
        
        has_linux = False
        has_arch = False
        detected_plats = set()
        
        for tag in tags:
            parts = tag.split('-')
            if len(parts) >= 3:
                plat = parts[2]
                detected_plats.add(plat)
                
                # Check OS
                if any(x in plat for x in compatible_os):
                    has_linux = True
                
                # Check Arch
                target_valid_archs = arch_map.get(target_arch, [])
                
                # Special handling for 'any' to avoid matching 'manylinux'
                if plat == 'any' and 'any' in target_valid_archs:
                    has_arch = True
                else:
                    # Filter out 'any' from search strings for substring check
                    search_archs = [x for x in target_valid_archs if x != 'any']
                    if any(x in plat for x in search_archs):
                        has_arch = True

        if not has_linux:
            print(f'Error: Wheel is not compatible with Linux.\nDetected platforms: {', '.join(sorted(detected_plats))}')
            sys.exit(1)
            
        if not has_arch:
            print(f'Error: Wheel architecture mismatch.\nTarget: {target_arch}\nDetected platforms: {', '.join(sorted(detected_plats))}')
            sys.exit(1)
            
except Exception as e:
    print(f'Warning: Could not validate wheel metadata: {e}')
    sys.exit(0) # Don't block build if validation script itself crashes
" "$WHEEL_FILE" "$ARCHITECTURE"

    # Check exit code of python script
    if [ $? -ne 0 ]; then
        exit 1
    fi
else
    # Fallback to simple filename check if python not found (unlikely)
    WHEEL_BASENAME=$(basename "$WHEEL_FILE")
    if [[ "$WHEEL_BASENAME" == *"macosx"* ]] || [[ "$WHEEL_BASENAME" == *"win32"* ]]; then
         printf "${YELLOW}Warning: Filename suggests non-Linux wheel ($WHEEL_BASENAME)${NC}\n"
    fi
fi

# Determine ABI tag (If not auto-detected)
# e.g., 3.12 -> cp312, 3.10 -> cp310
if [ -z "$ABI" ] || [ "$ABI" == "none" ]; then
    PY_MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
    PY_MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)
    ABI="cp${PY_MAJOR}${PY_MINOR}"
fi

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
printf "Target Architecture: $AWS_ARCH\n"
printf "Platform Tag: $PLATFORM\n"
printf "Python: $PYTHON_VERSION (ABI: $ABI)\n"

mkdir -p "$LAYER_DIR/python"

# Install
printf "${GREEN}Installing packages...${NC}\n"
CMD=("$PIP_EXE" "install" "$WHEEL_FILE")

if [ -n "$PACKAGES" ]; then
    # Replace commas with spaces
    PKG_SPACE=$(echo "$PACKAGES" | tr ',' ' ')
    # Split into array
    read -ra PKG_ARRAY <<< "$PKG_SPACE"
    CMD+=("${PKG_ARRAY[@]}")
fi

CMD+=("--target" "$LAYER_DIR/python")

# Handle multiple platform tags (e.g. manylinux1_x86_64.linux_x86_64)
# Split by dot and add each as separate --platform argument
IFS='.' read -ra PLAT_TAGS <<< "$PLATFORM"
for tag in "${PLAT_TAGS[@]}"; do
    CMD+=("--platform" "$tag")
done

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

# Handle absolute vs relative path for LAYER_NAME
ZIP_DEST="$LAYER_NAME"
if [[ "$LAYER_NAME" != /* ]]; then
    ZIP_DEST="$ORIGINAL_DIR/$LAYER_NAME"
fi

if zip -r "$ZIP_DEST" python > /dev/null; then
    printf "${GREEN}✅ Done! Created $LAYER_NAME${NC}\n"
    printf "File: $(basename "$LAYER_NAME")\n"
else
    printf "${RED}Error creating zip file at $ZIP_DEST${NC}\n"
    cd "$ORIGINAL_DIR"
    rm -rf "$LAYER_DIR"
    exit 1
fi

cd "$ORIGINAL_DIR"
rm -rf "$LAYER_DIR"
