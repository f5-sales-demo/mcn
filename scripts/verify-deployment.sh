#!/usr/bin/env bash
# Verify the rebuilt MCN deployment and write private, aggregate evidence.
#
# Run from the repository root after the second Terraform apply:
#
#   bash scripts/verify-deployment.sh --evidence-dir /private/path/mcn-evidence
#
# The default run verifies the rotated Site Console credentials as well as XC,
# Azure routing, and traffic. Set MCN_FACTORY_PASSWORD in the environment; the
# value is read from stdin by curl and never enters a command line or output.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
TERRAFORM_DIR="terraform"
EVIDENCE_DIR=""
SAMPLES_PER_BATCH=40
MAX_BATCHES=12
BATCH_INTERVAL=300
CHECK_CONSOLE=1
CONTEXT="${XCSH_CONTEXT:-f5-sales-demo}"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

usage() {
  sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

while [ "$#" -gt 0 ]; do
  case "$1" in
  --terraform-dir)
    TERRAFORM_DIR="${2:?--terraform-dir needs a value}"
    shift 2
    ;;
  --evidence-dir)
    EVIDENCE_DIR="${2:?--evidence-dir needs a value}"
    shift 2
    ;;
  --samples-per-batch)
    SAMPLES_PER_BATCH="${2:?--samples-per-batch needs a value}"
    shift 2
    ;;
  --max-batches)
    MAX_BATCHES="${2:?--max-batches needs a value}"
    shift 2
    ;;
  --batch-interval)
    BATCH_INTERVAL="${2:?--batch-interval needs a value}"
    shift 2
    ;;
  --context)
    CONTEXT="${2:?--context needs a value}"
    shift 2
    ;;
  --skip-console)
    CHECK_CONSOLE=0
    shift
    ;;
  -h | --help) usage ;;
  *) die "unknown argument: $1" ;;
  esac
done

[ -n "$EVIDENCE_DIR" ] || die "--evidence-dir is required"
case "$SAMPLES_PER_BATCH:$MAX_BATCHES:$BATCH_INTERVAL" in
*[!0-9:]* | *::* | :* | *:) die "sample and interval values must be non-negative integers" ;;
esac
[ "$SAMPLES_PER_BATCH" -gt 0 ] || die "--samples-per-batch must be greater than zero"
[ "$MAX_BATCHES" -ge 3 ] || die "--max-batches must allow at least three time-separated batches"
[ $((SAMPLES_PER_BATCH * MAX_BATCHES)) -ge 100 ] || die "the configured run cannot reach the required 100 VIP samples"
if [ "$BATCH_INTERVAL" -eq 0 ] && [ "${MCN_UAT_TEST_MODE:-0}" != "1" ]; then
  die "--batch-interval 0 is test-only; live evidence must be time-separated"
fi

for command_name in terraform jq curl az; do
  command -v "$command_name" >/dev/null 2>&1 || die "$command_name is required"
done

