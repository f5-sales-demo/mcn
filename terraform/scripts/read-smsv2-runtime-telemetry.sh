#!/usr/bin/env sh
# There is currently no published authenticated F5 runtime telemetry endpoint or
# approved stable export. Return an explicit unavailable result; do not derive
# GRE, BGP, MTU, interface, health, or route values from Terraform or AWS.
set -eu

query=$(cat)
release=$(printf '%s' "$query" | jq -er '.release | strings')
schema=$(printf '%s' "$query" | jq -er '.telemetry_schema_version | strings')

jq -cn \
  --arg release_tag "$release" \
  --arg schema_version "$schema" \
  '{available:"false",release_tag:$release_tag,schema_version:$schema_version,reason:"no-published-authenticated-runtime-telemetry-api"}'
