#!/bin/bash

# Node.js Lambda Layer Creator with NVM support and version specification
# Usage: 
#   ./create_nodejs_layer.sh -i express@4.18.2,axios@1.6.2
#   ./create_nodejs_layer.sh -i express@4.18.2,axios,lodash@4.17.21 -n my-layer.zip
#   ./create_nodejs_layer.sh --packages=express@4.18.2,axios --name=my-layer.zip --node-version=24

set -e  # Exit on error
set -u  # Treat unset variables as errors

# Generate unique temporary directory
TEMP_DIR=$(mktemp -d -t nodejs-layer)
WORK_DIR="$TEMP_DIR/layer-build"
NODE_DIR="$WORK_DIR/nodejs"

# Default values
PACKAGES=""
LAYER_NAME=""
NODE_VERSION="24"  # Default to Node.js 24
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

validate_version() {
    local version="$1"
    # Allow only numbers and dots
    if [[ ! "$version" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
        echo "Error: Invalid version format: $version"
        echo "Version must contain only numbers and dots (e.g., 24, 20.0.0)"
        exit 1
    fi
}

escape_package_name() {
    local pkg="$1"
    # Whitelist for Node.js: A-Za-z0-9._-@/
    # Keep only allowed characters
    echo "$pkg" | sed 's/[^A-Za-z0-9._\-@\/]//g'
}

# Extract base package name from version specification
# Example: express@4.18.2 -> express
# Example: @aws-sdk/client-lambda@3.515.0 -> @aws-sdk/client-lambda
extract_package_name() {
    local pkg="$1"
    # Remove version specification after @
    if [[ "$pkg" == *@* && ! "$pkg" =~ ^@ ]]; then
        # Regular package with version: express@4.18.2
        echo "${pkg%%@*}"
    elif [[ "$pkg" == @*@* ]]; then
        # Scoped package with version: @aws-sdk/client-lambda@3.515.0
        # Keep @scope/name part
        echo "${pkg%@*}"
    else
        # No version specified
        echo "$pkg"
    fi
}

# Extract version from package string if specified
# Example: express@4.18.2 -> 4.18.2
extract_package_version() {
    local pkg="$1"
    if [[ "$pkg" == *@* ]]; then
        if [[ "$pkg" == @*@* ]]; then
            # Scoped package: @aws-sdk/client-lambda@3.515.0
            echo "${pkg##*@}"
        else
            # Regular package: express@4.18.2
            echo "${pkg##*@}"
        fi
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
                echo "Example: $1 express@4.18.2,axios"
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
                echo "Example: $1 my-layer.zip"
                exit 1
            fi
            ;;
        --name=*)
            LAYER_NAME="${1#*=}"
            shift
            ;;
        --node-version)
            if [[ -n "$2" && "$2" != -* ]]; then
                NODE_VERSION="$2"
                validate_version "$NODE_VERSION"
                shift 2
            else
                echo "Error: $1 requires an argument"
                echo "Example: $1 24"
                exit 1
            fi
            ;;
        --node-version=*)
            NODE_VERSION="${1#*=}"
            validate_version "$NODE_VERSION"
            shift
            ;;
        -h|--help)
            cat << 'EOF'
Node.js Lambda Layer Creator with NVM support

Usage:
  ./create_nodejs_layer.sh -i express@4.18.2,axios@1.6.2
  ./create_nodejs_layer.sh --packages=express@4.18.2,axios,lodash -n my-layer.zip
  ./create_nodejs_layer.sh -i @aws-sdk/client-lambda@3.515.0 --name=aws-layer.zip --node-version=24

Options:
  -i, --packages      Comma-separated list of npm packages (with optional versions)
  -n, --name          Name of the output zip file
  --node-version      Node.js version (default: 24). Uses nvm if available, falls back to system node
  -h, --help          Show this help message

Version Specification:
  Package versions can be specified using @ symbol:
    express@4.18.2                    # Exact version
    express@^4.18.0                   # Caret range
    express@~4.18.0                   # Tilde range
    @aws-sdk/client-lambda@3.515.0    # Scoped package with version

Examples:
  ./create_nodejs_layer.sh -i express@4.18.2
  ./create_nodejs_layer.sh -i axios@1.6.2,lodash@4.17.21,moment@2.29.4 -n utilities.zip
  ./create_nodejs_layer.sh --packages=express@4.18.2,axios --name=web-framework.zip --node-version=24
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
    echo "Example: ./create_nodejs_layer.sh -i express@4.18.2,axios"
    exit 1
