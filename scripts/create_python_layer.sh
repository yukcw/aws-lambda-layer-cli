#!/bin/bash

# Python Lambda Layer Creator with version specification
# Usage:
#   ./create_python_layer.sh -i numpy==1.26.0,pandas==2.1.3
#   ./create_python_layer.sh -i numpy==1.26.0,pandas,boto3==1.34.0 -n my-layer.zip
#   ./create_python_layer.sh --packages=requests==2.31.0,boto3

set -e  # Exit on error
set -u  # Treat unset variables as errors

# Generate unique temporary directory
TEMP_DIR=$(mktemp -d)
WORK_DIR="$TEMP_DIR/layer-build"

# Default values
PACKAGES=""
LAYER_NAME=""
PYTHON_VERSION="3.14"  # Default to Python 3.14
PYTHON_VERSION_SPECIFIED=false
VENV_DIR="python"
ORIGINAL_DIR=$(pwd)
PLATFORM=""  # Optional platform targeting
IMPLEMENTATION="cp"
ABI=""
ARCHITECTURE="x86_64"  # Default architecture

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Security functions
sanitize_filename() {
    local filename="$1"
    # Remove dangerous characters: /, \, :, |, <, >, ?, *, ", ', `, $, (, ), {, }, ;, &, !
    filename=$(echo "$filename" | sed 's/[\/\\:|<>?*"\`$(){};&!]//g')
    # Remove leading/trailing dots and hyphens
    filename=$(echo "$filename" | sed 's/^[.-]*//' | sed 's/[.-]*$//')
    # Limit length
    echo "${filename:0:100}"
}

validate_python_version() {
    local version="$1"
    # Allow only numbers and dots in Python version (e.g., 3.9, 3.14.2)
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
        printf "${RED}Error: Invalid Python version format: $version${NC}\n"
        printf "Python version must be in format X.Y or X.Y.Z (e.g., 3.14, 3.14.2)\n"
        exit 1
    fi
}

escape_package_name() {
    local pkg="$1"
    # Whitelist for Python: A-Za-z0-9._- (with version operators: = > < ~ !)
    # FIXED: Place hyphen at the end of character class to avoid regex range interpretation
    echo "$pkg" | sed 's/[^A-Za-z0-9._=><~!+-]//g'
}

# Extract base package name from version specification
# Example: numpy==1.26.0 -> numpy
# Example: requests>=2.31.0 -> requests
extract_package_name() {
    local pkg="$1"
    # Remove version specification operators and everything after
    echo "$pkg" | sed 's/[=<>!~].*$//'
}

# Extract version specification from package string
# Example: numpy==1.26.0 -> ==1.26.0
# Example: requests>=2.31.0 -> >=2.31.0
extract_version_spec() {
    local pkg="$1"
    if [[ "$pkg" =~ [\=\<\>!~] ]]; then
        echo "$pkg" | grep -o '[=<>!~].*' || echo ""
    else
        echo ""
    fi
}

# Cleanup function
cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}

# Trap to ensure cleanup on exit
trap cleanup EXIT

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|--packages)
            if [[ -n "${2:-}" && "${2:-}" != -* ]]; then
                PACKAGES="$2"
                shift 2
            else
                printf "${RED}Error: $1 requires an argument${NC}\n"
                printf "Example: $1 numpy==1.26.0,requests\n"
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
                printf "Example: $1 my-python-layer.zip\n"
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
                PYTHON_VERSION_SPECIFIED=true
                validate_python_version "$PYTHON_VERSION"
                shift 2
            else
                printf "${RED}Error: $1 requires an argument${NC}\n"
                printf "Example: $1 3.14\n"
                exit 1
            fi
            ;;
        --python-version=*)
            PYTHON_VERSION="${1#*=}"
            PYTHON_VERSION_SPECIFIED=true
            validate_python_version "$PYTHON_VERSION"
            shift
            ;;
        -a|--architecture)
            if [[ -n "${2:-}" && "${2:-}" != -* ]]; then
                ARCHITECTURE="$2"
                shift 2
            else
                printf "${RED}Error: $1 requires an argument${NC}\n"
                printf "Example: $1 arm64\n"
                exit 1
            fi
            ;;
        --architecture=*)
            ARCHITECTURE="${1#*=}"
            shift
            ;;
        -h|--help)
            cat << 'EOF'
