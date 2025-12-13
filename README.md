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
- **AWS Profile Support**: Use different AWS profiles for publishing
- **Region Specification**: Target specific AWS regions

## Installation

```bash
# Clone or download the repository
git clone <repository-url>
cd aws-lambda-layer-cli

# Run installation script (requires sudo)
sudo ./install.sh
```

The installation will:
- Copy scripts to `/usr/local/lib/aws-lambda-layer`
- Create a symlink in `/usr/local/bin` for global access
- Install shell completions for bash and zsh

## Uninstallation

```bash
sudo ./uninstall.sh
```

## Usage

### Basic Syntax

```bash
# Create a local zip file
aws-lambda-layer zip --nodejs <packages> [options]
aws-lambda-layer zip --python <packages> [options]

# Publish directly to AWS
aws-lambda-layer publish --nodejs <packages> [options]
aws-lambda-layer publish --python <packages> [options]
```

### Commands

- **zip**: Create and package a Lambda layer as zip file
- **publish**: Create and publish a Lambda layer to AWS (uses IAM credentials)
- **help**: Show help message

### Runtime Options

- `--nodejs`, `--node`, `-n`: Create a Node.js Lambda layer
- `--python`, `--py`, `-p`: Create a Python Lambda layer
- `--runtime=RUNTIME`: Specify runtime (nodejs or python)

### Common Options

- `--name`: Name for the output zip file / layer name
- `--description`: Description for the layer (publish command only)
- `-h`, `--help`: Show help message

### AWS Options (publish command only)

- `--profile`: AWS CLI profile to use (default: default profile)
- `--region`: AWS region (e.g., us-east-1, ap-east-1)

### Node.js Specific Options

- `--node-version`: Node.js version (default: 24)

### Python Specific Options

- `--python-version`: Python version (default: 3.14)
- `--no-uv`: Use pip/venv instead of uv

## Examples

### Node.js Examples

#### Create Local Zip Files

```bash
# Single package with version
aws-lambda-layer zip --nodejs express@4.18.2

# Multiple packages with versions
aws-lambda-layer zip --nodejs express@4.18.2,axios@1.6.2,lodash@4.17.21

# With custom name
aws-lambda-layer zip --nodejs axios,lodash --name utility-layer

# With specific Node.js version
aws-lambda-layer zip --nodejs express@4.18.2 --node-version 20

# Scoped packages
aws-lambda-layer zip --nodejs @aws-sdk/client-lambda@3.515.0,@aws-sdk/client-s3
```

#### Publish to AWS

```bash
# Basic publish
aws-lambda-layer publish --nodejs express@4.18.2 --description "Express layer"

# With custom layer name
aws-lambda-layer publish --nodejs axios,lodash --name utility-layer --description "Utility packages"

# Using specific AWS profile
aws-lambda-layer publish --nodejs express@4.18.2 --profile production --description "Express layer"

# Specify AWS region
aws-lambda-layer publish --nodejs axios --region ap-east-1 --description "Axios layer"

# With both profile and region
aws-lambda-layer publish --nodejs lodash --profile dev --region us-east-1 --description "Lodash layer"
```

### Python Examples

#### Create Local Zip Files

```bash
# Single package with version
aws-lambda-layer zip --python numpy==1.26.0

# Multiple packages
aws-lambda-layer zip --python numpy==1.26.0,pandas==2.1.3,requests>=2.31.0

# With custom name
aws-lambda-layer zip --python requests,boto3 --name aws-utils

# With specific Python version
aws-lambda-layer zip --python numpy==1.26.0 --python-version 3.12

# Using pip instead of uv
aws-lambda-layer zip --python pandas==2.1.3 --no-uv
```

#### Publish to AWS

```bash
# Basic publish
aws-lambda-layer publish --python numpy==1.26.0 --description "NumPy layer"

# Multiple packages with description
aws-lambda-layer publish --python requests==2.31.0,boto3==1.34.0 --description "AWS utilities"

# Using specific AWS profile
aws-lambda-layer publish --python pandas==2.1.3 --profile production --description "Pandas layer"

# Specify AWS region
aws-lambda-layer publish --python numpy==1.26.0 --region us-west-2 --description "NumPy layer"

# With both profile and region
aws-lambda-layer publish --python scikit-learn --profile ml-account --region eu-west-1 --description "ML layer"
```

## Package Version Formats

### Node.js
- `express@4.18.2` - Exact version
- `axios` - Latest version
- `lodash@^4.17.0` - Compatible version
- `@aws-sdk/client-lambda@3.515.0` - Scoped package with version

### Python
- `numpy==1.26.0` - Exact version
- `pandas` - Latest version
- `requests>=2.31.0` - Minimum version
- `boto3~=1.34.0` - Compatible version

## Publishing to AWS

### Requirements

Before using the `publish` command, ensure you have:

1. **AWS CLI installed and configured**
   ```bash
   aws configure
   # or for specific profile
   aws configure --profile production
   ```

2. **IAM Permissions**: Your IAM user/role needs:
   - `lambda:PublishLayerVersion`
   - `sts:GetCallerIdentity` (for account verification)
   - `iam:ListAccountAliases` (optional, for account info)

3. **Region Configuration**: Either:
   - Set default region: `aws configure set region us-east-1`
   - Or use `--region` flag when publishing

### Confirmation Prompt

When publishing, you'll see:
1. AWS Account ID
2. AWS Profile (if specified)
3. Account Aliases (if available)
4. Target Region
5. Confirmation prompt: `Do you want to proceed? [Y/n]:`

Press Y (or Enter for default Yes) to proceed, or N to cancel.

## Output

### Zip Command
Creates a zip file in the current directory with format:
- Node.js: `<package-name>-<version>-nodejs<node-version>.zip`
- Python: `<package-name>-<version>-python<python-version>.zip`

### Publish Command
- Uploads layer to AWS Lambda
- Returns Layer ARN
- Shows usage examples
- Provides command to attach to existing Lambda functions

## Troubleshooting

### Common Issues

1. **AWS credentials not configured**
   ```bash
   aws configure
   # or
   aws configure --profile your-profile
   ```

2. **IAM permissions missing**
   - Ensure your IAM user has `lambda:PublishLayerVersion` permission

3. **Layer name already exists**
   - Use `--name` option to specify a different name
   - Or delete the existing layer version

4. **Zip file too large**
   - AWS limit: 50MB for direct upload
   - Consider using fewer packages or S3 upload for larger layers

5. **Region not configured**
   - Use `--region` flag or configure default region:
   ```bash
   aws configure set region us-east-1
   ```

## Shell Completion

Completions are installed for bash and zsh. Restart your shell or source the completion files:

```bash
# Bash
source /etc/bash_completion.d/aws-lambda-layer-completion.bash

# Zsh
source /usr/local/share/zsh/site-functions/_aws-lambda-layer
```

## License

MIT License

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
