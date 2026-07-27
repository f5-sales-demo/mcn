# Single-node Secure Mesh v2 CE site with an EXPLICIT eth0/SLO interface. The
# explicit interface is what makes XC auto-create the network_interface object
# (var.interface_name) that the BGP peer binds to — without it a standalone bgp
# object is accepted but never renders to FRR (see xcsh #1207).
resource "xcsh_securemesh_site_v2" "this" {
  name        = var.site_name
  namespace   = "system"
  description = "MCN CE-HA (BGP/ECMP) single-node SMSv2 site ${var.site_name} — explicit eth0 SLO interface for BGP peer binding."
  # `null`, not `{}`, when no labels are set. xcsh #1286 makes the provider preserve a
  # config-declared empty map on the POST-APPLY read-back, but import has no config to
  # read: the state carries only id/name/namespace and `ReadRequest` exposes nothing
  # else, so a literal `{}` would still re-plan as `+ labels = {}` on the first
  # post-import plan. Sending `null` when the map is empty stops asking the provider to
  # distinguish "declared empty" from "absent" — something it cannot observe on import.
  # (The nested `interface_list.labels {}` marker is a separate class, fixed by xcsh #1244.)
  labels = length(var.labels) > 0 ? var.labels : null

  azure {
    not_managed {
      node_list {
        hostname  = var.hostname
        type      = "Control"
        public_ip = ""

        interface_list {
          name = "eth0"

          ethernet_interface {
            device = "eth0"
            mac    = var.mgmt_nic_mac
          }

          # Site Local Outside (SLO) — required on every site; BGP peers from here.
          network_option {
            site_local_network {}
          }

          dhcp_client {}
        }
      }
    }
  }

  block_all_services {}
  disable_ha {}

  dns_ntp_config {
    f5_dns_default {}
    f5_ntp_default {}
  }

  local_vrf {
    default_config {}
    default_sli_config {}
  }

  logs_streaming_disabled {}
  no_forward_proxy {}
  no_network_policy {}
  no_s2s_connectivity_sli {}
  no_s2s_connectivity_slo {}

  offline_survivability_mode {
    no_offline_survivability_mode {}
  }

  performance_enhancement_mode {
    perf_mode_l7_enhanced {
      # Provider v3.80.0 gave perf_mode_l7_enhanced a {jumbo_disabled | jumbo_enabled}
      # sub-oneof. F5 materialises jumbo_disabled server-side, so leaving both members
      # undeclared makes the site land and then re-plan the marker as a removal on
      # every subsequent plan — it never reaches 0 changes. Declaring the server
      # default explicitly is what settles it (same fix coverage/smsv2 took in #625).
      jumbo_disabled {}
    }
  }

  re_select {
    geo_proximity {}
  }

  # Pin OS/SW versions to avoid the fresh-image force-upgrade (9.2024.6 -> latest)
  # whose churn stalls CE provisioning. Empty vars = use the server default (latest).
  software_settings {
    os {
      dynamic "default_os_version" {
        for_each = var.os_version == "" ? [1] : []
        content {}
      }
      operating_system_version = var.os_version == "" ? null : var.os_version
    }
    sw {
      dynamic "default_sw_version" {
        for_each = var.sw_version == "" ? [1] : []
        content {}
      }
      volterra_software_version = var.sw_version == "" ? null : var.sw_version
    }
  }

  # SSH access to the CE appliance, for `execcli` and on-box diagnostics.
  # The CE image manages its own OS authentication, so the Azure VM's
  # admin_ssh_key (modules/ce-node) does NOT grant CE login — this block is what
  # authorizes a key on the appliance itself. An empty var renders no block,
  # leaving the appliance default (no SSH listener), so this is opt-in.
  dynamic "admin_user_credentials" {
    for_each = var.ssh_public_key == "" ? [] : [1]
    content {
      ssh_key = var.ssh_public_key
    }
  }
}