Python Lambda Layer Creator

Usage:
  ./create_python_layer.sh -i numpy==1.26.0,pandas==2.1.3
  ./create_python_layer.sh --packages=numpy==1.26.0,pandas,boto3==1.34.0 -n my-layer.zip

Options:
  -i, --packages        Comma-separated list of Python packages (with optional versions)
  -n, --name            Name of the output zip file
  --python-version      Python version (default: 3.14)
  -a, --architecture    Target architecture (x86_64 or arm64, default: x86_64)
  -h, --help            Show this help message

Version Specification:
  Package versions can be specified using standard Python version specifiers:
    numpy==1.26.0               # Exact version
    pandas>=2.1.0               # Greater than or equal
    requests>2.30.0             # Greater than
    scipy<=1.11.0               # Less than or equal
    tensorflow~=2.15.0          # Compatible release
    Django!=3.2.0               # Version exclusion

Examples:
  # Basic usage
  ./create_python_layer.sh -i numpy==1.26.0

  # With platform targeting for Amazon Linux 2023
  ./create_python_layer.sh -i requests==2.31.0,boto3==1.34.0 --python-version=3.13 --platform=manylinux_2_28_x86_64

  # With platform targeting for ARM64
  ./create_python_layer.sh --packages=pandas==2.1.3,scikit-learn==1.3.0 --platform=manylinux_2_28_aarch64 -n ml-layer.zip
EOF
            exit 0
            ;;
        *)
            printf "${RED}Unknown option: $1${NC}\n"
            printf "Use -h or --help for usage information\n"
            exit 1
            ;;
    esac
done

# Check if packages are provided
if [ -z "$PACKAGES" ]; then
    printf "${RED}Error: Packages argument is required${NC}\n"
    printf "Use -i or --packages to specify packages (comma-separated)\n"
    printf "Example: ./create_python_layer.sh -i numpy==1.26.0,requests\n"
    exit 1
fi

# Check dependencies
if ! command -v zip &> /dev/null; then
    printf "${RED}Error: 'zip' command is not installed${NC}\n"
    exit 1
fi

if ! command -v python3 &> /dev/null && ! command -v python &> /dev/null; then
    printf "${RED}Error: 'python' command is not installed${NC}\n"
    exit 1
fi

# Sanitize packages input using whitelist
SANITIZED_PACKAGES=""
IFS=',' read -ra PACKAGE_ARRAY <<< "$PACKAGES"
for pkg in "${PACKAGE_ARRAY[@]}"; do
    # Trim whitespace
    pkg=$(echo "$pkg" | xargs)
    # Escape package name using whitelist
    escaped_pkg=$(escape_package_name "$pkg")
    if [ -n "$escaped_pkg" ]; then
        SANITIZED_PACKAGES="${SANITIZED_PACKAGES}${SANITIZED_PACKAGES:+,}$escaped_pkg"
    else
        printf "${YELLOW}Warning: Package name '$pkg' contains no valid characters after sanitization${NC}\n"
    fi
done

if [ -z "$SANITIZED_PACKAGES" ]; then
    printf "${RED}Error: No valid packages provided after sanitization${NC}\n"
    exit 1
fi

# Check if any package names were changed
if [ "$PACKAGES" != "$SANITIZED_PACKAGES" ]; then
    printf "${YELLOW}Warning: Some package names were sanitized:${NC}\n"
    printf "  Original: $PACKAGES\n"
    printf "  Sanitized: $SANITIZED_PACKAGES\n"
    PACKAGES="$SANITIZED_PACKAGES"
fi

# Normalize Architecture
AWS_ARCH="$ARCHITECTURE"
if [ "$ARCHITECTURE" = "arm64" ]; then
    ARCHITECTURE="aarch64"
    AWS_ARCH="arm64"
