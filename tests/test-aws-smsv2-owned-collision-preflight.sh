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
            "deployment_generation": "gen-01",
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
          "namespace": "multi-cloud-networking",
          "labels": {"mcn-deployment-generation": "gen-01"}
        }
      }
    },
    {
      "address": "xcsh_securemesh_site_v2.aws[\"01\"]",
      "type": "xcsh_securemesh_site_v2",
      "change": {
        "actions": ["create"],
        "after": {
          "name": "owned-site",
          "namespace": "system",
          "labels": {"mcn-deployment-generation": "gen-01"}
        }
      }
    },
    {
      "address": "xcsh_bgp.aws_tgw[\"01\"]",
      "type": "xcsh_bgp",
      "change": {
        "actions": ["create"],
        "after": {
          "name": "owned-bgp",
          "namespace": "system",
          "labels": {"mcn-deployment-generation": "gen-01"}
        }
      }
    },
    {
      "address": "xcsh_external_connector.aws_tgw[\"node_01_slo\"]",
      "type": "xcsh_external_connector",
      "change": {
        "actions": ["create"],
        "after": {
          "name": "owned-connector",
          "namespace": "system",
          "labels": {"mcn-deployment-generation": "gen-01"}
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
  *"sts get-caller-identity"*)
    printf '{"Account":"%s"}\n' "${FAKE_ACCOUNT_ID:-123456789012}"
    ;;
  *"describe-key-pairs"*"owned-key"*)
    if [[ ${FAKE_ABSENT:-false} == true ]]; then
      printf '%s\n' 'InvalidKeyPair.NotFound' >&2
      exit 255
    fi
    generation=${FAKE_AWS_GENERATION:-gen-01}
    printf '{"KeyPairs":[{"KeyPairId":"key-0123456789abcdef0","CreateTime":"2026-09-16T12:00:00Z","Tags":[{"Key":"component","Value":"mcn-ce-ha"},{"Key":"deployment_generation","Value":"%s"},{"Key":"deployer","Value":"tester"},{"Key":"managed_by","Value":"terraform"}]}]}\n' "$generation"
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
    generation=${FAKE_F5_GENERATION:-gen-01}
    printf '{"metadata":{"name":"owned-vsite","namespace":"multi-cloud-networking","labels":{"mcn-deployment-generation":"%s"}},"system_metadata":{"uid":"11111111-1111-1111-1111-111111111111","creation_timestamp":"2026-09-16T12:00:00Z","creator_id":"tester@example.test"}}\n' "$generation" >"$output"
    printf 200
    ;;
  */securemesh_site_v2s/owned-site | */bgps/owned-bgp | */external_connectors/owned-connector)
    if [[ ${FAKE_ABSENT:-false} == true ]]; then
      : >"$output"
      printf 404
      exit 0
    fi
    name=${url##*/}
    generation=${FAKE_F5_GENERATION:-gen-01}
    printf '{"metadata":{"name":"%s","namespace":"system","labels":{"mcn-deployment-generation":"%s"}},"system_metadata":{"uid":"22222222-2222-2222-2222-222222222222","creation_timestamp":"2026-09-16T12:00:00Z","creator_id":"tester@example.test"}}\n' "$name" "$generation" >"$output"
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
  --aws-account-id 123456789012 --deployment-generation gen-01 \
  --creator-id tester@example.test --manifest "$manifest" 2>&1)
