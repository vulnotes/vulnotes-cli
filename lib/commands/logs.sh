#!/usr/bin/env bash
# Logs command for Vulnotes CLI

cmd_logs() {
    check_initialized

    local service=""
    local follow=false
    local lines=100

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--follow)
                follow=true
                shift
                ;;
            -n|--lines)
                lines="$2"
                shift 2
                ;;
            nginx|backend|frontend|mongodb|puppeteer)
                service="$1"
                shift
                ;;
            *)
                die "Unknown option: $1"
                ;;
        esac
    done

    cd "$INSTALL_DIR"

    local compose_args=("logs" "--tail=$lines")
    if [[ "$follow" == "true" ]]; then
        compose_args+=("-f")
    fi
    if [[ -n "$service" ]]; then
        compose_args+=("$service")
    fi

    $DOCKER_COMPOSE "${compose_args[@]}"
}
