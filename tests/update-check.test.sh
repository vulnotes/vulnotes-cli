#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT_DIR/lib/config.sh"
source "$ROOT_DIR/lib/utils.sh"

version_is_newer v1.0.1 1.0.0
version_is_newer v2.0.0 1.99.99
! version_is_newer v1.0.0 1.0.0
! version_is_newer v0.9.9 1.0.0
! version_is_newer invalid 1.0.0

test_home=$(mktemp -d)
trap 'rm -rf "$test_home"' EXIT

HOME="$test_home"
XDG_CACHE_HOME="$test_home/cache"
VULNOTES_CLI_UPDATE_CHECK_INTERVAL=21600

curl() {
    printf '%s\n' '{"tag_name":"v9.8.7"}'
}

latest=$(get_latest_cli_version)
[[ "$latest" == "v9.8.7" ]]

# A fresh cache must keep the check non-blocking when GitHub is unavailable.
curl() {
    return 1
}

cached=$(get_latest_cli_version)
[[ "$cached" == "v9.8.7" ]]

get_latest_cli_version() {
    echo "v9.8.7"
}

notice=$(check_cli_update)
[[ "$notice" == *"v1.0.6 -> v9.8.7"* ]]

get_latest_cli_version() {
    echo "9.8.7"
}

notice=$(check_cli_update)
[[ "$notice" == *"v1.0.6 -> v9.8.7"* ]]

VULNOTES_SKIP_UPDATE_CHECK=1
[[ -z "$(check_cli_update)" ]]

echo "CLI update-check tests passed"
