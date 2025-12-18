#!/bin/bash

# Installation script for aws-lambda-layer CLI tool

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
NC='\033[0m' # No Color

# Styles
BOLD='\033[1m'
ITALIC='\033[3m'
UNDERLINE='\033[4m'

printf "${CYAN}${BOLD}Installing AWS Lambda Layer CLI Tool...${NC}\n"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    if command -v sudo &> /dev/null; then
        printf "${YELLOW}Warning: Not running as root. Using sudo for installation.${NC}\n"
        SUDO="sudo"
    else
        SUDO=""
    fi
else
    SUDO=""
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
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
$SUDO cp "$BASE_DIR/VERSION.txt" "$INSTALL_DIR/"

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
    $SUDO cp "$BASE_DIR/completion/aws-lambda-layer-completion.bash" "$COMPLETION_DIR/aws-lambda-layer"
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
printf "${BLUE}Installing zsh completion...${NC}\n"
# Try Homebrew location first (macOS with Homebrew), then standard location
ZSH_COMPLETION_DIR=""
if [ -d "/opt/homebrew/share/zsh/site-functions" ]; then
    ZSH_COMPLETION_DIR="/opt/homebrew/share/zsh/site-functions"
elif [ -d "/usr/local/share/zsh/site-functions" ]; then
    ZSH_COMPLETION_DIR="/usr/local/share/zsh/site-functions"
else
    # Create standard location if neither exists
    ZSH_COMPLETION_DIR="/usr/local/share/zsh/site-functions"
    printf "${YELLOW}Creating zsh completion directory...${NC}\n"
    $SUDO mkdir -p "$ZSH_COMPLETION_DIR"
fi

if [ -n "$ZSH_COMPLETION_DIR" ]; then
    $SUDO cp "$BASE_DIR/completion/aws-lambda-layer-completion.zsh" "$ZSH_COMPLETION_DIR/_aws-lambda-layer"
    printf "${GREEN}Zsh completion installed to: $ZSH_COMPLETION_DIR${NC}\n"
fi

printf "${GREEN}${BOLD}✅ Installation complete!${NC}\n\n"
printf "${MAGENTA}${UNDERLINE}Usage examples:${NC}\n"
printf "  aws-lambda-layer ${GREEN}zip${NC} ${YELLOW}--nodejs${NC} \"express@^4.0.0,lodash@~4.17.0\"\n"
printf "  aws-lambda-layer ${GREEN}zip${NC} ${YELLOW}--python${NC} \"numpy==1.26.0,pandas>=2.1.0\"\n\n"
printf "${YELLOW}To enable tab completion, restart your shell:${NC}\n"
printf "  For bash: source ~/.bashrc\n"
printf "  For zsh:  exec zsh\n\n"
printf "${YELLOW}Or reload zsh completions:${NC}\n"
printf "  autoload -U compinit && compinit\n"