status=$?
set -e
test "$status" -eq 3 || fail "owned collision must exit 3, got $status: $output"
[[ "$output" == *"owned collision"* ]] || fail "owned collision diagnostic missing"
jq -e '
  .schema_version == 1 and
  .status == "blocked" and
  .aws_account_id == "123456789012" and
  .deployment_generation == "gen-01" and
  (.collisions | length) == 5 and
  ([.collisions[].ownership] | all(. == "verified")) and
  ([.collisions[] | select(.engine == "f5") | .creator_id] | all(. == "tester@example.test")) and
  ([.collisions[] | select(.engine == "f5") | .created_at] | all(. == "2026-09-16T12:00:00Z")) and
  ([.collisions[] | select(.engine == "f5") | .resource_uid] | all(type == "string" and length > 0)) and
  ([.collisions[] | select(.engine == "aws") | .observed_tags.deployment_generation] | all(. == "gen-01")) and
  ([.collisions[] | select(.engine == "aws") | .resource_uid] | all(type == "string" and length > 0)) and
  ([.collisions[] | select(.engine == "aws") | .created_at] | all(. == "2026-09-16T12:00:00Z")) and
  ([.collisions[].name] | sort) == ["owned-bgp", "owned-connector", "owned-key", "owned-site", "owned-vsite"]
' "$manifest" >/dev/null || fail "manifest must retain the exact verified collision inventory"

empty_manifest="$scratch/empty-manifest.json"
if ! FAKE_ABSENT=true PATH="$fake_bin:$PATH" CURL_BIN="$fake_bin/curl" \
  XCSH_API_URL=https://f5-sales-demo.console.ves.volterra.io XCSH_API_TOKEN=test-token \
  "$script" --plan-json "$plan" --aws-region ap-northeast-1 --xc-tenant f5-sales-demo \
  --aws-account-id 123456789012 --deployment-generation gen-01 \
  --creator-id tester@example.test --manifest "$empty_manifest" >/dev/null; then
  fail "an absent planned name must pass the collision preflight"
fi
jq -e '.status == "ready" and .collisions == []' "$empty_manifest" >/dev/null ||
  fail "no-collision manifest must be explicitly ready and empty"

expect_rejection() {
  local label=$1 expected=$2
  shift 2
  local rejected_output rejected_status
  set +e
  rejected_output=$(env "$@" PATH="$fake_bin:$PATH" CURL_BIN="$fake_bin/curl" \
    XCSH_API_URL=https://f5-sales-demo.console.ves.volterra.io XCSH_API_TOKEN=test-token \
    "$script" --plan-json "$plan" --aws-region ap-northeast-1 --xc-tenant f5-sales-demo \
    --aws-account-id 123456789012 --deployment-generation gen-01 \
    --creator-id tester@example.test --manifest "$scratch/rejected-$label.json" 2>&1)
  rejected_status=$?
  set -e
  test "$rejected_status" -eq 2 || fail "$label must fail closed with exit 2, got $rejected_status"
  [[ "$rejected_output" == *"$expected"* ]] || fail "$label diagnostic is not actionable: $rejected_output"
  [[ ! -e "$scratch/rejected-$label.json" ]] || fail "$label must not produce an ownership manifest"
}

expect_rejection account-mismatch "caller account does not match" FAKE_ACCOUNT_ID=999999999999
expect_rejection aws-generation-mismatch "unowned or ambiguous AWS collision" FAKE_AWS_GENERATION=gen-02
expect_rejection f5-generation-mismatch "unowned or ambiguous F5 collision" FAKE_F5_GENERATION=gen-02

set +e
invalid_output=$(PATH="$fake_bin:$PATH" CURL_BIN="$fake_bin/curl" \
  XCSH_API_URL=https://f5-sales-demo.console.ves.volterra.io XCSH_API_TOKEN=test-token \
  "$script" --plan-json "$plan" --aws-region ap-northeast-1 --xc-tenant f5-sales-demo \
  --aws-account-id 123456789012 --deployment-generation INVALID \
  --creator-id tester@example.test --manifest "$scratch/invalid-generation.json" 2>&1)
invalid_status=$?
set -e
test "$invalid_status" -eq 2 || fail "invalid generation must fail closed with exit 2"
[[ "$invalid_output" == *"deployment generation"* ]] || fail "invalid generation diagnostic is missing"

printf 'PASS: owned AWS and F5 name collisions are rejected before Terraform apply with a verified manifest\n'
