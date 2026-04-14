#!/usr/bin/env bash
# Lifecycle commands for Vulnotes CLI (start, stop, restart, update)

cmd_start() {
    check_initialized

    log_step "Starting Vulnotes..."

    cd "$INSTALL_DIR"

    # Pull latest images
    log_info "Pulling latest images..."
    $DOCKER_COMPOSE pull

    # Start containers
    log_info "Starting containers..."
    $DOCKER_COMPOSE up -d

    log_success "Vulnotes started successfully!"
    echo
    echo -e "Access Vulnotes at: ${CYAN}$DOMAIN${NC}"
    echo -e "View logs with: ${CYAN}vulnotes logs${NC}"
}

cmd_stop() {
    check_initialized

    log_step "Stopping Vulnotes..."

    cd "$INSTALL_DIR"
    $DOCKER_COMPOSE down

    log_success "Vulnotes stopped"
}

cmd_restart() {
    check_initialized

    log_step "Restarting Vulnotes..."

    cd "$INSTALL_DIR"
    $DOCKER_COMPOSE restart

    log_success "Vulnotes restarted"
}

cmd_update() {
    check_initialized

    log_step "Updating Vulnotes..."

    cd "$INSTALL_DIR"

    # Re-login to registry (credentials might have expired)
    if [[ -n "${REGISTRY_USERNAME:-}" ]]; then
        log_info "Authenticating with registry..."
        docker pull "$REGISTRY_URL/vulnotes-app/backend:latest" 2>/dev/null || {
            log_warn "Registry authentication may have expired. Please run 'vulnotes init' again if pull fails."
        }
    fi

    log_info "Pulling latest images..."
    $DOCKER_COMPOSE pull

    log_info "Recreating containers..."
    $DOCKER_COMPOSE up -d --force-recreate

    log_success "Vulnotes updated successfully!"
}
