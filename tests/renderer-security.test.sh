#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

SCRIPT_DIR="$repo_dir"
source "$repo_dir/lib/config.sh"
update_paths "$test_dir/install"
mkdir -p "$INSTALL_DIR"
source "$repo_dir/lib/utils.sh"
source "$repo_dir/lib/templates.sh"
source "$repo_dir/lib/commands/lifecycle.sh"
source "$repo_dir/lib/commands/backup.sh"

log_success() { :; }
log_info() { :; }
log_warn() { :; }
log_error() { :; }

mode_of() {
    stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
}

fake_compose="$test_dir/fake-compose"
cat > "$fake_compose" <<'SH'
#!/usr/bin/env bash
set -e
[[ "$1" == "-f" && -s "$2" && "$3" == "config" && "$4" == "--quiet" ]]
SH
chmod 700 "$fake_compose"
DOCKER_COMPOSE="$fake_compose"

generate_env_file "https://example.test" "jwt-secret" "" "" 443
token=$(sed -n 's/^PUPPETEER_SERVICE_TOKEN=//p' "$ENV_FILE")
[[ "$token" =~ ^[0-9a-f]{64}$ ]]
[[ "$(mode_of "$ENV_FILE")" == 600 ]]

# Valid credentials are retained, while an overly permissive file is repaired.
chmod 644 "$ENV_FILE"
ensure_renderer_secret
[[ "$(sed -n 's/^PUPPETEER_SERVICE_TOKEN=//p' "$ENV_FILE")" == "$token" ]]
[[ "$(mode_of "$ENV_FILE")" == 600 ]]

# Strict validation rotates wrong-length, uppercase and otherwise malformed data.
sed 's/^PUPPETEER_SERVICE_TOKEN=.*/PUPPETEER_SERVICE_TOKEN=ABCDEF/' "$ENV_FILE" > "$ENV_FILE.next"
mv "$ENV_FILE.next" "$ENV_FILE"
ensure_renderer_secret
rotated=$(sed -n 's/^PUPPETEER_SERVICE_TOKEN=//p' "$ENV_FILE")
[[ "$rotated" =~ ^[0-9a-f]{64}$ && "$rotated" != "ABCDEF" ]]

# Missing baseline settings must fail without producing a token-only file.
printf 'JWT_SECRET=jwt\n' > "$ENV_FILE"
before=$(cksum "$ENV_FILE")
if ensure_renderer_secret; then
    echo "accepted .env without DOMAIN" >&2
    exit 1
fi
[[ "$(cksum "$ENV_FILE")" == "$before" ]]

cat > "$ENV_FILE" <<EOF
DOMAIN=https://example.test
JWT_SECRET=jwt-secret
PUPPETEER_SERVICE_TOKEN=$rotated
EOF
chmod 600 "$ENV_FILE"

# List syntax: comments do not count and wrong literals/URLs are normalized.
cat > "$COMPOSE_FILE" <<'YAML'
services:
  puppeteer:
    image: renderer
    environment:
      # PUPPETEER_SERVICE_TOKEN=looks-valid-but-is-only-a-comment
      - NODE_ENV=production
      - PUPPETEER_SERVICE_TOKEN=wrong-literal
      - DOCX_RENDER_FRONTEND_URL=https://attacker.invalid
  backend:
    environment:
      - PUPPETEER_SERVICE_TOKEN=another-wrong-literal
  frontend:
    image: frontend
YAML
refresh_renderer_compose_wiring
[[ "$(grep -c 'PUPPETEER_SERVICE_TOKEN=${PUPPETEER_SERVICE_TOKEN}' "$COMPOSE_FILE")" == 2 ]]
[[ "$(grep -c 'DOCX_RENDER_FRONTEND_URL=http://frontend:3000' "$COMPOSE_FILE")" == 1 ]]
list_checksum=$(cksum "$COMPOSE_FILE")
refresh_renderer_compose_wiring
[[ "$(cksum "$COMPOSE_FILE")" == "$list_checksum" ]]

