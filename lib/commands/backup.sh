#!/usr/bin/env bash
# Backup and restore commands for Vulnotes CLI

cmd_backup() {
    check_initialized

    cd "$INSTALL_DIR"

    # Check if Vulnotes is running
    if ! $DOCKER_COMPOSE ps --status running 2>/dev/null | grep -q "mongodb"; then
        die "Vulnotes is not running. Start it with 'vulnotes start' before creating a backup."
    fi

    local backup_name
    backup_name="vulnotes-backup-$(date +%Y%m%d-%H%M%S)"
    local backup_path="$INSTALL_DIR/backups/$backup_name"

    log_step "Creating backup: $backup_name"

    mkdir -p "$backup_path"

    # Get volume name
    local uploads_volume
    uploads_volume=$(get_volume_name "backend_uploads")

    # Backup MongoDB
    log_info "Backing up MongoDB..."
    $DOCKER_COMPOSE exec -T mongodb mongodump --archive --gzip > "$backup_path/mongodb.archive.gz" || {
        die "Failed to backup MongoDB"
    }

    # Backup volumes
    log_info "Backing up uploads..."
    docker run --rm \
        -v "$uploads_volume:/data" \
        -v "$backup_path:/backup" \
        alpine tar czf /backup/uploads.tar.gz -C /data . 2>/dev/null || {
        log_warn "Could not backup uploads volume (may not exist yet)"
    }

    # Backup configuration files
    log_info "Backing up configuration..."
    cp "$INSTALL_DIR/.env" "$backup_path/env.backup" 2>/dev/null || true
    cp "$INSTALL_DIR/license.json" "$backup_path/license.json" 2>/dev/null || true
    cp "$INSTALL_DIR/nginx.conf" "$backup_path/nginx.conf" 2>/dev/null || true

    # Create backup manifest
    cat > "$backup_path/manifest.json" << MANIFEST_EOF
{
  "version": "$VERSION",
  "created": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "components": {
    "mongodb": true,
    "uploads": true,
    "config": true
  }
}
MANIFEST_EOF

    # Create archive
    log_info "Creating backup archive..."
    cd "$INSTALL_DIR/backups"
    tar czf "$backup_name.tar.gz" "$backup_name"
    rm -rf "$backup_name"

    log_success "Backup created: $INSTALL_DIR/backups/$backup_name.tar.gz"

    # Show backup size
    local size
    size=$(du -h "$INSTALL_DIR/backups/$backup_name.tar.gz" | cut -f1)
    echo -e "Backup size: ${CYAN}$size${NC}"
}

