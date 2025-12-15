#!/bin/bash

# Python Lambda Layer Creator with UV and version specification
# Usage:
#   ./create_python_layer.sh -i numpy==1.26.0,pandas==2.1.3
#   ./create_python_layer.sh -i numpy==1.26.0,pandas,boto3==1.34.0 -n my-layer.zip
#   ./create_python_layer.sh --packages=requests==2.31.0,boto3 --no-uv

set -e  # Exit on error
set -u  # Treat unset variables as errors

# Generate unique temporary directory
TEMP_DIR=$(mktemp -d)
WORK_DIR="$TEMP_DIR/layer-build"

# Default values
PACKAGES=""
LAYER_NAME=""
PYTHON_VERSION="3.14"  # Default to Python 3.14
USE_UV=true
ORIGINAL_DIR=$(pwd)

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
            if [[ -n "$2" && "$2" != -* ]]; then
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
            if [[ -n "$2" && "$2" != -* ]]; then
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
            if [[ -n "$2" && "$2" != -* ]]; then
                PYTHON_VERSION="$2"
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
            validate_python_version "$PYTHON_VERSION"
            shift
            ;;
        --no-uv)
            USE_UV=false
            shift
            ;;
        -h|--help)
            cat << 'EOF'
Python Lambda Layer Creator with UV

Usage:
  ./create_python_layer.sh -i numpy==1.26.0,pandas==2.1.3
  ./create_python_layer.sh --packages=numpy==1.26.0,pandas,boto3==1.34.0 -n my-layer.zip
  ./create_python_layer.sh -i flask==3.0.0 --no-uv

Options:
  -i, --packages        Comma-separated list of Python packages (with optional versions)
  -n, --name            Name of the output zip file
  --python-version      Python version (default: 3.14)
  --no-uv               Use pip/venv instead of uv
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
  ./create_python_layer.sh -i numpy==1.26.0
  ./create_python_layer.sh -i requests==2.31.0,boto3==1.34.0 --python-version=3.14
  ./create_python_layer.sh --packages=pandas==2.1.3,scikit-learn==1.3.0 --no-uv -n ml-layer.zip
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

# Check if uv is available safely
if [ "$USE_UV" = true ]; then
    if ! command -v uv >/dev/null 2>&1; then
        printf "${YELLOW}Warning: uv not found, falling back to pip/venv${NC}\n"
        USE_UV=false
    fi
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

printf "${BLUE}=========================================${NC}\n"
printf "${GREEN}Python Lambda Layer Creator${NC}\n"
printf "${BLUE}=========================================${NC}\n"
printf "Packages: $PACKAGES\n"
printf "Python version: $PYTHON_VERSION\n"
printf "Using UV: $USE_UV\n"
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
if [ "$USE_UV" = true ]; then
    printf "  Using UV to create venv...\n"
    uv venv --python "python${PYTHON_VERSION}" python
    source python/bin/activate
else
    printf "  Using venv module...\n"
    if command -v "python${PYTHON_VERSION}" >/dev/null 2>&1; then
        "python${PYTHON_VERSION}" -m venv python
    else
        printf "${RED}Error: python${PYTHON_VERSION} not found${NC}\n"
        exit 1
    fi
    source python/bin/activate
fi

# Step 3: Install packages with versions
printf "[3/7] Installing packages...\n"
if [ "$USE_UV" = true ]; then
    printf "  Installing with UV...\n"
    # Convert to array for safe expansion
    IFS=',' read -ra PKG_ARRAY <<< "$PACKAGES"
    uv pip install "${PKG_ARRAY[@]}"
else
    printf "  Installing with pip...\n"
    # Convert to array for safe expansion
    IFS=',' read -ra PKG_ARRAY <<< "$PACKAGES"
    pip install "${PKG_ARRAY[@]}"
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
        if [ "$USE_UV" = true ]; then
            PKG_INFO=$(uv pip show "$PKG_NAME" 2>/dev/null || true)
        else
            PKG_INFO=$(pip show "$PKG_NAME" 2>/dev/null || true)
        fi
        
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
if [ "$USE_UV" = true ]; then
    uv pip list --format freeze
else
    pip list --format freeze
fi

# Deactivate virtual environment
deactivate

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
printf "⚡ Tool: $(if [ "$USE_UV" = true ]; then echo "UV"; else echo "pip/venv"; fi)\n"
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
    if [ "$USE_UV" = true ]; then
        installed_ver=$(find . -type f -name "METADATA" -path "*/${pkg_name}-*.dist-info/METADATA" -exec grep -h "^Version:" {} \; | head -1 | cut -d' ' -f2)
    else
        installed_ver=$(find . -type f -name "METADATA" -path "*/${pkg_name}-*.dist-info/METADATA" -exec grep -h "^Version:" {} \; | head -1 | cut -d' ' -f2)
    fi
    
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