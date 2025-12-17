#!/bin/bash

# Backward-compatible wrapper. The real installer lives in scripts/install.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/scripts/install.sh" "$@"
