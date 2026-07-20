#!/usr/bin/env bash
# Backup and restore commands for Vulnotes CLI

# Backup retention defaults
BACKUP_KEEP_DAILY=7
BACKUP_KEEP_WEEKLY=4
BACKUP_KEEP_MONTHLY=6

cmd_backup() {
    check_initialized

    local scheduled=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --scheduled)
                scheduled=true
                shift
                ;;
            *)
                die "Unknown option: $1"
                ;;
        esac
    done

    cd "$INSTALL_DIR"

    require_vulnotes_running "creating a backup"

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
    $DOCKER_COMPOSE exec -T mongodb sh -c '
        AUTH=""
        if [ -n "$MONGO_INITDB_ROOT_USERNAME" ]; then AUTH="-u $MONGO_INITDB_ROOT_USERNAME -p $MONGO_INITDB_ROOT_PASSWORD --authenticationDatabase admin"; fi
        exec mongodump --archive --gzip $AUTH
    ' > "$backup_path/mongodb.archive.gz" || {
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

    # Run rotation if this is a scheduled backup
    if [[ "$scheduled" == "true" ]]; then
        echo
        cmd_backup_rotate
    fi
}

# Rotate backups using a Grandfather-Father-Son (GFS) retention policy:
#   - Daily:   keep last 7 days
#   - Weekly:  keep 1 per week for 4 weeks
#   - Monthly: keep 1 per month for 6 months
cmd_backup_rotate() {
    check_initialized

    local backup_dir="$INSTALL_DIR/backups"
    local now
    now=$(date +%s)

    local daily_seconds=$((BACKUP_KEEP_DAILY * 86400))
    local weekly_seconds=$(( (BACKUP_KEEP_WEEKLY + 1) * 7 * 86400 ))
    local monthly_seconds=$((BACKUP_KEEP_MONTHLY * 31 * 86400))

    log_step "Rotating backups (keep ${BACKUP_KEEP_DAILY}d / ${BACKUP_KEEP_WEEKLY}w / ${BACKUP_KEEP_MONTHLY}m)"

    # Collect all backup files with their parsed dates
    local -a all_backups=()
    local -a keep_files=()
    local -A weekly_kept=()
    local -A monthly_kept=()

    # List backups sorted newest first
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        all_backups+=("$file")
    done < <(ls -1t "$backup_dir"/vulnotes-backup-*.tar.gz 2>/dev/null)

    if [[ ${#all_backups[@]} -eq 0 ]]; then
        log_info "No backups found to rotate."
        return
    fi

    for file in "${all_backups[@]}"; do
        local basename
        basename=$(basename "$file")

        # Parse date from filename: vulnotes-backup-YYYYMMDD-HHMMSS.tar.gz
        local date_part
        date_part=$(echo "$basename" | sed -n 's/vulnotes-backup-\([0-9]\{8\}\)-\([0-9]\{6\}\)\.tar\.gz/\1/p')

        if [[ -z "$date_part" ]]; then
            # Also match pre-restore backups - always keep these
            if [[ "$basename" == vulnotes-pre-restore-* ]]; then
                keep_files+=("$file")
            fi
            continue
        fi

        # Parse date components
        local year="${date_part:0:4}"
        local month="${date_part:4:2}"
        local day="${date_part:6:2}"

        local file_ts
        file_ts=$(date -d "${year}-${month}-${day}" +%s 2>/dev/null) || continue
        local age_seconds=$((now - file_ts))

        if [[ $age_seconds -le $daily_seconds ]]; then
            # Within daily retention window - keep all
            keep_files+=("$file")
        elif [[ $age_seconds -le $weekly_seconds ]]; then
            # Within weekly retention window - keep one per ISO week
            local iso_week
            iso_week=$(date -d "${year}-${month}-${day}" +%G-W%V 2>/dev/null)
            if [[ -z "${weekly_kept[$iso_week]+_}" ]]; then
                # First (newest) backup for this week - keep it
                weekly_kept[$iso_week]=1
                keep_files+=("$file")
            fi
        elif [[ $age_seconds -le $monthly_seconds ]]; then
            # Within monthly retention window - keep one per month
            local year_month="${year}-${month}"
            if [[ -z "${monthly_kept[$year_month]+_}" ]]; then
                # First (newest) backup for this month - keep it
                monthly_kept[$year_month]=1
                keep_files+=("$file")
            fi
        fi
        # Anything older than monthly window is not kept
    done

    # Build a set of files to keep for fast lookup
    local -A keep_set=()
    for f in "${keep_files[@]}"; do
        keep_set["$f"]=1
    done

    # Delete backups not in the keep set
    local deleted=0
    for file in "${all_backups[@]}"; do
        if [[ -z "${keep_set[$file]+_}" ]]; then
            rm -f "$file"
            ((deleted++))
        fi
    done

    local kept=${#keep_files[@]}
    if [[ $deleted -gt 0 ]]; then
        log_success "Rotation complete: kept $kept backups, removed $deleted old backups"
    else
        log_info "Rotation complete: all $kept backups are within retention policy"
    fi

    # Show disk usage
    local total_size
    total_size=$(du -sh "$backup_dir" 2>/dev/null | cut -f1)
    echo -e "Total backup storage: ${CYAN}$total_size${NC}"
}

# Set up or remove the automatic backup cron schedule
cmd_backup_schedule() {
    check_initialized

    local action="${1:-status}"

    case "$action" in
        enable|on)
            _backup_cron_install
            ;;
        disable|off)
            _backup_cron_remove
            ;;
        status)
            _backup_cron_status
            ;;
        *)
            die "Usage: vulnotes backup-schedule [enable|disable|status]"
            ;;
    esac
}

