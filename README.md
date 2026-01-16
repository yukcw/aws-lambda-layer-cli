# AWS Lambda Layer CLI Tool

A command-line tool for creating and publishing AWS Lambda layers for Node.js and Python.

## Features

- **Effortless Publishing**: Create and publish Node.js and Python layers in a single command
- **Smart Compatibility**: Auto-selects the right Linux binaries for Amazon Linux 2 or 2023
- **Cross-Architecture**: Native support for `x86_64` and `arm64` builds
- **Auto-Versioning**: Automatically handles layer naming and version increments

## Installation

### Package Managers (Recommended)

#### npm (Node.js)
```bash
npm i -g aws-lambda-layer-cli
```

#### uv (Python)
```bash
uv tool install aws-lambda-layer-cli
```

### Requirements
- **System**: Linux, macOS, or Windows (WSL recommended)
- **Tools**: `zip`, `aws-cli` (for publishing), `node` (for Node.js layers), `python` (for Python layers)

## Usage

```bash
aws-lambda-layer-cli <command> [options]
```

### Commands
- `zip`: Create a local zip file
- `publish`: Create and publish a layer to AWS
- `completion`: Generate shell completion scripts
- `uninstall`: Uninstall the tool
- `help`: Show help message

### Options

| Option | Description |
|--------|-------------|
| `--nodejs, -n <pkgs>` | Create Node.js layer (comma-separated packages) |
| `--python, -p <pkgs>` | Create Python layer (comma-separated packages) |
| `--wheel, -w <file>`  | Use with `--python` to create layer from `.whl` file |
| `--name` | Custom layer name |
| `--description` | Layer description (publish only) |
| `--profile` | AWS CLI profile (publish only) |
| `--region` | AWS region (publish only) |
| `--architecture, -a` | Target architecture (`x86_64` or `arm64`) |
| `--node-version` | Node.js version (default: 24) |
| `--python-version` | Python version (default: 3.14) |
| `-v, --version` | Show version |

## Examples

### Node.js
```bash
# Create local zip with multiple packages
aws-lambda-layer-cli zip --nodejs express@4.18.2,axios --name my-layer

# Publish to AWS with specific profile and region
aws-lambda-layer-cli publish --nodejs lodash --profile prod --region us-east-1 --description "Utils"
```

### Python
```bash
# Create local zip with specific python version and architecture
aws-lambda-layer-cli zip --python numpy==1.26.0,pandas --python-version 3.12 --architecture arm64

# Publish to AWS for ARM64 architecture
aws-lambda-layer-cli publish --python requests --name web-layer --architecture arm64
```
> **Note**: This tool automatically selects the optimal platform based on the Python version:
> - **Python 3.12+ (Amazon Linux 2023)**: Targets `manylinux_2_28` (GLIBC 2.28+)
> - **Python 3.11- (Amazon Linux 2)**: Targets `manylinux2014` (GLIBC 2.17+)

### Wheel File
The tool auto-detects Python version and architecture from the wheel filename.
```bash
# Create local zip from wheel (preferred syntax)
aws-lambda-layer-cli zip --python --wheel numpy-2.4.1-cp313-cp313-manylinux.whl

# Publish directly from wheel
aws-lambda-layer-cli publish --python --wheel pandas-2.1.0-cp311-...-x86_64.whl
```
> **Note**: For wheels, arguments like `--python-version` or `--architecture` are checked against the wheel metadata. If they conflict, the tool will error to prevent incompatibility.

## Shell Completion

Add to your shell config (`~/.bashrc` or `~/.zshrc`):

```bash
# Bash
source <(aws-lambda-layer-cli completion --bash)

# Zsh
source <(aws-lambda-layer-cli completion --zsh)
```

## License

MIT License

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
