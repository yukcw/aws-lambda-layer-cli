#!/bin/bash

# Uninstallation script for aws-lambda-layer CLI tool

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

printf "${RED}Uninstalling AWS Lambda Layer CLI Tool...${NC}\n"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    printf "${YELLOW}Warning: Not running as root. Using sudo for uninstallation.${NC}\n"
    SUDO="sudo"
else
    SUDO=""
fi

INSTALL_DIR="/usr/local/lib/aws-lambda-layer"
BIN_DIR="/usr/local/bin"
COMPLETION_DIR="/etc/bash_completion.d"

# Remove symlink
printf "${BLUE}Removing symlink...${NC}\n"
$SUDO rm -f "$BIN_DIR/aws-lambda-layer"

# Remove installation directory
printf "${BLUE}Removing installation directory...${NC}\n"
$SUDO rm -rf "$INSTALL_DIR"

# Remove bash completion
printf "${BLUE}Removing bash completion...${NC}\n"
$SUDO rm -f "$COMPLETION_DIR/aws-lambda-layer"

# Remove zsh completion
if [ -f "/usr/local/share/zsh/site-functions/_aws-lambda-layer" ]; then
    printf "${BLUE}Removing zsh completion...${NC}\n"
    $SUDO rm -f "/usr/local/share/zsh/site-functions/_aws-lambda-layer"
fi

# Remove from .bashrc
if [ -f "$HOME/.bashrc" ]; then
    printf "${BLUE}Cleaning up .bashrc...${NC}\n"
    $SUDO sed -i '/# AWS Lambda Layer CLI completion/d' "$HOME/.bashrc"
    $SUDO sed -i '/source.*aws-lambda-layer/d' "$HOME/.bashrc"
fi

printf "${GREEN}✅ Uninstallation complete!${NC}\n"