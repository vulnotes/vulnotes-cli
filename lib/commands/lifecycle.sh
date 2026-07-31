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

refresh_renderer_compose_wiring() {
    local needs_puppeteer_token needs_frontend_url needs_backend_token
    needs_puppeteer_token=$(awk '/^  puppeteer:/{s=1;next} /^  [a-zA-Z0-9_-]+:/{s=0} s && /PUPPETEER_SERVICE_TOKEN=/{found=1} END{print found ? 0 : 1}' "$COMPOSE_FILE")
    needs_frontend_url=$(awk '/^  puppeteer:/{s=1;next} /^  [a-zA-Z0-9_-]+:/{s=0} s && /DOCX_RENDER_FRONTEND_URL=/{found=1} END{print found ? 0 : 1}' "$COMPOSE_FILE")
    needs_backend_token=$(awk '/^  backend:/{s=1;next} /^  [a-zA-Z0-9_-]+:/{s=0} s && /PUPPETEER_SERVICE_TOKEN=/{found=1} END{print found ? 0 : 1}' "$COMPOSE_FILE")

    if [[ "$needs_puppeteer_token" == 0 && "$needs_frontend_url" == 0 && "$needs_backend_token" == 0 ]]; then
        return 0
    fi

    local backup_path temporary
    backup_path="${COMPOSE_FILE}.backup-$(date -u +%Y%m%dT%H%M%SZ)"
    temporary=$(mktemp "${COMPOSE_FILE}.renderer.XXXXXX")
    cp "$COMPOSE_FILE" "$backup_path"

    awk -v ppt="$needs_puppeteer_token" -v front="$needs_frontend_url" -v back="$needs_backend_token" '
        /^  puppeteer:/ { service="puppeteer" }
        /^  backend:/ { service="backend" }
        /^  [a-zA-Z0-9_-]+:/ && $0 !~ /^  (puppeteer|backend):/ { service="" }
        { print }
        service == "puppeteer" && /PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true/ {
            if (ppt == 1) print "      - PUPPETEER_SERVICE_TOKEN=${PUPPETEER_SERVICE_TOKEN}"
            if (front == 1) print "      - DOCX_RENDER_FRONTEND_URL=http://frontend:3000"
        }
        service == "backend" && /PUPPETEER_SERVICE_URL=http:\/\/puppeteer:3001/ && back == 1 {
            print "      - PUPPETEER_SERVICE_TOKEN=${PUPPETEER_SERVICE_TOKEN}"
        }
    ' "$COMPOSE_FILE" > "$temporary"
    mv "$temporary" "$COMPOSE_FILE"

    if ! $DOCKER_COMPOSE -f "$COMPOSE_FILE" config --quiet; then
        cp "$backup_path" "$COMPOSE_FILE"
        log_error "Renderer compose migration is invalid; restored $backup_path"
        return 1
    fi
    log_success "Secure renderer wiring added to Docker Compose (backup: $backup_path)"
}

cmd_update() {
    check_initialized

    log_step "Updating Vulnotes..."

    cd "$INSTALL_DIR"

    # Older installs predate the authenticated browser-renderer boundary.
    # Add a tenant-local credential before rendering the refreshed compose file.
    ensure_renderer_secret
    refresh_renderer_compose_wiring

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
