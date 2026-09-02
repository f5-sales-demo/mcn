#!/usr/bin/env bash
# Hermetic acceptance tests for scripts/verify-deployment.sh. Terraform, Azure,
# and XC are stubbed so the aggregate gates are exercised without credentials or
# network access.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="${REPO_ROOT}/scripts/verify-deployment.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

FAIL=0
ok() { printf '  ok   — %s\n' "$1"; }
bad() {
  printf '  FAIL — %s\n' "$1"
  FAIL=1
}

mkdir -p "${WORK}/bin"

cat >"${WORK}/bin/terraform" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "-chdir=terraform" ]; then shift; fi
case "${1:-} ${2:-} ${3:-}" in
"version -json ")
  printf '{"terraform_version":"1.15.8","provider_selections":{"registry.terraform.io/f5-sales-demo/xcsh":"6.1.2"}}\n'
  ;;
"output -json xc_site_names")
  printf '{"eastus01":"site-01","eastus02":"site-02","eastus03":"site-03"}\n'
  ;;
"output -json ce_mgmt_private_ips")
  printf '{"eastus01":"10.0.1.4","eastus02":"10.0.1.5","eastus03":"10.0.1.6"}\n'
  ;;
"output -json ce_vm_names")
  printf '{"eastus01":"ce-01","eastus02":"ce-02","eastus03":"ce-03"}\n'
  ;;
"output -json ce_vm_ids")
  printf '{"eastus01":"/subscriptions/000/resourceGroups/rg-example/providers/Microsoft.Compute/virtualMachines/ce-01","eastus02":"/subscriptions/000/resourceGroups/rg-example/providers/Microsoft.Compute/virtualMachines/ce-02","eastus03":"/subscriptions/000/resourceGroups/rg-example/providers/Microsoft.Compute/virtualMachines/ce-03"}\n'
  ;;
"output -json site_console_admin_passwords")
  printf '{"eastus01":"<GENERATED_PASSWORD_01>","eastus02":"<GENERATED_PASSWORD_02>","eastus03":"<GENERATED_PASSWORD_03>"}\n'
  ;;
"output -json ")
  printf '{"xc_site_names":{"sensitive":false,"value":{"eastus01":"site-01","eastus02":"site-02","eastus03":"site-03"}}}\n'
  ;;
"output -raw resource_group_name") printf 'rg-example\n' ;;
"output -raw route_server_name") printf 'route-server-example\n' ;;
"output -raw client_vm_name") printf 'client-example\n' ;;
"output -raw client_nic_name") printf 'client-nic-example\n' ;;
"output -raw lb_domain") printf 'mcn.example.com\n' ;;
"output -raw vip") printf '10.250.0.10\n' ;;
"output -raw origin_ip") printf '198.51.100.10\n' ;;
"output -raw bastion_name") printf 'bastion-example\n' ;;
*) printf 'unexpected terraform call: %s\n' "$*" >&2; exit 2 ;;
esac
EOF

cat >"${WORK}/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *"%{http_code}"* ]]; then
  header=$(cat)
  factory=$(printf 'admin:%s' '<FACTORY_SITE_CONSOLE_PASSWORD>' | base64)
  if grep -qF "$factory" <<<"$header"; then
    printf '401'
  else
    printf '200'
  fi
elif [[ "$*" == *"127.0.0.1"* ]]; then
  exit 0
else
  cat >/dev/null
  printf '{"spec":{"site_state":"ONLINE"}}\n'
fi
EOF

cat >"${WORK}/bin/az" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
*"vm get-instance-view"*)
  vm_name=""
  while [ "$#" -gt 0 ]; do
    if [ "$1" = "--name" ]; then vm_name=$2; break; fi
    shift
  done
  if [ "${AZ_VM_MODE:-ok}" = "stuck" ] && [ "$vm_name" = "ce-03" ]; then
    printf '{"provisioningState":"Updating","powerState":"PowerState/starting"}\n'
  else
    printf '{"provisioningState":"Succeeded","powerState":"PowerState/running"}\n'
  fi
  ;;
*"vm extension show"*)
  vm_name=""
  while [ "$#" -gt 0 ]; do
    if [ "$1" = "--vm-name" ]; then vm_name=$2; break; fi
    shift
  done
  if [ "${AZ_EXTENSION_MODE:-ok}" = "stuck" ] && [ "$vm_name" = "ce-03" ]; then
    printf 'Creating\n'
  else
    printf 'Succeeded\n'
  fi
  ;;
*"routeserver peering list-learned-routes"*)
  key=""
  while [ "$#" -gt 0 ]; do
    if [ "$1" = "--name" ]; then key=${2%-bgp}; break; fi
    shift
  done
  case "$key" in
  eastus01) hop=10.0.1.4 ;;
  eastus02) hop=10.0.1.5 ;;
  eastus03) hop=10.0.1.6 ;;
  *) exit 2 ;;
  esac
  if [ "${AZ_ROUTE_MODE:-ok}" = "missing" ] && [ "$key" = "eastus03" ]; then
    printf '[]\n'
  else
    printf '[{"network":"10.250.0.10/32","nextHop":"%s"}]\n' "$hop"
  fi
  ;;
*"network nic show-effective-route-table"*)
  printf '{"value":[{"addressPrefix":["10.250.0.10/32"],"nextHopIpAddress":["10.0.1.6","10.0.1.4","10.0.1.5"],"state":"Active"}]}\n'
  ;;
