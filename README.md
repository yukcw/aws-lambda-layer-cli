# AWS Lambda Layer CLI Tool

A powerful command-line tool for creating and publishing AWS Lambda layers for Node.js and Python.

## Features

- **Create Layers**: Generate Lambda layer zip files for Node.js and Python
- **Publish to AWS**: Directly publish layers to AWS Lambda with IAM credentials
- **Version Management**: Support for package version specification
- **Security**: Input validation and sanitization
- **Smart Naming**: Automatic layer naming with package versions
- **Multiple Packages**: Support for multiple packages in a single layer
- **Runtime Versioning**: Specify Node.js or Python versions
- **Package Managers**: Support for npm (Node.js) and uv/pip (Python)

## Installation

```bash
# Clone or download the repository
git clone <repository-url>
cd aws-lambda-layer-cli

# Run installation script (requires sudo)
sudo ./install.sh