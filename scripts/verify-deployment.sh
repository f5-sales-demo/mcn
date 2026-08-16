#!/usr/bin/env bash
# Verify the complete MCN showcase and write private, aggregate evidence.
#
# Run from the repository root after Terraform has converged:
#
#   bash scripts/verify-deployment.sh --evidence-dir /private/path/mcn-evidence
#
# The verifier requires the default Azure, Canada, AWS, and KVM paths. It reads
# deployment identifiers from Terraform output and never accepts copied names,
# addresses, API URLs, or signed image URLs as command-line inputs.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
TERRAFORM_DIR="terraform"
EVIDENCE_DIR=""

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
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
  -h | --help) usage ;;
  *) die "unknown argument: $1" ;;
  esac
done

[ -n "$EVIDENCE_DIR" ] || die "--evidence-dir is required"
[ -n "${XCSH_API_TOKEN:-}" ] || die "XCSH_API_TOKEN must contain a current, private credential"
for command_name in terraform jq curl az aws docker virsh; do
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

require_name() {
  [[ "$2" =~ ^[A-Za-z0-9._:/-]+$ ]] || die "$1 contains unsupported characters"
}

require_domain() {
  [[ "$2" =~ ^[A-Za-z0-9.-]+$ ]] || die "$1 is not a domain name"
}

require_ipv4() {
  [[ "$2" =~ ^[0-9.]+$ ]] || die "$1 is not an IPv4 address"
}

STARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
"${TF[@]}" version -json >"${EVIDENCE_DIR}/terraform-version.json"
"${TF[@]}" output -json >"${EVIDENCE_DIR}/terraform-output.json"

ROW_SITES=$(tf_json xc_site_names)
CA_SITES=$(tf_json ca_site_names)
AWS_SITES=$(tf_json aws_site_names)
KVM_SITE=$(tf_raw kvm_site_name)
for site_map in "$ROW_SITES" "$CA_SITES" "$AWS_SITES"; do
  [ "$(jq 'length' <<<"$site_map")" -gt 0 ] || die "the complete showcase requires every cloud site group"
done
[ -n "$KVM_SITE" ] && [ "$KVM_SITE" != "null" ] || die "the complete showcase requires the KVM site"

ALL_SITES=$(jq -cn \
  --argjson row "$ROW_SITES" \
  --argjson canada "$CA_SITES" \
  --argjson aws "$AWS_SITES" \
  --arg kvm "$KVM_SITE" \
  '$row + $canada + $aws + {kvm: $kvm}')
SITE_COUNT=$(jq 'length' <<<"$ALL_SITES")
[ "$(jq '[.[]] | unique | length' <<<"$ALL_SITES")" -eq "$SITE_COUNT" ] || die "site names must be unique"

