#!/usr/bin/env bash
# Create, review, and optionally apply exactly one AWS SMSv2 lifecycle phase.
# All persistent evidence and plans must be outside the repository.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
TERRAFORM_DIR="$REPO_ROOT/terraform/aws"
PHASE=""
PLAN_FILE=""
EVIDENCE_DIR=""
TFVARS=""
MAPPING_FILE=""
REGISTRATION_PROJECTION=""
ENI_PROJECTION=""
APPLY=false
PREFLIGHT_ARGS=()
EXPECTED_AWS_REGION=""

usage() {
  cat <<'EOF'
Usage: aws-smsv2-lifecycle-plan.sh --phase bootstrap|bootstrap_retirement|configured \
  --plan-file PRIVATE_PATH --evidence-dir EMPTY_PRIVATE_DIRECTORY --tfvars PRIVATE_TFVARS \
  --expected-aws-account ID --expected-aws-region REGION --expected-xc-tenant NAME \
  --creator-id EMAIL --deployment-generation VALUE --expected-site NAME [--expected-site NAME ...] \
  [--mapping-file PRIVATE_PATH --registration-projection PRIVATE_PATH --eni-projection PRIVATE_PATH] [--apply]

The script creates a saved plan, records only its SHA-256 digest, calls the
non-mutating AWS SMSv2 preflight, rechecks the digest, and applies that exact
plan only with --apply.  bootstrap and bootstrap_retirement forcibly disable
TGW Connect; configured forcibly enables it and generates the private mapping
from the observed bootstrap registration and Terraform-owned ENI projections.
EOF
}

die() {
  printf 'error: %s\n' "$1" >&2
  exit 2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
  --phase)
    PHASE=${2:?}
    shift 2
    ;;
  --plan-file)
    PLAN_FILE=${2:?}
    shift 2
    ;;
  --evidence-dir)
    EVIDENCE_DIR=${2:?}
    shift 2
    ;;
  --tfvars)
    TFVARS=${2:?}
    shift 2
    ;;
  --mapping-file)
    MAPPING_FILE=${2:?}
    shift 2
    ;;
  --registration-projection)
    REGISTRATION_PROJECTION=${2:?}
    shift 2
    ;;
  --eni-projection)
    ENI_PROJECTION=${2:?}
    shift 2
    ;;
  --apply)
    APPLY=true
    shift
    ;;
  --expected-aws-account | --expected-aws-region | --expected-xc-tenant | --creator-id | --deployment-generation | --component | --expected-site)
    [ "$1" != --expected-aws-region ] || EXPECTED_AWS_REGION=${2:?}
    PREFLIGHT_ARGS+=("$1" "${2:?}")
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *) die "unknown argument: $1" ;;
  esac
done

case "$PHASE" in bootstrap | bootstrap_retirement | configured) ;; *) die "--phase is required" ;; esac
[ -n "$PLAN_FILE" ] || die "--plan-file is required"
[ -n "$EVIDENCE_DIR" ] || die "--evidence-dir is required"
[ -n "$TFVARS" ] || die "--tfvars is required"
[ -n "$EXPECTED_AWS_REGION" ] || die "--expected-aws-region is required"
[ -f "$TFVARS" ] || die "--tfvars is not readable"
[ -d "$EVIDENCE_DIR" ] || die "--evidence-dir must already exist"
[ -z "$(find "$EVIDENCE_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ] || die "--evidence-dir must be empty"