fi

# Function to get Node.js version securely
get_node_version() {
    local version=""
    
    # Try to get version from node command
    if command -v node >/dev/null 2>&1; then
        version=$(node --version 2>/dev/null | head -1 || echo "")
        if [[ -n "$version" ]]; then
            # Remove 'v' prefix and get major version
            version=${version#v}
            version=${version%%.*}
            echo "$version"
            return 0
        fi
    fi
    
    echo ""
    return 1
}

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

# Set Node.js version if specified (already has default 24)
echo "Node.js version: $NODE_VERSION"
CURRENT_NODE_VERSION=$(get_node_version || echo "")
if [[ -n "$NODE_VERSION" ]]; then
    echo "Using Node.js version: $NODE_VERSION"
    
    # Check if nvm is available
    if [[ -f "$HOME/.nvm/nvm.sh" ]]; then
        echo "Using nvm to set Node.js version..."
        # Source nvm securely with fixed path
        if [ -f "$HOME/.nvm/nvm.sh" ]; then
            # shellcheck source=/dev/null
            source "$HOME/.nvm/nvm.sh"
        else
            echo "Error: nvm not found at expected location"
            exit 1
        fi
        
        # Check if requested version is installed using safe method
        NVM_VERSIONS=$(nvm list --no-colors 2>/dev/null | grep -E "->|v$NODE_VERSION\." | head -1 || true)
        if [[ -n "$NVM_VERSIONS" ]]; then
            nvm use "$NODE_VERSION" > /dev/null 2>&1 || true
            echo "Switched to Node.js version: $(node --version 2>/dev/null || echo 'unknown')"
        else
            echo "Warning: Requested Node.js version $NODE_VERSION not found via nvm"
            echo "Using current Node.js version: $(node --version 2>/dev/null || echo 'unknown')"
        fi
    elif command -v nvm >/dev/null 2>&1; then
        echo "Using nvm to set Node.js version..."
        # Check if requested version is installed
        NVM_VERSIONS=$(nvm list --no-colors 2>/dev/null | grep -E "->|v$NODE_VERSION\." | head -1 || true)
        if [[ -n "$NVM_VERSIONS" ]]; then
            nvm use "$NODE_VERSION" > /dev/null 2>&1 || true
            echo "Switched to Node.js version: $(node --version 2>/dev/null || echo 'unknown')"
        else
            echo "Warning: Requested Node.js version $NODE_VERSION not found via nvm"
            echo "Using current Node.js version: $(node --version 2>/dev/null || echo 'unknown')"
        fi
    else
        echo "Warning: nvm not found. Using system Node.js"
        if [[ -n "$CURRENT_NODE_VERSION" ]]; then
            echo "Current Node.js version: $CURRENT_NODE_VERSION"
        else
            echo "Warning: Could not determine Node.js version"
        fi
    fi
fi

# Get current Node.js version for naming
NODE_VERSION_USED=$(get_node_version || echo "$NODE_VERSION")

echo "========================================="
echo "Node.js Lambda Layer Creator"
echo "========================================="
echo "Packages: $PACKAGES"
echo "Node.js version: $NODE_VERSION_USED"
if [ -n "$LAYER_NAME" ]; then
    echo "Output name: $LAYER_NAME"
fi
echo ""

# Step 1: Create directory structure
echo "[1/5] Creating directory structure..."
mkdir -p "$NODE_DIR"
cd "$WORK_DIR"

# Step 2: Initialize npm project
echo "[2/5] Initializing npm project..."
cd "$NODE_DIR"
npm init -y --silent

# Step 3: Install packages with versions
echo "[3/5] Installing packages..."
# Convert to array for safe expansion
IFS=',' read -ra PKG_ARRAY <<< "$PACKAGES"
npm install --save --silent "${PKG_ARRAY[@]}"

# Count packages from command argument
PACKAGE_COUNT=$(echo "$PACKAGES" | tr ',' '\n' | wc -l | tr -d ' ')

# Step 4: Determine layer name
echo "[4/5] Determining layer name..."
if [ -z "$LAYER_NAME" ]; then
    if [ "$PACKAGE_COUNT" -eq 1 ]; then
        # Single package: get base package name without version
        PKG_FULL="$PACKAGES"
        PKG_NAME=$(extract_package_name "$PKG_FULL")
        SPECIFIED_VERSION=$(extract_package_version "$PKG_FULL")
        
        # Handle scoped packages
        if [[ "$PKG_NAME" == @* ]]; then
            SCOPE=$(echo "$PKG_NAME" | cut -d'/' -f1)
            PKG=$(echo "$PKG_NAME" | cut -d'/' -f2)
            PKG_JSON="$NODE_DIR/node_modules/$SCOPE/$PKG/package.json"
        else
            PKG_JSON="$NODE_DIR/node_modules/$PKG_NAME/package.json"
        fi
        
        if [ -f "$PKG_JSON" ]; then
            # Use grep instead of node -p with require
            INSTALLED_VERSION=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$PKG_JSON" | head -1 | cut -d'"' -f4 || echo "1.0.0")
            if [ -z "$INSTALLED_VERSION" ]; then
                INSTALLED_VERSION="1.0.0"
            fi
            
            # If user specified a version, include it in the name
            if [ -n "$SPECIFIED_VERSION" ]; then
                # Extract just the version number from spec (remove operators)
                SPEC_VERSION=$(echo "$SPECIFIED_VERSION" | sed 's/^[=<>!~^]*//')
                LAYER_NAME="${PKG_NAME}-${SPEC_VERSION}-nodejs${NODE_VERSION_USED}"
                echo "  Specified version: $SPEC_VERSION"
            else
                LAYER_NAME="${PKG_NAME}-${INSTALLED_VERSION}-nodejs${NODE_VERSION_USED}"
                echo "  Installed version: $INSTALLED_VERSION"
            fi
        else
            # Use project version as fallback
            PROJECT_VERSION=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$NODE_DIR/package.json" | head -1 | cut -d'"' -f4 || echo "1.0.0")
            if [ -z "$PROJECT_VERSION" ]; then
                PROJECT_VERSION="1.0.0"
            fi
            
            if [ -n "$SPECIFIED_VERSION" ]; then
                LAYER_NAME="${PKG_NAME}-${SPECIFIED_VERSION}-nodejs${NODE_VERSION_USED}"
                echo "  Specified version: $SPECIFIED_VERSION"
            else
                LAYER_NAME="${PKG_NAME}-${PROJECT_VERSION}-nodejs${NODE_VERSION_USED}"
                echo "  Project version: $PROJECT_VERSION"
            fi
        fi
    else
        # Multiple packages: use nodejs-[date]-nodejs[version].zip
        LAYER_NAME="nodejs-$(date +%Y%m%d)-nodejs${NODE_VERSION_USED}"
        echo "  Multiple packages, using date-based name"
    fi
    
    # Sanitize the layer name
    LAYER_NAME=$(sanitize_filename "$LAYER_NAME")
fi

# Additional sanitization for layer name
LAYER_NAME=$(sanitize_filename "$LAYER_NAME")

# Ensure .zip extension and check for path traversal
if [[ "$LAYER_NAME" =~ \.\. ]] || [[ "$LAYER_NAME" =~ ^/ ]]; then
    echo "Error: Invalid layer name (path traversal detected)"
    exit 1
fi

if [[ ! "$LAYER_NAME" =~ \.zip$ ]]; then
    LAYER_NAME="${LAYER_NAME}.zip"
fi

# Step 5: Zip the nodejs directory
echo "[5/5] Creating zip file: $LAYER_NAME"
cd "$WORK_DIR"
zip -r "$LAYER_NAME" "nodejs" -q

# Move zip to original directory - Check path
if [[ -f "$LAYER_NAME" ]]; then
    mv "$LAYER_NAME" "$ORIGINAL_DIR/"
else
    echo "Error: Zip file not created"
    exit 1
fi

echo ""
echo "✅ Node.js Lambda layer created successfully!"
echo "📁 File: $ORIGINAL_DIR/$LAYER_NAME"
echo "📦 Size: $(du -h "$ORIGINAL_DIR/$LAYER_NAME" | cut -f1)"
echo "📊 Packages installed: $PACKAGE_COUNT"
echo "🚀 Node.js version: $NODE_VERSION_USED"
echo ""