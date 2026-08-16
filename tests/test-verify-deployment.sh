#!/usr/bin/env bash
# Hermetic acceptance tests for the complete-showcase deployment verifier.
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
"version -json ") printf '{"terraform_version":"1.15.8"}\n' ;;
"output -json ") printf '{"xc_site_names":{"sensitive":false,"value":{"row01":"row-site-01","row02":"row-site-02"}}}\n' ;;
"output -json xc_site_names") printf '{"row01":"row-site-01","row02":"row-site-02"}\n' ;;
"output -json ca_site_names") printf '{"ca01":"ca-site-01","ca02":"ca-site-02"}\n' ;;
"output -json aws_site_names") printf '{"01":"aws-site-01","02":"aws-site-02","03":"aws-site-03"}\n' ;;
"output -json ce_mgmt_private_ips") printf '{"row01":"10.0.1.4","row02":"10.0.1.5"}\n' ;;
"output -json ce_vm_names") printf '{"row01":"row-ce-01","row02":"row-ce-02"}\n' ;;
"output -json route_server_bgp_connection_names") printf '{"row01":"row01-bgp","row02":"row02-bgp"}\n' ;;
"output -json ca_ce_mgmt_private_ips") printf '{"ca01":"10.200.1.4","ca02":"10.200.1.5"}\n' ;;
"output -json ca_ce_vm_names") printf '{"ca01":"ca-ce-01","ca02":"ca-ce-02"}\n' ;;
"output -json ca_route_server_bgp_connection_names") printf '{"ca01":"ca01-bgp","ca02":"ca02-bgp"}\n' ;;
"output -json aws_route_server_peer_ids") printf '{"01":"rsp-01","02":"rsp-02","03":"rsp-03"}\n' ;;
"output -json aws_route_server_propagated_route_tables") printf '{"private":"rtb-private","public":"rtb-public"}\n' ;;
"output -raw kvm_site_name") printf 'kvm-site\n' ;;
"output -raw xc_api_url") printf 'https://example.console.ves.volterra.io\n' ;;
"output -raw resource_group_name") printf 'row-rg\n' ;;
"output -raw route_server_name") printf 'row-rs\n' ;;
"output -raw client_vm_name") printf 'row-client\n' ;;
"output -raw client_nic_name") printf 'row-client-nic\n' ;;
"output -raw lb_domain") printf 'row.example.com\n' ;;
"output -raw vip") printf '10.250.0.10\n' ;;
"output -raw ca_resource_group_name") printf 'ca-rg\n' ;;
"output -raw ca_route_server_name") printf 'ca-rs\n' ;;
"output -raw ca_client_vm_name") printf 'ca-client\n' ;;
"output -raw ca_client_nic_name") printf 'ca-client-nic\n' ;;
"output -raw ca_lb_domain") printf 'ca.example.com\n' ;;
"output -raw ca_vip") printf '10.250.1.10\n' ;;
"output -raw ca_ilb_id") printf '/subscriptions/000/resourceGroups/ca-rg/providers/Microsoft.Network/loadBalancers/ca-ilb\n' ;;
"output -raw ca_ilb_rule_name") printf 'ha-ports-rule\n' ;;
"output -raw ca_ilb_frontend_ip") printf '10.200.1.10\n' ;;
"output -raw aws_region") printf 'us-east-2\n' ;;
"output -raw aws_route_server_id") printf 'rs-aws\n' ;;
"output -raw aws_vip") printf '198.51.100.10\n' ;;
"output -raw aws_lb_domain") printf 'aws.example.com\n' ;;
"output -raw aws_test_client_instance_id") printf 'i-client\n' ;;
"output -raw kvm_domain_name") printf 'kvm-ce\n' ;;
"output -raw kvm_frr_container_name") printf 'kvm-frr\n' ;;
"output -raw kvm_client_container_name") printf 'kvm-client\n' ;;
"output -raw kvm_vip") printf '198.51.100.20\n' ;;
"output -raw kvm_lb_domain") printf 'kvm.example.com\n' ;;
"plan -detailed-exitcode -no-color")
  [ "${TF_PLAN_MODE:-clean}" = clean ] && exit 0
  exit 2
  ;;
*) printf 'unexpected terraform call: %s\n' "$*" >&2; exit 2 ;;
esac
EOF

cat >"${WORK}/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
headers_file=""
output_file=""
method="GET"
url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
  -D) headers_file=$2; shift 2 ;;
  -o) output_file=$2; shift 2 ;;
  -X) method=$2; shift 2 ;;
  -H | --max-time | -w) shift 2 ;;
  -*) shift ;;
  *) url=$1; shift ;;
  esac
