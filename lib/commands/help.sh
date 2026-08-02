#!/usr/bin/env bash
# Help command for Vulnotes CLI

cmd_help() {
    echo -e "${CYAN}${BOLD}Vulnotes CLI v${VERSION}${NC}"
    echo
    echo "Manage on-prem Vulnotes deployments."
    echo
    echo -e "${BOLD}USAGE:${NC}"
    echo "    vulnotes <command> [options]"
    echo
    echo -e "${BOLD}COMMANDS:${NC}"
    echo -e "    ${CYAN}init${NC}              Initialize a new Vulnotes deployment"
    echo -e "    ${CYAN}start${NC}             Start Vulnotes containers"
    echo -e "    ${CYAN}stop${NC}              Stop Vulnotes containers"
    echo -e "    ${CYAN}restart${NC}           Restart Vulnotes containers"
    echo -e "    ${CYAN}update${NC}            Refresh config, pull images, and recreate containers"
    echo -e "    ${CYAN}reset${NC}             Wipe all data and return to a clean install (backs up first)"
    echo -e "    ${CYAN}logs${NC}              View container logs"
    echo -e "    ${CYAN}backup${NC}            Create a backup of data and configuration"
    echo -e "    ${CYAN}backup-rotate${NC}     Apply retention policy to existing backups"
    echo -e "    ${CYAN}backup-schedule${NC}   Manage automatic backup scheduling"
    echo -e "    ${CYAN}restore${NC}           Restore from a backup"
    echo -e "    ${CYAN}help${NC}              Show this help message"
    echo
    echo -e "${BOLD}INIT OPTIONS:${NC}"
    echo "    --token, -t <token>     Provisioning token from Vulnotes Manager (required)"
    echo "    --dir <path>            Installation directory (default: ./vulnotes)"
    echo
    echo -e "${BOLD}LOGS OPTIONS:${NC}"
    echo "    -f, --follow            Follow log output"
    echo "    -n, --lines <num>       Number of lines to show (default: 100)"
    echo "    <service>               Service: nginx, backend, frontend, mongodb, puppeteer, mcp"
    echo
    echo -e "${BOLD}BACKUP OPTIONS:${NC}"
    echo "    --scheduled             Run backup with automatic rotation (used by cron)"
    echo
    echo -e "${BOLD}RESET:${NC}"
    echo "    Deletes the database, uploads, logs and caches; keeps .env, license.json,"
    echo "    nginx.conf and docker-compose.yml, then restarts into first-time setup."
    echo "    Always backs up first and asks for confirmation (no flags)."
    echo
    echo -e "${BOLD}BACKUP-SCHEDULE OPTIONS:${NC}"
    echo "    enable                  Enable automatic daily backups at 2:00 AM"
    echo "    disable                 Disable automatic backups"
    echo "    status                  Show current backup schedule and stats (default)"
    echo
    echo -e "${BOLD}BACKUP RETENTION POLICY:${NC}"
    echo "    Daily backups are kept for 7 days"
    echo "    Weekly backups (1 per week) are kept for 4 weeks"
    echo "    Monthly backups (1 per month) are kept for 6 months"
    echo
    echo -e "${BOLD}RESTORE OPTIONS:${NC}"
    echo "    <backup-file>           Backup file to restore (required)"
    echo "    (default)               Restores MongoDB and uploads only; the current"
    echo "                            .env and nginx.conf are kept untouched"
    echo "    --restore-config        ALSO overwrite .env and nginx.conf from the archive."
    echo "                            The archive then controls JWT_SECRET and the nginx"
    echo "                            config that is loaded into the container, so use it"
    echo "                            only with an archive you created yourself. A diff of"
    echo "                            nginx.conf is shown and confirmation is required."
    echo "    --data-only             Explicit form of the default (accepted for"
    echo "                            compatibility with existing runbooks)"
    echo
    echo -e "${BOLD}ENVIRONMENT VARIABLES:${NC}"
    echo "    VULNOTES_DIR            Override default installation directory"
    echo "    VULNOTES_SKIP_UPDATE_CHECK=1"
    echo "                            Disable the failure-tolerant CLI release check"
    echo "    VULNOTES_CLI_UPDATE_CHECK_INTERVAL"
    echo "                            Cache duration in seconds (default: 21600)"
}

cmd_version() {
    echo "vulnotes v$VERSION"
}
