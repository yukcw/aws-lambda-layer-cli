#!/bin/bash

# Python Lambda Layer Creator with UV and version specification
# Usage:
#   ./create_python_layer.sh -i numpy==1.26.0,pandas==2.1.3
#   ./create_python_layer.sh -i numpy==1.26.0,pandas,boto3==1.34.0 -n my-layer.zip
#   ./create_python_layer.sh --packages=requests==2.31.0,boto3 --no-uv

set -e  # Exit on error
set -u  # Treat unset variables as errors

# Generate unique temporary directory
TEMP_DIR=$(mktemp -d -t python-layer)
WORK_DIR="$TEMP_DIR/layer-build"

# Default values
PACKAGES=""
LAYER_NAME=""
PYTHON_VERSION="3.14"  # Default to Python 3.14
USE_UV=true
ORIGINAL_DIR=$(pwd)

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
        echo "Error: Invalid Python version format: $version"
        echo "Python version must be in format X.Y or X.Y.Z (e.g., 3.14, 3.14.2)"
        exit 1
    fi
}

escape_package_name() {
    local pkg="$1"
    # Whitelist for Python: A-Za-z0-9._-=><~
    # Keep only allowed characters for package specifications
    echo "$pkg" | sed 's/[^A-Za-z0-9._\-\=><~]//g'
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
    if [[ "$pkg" =~ [=<>!~] ]]; then
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
                echo "Error: $1 requires an argument"
                echo "Example: $1 numpy==1.26.0,requests"
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
                echo "Error: $1 requires an argument"
                echo "Example: $1 my-python-layer.zip"
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
                echo "Error: $1 requires an argument"
                echo "Example: $1 3.14"
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
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

# Check if packages are provided
if [ -z "$PACKAGES" ]; then
    echo "Error: Packages argument is required"
    echo "Use -i or --packages to specify packages (comma-separated)"
    echo "Example: ./create_python_layer.sh -i numpy==1.26.0,requests"
    exit 1
fi

# Check if uv is available safely
if [ "$USE_UV" = true ]; then
    if ! command -v uv >/dev/null 2>&1; then
        echo "Warning: uv not found, falling back to pip/venv"
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
        echo "Warning: Package name '$pkg' contains no valid characters after sanitization"
    fi
done

if [ -z "$SANITIZED_PACKAGES" ]; then
    echo "Error: No valid packages provided after sanitization"
    exit 1
fi

# Check if any package names were changed
if [ "$PACKAGES" != "$SANITIZED_PACKAGES" ]; then
    echo "Warning: Some package names were sanitized:"
    echo "  Original: $PACKAGES"
    echo "  Sanitized: $SANITIZED_PACKAGES"
    PACKAGES="$SANITIZED_PACKAGES"
fi

echo "========================================="
echo "Python Lambda Layer Creator"
echo "========================================="
echo "Packages: $PACKAGES"
echo "Python version: $PYTHON_VERSION"
echo "Using UV: $USE_UV"
if [ -n "$LAYER_NAME" ]; then
    echo "Output name: $LAYER_NAME"
fi
echo ""

# Step 1: Create working directory
echo "[1/7] Creating directory structure..."
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Step 2: Create virtual environment
echo "[2/7] Creating virtual environment..."
if [ "$USE_UV" = true ]; then
    echo "  Using UV to create venv..."
    uv venv --python "python${PYTHON_VERSION}" python
    source python/bin/activate
else
    echo "  Using venv module..."
    if command -v "python${PYTHON_VERSION}" >/dev/null 2>&1; then
        "python${PYTHON_VERSION}" -m venv python
    else
        echo "Error: python${PYTHON_VERSION} not found"
        exit 1
    fi
    source python/bin/activate
fi

# Step 3: Install packages with versions
echo "[3/7] Installing packages..."
if [ "$USE_UV" = true ]; then
    echo "  Installing with UV..."
    # Convert to array for safe expansion
    IFS=',' read -ra PKG_ARRAY <<< "$PACKAGES"
    uv pip install "${PKG_ARRAY[@]}"
else
    echo "  Installing with pip..."
    # Convert to array for safe expansion
    IFS=',' read -ra PKG_ARRAY <<< "$PACKAGES"
    pip install "${PKG_ARRAY[@]}"
fi

# Count packages from command argument
PACKAGE_COUNT=$(echo "$PACKAGES" | tr ',' '\n' | wc -l | tr -d ' ')

# Step 4: Determine layer name
echo "[4/7] Determining layer name..."
if [ -z "$LAYER_NAME" ]; then
    if [ "$PACKAGE_COUNT" -eq 1 ]; then
        PKG_FULL="$PACKAGES"
        PKG_NAME=$(extract_package_name "$PKG_FULL")
        VERSION_SPEC=$(extract_version_spec "$PKG_FULL")
        
        echo "  Single package: $PKG_NAME"
        
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
                INSTALLED_VERSION=$(echo "$INSTALLED_VERSION" | sed 's/[^A-Za-z0-9._\-]//g')
                INSTALLED_VERSION=$(echo "$INSTALLED_VERSION" | sed 's/\.post[0-9]*//' | sed 's/\.dev[0-9]*//' | sed 's/\+.*//')
                
                # If user specified a version, use it in the name
                if [ -n "$VERSION_SPEC" ]; then
                    # Extract just the version number from spec (remove operators)
                    SPEC_VERSION=$(echo "$VERSION_SPEC" | sed 's/^[=<>!~]*//')
                    LAYER_NAME="${PKG_NAME}-${SPEC_VERSION}-python${PYTHON_VERSION}"
                    echo "  Specified version: $SPEC_VERSION"
                else
                    LAYER_NAME="${PKG_NAME}-${INSTALLED_VERSION}-python${PYTHON_VERSION}"
                    echo "  Installed version: $INSTALLED_VERSION"
                fi
            else
                LAYER_NAME="${PKG_NAME}-$(date +%Y%m%d)-python${PYTHON_VERSION}"
                echo "  Could not extract version, using date-based name"
            fi
        else
            LAYER_NAME="${PKG_NAME}-$(date +%Y%m%d)-python${PYTHON_VERSION}"
            echo "  No package info found, using date-based name"
        fi
    else
        LAYER_NAME="python-$(date +%Y%m%d)-python${PYTHON_VERSION}"
        echo "  Multiple packages, using date-based name"
    fi
    
    # Sanitize the layer name
    LAYER_NAME=$(sanitize_filename "$LAYER_NAME")
fi

# Additional sanitization
LAYER_NAME=$(sanitize_filename "$LAYER_NAME")

# Check for path traversal in layer name
if [[ "$LAYER_NAME" =~ \.\. ]] || [[ "$LAYER_NAME" =~ ^/ ]]; then
    echo "Error: Invalid layer name (path traversal detected)"
    exit 1
fi

# Ensure .zip extension
if [[ ! "$LAYER_NAME" =~ \.zip$ ]]; then
    LAYER_NAME="${LAYER_NAME}.zip"
fi

# Step 5: Show installed packages
echo "[5/7] Listing installed packages..."
if [ "$USE_UV" = true ]; then
    uv pip list --format freeze
else
    pip list --format freeze
fi

# Deactivate virtual environment
deactivate

# Step 6: Create zip file
echo "[6/7] Creating zip file: $LAYER_NAME"
cd "$WORK_DIR"
echo "  Zipping 'python' directory..."
zip -r "$LAYER_NAME" "python" -q
echo "  Zip file created successfully"

# Step 7: Move to final location
echo "[7/7] Moving to final location..."
if [[ -f "$LAYER_NAME" ]]; then
    mv "$LAYER_NAME" "$ORIGINAL_DIR/"
else
    echo "Error: Zip file not created"
    exit 1
fi

echo ""
echo "========================================="
echo "✅ SUCCESS: Python Lambda Layer Created"
echo "========================================="
echo "📁 File: $ORIGINAL_DIR/$LAYER_NAME"
echo "🐍 Python: $PYTHON_VERSION"
echo "⚡ Tool: $(if [ "$USE_UV" = true ]; then echo "UV"; else echo "pip/venv"; fi)"
echo "📦 Size: $(du -h "$ORIGINAL_DIR/$LAYER_NAME" | cut -f1)"
echo "📊 Package Count: $PACKAGE_COUNT"
echo ""