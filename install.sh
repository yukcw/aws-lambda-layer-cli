#!/bin/bash

# Installation script for aws-lambda-layer CLI tool

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

printf "${BLUE}Installing AWS Lambda Layer CLI Tool...${NC}\n"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    printf "${YELLOW}Warning: Not running as root. Using sudo for installation.${NC}\n"
    SUDO="sudo"
else
    SUDO=""
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/usr/local/lib/aws-lambda-layer"
BIN_DIR="/usr/local/bin"
COMPLETION_DIR="/etc/bash_completion.d"

# Create installation directory
printf "${BLUE}Creating installation directory...${NC}\n"
$SUDO mkdir -p "$INSTALL_DIR"

# Copy scripts
printf "${BLUE}Copying scripts...${NC}\n"
$SUDO cp "$SCRIPT_DIR/aws-lambda-layer" "$INSTALL_DIR/"
$SUDO cp "$SCRIPT_DIR/create_nodejs_layer.sh" "$INSTALL_DIR/"
$SUDO cp "$SCRIPT_DIR/create_python_layer.sh" "$INSTALL_DIR/"

# Make scripts executable
printf "${BLUE}Setting executable permissions...${NC}\n"
$SUDO chmod +x "$INSTALL_DIR/aws-lambda-layer"
$SUDO chmod +x "$INSTALL_DIR/create_nodejs_layer.sh"
$SUDO chmod +x "$INSTALL_DIR/create_python_layer.sh"

# Create symlink in bin directory
printf "${BLUE}Creating symlink in $BIN_DIR...${NC}\n"
$SUDO ln -sf "$INSTALL_DIR/aws-lambda-layer" "$BIN_DIR/aws-lambda-layer"

# Install bash completion
printf "${BLUE}Installing bash completion...${NC}\n"
if [ -d "$COMPLETION_DIR" ]; then
    $SUDO cp "$SCRIPT_DIR/completion/aws-lambda-layer-completion.bash" "$COMPLETION_DIR/aws-lambda-layer"
    # Source the completion script
    if [ -f "$HOME/.bashrc" ]; then
        if ! grep -q "aws-lambda-layer" "$HOME/.bashrc"; then
            printf "\n# AWS Lambda Layer CLI completion\nsource $COMPLETION_DIR/aws-lambda-layer\n" >> "$HOME/.bashrc"
        fi
    fi
    printf "${GREEN}Bash completion installed.${NC}\n"
else
    printf "${YELLOW}Bash completion directory not found. Skipping completion installation.${NC}\n"
fi

# Install zsh completion
if [ -d "/usr/local/share/zsh/site-functions" ]; then
    printf "${BLUE}Installing zsh completion...${NC}\n"
    $SUDO cp "$SCRIPT_DIR/completion/aws-lambda-layer-completion.zsh" "/usr/local/share/zsh/site-functions/_aws-lambda-layer"
    printf "${GREEN}Zsh completion installed.${NC}\n"
fi

printf "${GREEN}✅ Installation complete!${NC}\n\n"
printf "${BLUE}Usage examples:${NC}\n"
printf "  aws-lambda-layer zip --nodejs express@4.18.2\n"
printf "  aws-lambda-layer zip --python numpy==1.26.0\n\n"
printf "${YELLOW}Note: You may need to restart your shell or run:${NC}\n"
printf "  source ~/.bashrc  # for bash\n"
printf "  or\n"
printf "  exec zsh          # for zsh\n"