# AWS Lambda Layer CLI Tool

A command-line tool for creating and publishing AWS Lambda layers for Node.js and Python.

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

### Package Managers (Recommended)

These installs do **not** write to `/usr/local` and do **not** require `sudo`.

#### npm (Node.js)

```bash
npm i -g aws-lambda-layer-cli
aws-lambda-layer-cli --help
```

#### pip (Python)

```bash
python -m pip install --user aws-lambda-layer-cli
aws-lambda-layer-cli --help
```

#### uv (Python)

```bash
uv tool install aws-lambda-layer-cli
aws-lambda-layer-cli --help
```

### Native Installation

#### Linux/macOS

```bash
# Clone or download the repository
git clone https://github.com/yukcw/aws-lambda-layer-cli.git
cd aws-lambda-layer-cli

# Run installation script (requires sudo)
sudo ./scripts/install.sh
```

The installation will:
- Copy scripts to `/usr/local/lib/aws-lambda-layer-cli`
- Create a symlink in `/usr/local/bin` for global access
- Install shell completions for bash and zsh

#### Windows

##### Option 1: PowerShell

```powershell
# One-liner installation
powershell -ExecutionPolicy ByPass -c "irm https://raw.githubusercontent.com/yukcw/aws-lambda-layer-cli/main/scripts/install.ps1 | iex"
```

Or download and run manually:

```powershell
# Download the installer
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/yukcw/aws-lambda-layer-cli/main/scripts/install.ps1" -OutFile "install.ps1"

# Run the installer (as Administrator)
.\install.ps1
```

This will:
- Download the tool to `%USERPROFILE%\.aws-lambda-layer-cli`
- Add it to your PATH
- Create Windows wrapper scripts

##### Option 2: Manual Installation

1. Install prerequisites:
   - [Git for Windows](https://gitforwindows.org/) (includes Git Bash)
   - [AWS CLI](https://aws.amazon.com/cli/) (for publish command)

2. Download the scripts from the [repository](https://github.com/yukcw/aws-lambda-layer-cli)

3. Extract to a directory and add to PATH

### Requirements

- **Linux/macOS**: Bash shell
- **Windows**: Windows Subsystem for Linux (WSL) (recommended), or Git Bash/Cygwin
- **AWS CLI**: Required for `publish` command
- **Node.js**: Required for Node.js layer creation
- **Python**: Required for Python layer creation (uv recommended)
- **zip**: Required for creating zip archives

**Note**: If using WSL, ensure that AWS CLI, Node.js, Python, and zip are installed within WSL for proper functionality.

## Uninstallation

### Package managers

```bash
# npm
npm uninstall -g aws-lambda-layer-cli

# pip
python -m pip uninstall aws-lambda-layer-cli

# uv
uv tool uninstall aws-lambda-layer-cli
```

### Linux/macOS

```bash
sudo ./scripts/uninstall.sh
```

### Windows

#### Using PowerShell

```powershell
# Download and run the uninstaller
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/yukcw/aws-lambda-layer-cli/main/scripts/uninstall.ps1" -OutFile "uninstall.ps1"
.\uninstall.ps1
```

Or run directly without downloading:

```powershell
powershell -ExecutionPolicy ByPass -c "irm https://raw.githubusercontent.com/yukcw/aws-lambda-layer-cli/main/scripts/uninstall.ps1 | iex"
```
#### Troubleshooting Windows Installation

If you encounter issues:

1. **"bash: command not found"**
   - Install [Git for Windows](https://gitforwindows.org/) or [WSL](https://docs.microsoft.com/en-us/windows/wsl/install)
   - Restart PowerShell/Command Prompt after installation

2. **"No such file or directory"**
   - Try running: `bash "$env:USERPROFILE\.aws-lambda-layer-cli\aws-lambda-layer-cli" --help`
   - Or reinstall: `powershell -ExecutionPolicy ByPass -c "irm https://raw.githubusercontent.com/yukcw/aws-lambda-layer-cli/main/scripts/install.ps1 | iex"`

3. **Permission issues**
   - Run PowerShell as Administrator
   - Or run: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`
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
aws-lambda-layer zip --nodejs @babel/core@7.23.0,@babel/types@7.23.0
```

#### Publish to AWS

```bash
# Basic publish
aws-lambda-layer publish --nodejs express@4.18.2 --description "Express layer"

# With custom layer name
aws-lambda-layer publish --nodejs date-fns,uuid --name utility-layer --description "Utility packages"

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
aws-lambda-layer zip --python requests,pytz --name web-utils

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
aws-lambda-layer publish --python requests==2.31.0,pytz==2023.3 --description "Web utilities"

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
- `@babel/core@7.23.0,@babel/types@7.23.0` - Multiple scoped packages

### Python
- `numpy==1.26.0` - Exact version
- `pandas` - Latest version
- `requests>=2.31.0` - Minimum version
- `pytz~=2023.3` - Compatible version

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

4. **zip command installed**: Ensure the `zip` command is available on your system.

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
   - Ensure your AWS credentials has `lambda:PublishLayerVersion` permission

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
