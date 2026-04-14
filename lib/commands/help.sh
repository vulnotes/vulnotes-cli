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
    echo -e "    ${CYAN}update${NC}            Pull latest images and recreate containers"
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
    echo "    <service>               Service name: nginx, backend, frontend, mongodb, puppeteer"
    echo
    echo -e "${BOLD}BACKUP OPTIONS:${NC}"
    echo "    --scheduled             Run backup with automatic rotation (used by cron)"
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
    echo "    --data-only             Restore only MongoDB and uploads, keep current config"
    echo "                            (useful for migrating data between instances)"
    echo
    echo -e "${BOLD}ENVIRONMENT VARIABLES:${NC}"
    echo "    VULNOTES_DIR            Override default installation directory"
}

cmd_version() {
    echo "vulnotes v$VERSION"
}
