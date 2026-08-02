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

renderer_compose_static_valid() {
    awk '
        function reset_service() { service=""; in_environment=0 }
        /^  puppeteer:[[:space:]]*(#.*)?$/ { service="puppeteer"; in_environment=0; seen_puppeteer=1; next }
        /^  backend:[[:space:]]*(#.*)?$/ { service="backend"; in_environment=0; seen_backend=1; next }
        /^  [A-Za-z0-9_.-]+:[[:space:]]*(#.*)?$/ { reset_service(); next }
        service != "" && /^    environment:[[:space:]]*(#.*)?$/ { in_environment=1; next }
        service != "" && /^    [A-Za-z0-9_.-]+:/ { in_environment=0 }
        !in_environment || /^[[:space:]]*#/ { next }
        service == "puppeteer" {
            if ($0 ~ /^      -[[:space:]]*PUPPETEER_SERVICE_TOKEN(=|[[:space:]]*$)/ || $0 ~ /^      PUPPETEER_SERVICE_TOKEN:/) ppt_token_total++
            if ($0 ~ /^      -[[:space:]]*DOCX_RENDER_FRONTEND_URL(=|[[:space:]]*$)/ || $0 ~ /^      DOCX_RENDER_FRONTEND_URL:/) ppt_url_total++
            if ($0 ~ /^      -[[:space:]]*PUPPETEER_SERVICE_TOKEN=\$\{PUPPETEER_SERVICE_TOKEN\}[[:space:]]*$/ || $0 ~ /^      PUPPETEER_SERVICE_TOKEN:[[:space:]]*\$\{PUPPETEER_SERVICE_TOKEN\}[[:space:]]*$/) ppt_token++
            if ($0 ~ /^      -[[:space:]]*DOCX_RENDER_FRONTEND_URL=http:\/\/frontend:3000[[:space:]]*$/ || $0 ~ /^      DOCX_RENDER_FRONTEND_URL:[[:space:]]*http:\/\/frontend:3000[[:space:]]*$/) ppt_url++
        }
        service == "backend" {
            if ($0 ~ /^      -[[:space:]]*PUPPETEER_SERVICE_TOKEN(=|[[:space:]]*$)/ || $0 ~ /^      PUPPETEER_SERVICE_TOKEN:/) backend_token_total++
            if ($0 ~ /^      -[[:space:]]*PUPPETEER_SERVICE_TOKEN=\$\{PUPPETEER_SERVICE_TOKEN\}[[:space:]]*$/ || $0 ~ /^      PUPPETEER_SERVICE_TOKEN:[[:space:]]*\$\{PUPPETEER_SERVICE_TOKEN\}[[:space:]]*$/) backend_token++
        }
        END {
            exit !(seen_puppeteer && seen_backend && ppt_token == 1 && ppt_token_total == 1 && ppt_url == 1 && ppt_url_total == 1 && backend_token == 1 && backend_token_total == 1)
        }
    ' "$1"
}

migrate_renderer_compose_file() {
    local source_file="$1" destination_file="$2"

    # Inline/anchor-only environment declarations cannot be edited safely with
    # the CLI's dependency-free YAML migration. Fail closed instead of creating
    # a duplicate environment key or claiming a migration succeeded.
    if awk '
        /^  (puppeteer|backend):[[:space:]]*(#.*)?$/ { target=1; next }
        /^  [A-Za-z0-9_.-]+:/ { target=0 }
        target && /^    environment:[[:space:]]*[^#[:space:]]/ { found=1 }
        END { exit !found }
    ' "$source_file"; then
        log_error "Inline or aliased environment values are unsupported for backend/puppeteer; convert them to a list or mapping before updating"
        return 1
    fi

    awk '
        function print_entry(key, value) {
            if (style == "mapping") print "      " key ": " value
            else print "      - " key "=" value
        }
        function finish_environment() {
            if (!in_environment) return
            if (service == "puppeteer") {
                if (!token_seen) print_entry("PUPPETEER_SERVICE_TOKEN", "${PUPPETEER_SERVICE_TOKEN}")
                if (!url_seen) print_entry("DOCX_RENDER_FRONTEND_URL", "http://frontend:3000")
            } else if (service == "backend" && !token_seen) {
                print_entry("PUPPETEER_SERVICE_TOKEN", "${PUPPETEER_SERVICE_TOKEN}")
            }
            in_environment=0
        }
        function finish_service() {
            finish_environment()
            if (service != "" && !environment_seen) {
                print "    environment:"
                style="list"
                if (service == "puppeteer") {
                    print_entry("PUPPETEER_SERVICE_TOKEN", "${PUPPETEER_SERVICE_TOKEN}")
                    print_entry("DOCX_RENDER_FRONTEND_URL", "http://frontend:3000")
                } else if (service == "backend") {
                    print_entry("PUPPETEER_SERVICE_TOKEN", "${PUPPETEER_SERVICE_TOKEN}")
                }
            }
            service=""; environment_seen=0; token_seen=0; url_seen=0; style="list"
        }
        function start_service(name) {
            finish_service()
            service=name; environment_seen=0; token_seen=0; url_seen=0; style="list"
        }
        /^  puppeteer:[[:space:]]*(#.*)?$/ { start_service("puppeteer"); print; next }
        /^  backend:[[:space:]]*(#.*)?$/ { start_service("backend"); print; next }
        /^  [A-Za-z0-9_.-]+:[[:space:]]*(#.*)?$/ { finish_service(); print; next }
        service != "" && in_environment && /^    [A-Za-z0-9_.-]+:/ {
            finish_environment()
        }
        service != "" && /^    environment:[[:space:]]*(#.*)?$/ {
            environment_seen=1; in_environment=1; token_seen=0; url_seen=0; style="list"; print; next
        }
        service != "" && in_environment {
            if ($0 ~ /^      [A-Za-z_][A-Za-z0-9_]*:/) style="mapping"
            else if ($0 ~ /^      -[[:space:]]*/) style="list"

            if ($0 ~ /^      -[[:space:]]*PUPPETEER_SERVICE_TOKEN(=|[[:space:]]*$)/ ||
                $0 ~ /^      PUPPETEER_SERVICE_TOKEN:/) {
                if (!token_seen) print_entry("PUPPETEER_SERVICE_TOKEN", "${PUPPETEER_SERVICE_TOKEN}")
                token_seen=1
                next
            }
            if (service == "puppeteer" &&
                ($0 ~ /^      -[[:space:]]*DOCX_RENDER_FRONTEND_URL(=|[[:space:]]*$)/ ||
                 $0 ~ /^      DOCX_RENDER_FRONTEND_URL:/)) {
                if (!url_seen) print_entry("DOCX_RENDER_FRONTEND_URL", "http://frontend:3000")
                url_seen=1
                next
            }
        }
        { print }
        END { finish_service() }
    ' "$source_file" > "$destination_file"
}

refresh_renderer_compose_wiring() {
    if [[ ! -f "$COMPOSE_FILE" || -L "$COMPOSE_FILE" ]]; then
        log_error "Missing or unsafe $COMPOSE_FILE; cannot migrate renderer configuration"
        return 1
    fi

    if renderer_compose_static_valid "$COMPOSE_FILE"; then
        if ! $DOCKER_COMPOSE -f "$COMPOSE_FILE" config --quiet >/dev/null; then
            log_error "Docker Compose is invalid even though renderer wiring is present"
            return 1
        fi
        return 0
    fi

    local temporary
    temporary=$(mktemp "$(dirname "$COMPOSE_FILE")/.compose.renderer.XXXXXX") || return 1
    chmod 600 "$temporary" || { rm -f "$temporary"; return 1; }

    if ! migrate_renderer_compose_file "$COMPOSE_FILE" "$temporary" \
        || ! renderer_compose_static_valid "$temporary" \
        || ! $DOCKER_COMPOSE -f "$temporary" config --quiet >/dev/null; then
        rm -f "$temporary"
        log_error "Renderer Compose migration failed validation; existing configuration was not changed"
        return 1
    fi

    mv -f "$temporary" "$COMPOSE_FILE"
    log_success "Configured secure document renderer wiring in Docker Compose"
}

refresh_managed_compose_defaults() {
    if [[ ! -f "$COMPOSE_FILE" || -L "$COMPOSE_FILE" ]]; then
        log_error "Missing or unsafe $COMPOSE_FILE"
        return 1
    fi

    local temporary
    temporary=$(mktemp "$(dirname "$COMPOSE_FILE")/.compose.defaults.XXXXXX") || return 1
    chmod 600 "$temporary" || { rm -f "$temporary"; return 1; }

    awk '
        /^    image: nginx:(alpine|1[.]27-alpine)$/ {
            sub(/nginx:.*/, "nginx:1.30.4-alpine")
        }
        {
            gsub(/http:\/\/localhost\/health/, "http://127.0.0.1/health")
            gsub(/http:\/\/localhost:3000\/health/, "http://127.0.0.1:3000/health")
            gsub(/host: '\''localhost'\''/, "host: '\''127.0.0.1'\''")
            print
        }
    ' "$COMPOSE_FILE" > "$temporary"

    if cmp -s "$COMPOSE_FILE" "$temporary"; then
        rm -f "$temporary"
        return 0
    fi

    if ! $DOCKER_COMPOSE -f "$temporary" config --quiet >/dev/null; then
        rm -f "$temporary"
        log_error "Managed Docker Compose migration failed validation"
        return 1
    fi

    mv -f "$temporary" "$COMPOSE_FILE"
    log_success "Updated managed Docker Compose runtime defaults"
}

configure_renderer_for_update() {
    validate_update_env_file || return 1
    if [[ ! -f "$COMPOSE_FILE" || -L "$COMPOSE_FILE" ]]; then
        log_error "Missing or unsafe $COMPOSE_FILE"
        return 1
    fi

    local transaction_dir
    transaction_dir=$(mktemp -d "$INSTALL_DIR/.renderer-update.XXXXXX") || return 1
    chmod 700 "$transaction_dir" || { rm -rf "$transaction_dir"; return 1; }
    install -m 600 "$ENV_FILE" "$transaction_dir/env.before" || { rm -rf "$transaction_dir"; return 1; }
    install -m 600 "$COMPOSE_FILE" "$transaction_dir/compose.before" || { rm -rf "$transaction_dir"; return 1; }

    if ! ensure_renderer_secret \
        || ! refresh_renderer_compose_wiring \
        || ! refresh_managed_compose_defaults; then
        install -m 600 "$transaction_dir/env.before" "$ENV_FILE"
        install -m 600 "$transaction_dir/compose.before" "$COMPOSE_FILE"
        rm -rf "$transaction_dir"
        log_error "Renderer migration rolled back .env and Docker Compose"
        return 1
    fi

    rm -rf "$transaction_dir"
}

refresh_nginx_config() {
    local nginx_config="$INSTALL_DIR/nginx.conf"
    local nginx_template="$TEMPLATES_DIR/nginx.conf.tmpl"

    if cmp -s "$nginx_template" "$nginx_config"; then
        log_info "Nginx configuration is already up to date"
        return 0
    fi

    local backup_path="${nginx_config}.backup-$(date -u +%Y%m%dT%H%M%SZ)"
    cp "$nginx_config" "$backup_path"
    cp "$nginx_template" "$nginx_config"

    # Resolve the upstream service names locally so nginx -t validates the
    # generated file even when the application containers are currently stopped.
    if ! docker run --rm \
        --add-host frontend:127.0.0.1 \
        --add-host backend:127.0.0.1 \
        --add-host mcp:127.0.0.1 \
        -v "$nginx_config:/etc/nginx/nginx.conf:ro" \
        nginx:1.30.4-alpine nginx -t; then
        cp "$backup_path" "$nginx_config"
        log_error "The updated Nginx configuration is invalid; restored $backup_path"
        return 1
    fi

    log_success "Nginx configuration updated (backup: $backup_path)"
}

cmd_update() {
    check_initialized

    log_step "Updating Vulnotes..."

    cd "$INSTALL_DIR"

    # Migrate credentials and both consumers as a single transaction before any
    # image pull or container recreation can observe a partial configuration.
    configure_renderer_for_update

    # Re-login to registry (credentials might have expired)
    if [[ -n "${REGISTRY_USERNAME:-}" ]]; then
        log_info "Authenticating with registry..."
        docker pull "$REGISTRY_URL/vulnotes-app/backend:latest" 2>/dev/null || {
            log_warn "Registry authentication may have expired. Please run 'vulnotes init' again if pull fails."
        }
    fi

    log_info "Pulling latest images..."
    $DOCKER_COMPOSE pull

    log_info "Refreshing managed Nginx configuration..."
    refresh_nginx_config

    log_info "Recreating containers..."
    $DOCKER_COMPOSE up -d --force-recreate

    log_success "Vulnotes updated successfully!"
}
