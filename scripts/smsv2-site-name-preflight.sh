#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s --site NAME [--site NAME ...]\n' "${0##*/}" >&2
  exit 64
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 2
}

sites=()
while (($#)); do
  case "$1" in
  --site)
    (($# >= 2)) || usage
    sites+=("$2")
    shift 2
    ;;
  *) usage ;;
  esac
done

((${#sites[@]})) || usage
test "${XCSH_API_URL:-}" = "https://f5-sales-demo.console.ves.volterra.io" || die "XCSH_API_URL must be the F5 Sales Demo tenant"
test -n "${XCSH_API_TOKEN:-}" || die "XCSH_API_TOKEN is required"

curl_bin=${CURL_BIN:-curl}
status() {
  "$curl_bin" --silent --output /dev/null --write-out '%{http_code}' \
    -H "Authorization: APIToken $XCSH_API_TOKEN" "$XCSH_API_URL$1"
}

collision=0
for site in "${sites[@]}"; do
  generic=$(status "/api/config/namespaces/system/sites/$site")
  smsv2=$(status "/api/config/namespaces/system/securemesh_site_v2s/$site")
  case "$generic:$smsv2" in
  404:404 | 200:200)
    printf 'OK: %s generic=%s smsv2=%s\n' "$site" "$generic" "$smsv2"
    ;;
  200:404)
    printf 'BLOCKED: %s has a generic-site reservation without a Secure Mesh v2 object\n' "$site" >&2
    collision=1
    ;;
  *)
    die "unexpected F5 response for $site: generic=$generic smsv2=$smsv2"
    ;;
  esac
done

if ((collision)); then
  printf 'ERROR: generic-site reservation collision; stop before Terraform plan/apply and retire the listed Sales Demo generic site objects through a supported platform workflow.\n' >&2
  exit 3
fi
