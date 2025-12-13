# AWS Lambda Layer CLI Tool

A command-line tool for creating AWS Lambda layers for Node.js and Python.

## Installation

```bash
# Clone or download the repository
git clone <repository-url>
cd aws-lambda-layer-cli

# Run installation script (requires sudo)
sudo ./install.sh
```

## Usage
### Basic Syntax
```bash
aws-lambda-layer publish --nodejs [options]
aws-lambda-layer publish --python [options]
```

### Examples
Node.js:

```bash
# Create a Node.js layer with Express
aws-lambda-layer publish --nodejs -i express

# Create with multiple packages and custom name
aws-lambda-layer publish --nodejs -i axios,lodash,moment -n utilities.zip

# Specify Node.js version
aws-lambda-layer publish --nodejs -i @aws-sdk/client-lambda --node-version=18
```

Python:

```bash
# Create a Python layer with numpy
aws-lambda-layer publish --python -i numpy

# Multiple packages with specific Python version
aws-lambda-layer publish --python -i requests,boto3,pandas --python-version=3.11

# Without UV (use pip/venv)
aws-lambda-layer publish --python -i flask --no-uv
```

Short forms:

```bash
# Short flags
aws-lambda-layer publish -n express,axios    # Node.js
aws-lambda-layer publish -p numpy,pandas     # Python
```