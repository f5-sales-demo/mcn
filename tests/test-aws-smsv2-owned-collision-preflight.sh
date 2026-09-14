#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
script="$repo_root/scripts/aws-smsv2-owned-collision-preflight.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
plan="$scratch/plan.json"
manifest="$scratch/manifest.json"
fake_bin="$scratch/bin"
mkdir -p "$fake_bin"

cat >"$plan" <<'JSON'
{
  "resource_changes": [
    {
      "address": "aws_key_pair.ce[0]",
      "type": "aws_key_pair",
      "change": {
        "actions": ["create"],
        "after": {
          "key_name": "owned-key",
          "tags": {
            "component": "mcn-ce-ha",
            "deployer": "tester",
            "managed_by": "terraform"
          }
        }
      }
    },
    {
      "address": "xcsh_virtual_site.aws[0]",
      "type": "xcsh_virtual_site",
      "change": {
        "actions": ["create"],
        "after": {
          "name": "owned-vsite",
          "namespace": "multi-cloud-networking"
        }
      }
    }
  ]
}
JSON

cat >"$fake_bin/aws" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *"describe-key-pairs"*"owned-key"*)
    if [[ ${FAKE_ABSENT:-false} == true ]]; then
      printf '%s\n' 'InvalidKeyPair.NotFound' >&2
      exit 255
    fi
    printf '%s\n' '{"KeyPairs":[{"Tags":[{"Key":"component","Value":"mcn-ce-ha"},{"Key":"deployer","Value":"tester"},{"Key":"managed_by","Value":"terraform"}]}]}'
    ;;
  *)
    printf '%s\n' 'unexpected aws command' >&2
    exit 64
    ;;
esac
EOF
chmod +x "$fake_bin/aws"

cat >"$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output=""
while (($#)); do
  case "$1" in
    --output) output=$2; shift 2 ;;
    *) url=$1; shift ;;
  esac
done
case "$url" in
  */virtual_sites/owned-vsite)
    if [[ ${FAKE_ABSENT:-false} == true ]]; then
      : >"$output"
      printf 404
      exit 0
    fi
    printf '%s\n' '{"metadata":{"name":"owned-vsite","namespace":"multi-cloud-networking"},"system_metadata":{"creator_id":"tester@example.test"}}' >"$output"
    printf 200
    ;;
  *)
    : >"$output"
    printf 404
    ;;
esac
EOF
chmod +x "$fake_bin/curl"

set +e
output=$(PATH="$fake_bin:$PATH" CURL_BIN="$fake_bin/curl" \
  XCSH_API_URL=https://f5-sales-demo.console.ves.volterra.io XCSH_API_TOKEN=test-token \
  "$script" --plan-json "$plan" --aws-region ap-northeast-1 --xc-tenant f5-sales-demo \
  --creator-id tester@example.test --manifest "$manifest" 2>&1)
status=$?
set -e
test "$status" -eq 3 || fail "owned collision must exit 3, got $status: $output"
[[ "$output" == *"owned collision"* ]] || fail "owned collision diagnostic missing"
jq -e '
  .schema_version == 1 and
  .status == "blocked" and
  (.collisions | length) == 2 and
  ([.collisions[].ownership] | all(. == "verified")) and
  ([.collisions[].name] | sort) == ["owned-key", "owned-vsite"]
' "$manifest" >/dev/null || fail "manifest must retain the exact verified collision inventory"

empty_manifest="$scratch/empty-manifest.json"
if ! FAKE_ABSENT=true PATH="$fake_bin:$PATH" CURL_BIN="$fake_bin/curl" \
  XCSH_API_URL=https://f5-sales-demo.console.ves.volterra.io XCSH_API_TOKEN=test-token \
  "$script" --plan-json "$plan" --aws-region ap-northeast-1 --xc-tenant f5-sales-demo \
  --creator-id tester@example.test --manifest "$empty_manifest" >/dev/null; then
  fail "an absent planned name must pass the collision preflight"
fi
jq -e '.status == "ready" and .collisions == []' "$empty_manifest" >/dev/null ||
  fail "no-collision manifest must be explicitly ready and empty"

printf 'PASS: owned AWS and F5 name collisions are rejected before Terraform apply with a verified manifest\n'
