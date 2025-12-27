# Contributing to AWS Lambda Layer CLI

Thank you for your interest in contributing! This guide will help you understand the project structure and how to build and test your changes.

## Project Structure

The project is structured to support multiple distribution methods (direct script usage, npm, and PyPI) while maintaining a single source of truth for the core logic.

- **Core Scripts**: The main logic resides in the root directory:
  - `aws-lambda-layer-cli`: The main entry point script.
  - `create_nodejs_layer.sh`: Helper script for Node.js layers.
  - `create_python_layer.sh`: Helper script for Python layers.

- **Installers**: Installation scripts are in `scripts/`:
  - `scripts/install.sh` & `scripts/install.ps1`: Main installers.
  - `scripts/uninstall.sh` & `scripts/uninstall.ps1`: Uninstalls.

- **Packaging**:
  - **npm**: `package.json` and `bin/aws-lambda-layer-cli.js` (wrapper).
  - **PyPI**: `pyproject.toml` and `scripts/pypi_resources/` (Python wrapper code).

## Development Workflow

### 1. Making Changes

Modify the core scripts (`aws-lambda-layer-cli`, `create_*.sh`) in the root directory. These changes will be picked up by all distribution methods.

### 2. Building for npm (Node.js)

The npm package wraps the bash scripts. No separate build step is needed - just pack the package.

```bash
# Sync version first (optional, runs automatically via prepare script)
npm run sync-version

# Create a tarball
npm pack

# Install globally from tarball to test
npm install -g aws-lambda-layer-cli-*.tgz

# Verify installation
aws-lambda-layer-cli --version
```

**Note**: The `prepare` script automatically runs `sync-version` before packing, so the manual sync step is optional.

### 3. Building for PyPI (Python)

The Python package is built using a script that bundles the core bash scripts into the package assets.

```bash
# Create and activate virtual environment (recommended)
python3 -m venv .venv
source .venv/bin/activate

# Install build tool
pip install build

# Build the package
./scripts/build_pypi.sh

# The artifacts will be in dist/
ls -l dist/
```

To test the built package:

```bash
# Create a virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install the built wheel
pip install dist/aws_lambda_layer_cli-*.whl

# Verify installation
aws-lambda-layer-cli --version
```

### 4. Testing Installers

To test the direct installation scripts:

```bash
# Test Linux/macOS installer
sudo ./scripts/install.sh

# Test Windows installer (on Windows)
.\scripts\install.ps1
```

## Release Process

1. Update version in `VERSION.txt`

2. **PyPI Release**:
   ```bash
   # Create and activate virtual environment
   python3 -m venv .venv
   source .venv/bin/activate

   # Install build and publish tools
   pip install build twine

   # Build the package
   ./scripts/build_pypi.sh

   # Upload to PyPI
   twine upload dist/*
   ```

3. **npm Release**:
   ```bash
   # Optional: Test the package locally first
   npm pack
   npm install -g aws-lambda-layer-cli-*.tgz
   aws-lambda-layer-cli --version
   
   # Publish to npm (prepublishOnly script automatically syncs version)
   npm publish
   ```
   
   **Note**: The `prepublishOnly` script automatically runs `sync-version` before publishing.
