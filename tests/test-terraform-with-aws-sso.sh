#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
wrapper="$repo_root/scripts/terraform-with-aws-sso.sh"
deploy_guide="$repo_root/docs/en/demo/deploy.mdx"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

mkdir -p "$work/bin"
cat >"$work/bin/aws" <<'AWS'
#!/usr/bin/env bash
set -euo pipefail
[ "$*" = "configure export-credentials --profile default --format process" ]
printf '%s\n' '{"Version":1,"AccessKeyId":"test_access","SecretAccessKey":"test_secret","SessionToken":"test_session","Expiration":"2099-01-01T00:00:00Z"}'
AWS
cat >"$work/bin/terraform" <<'TERRAFORM'
#!/usr/bin/env bash
set -euo pipefail
[ "${AWS_PROFILE:-}" = "mcn-terraform" ]
[ "${AWS_SDK_LOAD_CONFIG:-}" = "1" ]
[ "${AWS_SHARED_CREDENTIALS_FILE:-}" = "/dev/null" ]
[ -r "${AWS_CONFIG_FILE:-}" ]
[ "$(stat -c %a "$AWS_CONFIG_FILE" 2>/dev/null || stat -f %Lp "$AWS_CONFIG_FILE")" = "600" ]
grep -Fq '[profile mcn-terraform]' "$AWS_CONFIG_FILE"
grep -Fq 'credential_process = ' "$AWS_CONFIG_FILE"
if grep -Fq 'credential_process = "' "$AWS_CONFIG_FILE"; then
  printf 'quoted credential_process executable is not supported by Terraform S3 backend\n' >&2
  exit 1
fi
if grep -Eq 'test_access|test_secret|test_session' "$AWS_CONFIG_FILE"; then
  printf 'credential values were written to disk\n' >&2
  exit 1
fi
printf '%s\n' "$*" >"${WRAPPER_TEST_ARGS:?}"
TERRAFORM
chmod +x "$work/bin/aws" "$work/bin/terraform"

cat >"$work/source-config" <<'CONFIG'
[profile default]
sso_session = test
sso_account_id = 123456789012
sso_role_name = Users
region = us-east-1
[sso-session test]
sso_start_url = https://example.awsapps.com/start
sso_region = us-east-1
CONFIG

[ -x "$wrapper" ] || fail "wrapper is not executable"

WRAPPER_TEST_ARGS="$work/args" \
  PATH="$work/bin:$PATH" \
  AWS_CONFIG_FILE="$work/source-config" \
  AWS_REGION="ap-northeast-1" \
  "$wrapper" --profile default -- plan -out=reviewed.tfplan

[ "$(cat "$work/args")" = "plan -out=reviewed.tfplan" ] ||
  fail "Terraform arguments were not preserved"

credentials=$(
  PATH="$work/bin:$PATH" \
    "$wrapper" __export_credentials default "$work/source-config" "$work/bin/aws"
)
printf '%s' "$credentials" | jq -e '
  .Version == 1 and
  .AccessKeyId == "test_access" and
  .SecretAccessKey == "test_secret" and
  .SessionToken == "test_session"
' >/dev/null || fail "credential_process output was not valid AWS process credentials"

if PATH="$work/bin:$PATH" AWS_CONFIG_FILE="$work/source-config" \
  "$wrapper" --profile '../invalid' -- version >/dev/null 2>&1; then
  fail "invalid source profile was accepted"
fi

grep -Fq './scripts/terraform-with-aws-sso.sh -- -chdir=terraform/bootstrap/state-backend init' "$deploy_guide" ||
  fail "backend bootstrap guidance does not use the credential-isolation wrapper"
grep -Fq '../scripts/terraform-with-aws-sso.sh -- init' "$deploy_guide" ||
  fail "showcase guidance does not use the credential-isolation wrapper"

printf 'PASS: Terraform uses isolated AWS CLI SSO process credentials\n'
