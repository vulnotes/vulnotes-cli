#!/usr/bin/env bash
# Init command for Vulnotes CLI

cmd_init() {
    local token=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --token|-t)
                token="$2"
                shift 2
                ;;
            --dir)
                update_paths "$2"
                shift 2
                ;;
            *)
                die "Unknown option: $1"
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$token" ]]; then
        die "Provisioning token is required. Use --token <token>"
    fi

    log_step "Initializing Vulnotes deployment"

    # Check if already initialized
    if [[ -f "$CONFIG_FILE" ]]; then
        log_warn "Vulnotes is already initialized in $INSTALL_DIR"
        read -p "Do you want to reinitialize? This will overwrite existing configuration. [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi

    # Create backups directory
    mkdir -p "$INSTALL_DIR/backups"

    log_info "Redeeming provisioning token..."

    # Call the manager API to redeem the token
    local response
    response=$(curl -sf -X POST \
        -H "Content-Type: application/json" \
        -d "{\"token\": \"$token\"}" \
        "$MANAGER_URL/api/provisioning/redeem" 2>&1) || {
        die "Failed to redeem provisioning token. Please check the token and try again."
    }

    # Parse response
    local license_key registry_username registry_password backronaut_secret support_api_token private_key

    license_key=$(echo "$response" | jq -r '.licenseKey')
    registry_username=$(echo "$response" | jq -r '.registryUsername')
    registry_password=$(echo "$response" | jq -r '.registryPassword')
    backronaut_secret=$(echo "$response" | jq -r '.backronautSecret // ""')
    support_api_token=$(echo "$response" | jq -r '.supportApiToken // ""')
    private_key=$(echo "$response" | jq -r '.privateKey')

    if [[ -z "$license_key" || "$license_key" == "null" ]]; then
        die "Invalid response from server. Missing license key."
    fi

    log_success "Token redeemed successfully"
    log_info "License: $license_key"

    # Generate JWT secret
    local jwt_secret
    jwt_secret=$(generate_random_hex 32)

    # Login to Docker registry
    log_info "Logging into Docker registry..."
    echo "$registry_password" | docker login "$REGISTRY_URL" -u "$registry_username" --password-stdin || {
        die "Failed to login to Docker registry"
    }
    log_success "Docker registry login successful"

    # Interactive configuration
    echo
    log_step "Configuration"
    echo

    # Ask for domain
    local domain
    read -p "Enter your domain (e.g., https://vulnotes.company.com) [http://localhost]: " domain
    domain="${domain:-http://localhost}"

    # Ask for port
    local http_port="80"
    read -p "HTTP port [80]: " http_port
    http_port="${http_port:-80}"

    # Ask for network binding
    local bind_address="127.0.0.1"
    local bind_choice
    echo
    echo "Network access:"
    echo "  1) Local only (127.0.0.1) - Only accessible from this server"
    echo "  2) External (0.0.0.0) - Accessible from network (if firewall allows)"
    read -p "Choose [1]: " bind_choice
    bind_choice="${bind_choice:-1}"
    if [[ "$bind_choice" == "2" ]]; then
        bind_address="0.0.0.0"
    fi

    echo
    log_info "Generating configuration files..."

    generate_docker_compose "$http_port" "$bind_address"
    generate_nginx_conf
    generate_env_file "$domain" "$jwt_secret" "$backronaut_secret" "$support_api_token" "$http_port"

    # Create license file with private key for backend license validation
    log_info "Creating license file..."
    jq -n \
      --arg licenseKey "$license_key" \
      --arg privateKey "$private_key" \
      --arg managerUrl "$MANAGER_URL" \
      --arg provisionedAt "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
      '{licenseKey: $licenseKey, clientPrivateKey: $privateKey, managerUrl: $managerUrl, provisionedAt: $provisionedAt}' \
      > "$INSTALL_DIR/license.json"
    chmod 600 "$INSTALL_DIR/license.json"

    # Save configuration
    cat > "$CONFIG_FILE" << CONFIG_EOF
# Vulnotes CLI Configuration
# Generated on $(date)

INSTALL_DIR="$INSTALL_DIR"
DOMAIN="$domain"
HTTP_PORT="$http_port"
LICENSE_KEY="$license_key"
REGISTRY_URL="$REGISTRY_URL"
REGISTRY_USERNAME='$registry_username'
CONFIG_EOF
    chmod 600 "$CONFIG_FILE"

    # Set up automatic daily backups with rotation
    log_info "Setting up automatic backups..."
    _backup_cron_install

    log_success "Vulnotes initialized successfully!"
    echo
    echo -e "${BOLD}Installation directory:${NC} $INSTALL_DIR"
    echo -e "${BOLD}Domain:${NC} $domain"
    echo -e "${BOLD}Port:${NC} $http_port"
    if [[ "$bind_address" == "127.0.0.1" ]]; then
        echo -e "${BOLD}Network access:${NC} Local only (127.0.0.1)"
    else
        echo -e "${BOLD}Network access:${NC} External (0.0.0.0)"
    fi
    echo
    echo -e "${BOLD}Generated files:${NC}"
    echo -e "  - ${CYAN}.env${NC}               Environment variables (JWT secret, domain, etc.)"
    echo -e "  - ${CYAN}docker-compose.yml${NC} Docker services configuration"
    echo -e "  - ${CYAN}nginx.conf${NC}         Nginx reverse proxy configuration"
    echo -e "  - ${CYAN}license.json${NC}       License file for the application"
    echo
    echo -e "${BOLD}Next steps:${NC}"
    echo -e "  1. Run ${CYAN}vulnotes start${NC} to start Vulnotes"
    if [[ "$bind_address" == "127.0.0.1" ]]; then
        echo -e "  2. Access Vulnotes at ${CYAN}http://127.0.0.1:$http_port${NC}"
    else
        echo -e "  2. Access Vulnotes at ${CYAN}http://<your-server-ip>:$http_port${NC}"
    fi
    echo
    echo -e "${BOLD}Exposing to the internet:${NC}"
    echo -e "  For production deployments with a domain name, you need to configure SSL."
    echo -e "  Use a reverse proxy like ${CYAN}Traefik${NC} or ${CYAN}Nginx${NC} with SSL certificates"
    echo -e "  from Let's Encrypt or another certificate provider."
    echo
}