PLAN_FILE=$(realpath -m "$PLAN_FILE")
EVIDENCE_DIR=$(realpath "$EVIDENCE_DIR")
case "$PLAN_FILE" in "$REPO_ROOT"/*) die "--plan-file must be outside the repository" ;; esac
case "$EVIDENCE_DIR" in "$REPO_ROOT"/*) die "--evidence-dir must be outside the repository" ;; esac
[ ! -e "$PLAN_FILE" ] || die "--plan-file must not already exist"

if [ "$PHASE" = configured ]; then
  [ -n "$MAPPING_FILE" ] || die "configured requires --mapping-file"
  [ -n "$REGISTRATION_PROJECTION" ] || die "configured requires --registration-projection"
  [ -n "$ENI_PROJECTION" ] || die "configured requires --eni-projection"
  MAPPING_FILE=$(realpath "$MAPPING_FILE")
  REGISTRATION_PROJECTION=$(realpath "$REGISTRATION_PROJECTION")
  ENI_PROJECTION=$(realpath "$ENI_PROJECTION")
  [ -f "$REGISTRATION_PROJECTION" ] || die "--registration-projection is not readable"
  [ -f "$ENI_PROJECTION" ] || die "--eni-projection is not readable"
  [ ! -e "$MAPPING_FILE" ] || die "--mapping-file must not already exist"
  case "$MAPPING_FILE" in "$REPO_ROOT"/*) die "--mapping-file must be outside the repository" ;; esac
  case "$REGISTRATION_PROJECTION" in "$REPO_ROOT"/*) die "--registration-projection must be outside the repository" ;; esac
  case "$ENI_PROJECTION" in "$REPO_ROOT"/*) die "--eni-projection must be outside the repository" ;; esac
else
  [ -z "$MAPPING_FILE$REGISTRATION_PROJECTION$ENI_PROJECTION" ] || die "mapping inputs are valid only for configured"
fi

TF_RUNNER=("$REPO_ROOT/scripts/terraform-with-aws-sso.sh" --profile sso --region "$EXPECTED_AWS_REGION")
PLAN_MODE=apply
TF_PHASE_ARGS=(-var="aws_site_configuration_phase=$PHASE")
if [ "$PHASE" = configured ]; then
  TF_PHASE_ARGS+=(-var='enable_aws_tgw_connect=true' -var="aws_smsv2_device_mapping_file=$MAPPING_FILE")
else
  TF_PHASE_ARGS+=(-var='enable_aws_tgw_connect=false')
fi
if [ "$PHASE" = bootstrap_retirement ]; then PLAN_MODE=destroy; fi

if [ "$PHASE" = configured ]; then
  "$REPO_ROOT/scripts/generate-aws-smsv2-device-mapping.py" \
    --registration-file "$REGISTRATION_PROJECTION" --eni-file "$ENI_PROJECTION" --output "$MAPPING_FILE"
  "$REPO_ROOT/scripts/generate-aws-smsv2-device-mapping.py" \
    --verify-file "$MAPPING_FILE" --eni-file "$ENI_PROJECTION"
fi

mkdir -p "$(dirname "$PLAN_FILE")"
umask 077
"${TF_RUNNER[@]}" -- -chdir="$TERRAFORM_DIR" plan -input=false -no-color -var-file="$TFVARS" \
  "${TF_PHASE_ARGS[@]}" -out="$PLAN_FILE"

PLAN_SHA256="sha256:$(sha256sum "$PLAN_FILE" | awk '{print $1}')"
"$REPO_ROOT/scripts/aws-smsv2-uat-preflight.sh" \
  --evidence-dir "$EVIDENCE_DIR" --terraform-dir "$TERRAFORM_DIR" --plan-file "$PLAN_FILE" \
  --plan-mode "$PLAN_MODE" --lifecycle-phase "$PHASE" "${PREFLIGHT_ARGS[@]}"

[ "$PLAN_SHA256" = "sha256:$(sha256sum "$PLAN_FILE" | awk '{print $1}')" ] || die "saved plan changed during review"
jq -n --arg phase "$PHASE" --arg plan_sha256 "$PLAN_SHA256" \
  '{phase:$phase, plan_sha256:$plan_sha256}' >"$EVIDENCE_DIR/plan-receipt.json"
chmod 600 "$EVIDENCE_DIR/plan-receipt.json"

[ "$APPLY" = true ] || exit 0
"${TF_RUNNER[@]}" -- -chdir="$TERRAFORM_DIR" apply -input=false -no-color "$PLAN_FILE"
if [ "$PHASE" = configured ]; then
  rm -f -- "$MAPPING_FILE" "$REGISTRATION_PROJECTION" "$ENI_PROJECTION"
fi
