#!/bin/bash

# Uninstallation script for aws-lambda-layer CLI tool

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${RED}Uninstalling AWS Lambda Layer CLI Tool...${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${YELLOW}Warning: Not running as root. Using sudo for uninstallation.${NC}"
    SUDO="sudo"
else
    SUDO=""
fi

INSTALL_DIR="/usr/local/lib/aws-lambda-layer"
BIN_DIR="/usr/local/bin"
COMPLETION_DIR="/etc/bash_completion.d"

# Remove symlink
echo -e "${BLUE}Removing symlink...${NC}"
$SUDO rm -f "$BIN_DIR/aws-lambda-layer"

# Remove installation directory
echo -e "${BLUE}Removing installation directory...${NC}"
$SUDO rm -rf "$INSTALL_DIR"

# Remove bash completion
echo -e "${BLUE}Removing bash completion...${NC}"
$SUDO rm -f "$COMPLETION_DIR/aws-lambda-layer"

# Remove zsh completion
if [ -f "/usr/local/share/zsh/site-functions/_aws-lambda-layer" ]; then
    echo -e "${BLUE}Removing zsh completion...${NC}"
    $SUDO rm -f "/usr/local/share/zsh/site-functions/_aws-lambda-layer"
fi

# Remove from .bashrc
if [ -f "$HOME/.bashrc" ]; then
    echo -e "${BLUE}Cleaning up .bashrc...${NC}"
    $SUDO sed -i '/# AWS Lambda Layer CLI completion/d' "$HOME/.bashrc"
    $SUDO sed -i '/source.*aws-lambda-layer/d' "$HOME/.bashrc"
fi

echo -e "${GREEN}✅ Uninstallation complete!${NC}"