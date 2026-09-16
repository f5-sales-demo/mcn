#!/usr/bin/env sh
# Reports the F5 XC tenant named by XCSH_API_URL in the CURRENT ENVIRONMENT.
#
# Consumed by data.external.xc_env_tenant in ../main.tf, which fails the plan when
# the answer disagrees with var.expected_xc_tenant. See the comment on that data
# source for why the guard exists (the whole MCN demo was once silently rehomed to
# another tenant because nothing in the configuration named the intended one).
#
# Terraform's `external` data source protocol: a JSON object arrives on stdin (an
# empty one here, because the data source declares no `query`) and a flat JSON
# object of string -> string must be written to stdout. Nothing else may go to
# stdout, and a non-zero exit fails the plan.
#
# This reads the environment and NOTHING else — no XC credential, no network call,
# no Azure. That is what lets `terraform test` and `terraform init -backend=false`
# keep working in CI, where XCSH_API_URL is simply unset: the tenant comes back
# empty and the guard abstains rather than failing.
#
# Unit-tested by ../../tests/test-xc-env-tenant.sh.
set -eu

url="${XCSH_API_URL:-}"

# https://example-corp.console.ves.volterra.io/api -> example-corp
#   1. drop the scheme            3. drop any :port
#   2. drop everything from the   4. keep only the first hostname label
#      first / ? or #
xc_label=$(
  printf '%s' "$url" |
    sed -e 's#^[A-Za-z][A-Za-z0-9+.-]*://##' \
      -e 's#[/?#].*##' \
      -e 's#:[0-9]*$##' \
      -e 's#\..*##'
)

# Belt and braces: the value is interpolated into JSON, so allow only the
# characters a DNS label can hold. Anything else would have to be a malformed
# XCSH_API_URL, and an empty tenant is reported rather than broken JSON emitted.
case "$xc_label" in
*[!A-Za-z0-9-]*) xc_label='' ;;
esac

# api_url_set distinguishes "no XCSH_API_URL at all" (CI, and the guard abstains)
# from "XCSH_API_URL set to something unparseable" (a real misconfiguration).
if [ -n "$url" ]; then
  api_url_set=true
else
  api_url_set=false
fi

identity_key=tenant
printf '{"%s":"%s","api_url_set":"%s"}\n' "$identity_key" "$xc_label" "$api_url_set"
