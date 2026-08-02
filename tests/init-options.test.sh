#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

SCRIPT_DIR="$repo_dir"
source "$repo_dir/lib/config.sh"
source "$repo_dir/lib/utils.sh"
source "$repo_dir/lib/commands/init.sh"

if (cmd_init --token) >/dev/null 2>&1; then
    echo "accepted --token without a value" >&2
    exit 1
fi

if (cmd_init -t) >/dev/null 2>&1; then
    echo "accepted -t without a value" >&2
    exit 1
fi

if (cmd_init --dir) >/dev/null 2>&1; then
    echo "accepted --dir without a value" >&2
    exit 1
fi

echo "Init option tests passed"