elif [ "$ARCHITECTURE" = "amd64" ]; then
    ARCHITECTURE="x86_64"
    AWS_ARCH="x86_64"
elif [ "$ARCHITECTURE" = "x86_64" ]; then
    AWS_ARCH="x86_64"
elif [ "$ARCHITECTURE" = "aarch64" ]; then
    AWS_ARCH="arm64"
fi

printf "${BLUE}=========================================${NC}\n"
printf "${GREEN}Python Lambda Layer Creator${NC}\n"
printf "${BLUE}=========================================${NC}\n"
printf "Packages: $PACKAGES\n"
printf "Python version: $PYTHON_VERSION\n"
printf "Target Architecture: $AWS_ARCH\n"
if [ -n "$PLATFORM" ]; then
    printf "Platform: $PLATFORM\n"
fi
if [ -n "$LAYER_NAME" ]; then
    printf "Output name: $LAYER_NAME\n"
fi
printf "\n"

# Step 1: Create working directory
printf "[1/7] Creating directory structure...\n"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Step 2: Create virtual environment
printf "[2/7] Creating virtual environment...\n"

TARGET_PYTHON="python${PYTHON_VERSION}"

# Check if target python exists
if ! command -v "$TARGET_PYTHON" >/dev/null 2>&1; then
    if [ "$PYTHON_VERSION_SPECIFIED" = false ]; then
        printf "${YELLOW}Warning: Default $TARGET_PYTHON not found. Checking for fallback...${NC}\n"
        if command -v python3 >/dev/null 2>&1 && python3 -V >/dev/null 2>&1; then
            TARGET_PYTHON="python3"
        elif command -v python >/dev/null 2>&1 && python -V >/dev/null 2>&1; then
            TARGET_PYTHON="python"
        else
             printf "${RED}Error: No python interpreter found${NC}\n"
             exit 1
        fi
        
        # Update PYTHON_VERSION to match the fallback
        DETECTED_VER=$($TARGET_PYTHON -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
        printf "${YELLOW}Falling back to $TARGET_PYTHON ($DETECTED_VER)${NC}\n"
        PYTHON_VERSION="$DETECTED_VER"
    fi
fi

printf "  Using venv module...\n"
if command -v "$TARGET_PYTHON" >/dev/null 2>&1; then
    "$TARGET_PYTHON" -m venv "$VENV_DIR"
else
    printf "${RED}Error: $TARGET_PYTHON not found${NC}\n"
    exit 1
fi

# Activate virtual environment
set +u
if [ -f "$VENV_DIR/Scripts/activate" ]; then
    source "$VENV_DIR/Scripts/activate"
elif [ -f "$VENV_DIR/bin/activate" ]; then
    source "$VENV_DIR/bin/activate"
else
    printf "${RED}Error: Cannot find activation script in $VENV_DIR${NC}\n"
    exit 1
fi
set -u

# Step 3: Install packages with versions
printf "[3/7] Installing packages...\n"

# Auto-detect platform if not specified
if [ -z "$PLATFORM" ]; then
    # Calculate major/minor version
    # PYTHON_VERSION is like 3.14 or 3.14.2
    PY_VER_MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
    PY_VER_MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)
    
    # Platform selection based on AWS Lambda Runtime
    if [ "$PY_VER_MAJOR" -eq 3 ] && [ "$PY_VER_MINOR" -ge 12 ]; then
        # Python 3.12+ runs on Amazon Linux 2023 (GLIBC 2.34)
        # We use manylinux_2_28 (GLIBC 2.28) which is well-supported
        PLATFORM_PREFIX="manylinux_2_28"
        printf "  Targeting Amazon Linux 2023 (Python $PYTHON_VERSION)\n"
    else
        # Python 3.11- runs on Amazon Linux 2 (GLIBC 2.26)
        # We use manylinux2014 (GLIBC 2.17) for max compatibility
        PLATFORM_PREFIX="manylinux2014"
        printf "  Targeting Amazon Linux 2 (Python $PYTHON_VERSION)\n"
    fi
    
    PLATFORM="${PLATFORM_PREFIX}_${ARCHITECTURE}"
    printf "Auto-detected platform: $PLATFORM (Python $PYTHON_VERSION, Arch $ARCHITECTURE)\n"