done
cat >/dev/null
case "$url:$method" in
*"/api/config/namespaces/system/sites/"*:GET)
  if [ "${XC_SITE_MODE:-online}" = offline ] && [[ "$url" == *"row-site-02" ]]; then
    printf '{"object":{"status":{"site_state":"REGISTERING"}}}\n'
  else
    printf '{"object":{"status":{"site_state":"ONLINE"}}}\n'
  fi
  ;;
*"/loadBalancingRules/"*"/health?"*:POST)
  printf 'HTTP/2 202\r\nLocation: https://management.azure.com/operationResults/health-01\r\n\r\n' >"$headers_file"
  ;;
*"/operationResults/health-01":GET)
  if [ "${AZ_ILB_MODE:-healthy}" = unhealthy ]; then
    printf '{"up":1,"down":1,"loadBalancerBackendAddresses":[{"state":"Up"},{"state":"Down"}]}' >"$output_file"
  else
    printf '{"up":2,"down":0,"loadBalancerBackendAddresses":[{"state":"Up"},{"state":"Up"}]}' >"$output_file"
  fi
  printf '200'
  ;;
*) printf 'unexpected curl URL: %s\n' "$url" >&2; exit 2 ;;
esac
EOF

cat >"${WORK}/bin/az" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
*"vm get-instance-view"*)
  vm=""
  while [ "$#" -gt 0 ]; do
    if [ "$1" = "--name" ]; then vm=$2; break; fi
    shift
  done
  if [ "${AZ_VM_MODE:-running}" = stopped ] && [ "$vm" = row-ce-02 ]; then
    printf '{"provisioningState":"Succeeded","powerState":"PowerState/deallocated"}\n'
  else
    printf '{"provisioningState":"Succeeded","powerState":"PowerState/running"}\n'
  fi
  ;;
*"routeserver peering list-learned-routes"*)
  peer=""
  while [ "$#" -gt 0 ]; do
    if [ "$1" = "--name" ]; then peer=$2; break; fi
    shift
  done
  case "$peer" in
  row01-bgp) prefix=10.250.0.10; hop=10.0.1.4 ;;
  row02-bgp) prefix=10.250.0.10; hop=10.0.1.5 ;;
  ca01-bgp) prefix=10.250.1.10; hop=10.200.1.4 ;;
  ca02-bgp) prefix=10.250.1.10; hop=10.200.1.5 ;;
  *) exit 2 ;;
  esac
  if [ "${AZ_ROUTE_MODE:-complete}" = missing ] && [ "$peer" = row02-bgp ]; then
    printf '[]\n'
  else
    printf '[{"network":"%s/32","nextHop":"%s"}]\n' "$prefix" "$hop"
  fi
  ;;
*"network nic show-effective-route-table"*)
  nic=""
  while [ "$#" -gt 0 ]; do
    if [ "$1" = "--name" ]; then nic=$2; break; fi
    shift
  done
  if [ "$nic" = row-client-nic ]; then
    printf '{"value":[{"addressPrefix":["10.250.0.10/32"],"nextHopIpAddress":["10.0.1.5","10.0.1.4"],"state":"Active"}]}\n'
  else
    printf '{"value":[{"addressPrefix":["10.250.1.10/32"],"nextHopIpAddress":["10.200.1.5","10.200.1.4"],"state":"Active"}]}\n'
  fi
  ;;
*"vm run-command invoke"*)
  if [ "${AZ_TRAFFIC_MODE:-ok}" = fail ]; then
    printf 'curl failed\n'
  elif [[ "$*" == *"MCN_ILB_OK"* ]]; then
    printf 'MCN_ILB_OK\n'
  else
    printf 'MCN_HTTP_OK\n'
  fi
  ;;
*"account get-access-token"*) printf '<AZURE_ACCESS_TOKEN>\n' ;;
*) printf 'unexpected az call: %s\n' "$*" >&2; exit 2 ;;
esac
EOF

cat >"${WORK}/bin/aws" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-} ${2:-}" in
"ec2 describe-route-server-peers")
  status=up
  [ "${AWS_PEER_MODE:-up}" = up ] || status=down
  printf '{"RouteServerPeers":[{"State":"available","BgpStatus":{"Status":"%s"}},{"State":"available","BgpStatus":{"Status":"up"}},{"State":"available","BgpStatus":{"Status":"up"}}]}\n' "$status"
  ;;
"ec2 get-route-server-routing-database")
  install=installed
  [ "${AWS_ROUTE_MODE:-installed}" = installed ] || install=rejected
  printf '{"Routes":['
  separator=""
  for peer in rsp-01 rsp-02 rsp-03; do
    printf '%s{"RouteServerPeerId":"%s","Prefix":"198.51.100.10/32","RouteStatus":"in-fib","RouteInstallationDetails":[{"RouteTableId":"rtb-private","RouteInstallationStatus":"%s"},{"RouteTableId":"rtb-public","RouteInstallationStatus":"%s"}]}' "$separator" "$peer" "$install" "$install"
    separator=,
  done
  printf ']}\n'
  ;;
