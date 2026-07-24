# SMSv2 Coverage Matrix (xcsh_securemesh_site_v2)

Legend: ✅ done · ⏳ in progress · ⬜ not started · ➖ n/a · ⚠️ done with a documented caveat

Columns:

- **Structural** — the arm is expressible in HCL / present in the probe or module.
- **Validated** — an out-of-range / invalid value is rejected by input validation (`.tftest.hcl`).
- **Applied** — the arm applies live against the XC tenant (HTTP 200).
- **Idempotent** — a re-plan after apply reports "No changes".
- **Import-clean** — `terraform import` of the object re-plans with 0 changes.
- **Notes** — slice that covers the arm and any caveats.

| Branch / leaf | Structural | Validated | Applied | Idempotent | Import-clean | Notes |
|---|---|---|---|---|---|---|
| azure.not_managed.node_list[].interface_list[] | ✅ | ⬜ | ✅ | ✅ | ✅ | iter-1 (live N=3) |
| interface_list.mtu (max 16384) | ✅ | ✅ | ✅ | ✅ | ⚠️ | S1: validator `AtMost(16384)` (reject 20000); base probe live-applied+idempotent; leaf does not drift on import but the object import carries the labels{} #1103 drift (see below) |
| interface_list.priority (0-255) | ✅ | ✅ | ✅ | ✅ | ⚠️ | S1: validator `Between(0, 255)` (reject 256); on the base eth0 interface, live-applied+idempotent; import caveat as mtu |
| vlan_interface.vlan_id (1-4095) | ✅ | ✅ | ⬜ | ➖ | ➖ | S1: validator `Between(1, 4095)` (reject 4096) proven at plan; NOT live-applicable — vlan_interface on the `azure` not_managed single Control node 400s (BAD_REQUEST); gated behind `var.extended_arms`, plan-validated only |
| custom_proxy.proxy_port (0-65535) | ✅ | ✅ | ⬜ | ➖ | ➖ | S1: validator `Between(0, 65535)` (reject 70000) proven at plan; NOT live-applicable — custom_proxy 400s on this probe; gated behind `var.extended_arms`, plan-validated only |
| ethernet_interface.mac | ✅ | ✅ | ✅ | ✅ | ⚠️ | S2: validator `MACValidator()` (reject `"not-a-mac"`); live-applied on the base eth0 with a valid MAC (`7C-1E-52-7F-F8-12`), idempotent; whole-object import carries the labels{} #1103 drift (see S1 note); gated by `string_arms` |
| static_ip.ip_address (CIDR) | ✅ | ✅ | ✅ | ✅ | ⚠️ | S2: validator `CIDRValidator()` (reject `"999.999.0.0/8"`); static_ip is the `dhcp_client` address-oneof sibling, live-applied+idempotent (`10.0.1.5/24`), gated by `string_arms`; import labels{} #1103 drift |
| static_ip.default_gw (IP) | ✅ | ✅ | ✅ | ✅ | ⚠️ | S2: validator `IPValidator()` (reject `"10.0.0.256"`); applied live with ip_address (`10.0.1.1`); import labels{} #1103 drift |
| local_vrf.sli_config.nameserver (IPv4) | ✅ | ✅ | ⬜ | ➖ | ➖ | S2: validator `IPv4Validator()` (reject `"300.1.1.1"`) proven at plan; NOT live-applied — `sli_config` is a distinct `local_vrf` oneof arm from the base `default_sli_config`; gated behind `vrf_string_arms` (default false), plan-validated only (live is an S3 oneof concern) |
| local_vrf.sli_config.vip (IPv4) | ✅ | ✅ | ⬜ | ➖ | ➖ | S2: validator `IPv4Validator()` (reject the IPv6 literal `"2001:db8::1"`, proving IPv4-specificity); plan-validated only, gated behind `vrf_string_arms` (S3 oneof, as nameserver) |
<!-- remaining toggle/interface/services arms seeded ⬜ for S3–S5 -->
| block_all_services{} | ✅ | ➖ | ✅ | ✅ | ✅ | iter-1 (S0 probe) |
| disable_ha{} | ✅ | ➖ | ✅ | ✅ | ✅ | iter-1 (S0 probe) |
| dns_ntp_config.f5_dns_default{} | ✅ | ➖ | ✅ | ✅ | ⬜ | S0 probe; oneof: custom_dns S3 |
| dns_ntp_config.f5_ntp_default{} | ✅ | ➖ | ✅ | ✅ | ⬜ | S0 probe; oneof: custom_ntp S3 |
| local_vrf.default_config{} | ✅ | ➖ | ✅ | ✅ | ⬜ | S0 probe |
| local_vrf.default_sli_config{} | ✅ | ➖ | ✅ | ✅ | ⬜ | S0 probe |
| logs_streaming_disabled{} | ✅ | ➖ | ✅ | ✅ | ⬜ | S0 probe; oneof: log_receiver S4 |
| no_forward_proxy{} | ✅ | ➖ | ✅ | ✅ | ⬜ | S0 probe; oneof: custom/active fwd proxy S4 |
| no_network_policy{} | ✅ | ➖ | ✅ | ✅ | ⬜ | S0 probe; oneof: active_network_policies S4 |
| no_s2s_connectivity_sli{} | ✅ | ➖ | ✅ | ✅ | ⬜ | S0 probe |
| no_s2s_connectivity_slo{} | ✅ | ➖ | ✅ | ✅ | ⬜ | S0 probe |
| offline_survivability_mode.no_offline_survivability_mode{} | ✅ | ➖ | ✅ | ✅ | ⬜ | S0 probe; oneof: enable S5 |
| performance_enhancement_mode.perf_mode_l7_enhanced{} | ✅ | ➖ | ✅ | ✅ | ⬜ | S0 probe; oneof: perf_mode_l3_enhanced S5 |
| re_select.geo_proximity{} | ✅ | ➖ | ✅ | ✅ | ⬜ | S0 probe; oneof: from_site_list S5 |
| software_settings.os.default_os_version{} | ✅ | ➖ | ✅ | ✅ | ⬜ | S0 probe; oneof: operating_system_version S5 |
| software_settings.sw.default_sw_version{} | ✅ | ➖ | ✅ | ✅ | ⬜ | S0 probe; oneof: volterra_software_version S5 |
| node_list[].type (Control/Worker) | ✅ | ✅ | ✅ | ✅ | ✅ | iter-1 live; S2: validator `OneOf("Control", "Worker")` (reject `"Bogus"`); the valid `Worker` arm plans clean and `Control` applied live |
| interface_list.ethernet_interface{} | ✅ | ➖ | ✅ | ✅ | ✅ | iter-1; block arm (its `mac` leaf → Validated ✅, row above); oneof vs vlan/dedicated S3 |
| interface_list.network_option.site_local_network{} | ✅ | ⬜ | ✅ | ✅ | ✅ | iter-1; oneof: SLI/inside S3 |
| interface_list.dhcp_client{} | ✅ | ➖ | ✅ | ✅ | ⚠️ | iter-1 + S3 `address_arm=dhcp_client`; block arm; the `static_ip` address-oneof sibling → Validated ✅ + Applied ✅ (rows above); live-applied+idempotent, labels{} #1244 import drift |
| labels | ✅ | ➖ | ✅ | ➖ | ➖ | iter-1; ignore_changes (empty-map drift, xcsh #1103 class) |
<!-- S3: interface / addressing oneof arms (enum selectors; live cycle uses -var extended_arms=false) -->
| interface_list.static_ip{} (address_choice) | ✅ | ✅ | ✅ | ✅ | ⚠️ | S3 `address_arm=static_ip` (default); ip_address/default_gw validated (rows above); live-applied+idempotent, labels{} #1244 import drift |
| interface_list.no_ipv4_address{} (address_choice) | ✅ | ➖ | ✅ | ✅ | ⚠️ | S3 `address_arm=no_ipv4_address`; empty marker; live apply→idempotent→import (labels{} #1244 drift only)→destroy |
| interface_list.no_ipv6_address{} (ipv6_address_choice) | ✅ | ➖ | ✅ | ✅ | ⚠️ | S3 `ipv6_arm=no_ipv6_address` (default); empty marker; live apply→idempotent→import (labels{} #1244 drift only)→destroy |
| interface_list.monitor{} (monitoring_choice) | ✅ | ➖ | ✅ | ✅ | ⚠️ | S3 `monitor_arm=monitor`; empty marker; live apply→idempotent→import (labels{} #1244 drift only)→destroy |
| interface_list.monitor_disabled{} (monitoring_choice) | ✅ | ➖ | ✅ | ✅ | ⚠️ | S3 `monitor_arm=monitor_disabled` (default); empty marker; live apply→idempotent→import (labels{} #1244 drift only)→destroy |
| interface_list.site_to_site_connectivity_interface_disabled{} | ✅ | ➖ | ✅ | ✅ | ⚠️ | S3 `s2s_iface_arm=disabled` (default); empty marker; live apply→idempotent→import (labels{} #1244 drift only)→destroy |
| interface_list.site_to_site_connectivity_interface_enabled{} | ✅ | ➖ | ✅ | ✅ | ⚠️ | S3 `s2s_iface_arm=enabled`; empty marker; recon expected 400 (s2s wiring) but the single-node `azure` probe ACCEPTS it — live apply→idempotent→import (labels{} #1244 drift only)→destroy |
| interface_list.ethernet_interface{} (interface_choice) | ✅ | ✅ | ✅ | ✅ | ⚠️ | S3 `interface_arm=ethernet` (default); mac leaf validated (row above); live-applied+idempotent, labels{} #1244 import drift |
| interface_list.bond_interface{} (interface_choice) | ✅ | ✅ | ⬜ | ➖ | ➖ | S3 `interface_arm=bond`; plan-only — 400 (BAD_REQUEST) on single-node `azure` probe (confirmed live); `devices` `SizeBetween(1, 8)` reject proven at plan (reject-bond-devices); `lacp.rate` `Between(1, 30)` + `devices` plan clean |
| interface_list.vlan_interface{} (interface_choice) | ✅ | ✅ | ⬜ | ➖ | ➖ | S3 `interface_arm=vlan` (primary oneof); plan-only — 400 on single-node `azure` probe (confirmed live); `vlan_id` `Between(1, 4095)` validated (S1 reject-vlan-id via the extended_arms second interface) |
| interface_list.ipv6_auto_config{} (ipv6_address_choice) | ✅ | ➖ | ⬜ | ➖ | ➖ | S3 `ipv6_arm=ipv6_auto_config`; plan-only — 400 on single-node IPv4 `azure` probe (confirmed live); renders the `host {}` autoconfig_choice member; plans clean |
| interface_list.static_ipv6_address{} (ipv6_address_choice) | ✅ | ✅ | ⬜ | ➖ | ➖ | S3 `ipv6_arm=static_ipv6_address`; plan-only — 400 on single-node IPv4 `azure` probe (confirmed live); `node_static_ip.ip_address` `CIDRValidator()` reject proven at plan (reject-static-ipv6) |
<!-- S4: networking / services top-level oneof arms (enum selectors; live cycle uses -var extended_arms=false) -->
| blocked_services.blocked_service{} (services_choice) | ✅ | ✅ | ⬜ | ➖ | ➖ | S4 `services_arm=blocked_services`; plan-only — provider round-trip bug: apply errors "Provider produced inconsistent result after apply: .blocked_services.blocked_service block count changed from 1 to 0" (read-back drops the block) — tracked as provider #1257. `network_type` `OneOf` reject proven at plan (reject-network-type) |
| blocked_services.blocked_service.network_type (OneOf) | ✅ | ✅ | ⬜ | ➖ | ➖ | S4: validator `OneOf(VIRTUAL_NETWORK_*)` (reject `"BOGUS"`) proven at plan (reject-network-type); not live (parent arm round-trip bug above) |
| f5_proxy{} (enterprise_proxy_choice) | ✅ | ➖ | ✅ | ✅ | ⚠️ | S4 `proxy_arm=f5_proxy`; empty marker; live apply→idempotent→import (labels{} #1244 drift only)→destroy |
| custom_proxy.proxy_ip_address (IPv4) | ✅ | ✅ | ⬜ | ➖ | ➖ | S4: validator `IPv4Validator()` (reject `"999.1.1.1"`) proven at plan (reject-proxy-ip); custom_proxy 400s live (S1), gated behind `extended_arms`, plan-validated only |
| dns_ntp_config.custom_dns.dns_servers | ✅ | ➖ | ✅ | ✅ | ⚠️ | S4 `dns_arm=custom_dns`; renders `dns_servers`; live apply→idempotent→import (labels{} #1244 drift only)→destroy |
| dns_ntp_config.custom_ntp.ntp_servers | ✅ | ➖ | ✅ | ✅ | ⚠️ | S4 `ntp_arm=custom_ntp`; renders `ntp_servers`; live apply→idempotent→import (labels{} #1244 drift only)→destroy |
| custom_proxy_bypass.proxy_bypass | ✅ | ➖ | ✅ | ✅ | ⚠️ | S4 `proxy_bypass_arm=custom_proxy_bypass`; renders `proxy_bypass` domain list; live apply→idempotent→import (labels{} #1244 drift only)→destroy |
| no_proxy_bypass{} (proxy_bypass_choice) | ✅ | ➖ | ✅ | ✅ | ⚠️ | S4 `proxy_bypass_arm=no_proxy_bypass`; empty marker; live apply→idempotent→import (labels{} #1244 drift only)→destroy |
| enable_url_categorization{} (url_categorization_choice) | ✅ | ➖ | ✅ | ✅ | ⚠️ | S4 `url_cat_arm=enable_url_categorization`; empty marker; live apply→idempotent→import (labels{} #1244 drift only)→destroy |
| disable_url_categorization{} (url_categorization_choice) | ✅ | ➖ | ✅ | ✅ | ⚠️ | S4 `url_cat_arm=disable_url_categorization`; empty marker; live apply→idempotent→import (labels{} #1244 drift only)→destroy |
| disable_management_network{} (management_network_choice) | ✅ | ➖ | ✅ | ✅ | ⚠️ | S4 `mgmt_net_arm=disable_management_network`; empty marker; live apply→idempotent→import (labels{} #1244 drift only)→destroy |
| load_balancing.vip_vrrp_mode (OneOf) | ✅ | ✅ | ✅ | ✅ | ⚠️ | S4 `vip_vrrp_mode=VIP_VRRP_ENABLE`/`VIP_VRRP_DISABLE`; validator `OneOf(VIP_VRRP_INVALID, VIP_VRRP_ENABLE, VIP_VRRP_DISABLE)` (reject `"BOGUS"`, reject-vip-vrrp-mode); both ENABLE and DISABLE live apply→idempotent→import (labels{} #1244 drift only)→destroy |
| site_mesh_group_on_slo{no_site_mesh_group{} sm_connection_public_ip{}} (s2s_slo_choice) | ✅ | ➖ | ✅ | ✅ | ⚠️ | S4 `s2s_slo_arm=site_mesh_group_empty`; renders both sub-oneofs (mesh_group_choice + connection_choice) all-empty; live apply→idempotent→import (labels{} #1244 drift only)→destroy |
| enable_ha{} (node_ha_choice) | ✅ | ➖ | ⬜ | ➖ | ➖ | S4 `ha_arm=enable_ha`; plan-only — 400 on single-node `azure` probe (needs >=3 nodes); plans clean |
| enable_management_network{} (management_network_choice) | ✅ | ➖ | ⬜ | ➖ | ➖ | S4 `mgmt_net_arm=enable_management_network`; plan-only — 400 on single-node `azure` probe; plans clean |
| active_forward_proxy_policies.forward_proxy_policies[] (ref) | ✅ | ➖ | ⬜ | ➖ | ➖ | S4 `forward_proxy_arm=active_forward_proxy_policies`; plan-only — ObjectRefType list, ref-dependent; plans clean |
| active_enhanced_firewall_policies.enhanced_firewall_policies[] (ref) | ✅ | ➖ | ⬜ | ➖ | ➖ | S4 `network_policy_arm=active_enhanced_firewall_policies`; plan-only — ObjectRefType list, ref-dependent; plans clean |
| log_receiver_with_net{log_receiver ref, use_slo_sli{}} (logs_choice) | ✅ | ➖ | ⬜ | ➖ | ➖ | S4 `logs_arm=log_receiver_with_net`; plan-only — ObjectRefType, ref-dependent; drives logs via `log_receiver_with_net`, NOT the stale top-level `log_receiver` field (provider #1256); plans clean |
| dc_cluster_group_sli{} (ref, s2s_sli_choice) | ✅ | ➖ | ⬜ | ➖ | ➖ | S4 `s2s_sli_arm=dc_cluster_group_sli`; plan-only — ObjectRefType, ref-dependent; plans clean |
| dc_cluster_group_slo{} (ref, s2s_slo_choice) | ✅ | ➖ | ⬜ | ➖ | ➖ | S4 `s2s_slo_arm=dc_cluster_group_slo`; plan-only — ObjectRefType, ref-dependent; plans clean |
| site_mesh_group_on_slo{site_mesh_group ref} (s2s_slo_choice) | ✅ | ➖ | ⬜ | ➖ | ➖ | S4 `s2s_slo_arm=site_mesh_group_ref`; plan-only — `site_mesh_group` ObjectRefType, ref-dependent; plans clean |
| segment_vrf.segment_config.nameserver (IPv4) | ✅ | ✅ | ⬜ | ➖ | ➖ | S4 `segment_vrf_arm=inline`; plan-only — needs a Segment object ref the provider cannot yet inject (specs #1053); validator `IPv4Validator()` (reject `"300.2.2.2"`, reject-segment-nameserver) proven at plan |

**S1 notes (numeric-leaf input validation):**

- **How "Validated" is proven** — `coverage/smsv2/verify.sh` drives `terraform test` with a
  mocked `xcsh` provider (credential-free; the real v3.75.0 schema validators still fire at
  plan). `validation.tftest.hcl` asserts valid bounds plan clean; `reject-tests/*.tftest.hcl`
  each push one leaf out of range and are *designed to fail* — `expect_failures` cannot capture
  provider schema validators (only user custom conditions), so verify.sh asserts the exact
  validator diagnostic per leaf instead.
- **mtu is `AtMost(16384)` only** — the API's discontinuous rule {0} ∪ [512,16384] has no single
  minimum, so the failing test uses `mtu = 20000` (a small value like 200 is *not* rejected).
- **⚠️ import caveat (mtu, priority)** — a whole-object `terraform import` re-plans with one
  in-place change: `- labels {}` on the interface (xcsh #1103 empty-marker class, still present
  on v3.75.0 for `securemesh_site_v2` interface labels). The numeric leaves themselves do not
  drift; the base probe is apply-clean and idempotent. Out of scope for S1 (numeric validators).
- **vlan_id / proxy_port not live-applied** — `vlan_interface` and top-level `custom_proxy` both
  return `[BAD_REQUEST] Invalid request parameters (400)` on the `azure` not_managed single Control
  node. They are gated behind `var.extended_arms` (default true) so their validators are reached
  at PLAN time; the live apply/idempotent/import ran with `-var extended_arms=false` on the base
  probe (which still carries the mtu and priority leaves).

**S2 notes (string-leaf input validation, provider >= 3.75.1):**

- **Same verify.sh harness** — the S2 string reject cases (`reject-mac`, `reject-ip-address`,
  `reject-default-gw`, `reject-nameserver`, `reject-vip`, `reject-node-type`) are driven by the
  same `verify.sh` Phase 2, which asserts each validator's exact diagnostic. The accept case in
  `validation.tftest.hcl` proves every string validator also passes a valid value at plan.
- **mac / static_ip live-applied** — unlike S1's vlan_interface/custom_proxy, the eth0
  `ethernet_interface.mac` and the `static_ip { ip_address, default_gw }` address-oneof arm both
  apply live (HTTP 200) on the `azure` not_managed single-node probe. The live cycle ran twice
  with a fresh `probe_name`: (a) the base arm `-var string_arms=false` (dhcp_client, no mac), and
  (b) the string arm `-var string_arms=true` (mac + static_ip) — both apply → 0-change re-plan →
  import → destroy, with only the shared labels{} #1103 import drift and no string-leaf drift.
- **nameserver / vip plan-only** — `IPv4Validator()` is proven at PLAN via `reject-nameserver`
  (bad IPv4 `300.1.1.1`) and `reject-vip` (the IPv6 literal `2001:db8::1`, proving IPv4-specificity).
  They live on `local_vrf.sli_config`, a distinct oneof arm from the base `default_sli_config`, so
  they are gated behind `var.vrf_string_arms` (default false) and NOT live-applied — the live oneof
  swap is an S3 concern. Not overclaimed: Applied stays ⬜.
- **validator string values** — MAC uses `net.ParseMAC`, CIDR `net.ParseCIDR`, IP `net.ParseIP`,
  IPv4 `net.ParseIP + To4()`; each skips null/empty (Optional) so absent leaves never error.

**S3 notes (interface / addressing oneof arms, provider v3.76.0):**

- **Enum selectors, not booleans** — each interface oneof is driven by an enum var
  (`interface_arm`, `address_arm`, `ipv6_arm`, `monitor_arm`, `s2s_iface_arm`) so exactly one
  member of each oneof renders and no two siblings coexist (which would trip `ConflictsWith`). The
  old S2 `string_arms` boolean now gates only the `mac` leaf; the address oneof is `address_arm`.
- **Live cycle uses `-var extended_arms=false`** — as in S1/S2, the default `extended_arms=true`
  second interface (vlan/custom_proxy) 400s, so every live apply/idempotent/import ran with
  `extended_arms=false` on the base probe (which still renders one member of every eth0 oneof).
- **Live-appliable arms** — `ethernet_interface`, `dhcp_client`, `static_ip`, `no_ipv4_address`,
  `no_ipv6_address`, `monitor`, `monitor_disabled`, `s2s_..._disabled`, `s2s_..._enabled` all
  apply (HTTP 200), re-plan clean, and import with only the known `labels {}` #1244 drift (already
  handled by `ignore_changes`). `s2s_..._enabled` was expected plan-only in recon but the
  single-node `azure` probe accepts it — reclassified live after verification.
- **Plan-only arms** — `bond_interface`, `vlan_interface`, `ipv6_auto_config`,
  `static_ipv6_address` each return `[BAD_REQUEST] Invalid request parameters (status: 400)` on the
  single-node `azure` not_managed probe (confirmed live), so their schema is proven at PLAN only via
  `validation.tftest.hcl` positive asserts, and their validated leaves via `verify.sh` reject tests
  (`reject-bond-devices` = `devices` `SizeBetween(1, 8)`, `reject-static-ipv6` = `node_static_ip`
  `ip_address` `CIDRValidator()`). `vlan_id` `Between(1, 4095)` reject is already covered by S1.
- **is_management / is_primary** — out of S3 scope (provider-capability gap, tracked in
  api-specs-enriched #1049; needs spec injection + regen).

**S4 notes (networking / services top-level oneof arms, provider v3.76.0):**

- **Enum selectors supersede the base literals** — each top-level networking/services oneof is driven
  by an enum var (`services_arm`, `ha_arm`, `dns_arm`, `ntp_arm`, `proxy_arm`, `proxy_bypass_arm`,
  `url_cat_arm`, `mgmt_net_arm`, `s2s_slo_arm`, `s2s_sli_arm`, `forward_proxy_arm`,
  `network_policy_arm`, `logs_arm`, `vip_vrrp_mode`, `segment_vrf_arm`) so exactly ONE member of each
  oneof renders. Every default is the arm the pre-S4 base probe already applied, so a bare
  `terraform plan` (all defaults) shows NO diff versus the pre-S4 base — verified live: applied the
  committed base, swapped in the S4 code, and a defaults plan reported "No changes."
- **Live cycle uses `-var extended_arms=false`** — as in S1–S3, `custom_proxy` and the second vlan
  interface 400 live, so every S4a live apply/idempotent/import ran with `extended_arms=false`.
- **S4a live-appliable arms** (HTTP 200, idempotent, import-clean modulo the known `labels {}` #1244
  drift): `f5_proxy`, `custom_dns`, `custom_ntp`, `custom_proxy_bypass`, `no_proxy_bypass`,
  `enable_url_categorization`, `disable_url_categorization`, `disable_management_network`,
  `load_balancing.vip_vrrp_mode` (ENABLE + DISABLE), and `site_mesh_group_on_slo` all-empty
  (`no_site_mesh_group{} sm_connection_public_ip{}`). Each ran apply→0-change re-plan→import→destroy.
- **`blocked_services` reclassified plan-only** — recon expected it live (S4a), but the apply errors
  with `Provider produced inconsistent result after apply: .blocked_services.blocked_service block
  count changed from 1 to 0` (the provider read-back drops the block). This is a provider round-trip
  bug, not a config error; the `network_type` `OneOf` validator is still proven at plan.
- **S4b plan-only (ref-dependent)** — `active_forward_proxy_policies`,
  `active_enhanced_firewall_policies`, `log_receiver_with_net`, `dc_cluster_group_sli`,
  `dc_cluster_group_slo`, and `site_mesh_group_on_slo` with a `site_mesh_group` ref are ObjectRefType
  arms whose referents must pre-exist; their schema is proven at PLAN via `validation.tftest.hcl`
  positive asserts.
- **S4c plan-only (single-node 400)** — `enable_ha` and `enable_management_network` 400 on the
  single-node `azure` probe; proven at PLAN.
- **`segment_vrf` plan-only** — a live `segment_vrf` needs a Segment object reference the provider
  cannot yet inject (specs #1053); proven at PLAN, and its `segment_config.nameserver`
  `IPv4Validator()` reject at plan (reject-segment-nameserver, `"300.2.2.2"`).
- **Stale `log_receiver` avoided** — logs are driven via `log_receiver_with_net`, never the stale
  top-level `log_receiver` field (provider #1256).

<!--
Slice roadmap:
- S0: probe workspace + this matrix (done).
- S1: numeric-leaf input validation (.tftest.hcl out-of-range rejection) — DONE (verify.sh; provider v3.75.0).
- S2: string-leaf input validation (mac/CIDR/IP/IPv4/node-type) — DONE (verify.sh; provider v3.75.1).
- S3: interface/addressing oneof arms (interface_choice ethernet/bond/vlan; address_choice dhcp_client/static_ip/no_ipv4_address; ipv6_address_choice; monitoring_choice; s2s_iface_choice) — DONE (verify.sh + live matrix; provider v3.76.0).
- S4: networking/services top-level oneof arms (blocked_services, dns/ntp, enterprise proxy, proxy bypass, url categorization, management network, load_balancing vip_vrrp_mode, s2s slo/sli, forward proxy, network policy, log streaming/receiver, site mesh group, segment_vrf) — DONE (verify.sh + live matrix; provider v3.76.0).
- S5: site-mode oneof arms (offline survivability, performance mode, re_select, software_settings explicit versions).
-->
