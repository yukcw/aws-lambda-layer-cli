#!/bin/bash

# Installation script for aws-lambda-layer CLI tool

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Installing AWS Lambda Layer CLI Tool...${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${YELLOW}Warning: Not running as root. Using sudo for installation.${NC}"
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
echo -e "${BLUE}Creating installation directory...${NC}"
$SUDO mkdir -p "$INSTALL_DIR"

# Copy scripts
echo -e "${BLUE}Copying scripts...${NC}"
$SUDO cp "$SCRIPT_DIR/aws-lambda-layer" "$INSTALL_DIR/"
$SUDO cp "$SCRIPT_DIR/create_nodejs_layer.sh" "$INSTALL_DIR/"
$SUDO cp "$SCRIPT_DIR/create_python_layer.sh" "$INSTALL_DIR/"

# Make scripts executable
echo -e "${BLUE}Setting executable permissions...${NC}"
$SUDO chmod +x "$INSTALL_DIR/aws-lambda-layer"
$SUDO chmod +x "$INSTALL_DIR/create_nodejs_layer.sh"
$SUDO chmod +x "$INSTALL_DIR/create_python_layer.sh"

# Create symlink in bin directory
echo -e "${BLUE}Creating symlink in $BIN_DIR...${NC}"
$SUDO ln -sf "$INSTALL_DIR/aws-lambda-layer" "$BIN_DIR/aws-lambda-layer"

# Install bash completion
echo -e "${BLUE}Installing bash completion...${NC}"
if [ -d "$COMPLETION_DIR" ]; then
    $SUDO cp "$SCRIPT_DIR/completion/aws-lambda-layer-completion.bash" "$COMPLETION_DIR/aws-lambda-layer"
    # Source the completion script
    if [ -f "$HOME/.bashrc" ]; then
        if ! grep -q "aws-lambda-layer" "$HOME/.bashrc"; then
            echo -e "\n# AWS Lambda Layer CLI completion\nsource $COMPLETION_DIR/aws-lambda-layer" >> "$HOME/.bashrc"
        fi
    fi
    echo -e "${GREEN}Bash completion installed.${NC}"
else
    echo -e "${YELLOW}Bash completion directory not found. Skipping completion installation.${NC}"
fi

# Install zsh completion
if [ -d "/usr/local/share/zsh/site-functions" ]; then
    echo -e "${BLUE}Installing zsh completion...${NC}"
    $SUDO cp "$SCRIPT_DIR/completion/aws-lambda-layer-completion.zsh" "/usr/local/share/zsh/site-functions/_aws-lambda-layer"
    echo -e "${GREEN}Zsh completion installed.${NC}"
fi

echo -e "${GREEN}✅ Installation complete!${NC}"
echo ""
echo -e "${BLUE}Usage examples:${NC}"
echo "  aws-lambda-layer publish --nodejs -i express,axios"
echo "  aws-lambda-layer publish --python -i numpy,pandas"
echo ""
echo -e "${YELLOW}Note: You may need to restart your shell or run:${NC}"
echo "  source ~/.bashrc  # for bash"
echo "  or"
echo "  exec zsh          # for zsh"