#!/usr/bin/env bash
# Utility functions for Vulnotes CLI

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_step() {
    echo -e "${CYAN}==>${NC} ${BOLD}$*${NC}"
}

die() {
    log_error "$@"
    exit 1
}

# Check required dependencies
check_dependencies() {
    local missing=()

    for cmd in docker curl jq openssl; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo
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

    # Check if Docker daemon is running and accessible
    if ! docker info &>/dev/null; then
        if [[ $EUID -ne 0 ]]; then
            echo
            log_error "Cannot connect to Docker daemon."
            echo
            echo "Either Docker is not running, or you need root privileges."
            echo "Try one of the following:"
            echo "  1. Start Docker: sudo systemctl start docker"
            echo "  2. Add yourself to docker group: sudo usermod -aG docker \$USER (then log out and back in)"
            echo "  3. Run with sudo: sudo vulnotes $*"
            echo
            exit 1
        else
            die "Cannot connect to Docker daemon. Is Docker running?"
        fi
    fi

    # Check docker compose (v2 or v1)
    if docker compose version &>/dev/null; then
        DOCKER_COMPOSE="docker compose"
    elif command -v docker-compose &>/dev/null; then
        DOCKER_COMPOSE="docker-compose"
    else
        echo
        log_error "Docker Compose is required but not installed."
        echo
        echo "Install Docker Compose: https://docs.docker.com/compose/install/"
        echo
        exit 1
    fi
}

# Check if vulnotes is initialized
check_initialized() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        die "Vulnotes is not initialized. Run 'vulnotes init' first."
    fi
    source "$CONFIG_FILE"
}

# Returns 0 if the mongodb service is up and running, 1 otherwise.
# Works on both docker compose v1 and v2 regardless of --status flag support.
is_vulnotes_running() {
    cd "$INSTALL_DIR" || return 1
    local cid
    cid=$($DOCKER_COMPOSE ps -q mongodb 2>/dev/null | head -1)
    [[ -n "$cid" ]] || return 1
    [[ "$(docker inspect -f '{{.State.Running}}' "$cid" 2>/dev/null)" == "true" ]]
}

# Aborts with a friendly message if Vulnotes isn't running.
require_vulnotes_running() {
    local action="${1:-this action}"
    if ! is_vulnotes_running; then
        die "Vulnotes is not running. Start it with 'vulnotes start' before ${action}."
    fi
}

# Get the docker compose project name (for volume naming)
get_compose_project() {
    cd "$INSTALL_DIR"
    # Docker compose v2 uses directory name with dashes converted to lowercase
    local project_name
    project_name=$($DOCKER_COMPOSE config --format json 2>/dev/null | jq -r '.name // empty')
    if [[ -z "$project_name" ]]; then
        # Fallback: use directory name
        project_name=$(basename "$INSTALL_DIR" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')
    fi
    echo "$project_name"
}

# Get volume name with project prefix
get_volume_name() {
    local volume_suffix="$1"
    local project
    project=$(get_compose_project)
    echo "${project}_${volume_suffix}"
}

# Generate random hex string
generate_random_hex() {
    local length="${1:-32}"
    openssl rand -hex "$length"
}
