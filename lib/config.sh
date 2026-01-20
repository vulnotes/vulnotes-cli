#!/usr/bin/env bash
# Configuration variables for Vulnotes CLI

VERSION="1.0.0"

# Fixed URLs
MANAGER_URL="https://manager.vulnotes.com"
#MANAGER_URL="http://localhost:5555"
REGISTRY_URL="registry.vulnotes.com"

# Installation paths (can be overridden by VULNOTES_DIR env var)
INSTALL_DIR="${VULNOTES_DIR:-$(pwd)}"
CONFIG_FILE="$INSTALL_DIR/.vulnotes-config"
COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"
ENV_FILE="$INSTALL_DIR/.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Update paths when --dir is used
update_paths() {
    local new_dir="$1"
    INSTALL_DIR="$new_dir"
    CONFIG_FILE="$INSTALL_DIR/.vulnotes-config"
    COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"
    ENV_FILE="$INSTALL_DIR/.env"
}
