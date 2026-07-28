#!/usr/bin/env bash
# Hermetic test for terraform/scripts/xc-env-tenant.sh — the program behind the
# tenant guard in terraform/main.tf (issue #696).
#
# The guard's whole job is to answer one question correctly: which F5 XC tenant
# does XCSH_API_URL name? Everything downstream is a string comparison, so an
# extraction bug is a guard that either blocks a correct deployment or waves the
# incorrect one through — the second being the failure that put the MCN demo in
# the wrong tenant in the first place.
#
# The mismatch branch cannot be exercised from a .tftest.hcl, because a Terraform
# test cannot set an environment variable. It is exercised here instead: this file
# owns the environment and can hand the program each case directly.
#
# No network, no credentials, no Terraform.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="${REPO_ROOT}/terraform/scripts/xc-env-tenant.sh"

FAIL=0

# expect <description> <expected-json> [url]
# Omitting the url argument runs with XCSH_API_URL UNSET, which is not the same
# case as setting it empty and is what CI actually looks like.
expect() {
  local desc="$1" want="$2" got
  if [ "$#" -ge 3 ]; then
    got=$(XCSH_API_URL="$3" sh "$SCRIPT")
  else
    got=$(env -u XCSH_API_URL sh "$SCRIPT")
  fi

  if [ "$got" = "$want" ]; then
    printf 'ok   %s\n' "$desc"
  else
    printf 'FAIL %s\n       want: %s\n       got:  %s\n' "$desc" "$want" "$got"
    FAIL=1
  fi
}

# --- The two tenants this repository has actually been pointed at -------------

expect 'the intended tenant' \
  '{"tenant":"f5-sales-demo","api_url_set":"true"}' \
  'https://f5-sales-demo.console.ves.volterra.io'

expect 'the tenant the demo was accidentally rehomed to' \
  '{"tenant":"f5-amer-ent","api_url_set":"true"}' \
  'https://f5-amer-ent.console.ves.volterra.io'

# --- URL shapes an operator or a credential file might hold -------------------

expect 'trailing slash' \
  '{"tenant":"f5-sales-demo","api_url_set":"true"}' \
  'https://f5-sales-demo.console.ves.volterra.io/'

expect 'an /api path, as some tooling writes it' \
  '{"tenant":"f5-sales-demo","api_url_set":"true"}' \
  'https://f5-sales-demo.console.ves.volterra.io/api'

expect 'a deep path' \
  '{"tenant":"f5-sales-demo","api_url_set":"true"}' \
  'https://f5-sales-demo.console.ves.volterra.io/api/config/namespaces/system'

expect 'a query string' \
  '{"tenant":"f5-sales-demo","api_url_set":"true"}' \
  'https://f5-sales-demo.console.ves.volterra.io?x=1'

expect 'an explicit port' \
  '{"tenant":"f5-sales-demo","api_url_set":"true"}' \
  'https://f5-sales-demo.console.ves.volterra.io:443'

expect 'plain http' \
  '{"tenant":"f5-sales-demo","api_url_set":"true"}' \
  'http://f5-sales-demo.console.ves.volterra.io'

expect 'no scheme at all' \
  '{"tenant":"f5-sales-demo","api_url_set":"true"}' \
  'f5-sales-demo.console.ves.volterra.io'

# --- Abstention: unset means "no opinion", not "mismatch" ---------------------
#
# This is the case CI runs in. If it ever reported a tenant, every credential-free
# `terraform test` and `terraform init -backend=false` would fail the guard.

expect 'XCSH_API_URL unset (CI): abstain' \
  '{"tenant":"","api_url_set":"false"}'

expect 'XCSH_API_URL set but empty: abstain' \
  '{"tenant":"","api_url_set":"false"}' \
  ''

# --- Malformed input must never produce a tenant, or broken JSON --------------
#
# The tenant is interpolated into the JSON the data source parses. A value
# carrying a quote or a brace would corrupt the document and fail the plan with a
# parse error instead of the guard's message; report no tenant instead.

expect 'not a URL' \
  '{"tenant":"","api_url_set":"true"}' \
  'not a url'

expect 'a value containing a double quote' \
  '{"tenant":"","api_url_set":"true"}' \
  'https://ev"il.console.ves.volterra.io'

expect 'a value containing JSON punctuation' \
  '{"tenant":"","api_url_set":"true"}' \
  'https://a{b}:c.console.ves.volterra.io'

expect 'an underscore, which is not legal in a hostname label' \
  '{"tenant":"","api_url_set":"true"}' \
  'https://f5_sales_demo.console.ves.volterra.io'

if [ "$FAIL" -ne 0 ]; then
  printf '\nxc-env-tenant: FAILURES\n'
  exit 1
fi

printf '\nxc-env-tenant: all checks passed\n'