# The approve API takes the runtime registration name ("r-<uuid>"), NOT the site
# name (GET .../registrations/<site> -> 404). registrations_by_site returns
# HTTP 200 with items:[] for a site whose CE has not registered yet, so this read
# never fails an early apply — it just reports found = false.
#
# NOTE: this data source must never carry depends_on. Its inputs are statically
# derived from ce_topology, so it resolves at plan time; a resource dependency
# would make the count below unknown at plan time ("The count value depends on
# resource attributes that cannot be determined until apply").
data "xcsh_site_registration" "this" {
  site_name = var.site_name # == passport.cluster_name (cloud-init ClusterName)
  hostname  = var.hostname  # discriminator for multi-node sites
  namespace = "system"
}

# Approve the CE registration so the node reaches ONLINE without the manual
# console step (#1206 / #1210). The registration exists only after the CE boots
# and registers via the token, so the first apply plans no approval; re-apply
# once the CE has registered (see the deploy ordering in main.tf).
#
# ADOPTING AN ALREADY-APPROVED CE: the approve action only legitimately moves a
# registration out of NEW, so applying this against a CE that is already
# APPROVED/ONLINE would POST a redundant approve (which the API may reject —
# xcsh #1278). Import the existing approval instead of letting Terraform create
# it, using namespace/name with the RUNTIME registration name (the site name
# 404s — read it from the data source's `registration_name` output):
#
#   terraform import 'module.xc_site["eastus01"].xcsh_registration_approval.this[0]' \
#     system/r-dcec2400-52d5-4154-9fd0-4b042d3fe18d
#
# Or set approve_registration = false to keep approval out of the graph entirely.
resource "xcsh_registration_approval" "this" {
  count = var.approve_registration && data.xcsh_site_registration.this.found ? 1 : 0

  namespace = "system"
  name      = data.xcsh_site_registration.this.name
  state     = "APPROVED"
}

# One bgp object per CE site: eBGP from the CE (ASN var.ce_asn) to the Azure
# Route Server (ASN var.rs_asn), one external peer per Route Server virtual
# router IP, each bound to the explicit SLO interface.
#
# NOT BLOCKED — and nothing about this arm is gated any more. The object-ref name
# length limit that used to block it is gone: the provider relaxed it to
# stringvalidator.LengthBetween(1, 128) in v3.74.0, so the 71-char interface object
# XC auto-generates for the explicit SLO interface
# (ves-io-securemesh-site-v2-<site>-network-<hostname>-eth0-0) validates. The floor
# that guarantees it is declared once, in versions.tf — do not restate the number.
#
# var.enable_bgp therefore defaults true and every test now runs with that default;
# it survives only as an escape hatch for deploying the topology without BGP. It is
# NOT an ordering gate: var.interface_name is derived statically from ce_topology, and
# XC accepts a bgp object naming an interface that does not exist yet (it converges
# once the CE is up — see the deploy ordering in the root main.tf).
resource "xcsh_bgp" "this" {
  count = var.enable_bgp ? 1 : 0

  name        = "${var.site_name}-bgp"
  namespace   = "system"
  description = "CE ${var.site_name} BGP to Azure Route Server via explicit SLO interface."

  where {
    site {
      ref {
        namespace = "system"
        name      = xcsh_securemesh_site_v2.this.name
      }
      network_type = "VIRTUAL_NETWORK_SITE_LOCAL"
      disable_internet_vip {}
    }
  }

  bgp_parameters {
    asn = var.ce_asn
    # local_address {} = derive the BGP router ID from the interface's local
    # address (the JSON's BGP_ROUTER_ID_FROM_INTERFACE; there is no separate
    # bgp_router_id_type attribute in the provider schema).
    local_address {}
  }

  # Iterate over a plan-KNOWN peer count (rs_peer_count) and index into
  # rs_peer_ips. The IP values may be unknown until the Route Server is applied,
  # but the number of peers is fixed, so the block expands cleanly at plan time.
  dynamic "peers" {
    for_each = { for i in range(var.rs_peer_count) : "azure-rrs-${i + 1}" => i }
    content {
      metadata {
        name = peers.key
      }

      external {
        asn     = var.rs_asn
        address = var.rs_peer_ips[peers.value]
        port    = var.peer_port

        interface {
          namespace = "system"
          name      = var.interface_name
        }

        disable_v6 {}
      }

      passive_mode_disabled {}
      bfd_disabled {}
    }
  }
}