# An exact entry plus an overriding literal must not be mistaken for valid.
awk '/PUPPETEER_SERVICE_TOKEN=\$\{PUPPETEER_SERVICE_TOKEN\}/ && ++seen == 1 { print; print "      - PUPPETEER_SERVICE_TOKEN=override"; next } { print }' "$COMPOSE_FILE" > "$COMPOSE_FILE.duplicate"
mv "$COMPOSE_FILE.duplicate" "$COMPOSE_FILE"
refresh_renderer_compose_wiring
[[ "$(grep -c 'PUPPETEER_SERVICE_TOKEN=' "$COMPOSE_FILE")" == 2 ]]
[[ "$(grep -c 'PUPPETEER_SERVICE_TOKEN=${PUPPETEER_SERVICE_TOKEN}' "$COMPOSE_FILE")" == 2 ]]

# Mapping syntax is preserved and missing keys are inserted.
cat > "$COMPOSE_FILE" <<'YAML'
services:
  puppeteer:
    environment:
      NODE_ENV: production
      PUPPETEER_SERVICE_TOKEN: literal
  backend:
    image: backend
    environment:
      NODE_ENV: production
YAML
refresh_renderer_compose_wiring
grep -q '^      PUPPETEER_SERVICE_TOKEN: ${PUPPETEER_SERVICE_TOKEN}$' "$COMPOSE_FILE"
grep -q '^      DOCX_RENDER_FRONTEND_URL: http://frontend:3000$' "$COMPOSE_FILE"
[[ "$(grep -c '^    environment:' "$COMPOSE_FILE")" == 2 ]]

# Missing environment blocks are added without depending on image/URL anchors.
cat > "$COMPOSE_FILE" <<'YAML'
services:
  puppeteer:
    image: renderer
  backend:
    image: backend
YAML
refresh_renderer_compose_wiring
renderer_compose_static_valid "$COMPOSE_FILE"

# Static wiring cannot mask a Compose parser failure.
valid_compose=$(cat "$COMPOSE_FILE")
DOCKER_COMPOSE=false
if refresh_renderer_compose_wiring; then
    echo "accepted renderer wiring without effective Compose validation" >&2
    exit 1
fi
DOCKER_COMPOSE="$fake_compose"
printf '%s\n' "$valid_compose" > "$COMPOSE_FILE"

# Unsupported aliases and missing target services fail transactionally: neither
# the newly generated token nor Compose modifications may survive.
cat > "$ENV_FILE" <<'EOF'
DOMAIN=https://example.test
JWT_SECRET=jwt-secret
EOF
chmod 644 "$ENV_FILE"
cat > "$COMPOSE_FILE" <<'YAML'
services:
  puppeteer:
    environment: *renderer_environment
  backend:
    environment:
      - NODE_ENV=production
YAML
env_before=$(cksum "$ENV_FILE")
compose_before=$(cksum "$COMPOSE_FILE")
if configure_renderer_for_update; then
    echo "accepted aliased renderer environment" >&2
    exit 1
fi
[[ "$(cksum "$ENV_FILE")" == "$env_before" ]]
[[ "$(cksum "$COMPOSE_FILE")" == "$compose_before" ]]

cat > "$COMPOSE_FILE" <<'YAML'
services:
  backend:
    environment:
      - NODE_ENV=production
YAML
if configure_renderer_for_update; then
    echo "accepted Compose file without puppeteer service" >&2
    exit 1
fi
[[ "$(cksum "$ENV_FILE")" == "$env_before" ]]

# Backup roots, copies, partial archives and final archives are owner-only.
secure_backup_root
[[ "$(mode_of "$INSTALL_DIR/backups")" == 700 ]]
backup_name=vulnotes-backup-test
install -d -m 700 "$INSTALL_DIR/backups/$backup_name"
install -m 600 "$ENV_FILE" "$INSTALL_DIR/backups/$backup_name/env.backup"
(
    cd "$INSTALL_DIR/backups"
    secure_pack_backup "$backup_name"
)
[[ "$(mode_of "$INSTALL_DIR/backups/$backup_name.tar.gz")" == 600 ]]
[[ -z "$(find "$INSTALL_DIR/backups" -name '*.partial.*' -print -quit)" ]]

echo "Renderer and backup security tests passed"
