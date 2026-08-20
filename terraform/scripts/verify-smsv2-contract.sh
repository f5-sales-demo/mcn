#!/usr/bin/env bash
# Verify an immutable public SMSv2 release without trusting local cached specs.
# Terraform external-data protocol: JSON in on stdin, a flat JSON map on stdout.
set -euo pipefail

readonly REPOSITORY='f5-sales-demo/api-specs-enriched'
query=$(cat)
release=$(jq -er '.release | strings' <<<"$query")

case "$release" in
v[0-9]*.[0-9]*.[0-9]*) ;;
*) echo 'release must be a stable vX.Y.Z tag' >&2; exit 2 ;;
esac

release_json=$(gh api "repos/${REPOSITORY}/releases/tags/${release}")
if [ "$(jq -r '.draft or .prerelease' <<<"$release_json")" != false ]; then
  echo 'SMSv2 release is draft or prerelease' >&2
  exit 3
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
asset_id() {
  jq -er --arg name "$1" '.assets[] | select(.name == $name) | .id' <<<"$release_json"
}
download() {
  gh api -H 'Accept: application/octet-stream' "repos/${REPOSITORY}/releases/assets/$(asset_id "$1")" >"$work/$1"
}

download smsv2-contract-manifest.json
download smsv2-contract.json
download smsv2-evidence-receipt.json

manifest="$work/smsv2-contract-manifest.json"
contract="$work/smsv2-contract.json"
receipt="$work/smsv2-evidence-receipt.json"
sha() { sha256sum "$1" | awk '{print $1}'; }
expected_contract=$(jq -er '.assets["smsv2-contract.json"] | sub("^sha256:"; "")' "$manifest")
expected_receipt=$(jq -er '.assets["smsv2-evidence-receipt.json"] | sub("^sha256:"; "")' "$manifest")
[ "$(sha "$contract")" = "$expected_contract" ] || { echo 'SMSv2 contract checksum mismatch' >&2; exit 4; }
[ "$(sha "$receipt")" = "$expected_receipt" ] || { echo 'SMSv2 receipt checksum mismatch' >&2; exit 4; }
[ "$(jq -er '.release.tag' "$manifest")" = "$release" ] || { echo 'SMSv2 manifest release tag mismatch' >&2; exit 4; }
[ "$(jq -er '.contract_id' "$manifest")" = 'f5xc-ce-automation/v1' ] || { echo 'unexpected SMSv2 contract identity' >&2; exit 4; }
[ "$(jq -er '.contract_id' "$contract")" = "$(jq -er '.contract_id' "$receipt")" ] || { echo 'SMSv2 receipt identity mismatch' >&2; exit 4; }
[ "$(jq -er '[.receipts[].sanitized] | all' "$receipt")" = true ] || { echo 'SMSv2 receipt is not sanitized' >&2; exit 4; }
tag_commit=$(git ls-remote "https://github.com/${REPOSITORY}.git" "refs/tags/${release}^{}" | awk 'NR == 1 { print $1 }')
[ "$tag_commit" = "$(jq -er '.release.commit' "$manifest")" ] || { echo 'SMSv2 release commit mismatch' >&2; exit 4; }

jq -cn \
  --arg release_tag "$release" \
  --arg release_commit "$tag_commit" \
  --arg contract_sha256 "$expected_contract" \
  --arg receipt_sha256 "$expected_receipt" \
  --arg runtime_status "$(jq -er '.providers.aws.capabilities.runtime_status' "$contract")" \
  --arg tgw_connect "$(jq -er '.providers.aws.capabilities.tgw_connect' "$contract")" \
  --arg telemetry_schema_version "$(jq -r '.providers.aws.telemetry.schema_version // "unavailable"' "$contract")" \
  '{verified:"true",release_tag:$release_tag,release_commit:$release_commit,contract_sha256:$contract_sha256,receipt_sha256:$receipt_sha256,runtime_status:$runtime_status,tgw_connect:$tgw_connect,telemetry_schema_version:$telemetry_schema_version}'
