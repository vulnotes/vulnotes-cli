#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

SCRIPT_DIR="$repo_dir"
source "$repo_dir/lib/config.sh"
update_paths "$test_dir/install"
mkdir -p "$INSTALL_DIR"
printf 'DOMAIN=https://example.test\n' > "$CONFIG_FILE"

source "$repo_dir/lib/utils.sh"
source "$repo_dir/lib/commands/logs.sh"
source "$repo_dir/lib/commands/help.sh"

fake_compose="$test_dir/fake-compose"
cat > "$fake_compose" <<'SH'
#!/usr/bin/env bash
[[ "$1" == "logs" && "$2" == "--tail=1" && "$3" == "mcp" ]]
SH
chmod 700 "$fake_compose"
DOCKER_COMPOSE="$fake_compose"

cmd_logs --lines 1 mcp

help_output=$(cmd_help)
[[ "$help_output" == *"puppeteer, mcp"* ]]

if (cmd_logs --lines) >/dev/null 2>&1; then
    echo "accepted --lines without a value" >&2
    exit 1
fi

if (cmd_logs --lines invalid) >/dev/null 2>&1; then
    echo "accepted a non-numeric line count" >&2
    exit 1
fi

echo "Logs option tests passed"