mkdir -p "$EVIDENCE_DIR"
EVIDENCE_DIR=$(cd "$EVIDENCE_DIR" && pwd)
case "$EVIDENCE_DIR/" in
"$REPO_ROOT"/*) die "evidence must stay outside the repository" ;;
esac
if find "$EVIDENCE_DIR" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
  die "evidence directory is not empty: $EVIDENCE_DIR"
fi
chmod 700 "$EVIDENCE_DIR"
umask 077

TF=(terraform "-chdir=${TERRAFORM_DIR}")
tf_raw() { "${TF[@]}" output -raw "$1"; }
tf_json() { "${TF[@]}" output -json "$1"; }

# Resolve the XC credential exactly as the capture harness does. A token on the
# command line is intentionally unsupported because it would enter shell history
# and process listings.
API_URL="${XCSH_API_URL:-}"
API_TOKEN="${XCSH_API_TOKEN:-}"
if [ -z "$API_URL" ] || [ -z "$API_TOKEN" ]; then
  context_file="${HOME}/.config/xcsh/contexts/${CONTEXT}.json"
  [ -f "$context_file" ] || die "no XC environment credential and no context at $context_file"
  [ -n "$API_URL" ] || API_URL=$(jq -r '.apiUrl // empty' "$context_file")
  [ -n "$API_TOKEN" ] || API_TOKEN=$(jq -r '.apiToken // empty' "$context_file")
fi
[ -n "$API_URL" ] || die "could not resolve the XC API URL"
[ -n "$API_TOKEN" ] || die "could not resolve the XC API token"

api_get() {
  local url=$1
  printf 'Authorization: APIToken %s\n' "$API_TOKEN" |
    curl -fsS --max-time 120 -H @- "$url"
}

# Azure serializes Run Command executions per VM. A preceding command can be
# complete from the caller's perspective while the extension still reports a
# short-lived Conflict. Retry only that exact transient; authentication,
# validation, and script failures remain immediate hard failures.
az_vm_run_command() {
  local attempt=1 max_attempts=20 retry_delay=15 output stderr_file
  stderr_file=$(mktemp)
  if [ "${MCN_UAT_TEST_MODE:-0}" = "1" ]; then retry_delay=0; fi
  while true; do
    if output=$(az vm run-command invoke --only-show-errors "$@" 2>"$stderr_file"); then
      rm -f "$stderr_file"
      printf '%s\n' "$output"
      return 0
    fi
    if ! grep -qF 'Run command extension execution is in progress' "$stderr_file" ||
      [ "$attempt" -ge "$max_attempts" ]; then
      cat "$stderr_file" >&2
      rm -f "$stderr_file"
      return 1
    fi
    printf 'Azure Run Command busy; retrying (%s/%s)\n' "$attempt" "$max_attempts" >&2
    attempt=$((attempt + 1))
    sleep "$retry_delay"
  done
}

STARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
"${TF[@]}" version -json >"${EVIDENCE_DIR}/terraform-version.json"
"${TF[@]}" output -json >"${EVIDENCE_DIR}/terraform-output.json"

SITES=$(tf_json xc_site_names)
CE_IPS=$(tf_json ce_mgmt_private_ips)
SITE_COUNT=$(jq 'length' <<<"$SITES")
[ "$SITE_COUNT" -eq 3 ] || die "expected three XC sites, found $SITE_COUNT"
[ "$(jq 'length' <<<"$CE_IPS")" -eq "$SITE_COUNT" ] || die "site and CE address maps differ in size"

sites_online=0
while IFS= read -r key; do
  site=$(jq -r --arg key "$key" '.[$key]' <<<"$SITES")
  state=$(api_get "${API_URL}/api/config/namespaces/system/sites/${site}" | jq -r '.spec.site_state // .get_spec.site_state // empty')
  [ "$state" = "ONLINE" ] || die "one or more XC sites are not ONLINE"
  sites_online=$((sites_online + 1))
done < <(jq -r 'keys[]' <<<"$SITES")
printf 'sites_online=%s/%s\n' "$sites_online" "$SITE_COUNT"

RG=$(tf_raw resource_group_name)
RS=$(tf_raw route_server_name)
CLIENT=$(tf_raw client_vm_name)
NIC=$(tf_raw client_nic_name)
DOMAIN=$(tf_raw lb_domain)
VIP=$(tf_raw vip)
ORIGIN=$(tf_raw origin_ip)
CE_VM_NAMES=$(tf_json ce_vm_names)
[[ "$DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]] || die "lb_domain contains characters unsafe for the remote verifier"
[[ "$VIP" =~ ^[0-9.]+$ ]] || die "vip is not an IPv4 literal"
[[ "$ORIGIN" =~ ^[0-9.]+$ ]] || die "origin_ip is not an IPv4 literal"
[ "$(jq 'length' <<<"$CE_VM_NAMES")" -eq "$SITE_COUNT" ] || die "site and CE VM name maps differ in size"

# Terraform and the XC API can both become ready while Azure still reports a VM
# or extension transition. Query Azure directly so a stuck control-plane
# operation cannot be mistaken for a healthy deployment.
azure_vms_running=0
password_extensions_succeeded=0
while IFS= read -r key; do
  vm_name=$(jq -r --arg key "$key" '.[$key]' <<<"$CE_VM_NAMES")
  instance_view=$(az vm get-instance-view \
    --resource-group "$RG" \
    --name "$vm_name" \
    --query '{provisioningState:provisioningState,powerState:instanceView.statuses[?starts_with(code, `PowerState/`)].code | [0]}' \
    --output json)
  provisioning_state=$(jq -r '.provisioningState // empty' <<<"$instance_view")
  power_state=$(jq -r '.powerState // empty' <<<"$instance_view")
  if [ "$provisioning_state" != "Succeeded" ] || [ "$power_state" != "PowerState/running" ]; then
    die "one CE VM is not fully running in Azure (provisioning=${provisioning_state:-unknown}, power=${power_state:-unknown})"
  fi
  azure_vms_running=$((azure_vms_running + 1))

  extension_state=$(az vm extension show \
    --resource-group "$RG" \
    --vm-name "$vm_name" \
    --name site-console-admin-password \
    --query provisioningState \
    --output tsv)
  [ "$extension_state" = "Succeeded" ] ||
    die "one Site Console password extension is not complete in Azure (provisioning=${extension_state:-unknown})"
  password_extensions_succeeded=$((password_extensions_succeeded + 1))
done < <(jq -r 'keys[]' <<<"$SITES")
printf 'azure_vms_running=%s/%s\n' "$azure_vms_running" "$SITE_COUNT"
printf 'password_extensions_succeeded=%s/%s\n' "$password_extensions_succeeded" "$SITE_COUNT"

peerings_with_vip=0
learned_hops='[]'
while IFS= read -r key; do
  expected_hop=$(jq -r --arg key "$key" '.[$key]' <<<"$CE_IPS")
  routes=$(az network routeserver peering list-learned-routes \
    --name "${key}-bgp" \
    --routeserver "$RS" \
    --resource-group "$RG" \
    --query "RouteServiceRole_IN_0[?network=='${VIP}/32']" \
    --output json)
  route_count=$(jq 'length' <<<"$routes")
  [ "$route_count" -eq 1 ] || die "one Route Server peering does not expose exactly one VIP route"
  actual_hop=$(jq -r '.[0].nextHop // empty' <<<"$routes")
  [ "$actual_hop" = "$expected_hop" ] || die "one Route Server peering exposes the wrong VIP next hop"
  learned_hops=$(jq -c --arg hop "$actual_hop" '. + [$hop]' <<<"$learned_hops")
  peerings_with_vip=$((peerings_with_vip + 1))
done < <(jq -r 'keys[]' <<<"$SITES")
[ "$(jq 'unique | length' <<<"$learned_hops")" -eq "$SITE_COUNT" ] || die "per-peering VIP next hops are not distinct"
printf 'peerings_with_vip=%s/%s\n' "$peerings_with_vip" "$SITE_COUNT"

effective_raw=$(az network nic show-effective-route-table \
  --resource-group "$RG" \
  --name "$NIC" \
  --query "value[?addressPrefix[0]=='${VIP}/32']" \
  --output json)
effective_routes=$(jq -c 'if type == "array" then . else (.value // []) end' <<<"$effective_raw")
effective_hops=$(jq -c --arg prefix "${VIP}/32" '[.[] | select((.addressPrefix[0] // "") == $prefix and (.state // "Active") == "Active") | .nextHopIpAddress[]?] | unique | sort' <<<"$effective_routes")
expected_hops=$(jq -c '[.[]] | unique | sort' <<<"$CE_IPS")
[ "$effective_hops" = "$expected_hops" ] || die "the client effective route does not contain every CE next hop"
printf 'effective_next_hops=%s/%s\n' "$(jq 'length' <<<"$effective_hops")" "$SITE_COUNT"

vip_ok=0
vip_fail=0
origin_ok=0
origin_fail=0
zero_streak=0
batches=0
converged=false
origin_samples=$((SAMPLES_PER_BATCH / 2))
[ "$origin_samples" -ge 20 ] || origin_samples=20

while [ "$batches" -lt "$MAX_BATCHES" ]; do
  batches=$((batches + 1))
  remote_script=$(printf '%s' \
    "vip_ok=0; vip_fail=0; origin_ok=0; origin_fail=0; " \
    "for i in \$(seq 1 ${SAMPLES_PER_BATCH}); do code=\$(curl -sS -o /dev/null -m 10 -w '%{http_code}' -H 'Host: ${DOMAIN}' 'http://${VIP}/' || true); if [ \"\$code\" = 200 ]; then vip_ok=\$((vip_ok+1)); else vip_fail=\$((vip_fail+1)); fi; done; " \
    "for i in \$(seq 1 ${origin_samples}); do code=\$(curl -sS -o /dev/null -m 10 -w '%{http_code}' 'http://${ORIGIN}/' || true); if [ \"\$code\" = 200 ]; then origin_ok=\$((origin_ok+1)); else origin_fail=\$((origin_fail+1)); fi; done; " \
    "echo MCN_UAT vip_ok=\$vip_ok vip_fail=\$vip_fail origin_ok=\$origin_ok origin_fail=\$origin_fail")
  message=$(az_vm_run_command \
    --resource-group "$RG" \
    --name "$CLIENT" \
    --command-id RunShellScript \
    --query 'value[0].message' \
    --output tsv \
    --scripts "$remote_script")
  result=$(grep -Eo 'MCN_UAT vip_ok=[0-9]+ vip_fail=[0-9]+ origin_ok=[0-9]+ origin_fail=[0-9]+' <<<"$message" | tail -n 1)
  [ -n "$result" ] || die "client traffic verifier returned no aggregate result"
  batch_vip_ok=$(sed -E 's/.*vip_ok=([0-9]+).*/\1/' <<<"$result")
  batch_vip_fail=$(sed -E 's/.*vip_fail=([0-9]+).*/\1/' <<<"$result")
  batch_origin_ok=$(sed -E 's/.*origin_ok=([0-9]+).*/\1/' <<<"$result")
  batch_origin_fail=$(sed -E 's/.*origin_fail=([0-9]+).*/\1/' <<<"$result")
  [ $((batch_vip_ok + batch_vip_fail)) -eq "$SAMPLES_PER_BATCH" ] || die "VIP batch returned the wrong sample count"
  [ $((batch_origin_ok + batch_origin_fail)) -eq "$origin_samples" ] || die "origin batch returned the wrong sample count"
  [ "$batch_origin_fail" -eq 0 ] || die "origin control failed; VIP results are not attributable"
  vip_ok=$((vip_ok + batch_vip_ok))
  vip_fail=$((vip_fail + batch_vip_fail))
  origin_ok=$((origin_ok + batch_origin_ok))
  origin_fail=$((origin_fail + batch_origin_fail))
  if [ "$batch_vip_fail" -eq 0 ]; then
    zero_streak=$((zero_streak + 1))
  else
    zero_streak=0
  fi
  printf 'batch=%s vip_ok=%s vip_fail=%s origin_ok=%s origin_fail=%s\n' \
    "$batches" "$batch_vip_ok" "$batch_vip_fail" "$batch_origin_ok" "$batch_origin_fail"
  if [ $((vip_ok + vip_fail)) -ge 100 ] && [ "$batches" -ge 3 ] && [ "$zero_streak" -ge 2 ]; then
    converged=true
    break
  fi
  [ "$batches" -ge "$MAX_BATCHES" ] || sleep "$BATCH_INTERVAL"