*"vm run-command invoke"*)
  if [ "${AZ_RUN_COMMAND_MODE:-ok}" = "conflict-once" ] &&
    [ ! -e "${AZ_RUN_COMMAND_COUNT_FILE:?}" ]; then
    : >"$AZ_RUN_COMMAND_COUNT_FILE"
    printf '%s\n' 'ERROR: (Conflict) Run command extension execution is in progress. Please wait for completion before invoking a run command.' >&2
    exit 1
  fi
  printf 'MCN_UAT vip_ok=50 vip_fail=0 origin_ok=25 origin_fail=0\n'
  ;;
*"network bastion tunnel"*)
  sleep 30
  ;;
*) printf 'unexpected az call: %s\n' "$*" >&2; exit 2 ;;
esac
EOF
chmod +x "${WORK}/bin/terraform" "${WORK}/bin/curl" "${WORK}/bin/az"

run_uat() {
  PATH="${WORK}/bin:${PATH}" \
    XCSH_API_URL="https://example.invalid" \
    XCSH_API_TOKEN="<XC_API_TOKEN>" \
    MCN_UAT_TEST_MODE=1 \
    bash "$SCRIPT" \
    --terraform-dir terraform \
    --evidence-dir "${WORK}/evidence-$1" \
    --samples-per-batch 50 \
    --max-batches 3 \
    --batch-interval 0 \
    --skip-console
}

echo "1. healthy deployment passes every aggregate gate"
if OUT=$(run_uat healthy 2>&1); then
  for expected in 'sites_online=3/3' 'azure_vms_running=3/3' 'password_extensions_succeeded=3/3' 'peerings_with_vip=3/3' 'effective_next_hops=3/3' 'vip_samples=150' 'origin_failures=0' 'converged=yes'; do
    if grep -qF "$expected" <<<"$OUT"; then
      ok "reported ${expected}"
    else
      bad "missing ${expected} from output"
    fi
  done
  if jq -e '.sites_online == 3 and .azure_vms_running == 3 and .password_extensions_succeeded == 3 and .peerings_with_vip == 3 and .vip_samples == 150 and .converged == true' "${WORK}/evidence-healthy/summary.json" >/dev/null; then
    ok "wrote a machine-readable aggregate summary"
  else
    bad "aggregate summary is missing or incorrect"
  fi
  if jq -e '.xc_site_names.value | length == 3' "${WORK}/evidence-healthy/terraform-output.json" >/dev/null; then
    ok "wrote the private Terraform output snapshot"
  else
    bad "Terraform output snapshot is missing"
  fi
else
  bad "healthy UAT failed: ${OUT}"
fi

echo "2. a CE stuck in Azure provisioning fails the UAT"
if AZ_VM_MODE=stuck run_uat stuck-vm >/dev/null 2>&1; then
  bad "UAT passed with one CE still starting in Azure"
else
  ok "rejected the stuck Azure VM"
fi

echo "3. a stuck password-rotation extension fails the UAT"
if AZ_EXTENSION_MODE=stuck run_uat stuck-extension >/dev/null 2>&1; then
  bad "UAT passed with one password extension still creating"
else
  ok "rejected the stuck Azure VM extension"
fi

echo "4. a missing per-peering VIP route fails the UAT"
if AZ_ROUTE_MODE=missing run_uat missing-route >/dev/null 2>&1; then
  bad "UAT passed with one peering missing its VIP route"
else
  ok "rejected the missing per-peering route"
fi

echo "5. fewer than 100 possible samples is rejected before any API call"
if PATH="${WORK}/bin:${PATH}" MCN_UAT_TEST_MODE=1 bash "$SCRIPT" \
  --terraform-dir terraform \
  --evidence-dir "${WORK}/evidence-too-small" \
  --samples-per-batch 30 \
  --max-batches 3 \
  --batch-interval 0 \
  --skip-console >/dev/null 2>&1; then
  bad "accepted a run capped below 100 samples"
else
  ok "enforced the 100-sample minimum"
fi

echo "6. a transient Azure Run Command conflict is retried"
if OUT=$(AZ_RUN_COMMAND_MODE=conflict-once \
  AZ_RUN_COMMAND_COUNT_FILE="${WORK}/run-command-conflict-seen" \
  run_uat transient-conflict 2>&1); then
  if grep -qF 'converged=yes' <<<"$OUT"; then
    ok "recovered from the transient Azure conflict"
  else
    bad "retry run completed without convergence evidence"
  fi
else
  bad "transient Azure conflict aborted the UAT: ${OUT}"
fi

echo "7. factory credentials fail and generated credentials pass on every console"
if OUT=$(PATH="${WORK}/bin:${PATH}" \
  XCSH_API_URL="https://example.invalid" \
  XCSH_API_TOKEN="<XC_API_TOKEN>" \
  MCN_FACTORY_PASSWORD="<FACTORY_SITE_CONSOLE_PASSWORD>" \
  MCN_UAT_TEST_MODE=1 \
  bash "$SCRIPT" \
  --terraform-dir terraform \
  --evidence-dir "${WORK}/evidence-console" \
  --samples-per-batch 50 \
  --max-batches 3 \
  --batch-interval 0 2>&1); then
  for expected in 'console_factory_rejected=3/3' 'console_generated_accepted=3/3'; do
    if grep -qF "$expected" <<<"$OUT"; then
      ok "reported ${expected}"
    else
      bad "missing ${expected} from output"
    fi
  done
else
  bad "Site Console UAT failed: ${OUT}"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: deployment UAT harness"
else
  echo "FAIL: deployment UAT harness"
fi
exit "$FAIL"
