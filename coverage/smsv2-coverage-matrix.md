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
| interface_list.dhcp_client{} | ✅ | ➖ | ✅ | ✅ | ✅ | iter-1; block arm; the `static_ip` address-oneof sibling (ip_address/default_gw leaves) → Validated ✅ + Applied ✅ (rows above); dhcp_server S3 |
| labels | ✅ | ➖ | ✅ | ➖ | ➖ | iter-1; ignore_changes (empty-map drift, xcsh #1103 class) |

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

<!--
Slice roadmap:
- S0: probe workspace + this matrix (done).
- S1: numeric-leaf input validation (.tftest.hcl out-of-range rejection) — DONE (verify.sh; provider v3.75.0).
- S2: string-leaf input validation (mac/CIDR/IP/IPv4/node-type) — DONE (verify.sh; provider v3.75.1).
- S3: interface oneof arms (ethernet vs vlan_interface vs dedicated; network_option SLI/inside; dhcp_client vs static_ip vs dhcp_server; custom_proxy).
- S4: services oneof arms (forward proxy, network policy, log streaming/receiver).
- S5: site-mode oneof arms (offline survivability, performance mode, re_select, software_settings explicit versions).
-->