done

console_factory_rejected=0
console_generated_accepted=0
if [ "$CHECK_CONSOLE" -eq 1 ]; then
  [ -n "${MCN_FACTORY_PASSWORD:-}" ] || die "MCN_FACTORY_PASSWORD is required unless --skip-console is explicit"
  BASTION=$(tf_raw bastion_name)
  [ -n "$BASTION" ] && [ "$BASTION" != "null" ] || die "Azure Bastion must be enabled for Site Console verification"
  VM_IDS=$(tf_json ce_vm_ids)
  GENERATED_PASSWORDS=$(tf_json site_console_admin_passwords)
  index=0
  while IFS= read -r key; do
    port=$((65500 + index))
    vm_id=$(jq -r --arg key "$key" '.[$key]' <<<"$VM_IDS")
    generated_password=$(jq -r --arg key "$key" '.[$key]' <<<"$GENERATED_PASSWORDS")
    az network bastion tunnel \
      --name "$BASTION" \
      --resource-group "$RG" \
      --target-resource-id "$vm_id" \
      --resource-port 65500 \
      --port "$port" >"${EVIDENCE_DIR}/bastion-tunnel-${index}.log" 2>&1 &
    tunnel_pid=$!
    ready=0
    for _ in $(seq 1 60); do
      if curl -ksS --max-time 2 -o /dev/null "https://127.0.0.1:${port}/"; then
        ready=1
        break
      fi
      sleep 2
    done
    if [ "$ready" -ne 1 ]; then
      kill "$tunnel_pid" 2>/dev/null || true
      wait "$tunnel_pid" 2>/dev/null || true
      die "one Site Console tunnel did not become ready"
    fi
    factory_auth=$(printf 'Authorization: Basic %s\n' "$(printf 'admin:%s' "$MCN_FACTORY_PASSWORD" | base64)" |
      curl -ksS --max-time 10 -o /dev/null -w '%{http_code}' -H @- "https://127.0.0.1:${port}/")
    generated_auth=$(printf 'Authorization: Basic %s\n' "$(printf 'admin:%s' "$generated_password" | base64)" |
      curl -ksS --max-time 10 -o /dev/null -w '%{http_code}' -H @- "https://127.0.0.1:${port}/")
    kill "$tunnel_pid" 2>/dev/null || true
    wait "$tunnel_pid" 2>/dev/null || true
    [ "$factory_auth" != "200" ] || die "the factory Site Console credential still authenticates"
    [ "$generated_auth" = "200" ] || die "a generated Site Console credential does not authenticate"
    console_factory_rejected=$((console_factory_rejected + 1))
    console_generated_accepted=$((console_generated_accepted + 1))
    generated_password=""
    index=$((index + 1))
  done < <(jq -r 'keys[]' <<<"$SITES")
  printf 'console_factory_rejected=%s/%s\n' "$console_factory_rejected" "$SITE_COUNT"
  printf 'console_generated_accepted=%s/%s\n' "$console_generated_accepted" "$SITE_COUNT"
