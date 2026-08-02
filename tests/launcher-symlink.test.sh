#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

mkdir -p "$test_dir/bin"

cat > "$test_dir/bin/docker" <<'SH'
#!/usr/bin/env bash
exit 0
SH

for dependency in curl jq openssl; do
    cp "$test_dir/bin/docker" "$test_dir/bin/$dependency"
done

chmod 700 "$test_dir/bin/docker" "$test_dir/bin/curl" "$test_dir/bin/jq" "$test_dir/bin/openssl"
ln -s "$repo_dir/vulnotes" "$test_dir/bin/vulnotes"

output=$(PATH="$test_dir/bin:$PATH" VULNOTES_SKIP_UPDATE_CHECK=1 "$test_dir/bin/vulnotes" --version)
[[ "$output" == "vulnotes v1.0.7" ]]

echo "Launcher symlink test passed"