fi

# Prepare platform-specific options
INSTALL_OPTS=()
if [ -n "$PLATFORM" ]; then
    # Calculate ABI tag based on Python version (e.g., 3.12 -> cp312)
    # We use cut instead of potentially fragile regex
    PY_MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
    PY_MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)
    ABI="cp${PY_MAJOR}${PY_MINOR}"
    
    INSTALL_OPTS+=("--platform" "$PLATFORM")
    INSTALL_OPTS+=("--implementation" "$IMPLEMENTATION")
    INSTALL_OPTS+=("--python-version" "$PYTHON_VERSION")
    INSTALL_OPTS+=("--abi" "$ABI")
    INSTALL_OPTS+=("--only-binary=:all:")
    printf "  Using platform-specific installation: $PLATFORM\n"
    printf "  ABI tag: $ABI\n"
fi

printf "  Installing with pip...\n"
# Convert to array for safe expansion
IFS=',' read -ra PKG_ARRAY <<< "$PACKAGES"
if [ ${#INSTALL_OPTS[@]} -gt 0 ]; then
    # When using platform specific options, we must specify --target
    # We use the site-packages directory of the current venv
    SITE_PACKAGES=$(python -c "import site; print(site.getsitepackages()[0])")
    printf "  Targeting site-packages: $SITE_PACKAGES\n"
    CMD=(pip install "${PKG_ARRAY[@]}" "${INSTALL_OPTS[@]}" --target "$SITE_PACKAGES")
    echo "  Running: ${CMD[*]}"
    "${CMD[@]}"
else
    CMD=(pip install "${PKG_ARRAY[@]}")
    echo "  Running: ${CMD[*]}"
    "${CMD[@]}"
fi

# Count packages from command argument
PACKAGE_COUNT=$(echo "$PACKAGES" | tr ',' '\n' | wc -l | tr -d ' ')

# Step 4: Determine layer name
printf "[4/7] Determining layer name...\n"
if [ -z "$LAYER_NAME" ]; then
    if [ "$PACKAGE_COUNT" -eq 1 ]; then
        PKG_FULL="$PACKAGES"
        PKG_NAME=$(extract_package_name "$PKG_FULL")
        VERSION_SPEC=$(extract_version_spec "$PKG_FULL")
        
        printf "  Single package: $PKG_NAME\n"
        
        # Extract version from installed package
        PKG_INFO=$(pip show "$PKG_NAME" 2>/dev/null || true)
        
        if [ -n "$PKG_INFO" ]; then
            # Use safer extraction methods
            INSTALLED_VERSION=$(echo "$PKG_INFO" | grep -E '^Version:' | head -1 | awk '{print $2}')
            
            if [ -z "$INSTALLED_VERSION" ]; then
                INSTALLED_VERSION=$(echo "$PKG_INFO" | grep -E '^version:' | head -1 | awk '{print $2}')
            fi
            
            if [ -z "$INSTALLED_VERSION" ]; then
                INSTALLED_VERSION=$(echo "$PKG_INFO" | grep -i '^version[[:space:]]*:' | head -1 | awk '{print $2}')
            fi
            
            if [ -n "$INSTALLED_VERSION" ]; then
                # Sanitize version string using whitelist
                INSTALLED_VERSION=$(echo "$INSTALLED_VERSION" | sed 's/[^A-Za-z0-9._=><~!+-]//g')
                INSTALLED_VERSION=$(echo "$INSTALLED_VERSION" | sed 's/\.post[0-9]*//' | sed 's/\.dev[0-9]*//' | sed 's/\+.*//')
                
                # If user specified a version, use it in the name
                if [ -n "$VERSION_SPEC" ]; then
                    # Extract just the version number from spec (remove operators)
                    SPEC_VERSION=$(echo "$VERSION_SPEC" | sed 's/^[=<>!~]*//')
                    LAYER_NAME="${PKG_NAME}-${SPEC_VERSION}-python${PYTHON_VERSION}"
                    printf "  Specified version: $SPEC_VERSION\n"
                    printf "  Using versioned name\n"
                else
                    LAYER_NAME="${PKG_NAME}-${INSTALLED_VERSION}-python${PYTHON_VERSION}"
                    printf "  Installed version: $INSTALLED_VERSION\n"
                fi
            else
                LAYER_NAME="${PKG_NAME}-$(date +%Y%m%d)-python${PYTHON_VERSION}"
                printf "  Could not extract version, using date-based name\n"
            fi
        else
            LAYER_NAME="${PKG_NAME}-$(date +%Y%m%d)-python${PYTHON_VERSION}"
            printf "  No package info found, using date-based name\n"
        fi
    else
        LAYER_NAME="python-$(date +%Y%m%d)-python${PYTHON_VERSION}"
        printf "  Multiple packages, using date-based name\n"
    fi
    
    # Sanitize the layer name
    LAYER_NAME=$(sanitize_filename "$LAYER_NAME")
fi

# Additional sanitization
LAYER_NAME=$(sanitize_filename "$LAYER_NAME")

# Check for path traversal in layer name
if [[ "$LAYER_NAME" =~ \.\. ]] || [[ "$LAYER_NAME" =~ ^/ ]]; then
    printf "${RED}Error: Invalid layer name (path traversal detected)${NC}\n"
    exit 1
fi

# Ensure .zip extension
if [[ ! "$LAYER_NAME" =~ \.zip$ ]]; then
    LAYER_NAME="${LAYER_NAME}.zip"
fi

# Step 5: Show installed packages
printf "[5/7] Listing installed packages...\n"
pip list --format freeze

# Deactivate virtual environment
set +u
deactivate
set -u

# Step 6: Create zip file
printf "[6/7] Creating zip file: $LAYER_NAME\n"
cd "$WORK_DIR"
printf "  Zipping 'python' directory...\n"
zip -r "$LAYER_NAME" "python" -q
printf "  Zip file created successfully\n"

# Step 7: Move to final location
printf "[7/7] Moving to final location...\n"
if [[ -f "$LAYER_NAME" ]]; then
    mv "$LAYER_NAME" "$ORIGINAL_DIR/"
else
    printf "${RED}Error: Zip file not created${NC}\n"
    exit 1
fi

printf "\n"
printf "${BLUE}=========================================${NC}\n"
printf "${GREEN}✅ SUCCESS: Python Lambda Layer Created${NC}\n"
printf "${BLUE}=========================================${NC}\n"
printf "📁 File: $ORIGINAL_DIR/$LAYER_NAME\n"
printf "🐍 Python Version: $PYTHON_VERSION\n"
printf "⚡ Tool: pip/venv\n"
printf "📦 Size: $(du -h "$ORIGINAL_DIR/$LAYER_NAME" | cut -f1)\n"
printf "📊 Package Count: $PACKAGE_COUNT\n"

# Output installed packages with versions for description
printf "Installed packages: "
cd "$WORK_DIR/python"
INSTALLED_PKGS=""
IFS=',' read -ra PKG_ARRAY <<< "$PACKAGES"
for pkg_full in "${PKG_ARRAY[@]}"; do
    pkg_name=$(extract_package_name "$pkg_full")
    
    # Get installed version from pip show or metadata
    installed_ver=$(find . -type f -name "METADATA" -path "*/${pkg_name}-*.dist-info/METADATA" -exec grep -h "^Version:" {} \; | head -1 | cut -d' ' -f2)
    
    if [ -n "$installed_ver" ]; then
        if [ -n "$INSTALLED_PKGS" ]; then
            INSTALLED_PKGS="$INSTALLED_PKGS, ${pkg_name}==${installed_ver}"
        else
            INSTALLED_PKGS="${pkg_name}==${installed_ver}"
        fi
    fi
done
printf "$INSTALLED_PKGS\n"

printf "\n"