API_URL=$(tf_raw xc_api_url)
[[ "$API_URL" =~ ^https://[a-z0-9-]+\.console\.ves\.volterra\.io$ ]] || die "xc_api_url is not a supported tenant endpoint"

api_get() {
  local url=$1
  printf 'Authorization: APIToken %s\n' "$XCSH_API_TOKEN" |
    curl -fsS --max-time 120 -H @- "$url"
}

sites_online=0
while IFS= read -r site; do
  require_name "site name" "$site"
  state=$(api_get "${API_URL}/api/config/namespaces/system/sites/${site}" |
    jq -r '.object.status.site_state // .status.site_state // .spec.site_state // .get_spec.site_state // empty')
  [ "$state" = "ONLINE" ] || die "site ${site} is not ONLINE"
  sites_online=$((sites_online + 1))
done < <(jq -r '.[]' <<<"$ALL_SITES")
printf 'sites_online=%s/%s\n' "$sites_online" "$SITE_COUNT"

azure_vms_running=0
azure_peerings_with_vip=0
azure_effective_next_hops=0
azure_traffic_paths=0

verify_azure_path() {
  local label=$1 resource_group=$2 route_server=$3 client_vm=$4 client_nic=$5 domain=$6 vip=$7
  local sites=$8 ce_ips=$9 ce_vms=${10} peer_names=${11}
  local expected_count key vm_name view provisioning power peer expected_hop routes actual_hop
  local learned_hops effective_raw effective_routes effective_hops expected_hops message

  require_name "${label} resource group" "$resource_group"
  require_name "${label} Route Server" "$route_server"
  require_name "${label} client VM" "$client_vm"
  require_name "${label} client NIC" "$client_nic"
  require_domain "${label} load-balancer domain" "$domain"
  require_ipv4 "${label} VIP" "$vip"

  expected_count=$(jq 'length' <<<"$sites")
  [ "$(jq 'length' <<<"$ce_ips")" -eq "$expected_count" ] || die "${label} site and CE address maps differ"
  [ "$(jq 'length' <<<"$ce_vms")" -eq "$expected_count" ] || die "${label} site and VM maps differ"
  [ "$(jq 'length' <<<"$peer_names")" -eq "$expected_count" ] || die "${label} site and peering maps differ"

  while IFS= read -r key; do
    vm_name=$(jq -r --arg key "$key" '.[$key]' <<<"$ce_vms")
    view=$(az vm get-instance-view --only-show-errors --resource-group "$resource_group" --name "$vm_name" \
      --query '{provisioningState:provisioningState,powerState:instanceView.statuses[?starts_with(code, `PowerState/`)].code | [0]}' --output json)
    provisioning=$(jq -r '.provisioningState // empty' <<<"$view")
    power=$(jq -r '.powerState // empty' <<<"$view")
    [ "$provisioning" = "Succeeded" ] && [ "$power" = "PowerState/running" ] ||
      die "one ${label} CE VM is not fully running"
    azure_vms_running=$((azure_vms_running + 1))

    peer=$(jq -r --arg key "$key" '.[$key]' <<<"$peer_names")
    expected_hop=$(jq -r --arg key "$key" '.[$key]' <<<"$ce_ips")
    routes=$(az network routeserver peering list-learned-routes --only-show-errors \
      --name "$peer" --routeserver "$route_server" --resource-group "$resource_group" \
      --query "RouteServiceRole_IN_0[?network=='${vip}/32']" --output json)
    [ "$(jq 'length' <<<"$routes")" -eq 1 ] || die "one ${label} peering is missing its VIP route"
    actual_hop=$(jq -r '.[0].nextHop // empty' <<<"$routes")
    [ "$actual_hop" = "$expected_hop" ] || die "one ${label} peering has the wrong VIP next hop"
    learned_hops=$(jq -cn --argjson current "${learned_hops:-[]}" --arg hop "$actual_hop" '$current + [$hop]')
    azure_peerings_with_vip=$((azure_peerings_with_vip + 1))
  done < <(jq -r 'keys[]' <<<"$sites")

  [ "$(jq 'unique | length' <<<"$learned_hops")" -eq "$expected_count" ] || die "${label} VIP next hops are not distinct"
  effective_raw=$(az network nic show-effective-route-table --only-show-errors \
    --resource-group "$resource_group" --name "$client_nic" --output json)
  effective_routes=$(jq -c 'if type == "array" then . else (.value // []) end' <<<"$effective_raw")
  effective_hops=$(jq -c --arg prefix "${vip}/32" \
    '[.[] | select((.addressPrefix[0] // "") == $prefix and (.state // "Active") == "Active") | .nextHopIpAddress[]?] | unique | sort' <<<"$effective_routes")
  expected_hops=$(jq -c '[.[]] | unique | sort' <<<"$ce_ips")
  [ "$effective_hops" = "$expected_hops" ] || die "${label} client does not have every active ECMP next hop"
  azure_effective_next_hops=$((azure_effective_next_hops + expected_count))

  message=$(az vm run-command invoke --only-show-errors --resource-group "$resource_group" --name "$client_vm" \
    --command-id RunShellScript --query 'value[0].message' --output tsv \
    --scripts "curl -fsS -H 'Host: ${domain}' 'http://${vip}/' >/dev/null && echo MCN_HTTP_OK")
  grep -qF 'MCN_HTTP_OK' <<<"$message" || die "${label} client traffic failed"
  azure_traffic_paths=$((azure_traffic_paths + 1))
}

verify_azure_path \
  "Azure Rest-of-World" \
  "$(tf_raw resource_group_name)" "$(tf_raw route_server_name)" "$(tf_raw client_vm_name)" "$(tf_raw client_nic_name)" \
  "$(tf_raw lb_domain)" "$(tf_raw vip)" "$ROW_SITES" "$(tf_json ce_mgmt_private_ips)" "$(tf_json ce_vm_names)" \
  "$(tf_json route_server_bgp_connection_names)"

verify_azure_path \
  "Azure Canada" \
  "$(tf_raw ca_resource_group_name)" "$(tf_raw ca_route_server_name)" "$(tf_raw ca_client_vm_name)" "$(tf_raw ca_client_nic_name)" \
  "$(tf_raw ca_lb_domain)" "$(tf_raw ca_vip)" "$CA_SITES" "$(tf_json ca_ce_mgmt_private_ips)" "$(tf_json ca_ce_vm_names)" \
  "$(tf_json ca_route_server_bgp_connection_names)"

printf 'azure_vms_running=%s\n' "$azure_vms_running"
printf 'azure_peerings_with_vip=%s\n' "$azure_peerings_with_vip"
printf 'azure_effective_next_hops=%s\n' "$azure_effective_next_hops"
printf 'azure_traffic_paths=%s/2\n' "$azure_traffic_paths"

CA_ILB_ID=$(tf_raw ca_ilb_id)
CA_ILB_RULE=$(tf_raw ca_ilb_rule_name)
CA_ILB_IP=$(tf_raw ca_ilb_frontend_ip)
CA_CLIENT=$(tf_raw ca_client_vm_name)
CA_RG=$(tf_raw ca_resource_group_name)
require_name "Canadian ILB ID" "$CA_ILB_ID"
require_name "Canadian ILB rule" "$CA_ILB_RULE"
require_ipv4 "Canadian ILB frontend" "$CA_ILB_IP"

AZURE_ACCESS_TOKEN=$(az account get-access-token --resource https://management.azure.com/ --query accessToken --output tsv)
[ -n "$AZURE_ACCESS_TOKEN" ] || die "Azure did not issue a management API token"
health_headers=$(mktemp)
health_body=$(mktemp)
trap 'rm -f "$health_headers" "$health_body"' EXIT
health_url="https://management.azure.com${CA_ILB_ID}/loadBalancingRules/${CA_ILB_RULE}/health?api-version=2025-07-01&preserve-view=true"
printf 'Authorization: Bearer %s\n' "$AZURE_ACCESS_TOKEN" |
  curl -fsS -D "$health_headers" -o /dev/null -X POST -H @- "$health_url"
health_location=$(awk 'tolower($1) == "location:" {sub(/^[^:]*:[[:space:]]*/, ""); sub(/\r$/, ""); print; exit}' "$health_headers")
[ -n "$health_location" ] || die "Azure Load Balancer health request returned no operation location"

health_status=0
for _ in $(seq 1 24); do
  health_status=$(printf 'Authorization: Bearer %s\n' "$AZURE_ACCESS_TOKEN" |
    curl -sS -o "$health_body" -w '%{http_code}' -H @- "$health_location")
  [ "$health_status" = 200 ] && break
  [ "$health_status" = 202 ] || die "Azure Load Balancer health operation failed"
  sleep 5
done
[ "$health_status" = 200 ] || die "Azure Load Balancer health operation did not complete"
ca_expected=$(jq 'length' <<<"$CA_SITES")
jq -e --argjson expected "$ca_expected" \
  '.up == $expected and .down == 0 and (.loadBalancerBackendAddresses | length) == $expected and all(.loadBalancerBackendAddresses[]; .state == "Up")' \
  "$health_body" >/dev/null || die "Canadian ILB does not report every backend healthy"
printf 'canada_ilb_backends_up=%s/%s\n' "$ca_expected" "$ca_expected"

ilb_message=$(az vm run-command invoke --only-show-errors --resource-group "$CA_RG" --name "$CA_CLIENT" \
  --command-id RunShellScript --query 'value[0].message' --output tsv \
  --scripts "curl -skf 'https://${CA_ILB_IP}:65500/' >/dev/null && echo MCN_ILB_OK")
grep -qF 'MCN_ILB_OK' <<<"$ilb_message" || die "Canadian ILB frontend traffic failed"
printf 'canada_ilb_traffic=ok\n'

AWS_REGION=$(tf_raw aws_region)
AWS_RS=$(tf_raw aws_route_server_id)
AWS_VIP=$(tf_raw aws_vip)
AWS_DOMAIN=$(tf_raw aws_lb_domain)
AWS_CLIENT=$(tf_raw aws_test_client_instance_id)
AWS_PEER_IDS=$(tf_json aws_route_server_peer_ids)
AWS_ROUTE_TABLES=$(tf_json aws_route_server_propagated_route_tables)
require_name "AWS region" "$AWS_REGION"
require_name "AWS Route Server ID" "$AWS_RS"
require_ipv4 "AWS VIP" "$AWS_VIP"
require_domain "AWS load-balancer domain" "$AWS_DOMAIN"
require_name "AWS client instance ID" "$AWS_CLIENT"

aws_peer_args=()
while IFS= read -r peer_id; do
  require_name "AWS Route Server peer ID" "$peer_id"
  aws_peer_args+=("$peer_id")
done < <(jq -r '.[]' <<<"$AWS_PEER_IDS")
AWS_PEER_COUNT=${#aws_peer_args[@]}
[ "$AWS_PEER_COUNT" -eq "$(jq 'length' <<<"$AWS_SITES")" ] || die "AWS site and Route Server peer counts differ"

aws_peers=$(aws ec2 describe-route-server-peers --region "$AWS_REGION" --route-server-peer-ids "${aws_peer_args[@]}" --output json)
jq -e --argjson expected "$AWS_PEER_COUNT" \
  '(.RouteServerPeers | length) == $expected and all(.RouteServerPeers[]; .State == "available" and .BgpStatus.Status == "up")' \
  <<<"$aws_peers" >/dev/null || die "not every AWS Route Server BGP peer is up"
printf 'aws_bgp_peers_up=%s/%s\n' "$AWS_PEER_COUNT" "$AWS_PEER_COUNT"

aws_routes=$(aws ec2 get-route-server-routing-database --region "$AWS_REGION" --route-server-id "$AWS_RS" --output json)
propagated_count=$(jq 'length' <<<"$AWS_ROUTE_TABLES")
jq -e --arg prefix "${AWS_VIP}/32" --argjson peers "$AWS_PEER_COUNT" --argjson tables "$propagated_count" \
  '[.Routes[] | select(.Prefix == $prefix)] as $routes |
   ($routes | length) == $peers and
   all($routes[]; .RouteStatus == "in-fib" and
     ([.RouteInstallationDetails[] | select(.RouteInstallationStatus == "installed")] | length) == $tables)' \
  <<<"$aws_routes" >/dev/null || die "AWS VIP is not installed from every peer in every propagated route table"
printf 'aws_vip_routes_installed=%s/%s\n' "$AWS_PEER_COUNT" "$AWS_PEER_COUNT"

aws_command=$(aws ssm send-command --region "$AWS_REGION" --instance-ids "$AWS_CLIENT" \
  --document-name AWS-RunShellScript \
  --parameters "commands=curl -fsS -H 'Host: ${AWS_DOMAIN}' 'http://${AWS_VIP}/' >/dev/null" \
  --query 'Command.CommandId' --output text)
require_name "AWS Systems Manager command ID" "$aws_command"
aws ssm wait command-executed --region "$AWS_REGION" --command-id "$aws_command" --instance-id "$AWS_CLIENT"
aws_status=$(aws ssm get-command-invocation --region "$AWS_REGION" --command-id "$aws_command" --instance-id "$AWS_CLIENT" --query Status --output text)
[ "$aws_status" = "Success" ] || die "AWS test-client traffic failed"
printf 'aws_client_traffic=ok\n'

KVM_DOMAIN=$(tf_raw kvm_domain_name)
KVM_FRR=$(tf_raw kvm_frr_container_name)
KVM_CLIENT=$(tf_raw kvm_client_container_name)
KVM_VIP=$(tf_raw kvm_vip)
KVM_LB_DOMAIN=$(tf_raw kvm_lb_domain)
require_name "KVM domain" "$KVM_DOMAIN"
require_name "KVM FRR container" "$KVM_FRR"
require_name "KVM client container" "$KVM_CLIENT"
require_ipv4 "KVM VIP" "$KVM_VIP"
require_domain "KVM load-balancer domain" "$KVM_LB_DOMAIN"

[ "$(virsh -c qemu:///system domstate "$KVM_DOMAIN" | tr -d '[:space:]')" = "running" ] || die "KVM CE domain is not running"
[ "$(docker inspect --format '{{.State.Running}}' "$KVM_FRR")" = "true" ] || die "KVM FRR container is not running"
[ "$(docker inspect --format '{{.State.Running}}' "$KVM_CLIENT")" = "true" ] || die "KVM client container is not running"
kvm_summary=$(docker exec "$KVM_FRR" vtysh -c 'show ip bgp summary json')
jq -e '[.. | objects | .peers? // empty | to_entries[] | select(.value.state == "Established")] | length == 1' \
  <<<"$kvm_summary" >/dev/null || die "KVM FRR does not have exactly one established CE peer"
kvm_route=$(docker exec "$KVM_FRR" vtysh -c "show ip bgp ${KVM_VIP}/32 json")
jq -e '(.paths | length) > 0 and any(.paths[]; .valid == true)' <<<"$kvm_route" >/dev/null ||
  die "KVM FRR has not learned a valid VIP route"
docker exec "$KVM_CLIENT" curl -fsS -H "Host: ${KVM_LB_DOMAIN}" "http://${KVM_VIP}/" >/dev/null ||
  die "KVM client traffic failed"
printf 'kvm_bgp_peer=established\n'
printf 'kvm_vip_route=learned\n'
printf 'kvm_client_traffic=ok\n'

set +e
"${TF[@]}" plan -detailed-exitcode -no-color >"${EVIDENCE_DIR}/terraform-plan.txt" 2>&1
plan_exit=$?
set -e
[ "$plan_exit" -eq 0 ] || die "Terraform has not converged to a clean plan"
printf 'terraform_plan=clean\n'

FINISHED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
jq -n \
  --arg started_at "$STARTED_AT" \
  --arg finished_at "$FINISHED_AT" \
  --argjson sites_online "$sites_online" \
  --argjson site_count "$SITE_COUNT" \
  --argjson azure_vms_running "$azure_vms_running" \
  --argjson azure_peerings_with_vip "$azure_peerings_with_vip" \
  --argjson azure_effective_next_hops "$azure_effective_next_hops" \
  --argjson canada_ilb_backends_up "$ca_expected" \
  --argjson aws_bgp_peers_up "$AWS_PEER_COUNT" \
  --argjson aws_vip_routes_installed "$AWS_PEER_COUNT" \
  '{
    started_at: $started_at,
    finished_at: $finished_at,
    sites_online: $sites_online,
    site_count: $site_count,
    azure_vms_running: $azure_vms_running,
    azure_peerings_with_vip: $azure_peerings_with_vip,
    azure_effective_next_hops: $azure_effective_next_hops,
    azure_traffic_paths: 2,
    canada_ilb_backends_up: $canada_ilb_backends_up,
    canada_ilb_traffic: "ok",
    aws_bgp_peers_up: $aws_bgp_peers_up,
    aws_vip_routes_installed: $aws_vip_routes_installed,
    aws_client_traffic: "ok",
    kvm_bgp_peer: "established",
    kvm_vip_route: "learned",
    kvm_client_traffic: "ok",
    terraform_plan: "clean"
  }' >"${EVIDENCE_DIR}/summary.json"

echo 'full_showcase_verified=yes'
