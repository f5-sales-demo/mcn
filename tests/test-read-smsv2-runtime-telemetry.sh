#!/usr/bin/env sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
script="$repo_root/terraform/scripts/read-smsv2-runtime-telemetry.sh"

output=$(printf '%s\n' '{"release":"v9.9.9","telemetry_schema_version":"future-schema"}' | "$script")
[ "$(printf '%s' "$output" | jq -r '.available')" = false ]
[ "$(printf '%s' "$output" | jq -r '.release_tag')" = v9.9.9 ]
[ "$(printf '%s' "$output" | jq -r '.schema_version')" = future-schema ]
[ "$(printf '%s' "$output" | jq -r '.reason')" = no-published-authenticated-runtime-telemetry-api ]
[ "$(printf '%s' "$output" | jq 'keys | length')" -eq 4 ]
printf '%s\n' 'PASS: runtime telemetry reader fails closed without an F5 operational API.'
