#!/bin/bash
set -e

# Directory setup
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$BASE_DIR/aws_lambda_layer_cli"
ASSETS_DIR="$BUILD_DIR/assets"

echo "Preparing PyPI package structure..."

# Clean up any previous build artifacts
rm -rf "$BUILD_DIR" "$BASE_DIR/dist" "$BASE_DIR/build" "$BASE_DIR/aws_lambda_layer_cli.egg-info"

# Create package directories
mkdir -p "$ASSETS_DIR"

# Copy Python package files
cp "$BASE_DIR/scripts/pypi_resources/__init__.py" "$BUILD_DIR/"
cp "$BASE_DIR/scripts/pypi_resources/cli.py" "$BUILD_DIR/"
cp "$BASE_DIR/VERSION.txt" "$BUILD_DIR/"

# Copy assets (bash scripts)
cp "$BASE_DIR/aws-lambda-layer" "$ASSETS_DIR/"
cp "$BASE_DIR/create_nodejs_layer.sh" "$ASSETS_DIR/"
cp "$BASE_DIR/create_python_layer.sh" "$ASSETS_DIR/"

# Create __init__.py for assets package
touch "$ASSETS_DIR/__init__.py"

echo "Building PyPI package..."
cd "$BASE_DIR"
python3 -m build

echo "Cleaning up temporary package files..."
rm -rf "$BUILD_DIR" "$BASE_DIR/aws_lambda_layer_cli.egg-info" "$BASE_DIR/build"

echo "Build complete! Artifacts are in dist/"
