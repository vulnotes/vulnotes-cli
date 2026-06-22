#!/usr/bin/env bash
# Reset command for Vulnotes CLI — wipe all data and return to a clean install.
#
# A reset removes the Docker named volumes (database, uploads, logs and caches)
# but PRESERVES the on-disk config files (.env, license.json, nginx.conf,
# docker-compose.yml), so the instance keeps its domain, secrets and license and
# can be brought straight back up into first-time setup.
#
# It is intentionally destructive and irreversible for the data in those volumes,
# so it ALWAYS takes a full backup first and ALWAYS requires explicit confirmation.

cmd_reset() {
    check_initialized

    if [[ $# -gt 0 ]]; then
        die "Unknown option: $1 (usage: vulnotes reset)"
    fi

    cd "$INSTALL_DIR"

    log_step "Reset Vulnotes"
    echo
    log_warn "This will PERMANENTLY DELETE all data on this instance:"
    echo -e "  ${RED}•${NC} Database       (reports, findings, users, companies, templates)"
    echo -e "  ${RED}•${NC} Uploaded files (attachments, images)"
    echo -e "  ${RED}•${NC} Logs and license cache"
    echo
    echo -e "The following are ${GREEN}preserved${NC} (so the instance can be reused):"
    echo -e "  ${GREEN}•${NC} .env (domain, JWT & service secrets)"
    echo -e "  ${GREEN}•${NC} license.json"
    echo -e "  ${GREEN}•${NC} nginx.conf and docker-compose.yml"
    echo
    log_info "A full backup will be taken before anything is deleted."
    echo

    # --- Confirmation gate ---
    read -p "Are you sure you want to reset this instance? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Reset cancelled."
        exit 0
    fi

    # Second, typed-phrase confirmation for this irreversible action
    local confirm_phrase
    read -p "Type 'reset' to confirm: " -r confirm_phrase
    if [[ "$confirm_phrase" != "reset" ]]; then
        log_info "Reset cancelled (confirmation phrase did not match)."
        exit 0
    fi

    # --- Back up first ---
    if ! is_vulnotes_running; then
        die "Vulnotes must be running to take the pre-reset backup. Start it with 'vulnotes start', then re-run 'vulnotes reset'."
    fi
    log_step "Creating pre-reset backup..."
    # cmd_backup will 'die' on failure, aborting the reset before anything is deleted.
    cmd_backup
    echo

    # --- Destroy data volumes (containers + named volumes; bind-mounted config stays) ---
    log_step "Removing containers and data volumes..."
    $DOCKER_COMPOSE down -v

    # --- Bring the instance back up clean ---
    log_step "Starting a fresh instance..."
    $DOCKER_COMPOSE up -d

    echo
    log_success "Vulnotes has been reset to a clean state."
    echo
    echo -e "Open ${CYAN}${DOMAIN:-your Vulnotes URL}${NC} to run first-time setup and create the initial admin."
    echo
    echo -e "A pre-reset backup was saved in ${CYAN}$INSTALL_DIR/backups/${NC}"
    echo -e "Restore it any time with: ${CYAN}vulnotes restore <backup-file>${NC}"
}
