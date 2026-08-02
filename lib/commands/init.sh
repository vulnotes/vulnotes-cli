#!/usr/bin/env bash
# Init command for Vulnotes CLI

cmd_init() {
    umask 077
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

    # Create backups directory (owner-only: archives contain .env / JWT_SECRET)
    secure_backup_root

    log_info "Redeeming provisioning token..."

    # Call the manager API to redeem the token
    local response
    response=$(curl -sf -X POST \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg token "$token" '{token: $token}')" \
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

    # Generate independent secrets for user sessions and the internal renderer.
    local jwt_secret puppeteer_service_token
    jwt_secret=$(generate_random_hex 32)
    puppeteer_service_token=$(generate_random_hex 32)

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
        echo
        log_warn "Option 2 publishes Vulnotes on port $http_port over PLAIN HTTP, with no TLS."
        echo "  Logins, session tokens and full report contents will cross the network"
        echo "  in cleartext and can be read or modified by anyone on the path."
        echo
        echo "  Recommended instead: keep option 1 (127.0.0.1) and put a TLS-terminating"
        echo "  reverse proxy (nginx + Let's Encrypt, Traefik, Caddy) in front of it,"
        echo "  forwarding to 127.0.0.1:$http_port."
        echo
        read -p "Publish on 0.0.0.0 without TLS anyway? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            bind_address="0.0.0.0"
        else
            log_info "Keeping local-only binding (127.0.0.1)"
        fi
    fi

    echo
    log_info "Generating configuration files..."

    generate_docker_compose "$http_port" "$bind_address"
    generate_nginx_conf
    generate_env_file "$domain" "$jwt_secret" "$backronaut_secret" "$support_api_token" "$http_port" "$puppeteer_service_token"

    # Create license file with private key for backend license validation
    log_info "Creating license file..."
    jq -n \
      --arg licenseKey "$license_key" \
      --arg privateKey "$private_key" \
      --arg managerUrl "$MANAGER_URL" \
      --arg provisionedAt "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
      '{licenseKey: $licenseKey, clientPrivateKey: $privateKey, managerUrl: $managerUrl, provisionedAt: $provisionedAt}' \
      > "$INSTALL_DIR/license.json"
    # license.json holds clientPrivateKey. Restrict it to the backend container's
    # runtime user (uid 1001 — see the backend image's Dockerfile) where we have
    # the privilege to do so; otherwise keep the previous 644 so the container can
    # still read it, and lock the install directory instead.
    if chown 1001:1001 "$INSTALL_DIR/license.json" 2>/dev/null; then
        chmod 600 "$INSTALL_DIR/license.json"
    else
        chmod 644 "$INSTALL_DIR/license.json"
        log_warn "Could not restrict ownership of license.json (needs root)."
        log_warn "It stays readable by other local users of this machine."
        log_warn "To lock it down later: sudo chown 1001:1001 license.json && sudo chmod 600 license.json"
    fi

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
        echo -e "     ${YELLOW}This URL is plain HTTP — credentials and reports are sent in cleartext.${NC}"
        echo -e "     ${YELLOW}Put a TLS reverse proxy in front of it before real use (see below).${NC}"
    fi
    echo
    echo -e "${BOLD}Exposing to the internet:${NC}"
    echo -e "  For production deployments with a domain name, you need to configure SSL."
    echo -e "  Use a reverse proxy like ${CYAN}Traefik${NC} or ${CYAN}Nginx${NC} with SSL certificates"
    echo -e "  from Let's Encrypt or another certificate provider."
    echo
}