fi

FINISHED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
jq -n \
  --arg started_at "$STARTED_AT" \
  --arg finished_at "$FINISHED_AT" \
  --argjson sites_online "$sites_online" \
  --argjson azure_vms_running "$azure_vms_running" \
  --argjson password_extensions_succeeded "$password_extensions_succeeded" \
  --argjson peerings_with_vip "$peerings_with_vip" \
  --argjson effective_next_hops "$(jq 'length' <<<"$effective_hops")" \
  --argjson batches "$batches" \
  --argjson vip_samples "$((vip_ok + vip_fail))" \
  --argjson vip_failures "$vip_fail" \
  --argjson origin_samples "$((origin_ok + origin_fail))" \
  --argjson origin_failures "$origin_fail" \
  --argjson console_factory_rejected "$console_factory_rejected" \
  --argjson console_generated_accepted "$console_generated_accepted" \
  --argjson converged "$converged" \
  '{
    started_at: $started_at,
    finished_at: $finished_at,
    sites_online: $sites_online,
    azure_vms_running: $azure_vms_running,
    password_extensions_succeeded: $password_extensions_succeeded,
    peerings_with_vip: $peerings_with_vip,
    effective_next_hops: $effective_next_hops,
    batches: $batches,
    vip_samples: $vip_samples,
    vip_failures: $vip_failures,
    origin_samples: $origin_samples,
    origin_failures: $origin_failures,
    console_factory_rejected: $console_factory_rejected,
    console_generated_accepted: $console_generated_accepted,
    converged: $converged
  }' >"${EVIDENCE_DIR}/summary.json"

printf 'vip_samples=%s vip_failures=%s\n' "$((vip_ok + vip_fail))" "$vip_fail"
printf 'origin_samples=%s origin_failures=%s\n' "$((origin_ok + origin_fail))" "$origin_fail"
if [ "$converged" = true ]; then
  echo 'converged=yes'
else
  echo 'converged=no'
  exit 1
fi
