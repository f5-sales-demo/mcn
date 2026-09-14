#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
script="$repo_root/scripts/smsv2-site-name-preflight.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
fake_curl="$scratch/curl"

cat >"$fake_curl" <<'EOF'
#!/usr/bin/env bash
url="${!#}"
case "$url" in
  */sites/collision) printf 200 ;;
  */securemesh_site_v2s/collision) printf 404 ;;
  */sites/managed) printf 200 ;;
  */securemesh_site_v2s/managed) printf 200 ;;
  */sites/absent) printf 404 ;;
  */securemesh_site_v2s/absent) printf 404 ;;
  *) printf 500 ;;
esac
EOF
chmod +x "$fake_curl"

env CURL_BIN="$fake_curl" XCSH_API_URL=https://f5-sales-demo.console.ves.volterra.io XCSH_API_TOKEN=test-token \
  "$script" --site managed --site absent >/dev/null || fail "managed and absent names must pass"

set +e
output=$(env CURL_BIN="$fake_curl" XCSH_API_URL=https://f5-sales-demo.console.ves.volterra.io XCSH_API_TOKEN=test-token \
  "$script" --site collision 2>&1)
status=$?
set -e
test "$status" -eq 3 || fail "collision must exit 3, got $status"
[[ "$output" == *"generic-site reservation"* ]] || fail "collision diagnostic missing"

printf 'PASS: SMSv2 site-name preflight blocks orphan generic sites before apply\n'
