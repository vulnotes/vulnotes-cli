#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

SCRIPT_DIR="$repo_dir"
INSTALL_DIR="$test_dir"
ENV_FILE="$test_dir/.env"
COMPOSE_FILE="$test_dir/docker-compose.yml"
DOCKER_COMPOSE=true

source "$repo_dir/lib/utils.sh"
source "$repo_dir/lib/templates.sh"
source "$repo_dir/lib/commands/lifecycle.sh"
log_success() { :; }
log_error() { :; }

generate_env_file "https://example.test" "jwt" "" "" 443
token=$(sed -n 's/^PUPPETEER_SERVICE_TOKEN=//p' "$ENV_FILE")
[[ "$token" =~ ^[0-9a-f]{64}$ ]]
[[ $(stat -c '%a' "$ENV_FILE" 2>/dev/null || stat -f '%Lp' "$ENV_FILE") == 600 ]]

cat > "$COMPOSE_FILE" <<'YAML'
services:
  puppeteer:
    environment:
      - PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
  backend:
    environment:
      - PUPPETEER_SERVICE_URL=http://puppeteer:3001
YAML

refresh_renderer_compose_wiring
[[ $(grep -c 'PUPPETEER_SERVICE_TOKEN=${PUPPETEER_SERVICE_TOKEN}' "$COMPOSE_FILE") == 2 ]]
grep -q 'DOCX_RENDER_FRONTEND_URL=http://frontend:3000' "$COMPOSE_FILE"

# The migration is idempotent.
refresh_renderer_compose_wiring
[[ $(grep -c 'PUPPETEER_SERVICE_TOKEN=${PUPPETEER_SERVICE_TOKEN}' "$COMPOSE_FILE") == 2 ]]
