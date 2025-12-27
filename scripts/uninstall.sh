#!/bin/bash

# Uninstallation script for aws-lambda-layer CLI tool

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check for help flag
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    printf "${BLUE}Usage:${NC}\n"
    printf "  aws-lambda-layer-cli ${GREEN}uninstall${NC}\n\n"
    printf "${BLUE}Description:${NC}\n"
    printf "  Uninstalls the AWS Lambda Layer CLI tool and removes all associated files.\n"
    printf "  This includes:\n"
    printf "  - The CLI executable and symlinks\n"
    printf "  - The installation directory (/usr/local/lib/aws-lambda-layer-cli)\n"
    printf "  - Shell completion scripts\n"
    exit 0
fi

printf "${RED}Uninstalling AWS Lambda Layer CLI Tool...${NC}\n"

# Check for other installation sources
printf "\n${BLUE}Checking installation sources...${NC}\n"

# Check NPM
if command -v npm &> /dev/null; then
    if npm list -g aws-lambda-layer-cli --depth=0 &> /dev/null; then
        printf "${YELLOW}Detected NPM installation.${NC}\n"
        printf "  Removing NPM package...\n"
        npm uninstall -g aws-lambda-layer-cli
    fi
fi

# Check PyPI (pip)
if command -v pip &> /dev/null || command -v pip3 &> /dev/null; then
    # Try pip then pip3
    PIP_CMD="pip"
    if ! command -v pip &> /dev/null; then
        PIP_CMD="pip3"
    fi
    
    if $PIP_CMD show aws-lambda-layer-cli &> /dev/null; then
        printf "${YELLOW}Detected PyPI installation.${NC}\n"
        printf "  Removing PyPI package...\n"
        $PIP_CMD uninstall -y aws-lambda-layer-cli
    fi
fi
aws-lambda-layer-cli --version
# Check uv
if command -v uv &> /dev/null; then
    if uv tool list | grep -q "aws-lambda-layer-cli"; then
        printf "${YELLOW}Detected uv installation.${NC}\n"
        printf "  Removing uv tool...\n"
        uv tool uninstall aws-lambda-layer-cli
    fi
fi

# Check Native (System)
if [ -d "/usr/local/lib/aws-lambda-layer-cli" ]; then
    printf "${YELLOW}Detected Native/System installation.${NC}\n"
    printf "  Proceeding with removal of system files...\n"
else
    printf "No Native/System installation found at /usr/local/lib/aws-lambda-layer-cli.\n"
fi

printf "\n"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    # Check if we need a password (sudo -n true returns 0 if we have access, 1 if we need password)
    if ! sudo -n true 2>/dev/null; then
        printf "${YELLOW}This script requires root privileges to uninstall from /usr/local/lib.${NC}\n"
        printf "${YELLOW}Please enter your password if prompted.${NC}\n"
    fi
    SUDO="sudo"
else
    SUDO=""
fi

INSTALL_DIR="/usr/local/lib/aws-lambda-layer-cli"
BIN_DIR="/usr/local/bin"
COMPLETION_DIR="/etc/bash_completion.d"

# Remove symlink
printf "${BLUE}Removing symlink...${NC}\n"
$SUDO rm -f "$BIN_DIR/aws-lambda-layer-cli"

# Remove installation directory
printf "${BLUE}Removing installation directory...${NC}\n"
$SUDO rm -rf "$INSTALL_DIR"

# Remove bash completion
printf "${BLUE}Removing bash completion...${NC}\n"
$SUDO rm -f "$COMPLETION_DIR/aws-lambda-layer-cli"

# Remove zsh completion
if [ -f "/usr/local/share/zsh/site-functions/_aws-lambda-layer-cli" ]; then
    printf "${BLUE}Removing zsh completion (standard)...${NC}\n"
    $SUDO rm -f "/usr/local/share/zsh/site-functions/_aws-lambda-layer-cli"
fi

if [ -f "/opt/homebrew/share/zsh/site-functions/_aws-lambda-layer-cli" ]; then
    printf "${BLUE}Removing zsh completion (Homebrew)...${NC}\n"
    $SUDO rm -f "/opt/homebrew/share/zsh/site-functions/_aws-lambda-layer-cli"
fi

# Remove from .bashrc
if [ -f "$HOME/.bashrc" ]; then
    printf "${BLUE}Cleaning up .bashrc...${NC}\n"
    $SUDO sed -i '/# AWS Lambda Layer CLI completion/d' "$HOME/.bashrc"
    $SUDO sed -i '/source.*aws-lambda-layer-cli/d' "$HOME/.bashrc"
fi

printf "${GREEN}✅ Uninstallation complete!${NC}\n"