"ssm send-command") printf 'cmd-01\n' ;;
"ssm wait") [ "${AWS_TRAFFIC_MODE:-ok}" = ok ] ;;
"ssm get-command-invocation")
  [ "${AWS_TRAFFIC_MODE:-ok}" = ok ] && printf 'Success\n' || printf 'Failed\n'
  ;;
*) printf 'unexpected aws call: %s\n' "$*" >&2; exit 2 ;;
esac
EOF

cat >"${WORK}/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
inspect) printf 'true\n' ;;
exec)
  if [[ "$*" == *"show ip bgp summary json"* ]]; then
    printf '{"ipv4Unicast":{"peers":{"172.30.10.10":{"state":"Established"}}}}\n'
  elif [[ "$*" == *"show ip bgp 198.51.100.20/32 json"* ]]; then
    if [ "${KVM_ROUTE_MODE:-learned}" = learned ]; then
      printf '{"paths":[{"valid":true}]}\n'
    else
      printf '{"paths":[]}\n'
    fi
  elif [ "${KVM_TRAFFIC_MODE:-ok}" != ok ]; then
    exit 1
  fi
  ;;
*) exit 2 ;;
esac
EOF

cat >"${WORK}/bin/virsh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[ "${KVM_VM_MODE:-running}" = running ] && printf 'running\n' || printf 'shut off\n'
EOF

chmod +x "${WORK}/bin/terraform" "${WORK}/bin/curl" "${WORK}/bin/az" "${WORK}/bin/aws" "${WORK}/bin/docker" "${WORK}/bin/virsh"

run_uat() {
  PATH="${WORK}/bin:${PATH}" \
    XCSH_API_TOKEN="<XC_API_TOKEN>" \
    bash "$SCRIPT" \
    --terraform-dir terraform \
    --evidence-dir "${WORK}/evidence-$1"
}

echo "1. a healthy complete showcase passes every aggregate gate"
if OUT=$(run_uat healthy 2>&1); then
  for expected in \
    'sites_online=8/8' \
    'azure_vms_running=4' \
    'azure_peerings_with_vip=4' \
    'azure_effective_next_hops=4' \
    'azure_traffic_paths=2/2' \
    'canada_ilb_backends_up=2/2' \
    'canada_ilb_traffic=ok' \
    'aws_bgp_peers_up=3/3' \
    'aws_vip_routes_installed=3/3' \
    'aws_client_traffic=ok' \
    'kvm_bgp_peer=established' \
    'kvm_vip_route=learned' \
    'kvm_client_traffic=ok' \
    'terraform_plan=clean' \
    'full_showcase_verified=yes'; do
    if grep -qF "$expected" <<<"$OUT"; then
      ok "reported ${expected}"
    else
      bad "missing ${expected}"
    fi
  done
  if jq -e '.site_count == 8 and .canada_ilb_backends_up == 2 and .aws_bgp_peers_up == 3 and .kvm_vip_route == "learned" and .terraform_plan == "clean"' \
    "${WORK}/evidence-healthy/summary.json" >/dev/null; then
    ok "wrote a machine-readable complete-showcase summary"
  else
    bad "aggregate summary is missing or incorrect"
  fi
else
  bad "healthy UAT failed: ${OUT}"
fi

expect_failure() {
  local label=$1 mode=$2 value=$3
  echo "$label"
  export "$mode=$value"
  if run_uat "failure-${mode}" >/dev/null 2>&1; then
    unset "$mode"
    bad "accepted ${mode}=${value}"
  else
    unset "$mode"
    ok "rejected ${mode}=${value}"
  fi
}

expect_failure "2. an offline F5 site fails verification" XC_SITE_MODE offline
expect_failure "3. a stopped Azure CE fails verification" AZ_VM_MODE stopped
expect_failure "4. a missing Azure VIP route fails verification" AZ_ROUTE_MODE missing
expect_failure "5. unhealthy Canadian ILB backends fail verification" AZ_ILB_MODE unhealthy
expect_failure "6. a down AWS BGP peer fails verification" AWS_PEER_MODE down
expect_failure "7. a rejected AWS propagated route fails verification" AWS_ROUTE_MODE rejected
expect_failure "8. a missing KVM VIP route fails verification" KVM_ROUTE_MODE missing
expect_failure "9. Terraform drift fails verification" TF_PLAN_MODE drift

if rg -n 'virtual_machine_extension|password[_-]extension|registration_approval|xcsh_token' "$SCRIPT"; then
  bad "the verifier contains a removed legacy deployment path"
else
  ok "the verifier contains no legacy registration or VM-extension path"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: complete-showcase deployment verifier"
else
  echo "FAIL: complete-showcase deployment verifier"
fi
exit "$FAIL"