cmd_restore() {
    check_initialized

    local backup_file=""
    local data_only=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --data-only)
                data_only=true
                shift
                ;;
            -*)
                die "Unknown option: $1"
                ;;
            *)
                backup_file="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$backup_file" ]]; then
        log_info "Available backups:"
        ls -la "$INSTALL_DIR/backups/"*.tar.gz 2>/dev/null || {
            die "No backups found in $INSTALL_DIR/backups/"
        }
        echo
        die "Usage: vulnotes restore <backup-file> [--data-only]"
    fi

    if [[ ! -f "$backup_file" ]]; then
        # Try to find in backups directory
        if [[ -f "$INSTALL_DIR/backups/$backup_file" ]]; then
            backup_file="$INSTALL_DIR/backups/$backup_file"
        else
            die "Backup file not found: $backup_file"
        fi
    fi

    log_step "Restoring from backup: $backup_file"

    if [[ "$data_only" == "true" ]]; then
        log_info "Data-only mode: will restore MongoDB and uploads only (no config files)"
    fi

    log_warn "This will overwrite current data and restart Vulnotes."
    read -p "Continue? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi

    cd "$INSTALL_DIR"

    # Get volume name
    local uploads_volume
    uploads_volume=$(get_volume_name "backend_uploads")

    # Ask about pre-restore backup
    local create_safety_backup
    read -p "Create a safety backup before restoring? [Y/n] " -n 1 -r create_safety_backup
    echo
    create_safety_backup="${create_safety_backup:-Y}"

    if [[ $create_safety_backup =~ ^[Yy]$ ]] || [[ -z "$create_safety_backup" ]]; then
        local pre_restore_name="vulnotes-pre-restore-$(date +%Y%m%d-%H%M%S)"
        local pre_restore_path="$INSTALL_DIR/backups/$pre_restore_name"

        log_info "Creating safety backup before restore..."
        mkdir -p "$pre_restore_path"

        # Backup MongoDB (if running)
        if $DOCKER_COMPOSE exec -T mongodb mongodump --archive --gzip > "$pre_restore_path/mongodb.archive.gz" 2>/dev/null; then
            log_info "MongoDB backed up"
        else
            log_warn "Could not backup MongoDB (may not be running)"
            rm -f "$pre_restore_path/mongodb.archive.gz"
        fi

        # Backup uploads volume
        docker run --rm \
            -v "$uploads_volume:/data" \
            -v "$pre_restore_path:/backup" \
            alpine tar czf /backup/uploads.tar.gz -C /data . 2>/dev/null || {
            log_warn "Could not backup uploads volume (may not exist)"
        }

        # Backup configuration files
        cp "$INSTALL_DIR/.env" "$pre_restore_path/env.backup" 2>/dev/null || true
        cp "$INSTALL_DIR/license.json" "$pre_restore_path/license.json" 2>/dev/null || true
        cp "$INSTALL_DIR/nginx.conf" "$pre_restore_path/nginx.conf" 2>/dev/null || true

        # Create backup manifest
        cat > "$pre_restore_path/manifest.json" << MANIFEST_EOF
{
  "version": "$VERSION",
  "created": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "type": "pre-restore",
  "components": {
    "mongodb": true,
    "uploads": true,
    "config": true
  }
}
MANIFEST_EOF

        # Create archive
        cd "$INSTALL_DIR/backups"
        tar czf "$pre_restore_name.tar.gz" "$pre_restore_name"
        rm -rf "$pre_restore_name"
        cd "$INSTALL_DIR"

        log_success "Safety backup created: backups/$pre_restore_name.tar.gz"
    else
        log_info "Skipping safety backup"
    fi

    # Stop containers
    log_info "Stopping Vulnotes..."
    $DOCKER_COMPOSE down 2>/dev/null || true

    # Extract backup
    local restore_dir
    restore_dir=$(mktemp -d)
    tar xzf "$backup_file" -C "$restore_dir"

    # Find the backup folder
    local backup_dir
    backup_dir=$(find "$restore_dir" -maxdepth 1 -type d -name "vulnotes-backup-*" | head -1)

    if [[ -z "$backup_dir" ]]; then
        rm -rf "$restore_dir"
        die "Invalid backup archive"
    fi

    # Restore MongoDB
    if [[ -f "$backup_dir/mongodb.archive.gz" ]]; then
        log_info "Restoring MongoDB..."
        $DOCKER_COMPOSE up -d mongodb
        sleep 5
        $DOCKER_COMPOSE exec -T mongodb mongorestore --archive --gzip --drop < "$backup_dir/mongodb.archive.gz"
        $DOCKER_COMPOSE stop mongodb
    fi

    # Restore uploads
    if [[ -f "$backup_dir/uploads.tar.gz" ]]; then
        log_info "Restoring uploads..."
        docker run --rm \
            -v "$uploads_volume:/data" \
            -v "$backup_dir:/backup" \
            alpine sh -c "rm -rf /data/* && tar xzf /backup/uploads.tar.gz -C /data"
    fi

    # Restore config files (unless --data-only)
    if [[ "$data_only" != "true" ]]; then
        log_info "Restoring configuration files..."
        [[ -f "$backup_dir/env.backup" ]] && cp "$backup_dir/env.backup" "$INSTALL_DIR/.env"
        [[ -f "$backup_dir/license.json" ]] && cp "$backup_dir/license.json" "$INSTALL_DIR/license.json"
        [[ -f "$backup_dir/nginx.conf" ]] && cp "$backup_dir/nginx.conf" "$INSTALL_DIR/nginx.conf"
    else
        log_info "Skipping config files (--data-only mode)"
    fi

    # Cleanup
    rm -rf "$restore_dir"

    # Start Vulnotes
    log_info "Starting Vulnotes..."
    $DOCKER_COMPOSE up -d

    log_success "Restore completed! Vulnotes is now starting..."
}
