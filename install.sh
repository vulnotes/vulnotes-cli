#!/usr/bin/env bash
#
# Vulnotes CLI Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/vulnotes/vulnotes-cli/master/install.sh | bash
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Configuration
REPO="vulnotes/vulnotes-cli"
INSTALL_DIR="${VULNOTES_INSTALL_DIR:-$HOME/.vulnotes-cli}"
BIN_DIR="${VULNOTES_BIN_DIR:-$HOME/.local/bin}"

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step() { echo -e "${CYAN}==>${NC} ${BOLD}$*${NC}"; }

die() {
    log_error "$@"
    exit 1
}

check_command() {
    command -v "$1" &>/dev/null
}

# Check dependencies
check_dependencies() {
    log_step "Checking dependencies"

    local missing=()

    # Required for installation
    if ! check_command curl; then
        missing+=("curl")
    fi

    # Required for CLI
    if ! check_command jq; then
        missing+=("jq")
    fi

    if ! check_command openssl; then
        missing+=("openssl")
    fi

    # Docker is required
    if ! check_command docker; then
        missing+=("docker")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing[*]}"
        echo
        echo "Please install the missing dependencies:"
        echo
        for dep in "${missing[@]}"; do
            case "$dep" in
                docker)
                    echo "  Docker: https://docs.docker.com/get-docker/"
                    ;;
                jq)
                    echo "  jq: sudo apt install jq  OR  brew install jq"
                    ;;
                curl)
                    echo "  curl: sudo apt install curl  OR  brew install curl"
                    ;;
                openssl)
                    echo "  openssl: sudo apt install openssl  OR  brew install openssl"
                    ;;
            esac
        done
        echo
        exit 1
    fi

    log_success "All dependencies installed"

    # Check Docker access
    log_info "Checking Docker access..."
    if ! docker info &>/dev/null; then
        echo
        log_error "Cannot connect to Docker daemon."
        echo
        echo "Either Docker is not running, or you need proper permissions."
        echo "Try one of the following:"
        echo "  1. Start Docker: sudo systemctl start docker"
        echo "  2. Add yourself to docker group: sudo usermod -aG docker \$USER"
        echo "     (then log out and back in)"
        echo
        exit 1
    fi
    log_success "Docker is accessible"

    # Check Docker Compose
    if docker compose version &>/dev/null; then
        log_success "Docker Compose v2 found"
    elif check_command docker-compose; then
        log_success "Docker Compose v1 found"
    else
        die "Docker Compose is required but not installed. Please install it: https://docs.docker.com/compose/install/"
    fi
}

# Download and install
install_cli() {
    log_step "Installing Vulnotes CLI"

    # Create directories
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$BIN_DIR"

    # Download latest release
    log_info "Downloading from GitHub..."

    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap "rm -rf $tmp_dir" EXIT

    curl -fsSL "https://github.com/$REPO/archive/refs/heads/master.tar.gz" -o "$tmp_dir/vulnotes-cli.tar.gz"

    # Extract
    log_info "Extracting..."
    tar -xzf "$tmp_dir/vulnotes-cli.tar.gz" -C "$tmp_dir"

    # Install files
    log_info "Installing to $INSTALL_DIR..."
    rm -rf "$INSTALL_DIR"/*
    cp -r "$tmp_dir"/vulnotes-cli-master/* "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/vulnotes"

    # Create symlink in bin directory
    log_info "Creating symlink in $BIN_DIR..."
    ln -sf "$INSTALL_DIR/vulnotes" "$BIN_DIR/vulnotes"

    log_success "Vulnotes CLI installed successfully!"
}

# Check PATH
check_path() {
    if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
        echo
        log_warn "$BIN_DIR is not in your PATH"
        echo
        echo "Add the following to your shell profile (~/.bashrc, ~/.zshrc, etc.):"
        echo
        echo "  export PATH=\"\$PATH:$BIN_DIR\""
        echo
        echo "Then reload your shell or run:"
        echo
        echo "  source ~/.bashrc  # or ~/.zshrc"
        echo
    fi
}

# Main
main() {
    echo
    echo -e "${BOLD}Vulnotes CLI Installer${NC}"
    echo

    check_dependencies
    install_cli
    check_path

    echo
    echo -e "${GREEN}${BOLD}Installation complete!${NC}"
    echo
    echo "Get started:"
    echo "  1. Get a provisioning token from your Vulnotes Manager"
    echo "  2. Run: vulnotes init --token <your-token>"
    echo "  3. Run: vulnotes start"
    echo
    echo "For help: vulnotes help"
    echo
}

main "$@"
