#!/usr/bin/env bash
# S1 numeric-validation gate for the SMSv2 coverage probe.
#
# Proves the provider v3.75.0 SMSv2 numeric validators both ACCEPT valid bounds and REJECT
# out-of-range input, entirely credential-free (mock_provider fires the real schema
# validators at plan). This wraps `terraform test` because Terraform's `expect_failures`
# only captures user-defined custom conditions, not provider schema attribute validators, so
# a rejection cannot be asserted as a passing test run natively.
#
#   Phase 1 (accept): plain `terraform test` runs the root accept case -> must exit 0.
#   Phase 2 (reject): `terraform test -test-directory=reject-tests` runs the DESIGNED-TO-FAIL
#                     reject cases -> must exit non-zero AND emit each leaf's exact validator
#                     message. One reject run per file (a failing run halts its own file).
#
# Idempotent and deterministic: no state, no network, same result every run / in CI.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

echo "== Phase 1: accept valid bounds (plain terraform test) =="
if ! terraform test; then
  fail "accept_valid_bounds did not pass 'terraform test'"
fi

echo
echo "== Phase 2: reject out-of-range input (terraform test -test-directory=reject-tests) =="
reject_out="$(terraform test -test-directory=reject-tests 2>&1)"
reject_rc=$?
echo "${reject_out}"

if [ "${reject_rc}" -eq 0 ]; then
  fail "reject suite exited 0 — validators did NOT reject out-of-range input"
fi

# Normalize: strip ANSI colors and box-drawing gutters, then join wrapped diagnostic
# lines into one blob so each validator message matches regardless of terminal wrapping.
reject_norm="$(printf '%s' "${reject_out}" | sed $'s/\x1b\\[[0-9;]*m//g' | tr '\n' ' ' | sed 's/\xe2\x94\x82//g' | tr -s ' ')"

# Each leaf's exact validator diagnostic must appear.
declare -a expected=(
  "must be at most 16384, got: 20000"
  "must be between 0 and 255, got: 256"
  "must be between 1 and 4095, got: 4096"
  "must be between 0 and 65535, got: 70000"
)
for msg in "${expected[@]}"; do
  case "${reject_norm}" in
  *"${msg}"*) echo "OK: validator emitted -> ${msg}" ;;
  *) fail "expected validator message not found -> ${msg}" ;;
  esac
done

echo
echo "PASS: S1 numeric validators accept valid bounds and reject all four out-of-range leaves."