_backup_cron_install() {
    local vulnotes_bin
    vulnotes_bin=$(command -v vulnotes 2>/dev/null || echo "$SCRIPT_DIR/vulnotes")
    local cron_marker="# vulnotes-auto-backup"
    local install_dir="$INSTALL_DIR"
    local log_file="$INSTALL_DIR/backups/backup.log"

    # Build the cron line: daily at 2 AM
    local cron_line="0 2 * * * cd ${install_dir} && ${vulnotes_bin} backup --scheduled >> ${log_file} 2>&1 ${cron_marker}"

    # Remove any existing vulnotes cron entry before adding
    local existing_crontab
    existing_crontab=$(crontab -l 2>/dev/null || true)
    local new_crontab
    new_crontab=$(echo "$existing_crontab" | grep -v "$cron_marker" || true)

    # Add the new cron line
    if [[ -n "$new_crontab" ]]; then
        echo -e "${new_crontab}\n${cron_line}" | crontab -
    else
        echo "$cron_line" | crontab -
    fi

    log_success "Automatic backups enabled (daily at 2:00 AM)"
    echo -e "  Retention: ${CYAN}${BACKUP_KEEP_DAILY}${NC} daily, ${CYAN}${BACKUP_KEEP_WEEKLY}${NC} weekly, ${CYAN}${BACKUP_KEEP_MONTHLY}${NC} monthly"
    echo -e "  Log file:  ${CYAN}${log_file}${NC}"
}

_backup_cron_remove() {
    local cron_marker="# vulnotes-auto-backup"
    local existing_crontab
    existing_crontab=$(crontab -l 2>/dev/null || true)

    if echo "$existing_crontab" | grep -q "$cron_marker"; then
        echo "$existing_crontab" | grep -v "$cron_marker" | crontab -
        log_success "Automatic backups disabled"
    else
        log_info "Automatic backups are not currently enabled"
    fi
}

_backup_cron_status() {
    local cron_marker="# vulnotes-auto-backup"
    local existing_crontab
    existing_crontab=$(crontab -l 2>/dev/null || true)

    if echo "$existing_crontab" | grep -q "$cron_marker"; then
        log_success "Automatic backups are enabled"
        echo
        echo -e "  Schedule:  ${CYAN}Daily at 2:00 AM${NC}"
        echo -e "  Retention: ${CYAN}${BACKUP_KEEP_DAILY}${NC} daily, ${CYAN}${BACKUP_KEEP_WEEKLY}${NC} weekly, ${CYAN}${BACKUP_KEEP_MONTHLY}${NC} monthly"
        echo
        echo -e "  ${BOLD}Cron entry:${NC}"
        echo "  $(echo "$existing_crontab" | grep "$cron_marker")"
    else
        log_info "Automatic backups are not enabled"
        echo -e "  Enable with: ${CYAN}vulnotes backup-schedule enable${NC}"
    fi

    # Show existing backups summary
    local backup_count
    backup_count=$(ls -1 "$INSTALL_DIR/backups/"vulnotes-backup-*.tar.gz 2>/dev/null | wc -l)
    local total_size
    total_size=$(du -sh "$INSTALL_DIR/backups" 2>/dev/null | cut -f1)
    echo
    echo -e "  Backups:   ${CYAN}${backup_count}${NC} files using ${CYAN}${total_size}${NC}"
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
        require_vulnotes_running "creating a safety backup (or re-run and decline the safety backup)"

        local pre_restore_name="vulnotes-pre-restore-$(date +%Y%m%d-%H%M%S)"
        local pre_restore_path="$INSTALL_DIR/backups/$pre_restore_name"

        log_info "Creating safety backup before restore..."
        mkdir -p "$pre_restore_path"

        # Backup MongoDB
        if $DOCKER_COMPOSE exec -T mongodb sh -c '
            AUTH=""
            if [ -n "$MONGO_INITDB_ROOT_USERNAME" ]; then AUTH="-u $MONGO_INITDB_ROOT_USERNAME -p $MONGO_INITDB_ROOT_PASSWORD --authenticationDatabase admin"; fi
            exec mongodump --archive --gzip $AUTH
        ' > "$pre_restore_path/mongodb.archive.gz" 2>/dev/null; then
            log_info "MongoDB backed up"
        else
            log_warn "Could not backup MongoDB"
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
        log_error "Invalid backup archive: no 'vulnotes-backup-*' directory found inside $backup_file"
        echo
        echo "  This usually means one of:"
        echo "    - The archive was created while Vulnotes was not running (mongodump produced no output)"
        echo "    - The archive is a pre-restore safety backup (named 'vulnotes-pre-restore-*'); rename its inner directory or extract manually"
        echo "    - The file is corrupted or was created by a different tool"
        echo
        exit 1
    fi

    # Restore MongoDB
    if [[ -f "$backup_dir/mongodb.archive.gz" ]]; then
        log_info "Restoring MongoDB..."
        $DOCKER_COMPOSE up -d mongodb
        sleep 5
        $DOCKER_COMPOSE exec -T mongodb sh -c '
            AUTH=""
            if [ -n "$MONGO_INITDB_ROOT_USERNAME" ]; then AUTH="-u $MONGO_INITDB_ROOT_USERNAME -p $MONGO_INITDB_ROOT_PASSWORD --authenticationDatabase admin"; fi
            exec mongorestore --archive --gzip --drop $AUTH --nsInclude="vulnotes.*"
        ' < "$backup_dir/mongodb.archive.gz"
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
