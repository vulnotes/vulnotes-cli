#!/usr/bin/env bash
#
# Vulnotes CLI Installer
#
# Usage (download, review, then run — do not pipe into a shell):
#   curl -fsSLO https://raw.githubusercontent.com/vulnotes/vulnotes-cli/master/install.sh
#   less install.sh
#   bash install.sh
#
# Installs the newest published GitHub release and verifies it against the
# SHA-256 published with that release. Override with VULNOTES_CLI_VERSION=v1.2.3.
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

# Release to install. Pin with VULNOTES_CLI_VERSION=v1.2.3 to install a specific
# tag. "latest" resolves to the most recent published GitHub release.
VULNOTES_CLI_VERSION="${VULNOTES_CLI_VERSION:-latest}"

# Set VULNOTES_ALLOW_UNVERIFIED=1 to install from the master branch head with no
# integrity check. Only for pre-release testing.
VULNOTES_ALLOW_UNVERIFIED="${VULNOTES_ALLOW_UNVERIFIED:-0}"

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

    if ! check_command sha256sum && ! check_command shasum; then
        missing+=("sha256sum")
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
                sha256sum)
                    echo "  sha256sum: sudo apt install coreutils  OR  brew install coreutils"
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

sha256_of() {
    if check_command sha256sum; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

# Resolve the tag to install. "latest" asks GitHub for the newest published release.
resolve_tag() {
    if [[ "$VULNOTES_CLI_VERSION" != "latest" ]]; then
        echo "$VULNOTES_CLI_VERSION"
        return 0
    fi
    curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
        | grep '"tag_name"' | head -1 | cut -d'"' -f4
}

# Download and install
install_cli() {
    log_step "Installing Vulnotes CLI"

    # Create directories
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$BIN_DIR"

    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap "rm -rf $tmp_dir" EXIT

    local tag src_dir
    tag=$(resolve_tag || true)

    if [[ -n "$tag" ]]; then
        log_info "Downloading release $tag from GitHub..."
        local base="https://github.com/$REPO/releases/download/$tag"
        curl -fsSL "$base/vulnotes-cli-$tag.tar.gz" -o "$tmp_dir/vulnotes-cli.tar.gz" \
            || die "Could not download the $tag release archive from $base"

        log_info "Verifying SHA-256..."
        curl -fsSL "$base/vulnotes-cli-$tag.tar.gz.sha256" -o "$tmp_dir/SHA256" \
            || die "Could not download the published checksum for $tag. Refusing to install unverified code."

        local expected actual
        expected=$(awk '{print $1}' "$tmp_dir/SHA256" | head -1)
        actual=$(sha256_of "$tmp_dir/vulnotes-cli.tar.gz")
        if [[ -z "$expected" ]]; then
            die "Published checksum for $tag is empty. Refusing to install unverified code."
        fi
        if [[ "$expected" != "$actual" ]]; then
            log_error "CHECKSUM MISMATCH for $tag"
            log_error "  expected: $expected"
            log_error "  actual:   $actual"
            die "Refusing to install. The download does not match the published release."
        fi
        log_success "Checksum verified"
        src_dir="vulnotes-cli-${tag#v}"
    elif [[ "$VULNOTES_ALLOW_UNVERIFIED" == "1" ]]; then
        log_warn "No tagged release found and VULNOTES_ALLOW_UNVERIFIED=1 is set."
        log_warn "Installing the master branch head WITHOUT any integrity check."
        log_warn "Anyone who can push to master reaches this machine. Do not use in production."
        curl -fsSL "https://github.com/$REPO/archive/refs/heads/master.tar.gz" -o "$tmp_dir/vulnotes-cli.tar.gz"
        src_dir="vulnotes-cli-master"
    else
        log_error "No published release found for $REPO."
        echo
        echo "This installer only installs signed-off, checksummed releases."
        echo "Options:"
        echo "  - Install a specific tag:  VULNOTES_CLI_VERSION=v1.0.0 <installer>"
        echo "  - Clone the repository manually (see the README), or"
        echo "  - For pre-release testing only, re-run with VULNOTES_ALLOW_UNVERIFIED=1"
        echo
        exit 1
    fi

    # Extract
    log_info "Extracting..."
    tar -xzf "$tmp_dir/vulnotes-cli.tar.gz" -C "$tmp_dir"

    if [[ ! -d "$tmp_dir/$src_dir" ]]; then
        src_dir=$(find "$tmp_dir" -maxdepth 1 -mindepth 1 -type d -name 'vulnotes-cli*' -exec basename {} \; | head -1)
        [[ -n "$src_dir" ]] || die "Unexpected archive layout: no vulnotes-cli* directory inside the tarball"
    fi

    # Install files
    log_info "Installing to $INSTALL_DIR..."
    rm -rf "${INSTALL_DIR:?}"/*
    cp -r "$tmp_dir/$src_dir"/* "$INSTALL_DIR/"
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
