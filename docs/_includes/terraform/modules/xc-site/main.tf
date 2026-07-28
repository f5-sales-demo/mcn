# Parks the identity of the CE VM instance the site's node runs on, so the site
# object has something to be coupled to. Nothing else reads it — its only job is
# to be named in the site's replace_triggered_by below.
#
# WHY A SEPARATE RESOURCE. replace_triggered_by may only name managed resources
# declared in the SAME module as the resource carrying the lifecycle block, and
# the CE VM lives in modules/ce-node. Parking the id here is the standard way to
# carry an external value across that boundary.
#
# WHY input AND NOT triggers_replace. This resource must never itself be
# replaced — only observed. A changed `input` is an in-place UPDATE, which is
# what replace_triggered_by reacts to; that keeps the resource cheap and its
# behaviour on ADOPTION correct (see below).
#
# ADOPTION IS INERT. Adding this resource to a deployment that already exists
# plans it as a CREATE, and a create of the referenced resource does NOT fire
# replace_triggered_by — only a subsequent change to its value does. Verified on
# Terraform v1.10.5 (the version .terraform-version pins) and again on v1.15.0:
# adding the pair to a populated state plans "1 to add, 0 to change,
# 0 to destroy". So this fix does not itself trigger the fleet-wide rebuild it
# exists to prevent — no import, no targeted apply, no seeding.
resource "terraform_data" "ce_vm" {
  input = var.ce_vm_instance_id
}

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
  #
  # EXPECTED ONE-TIME DRIFT AFTER A NODE (RE)REGISTERS. F5 XC stamps the node's
  # hardware facts onto the site as labels (host-os-version, hw-model,
  # hw-serial-number, hw-vendor, hw-version) once the CE registers. The next plan
  # therefore shows `- labels = {...} -> null` for that site, and applying it
  # settles — XC does not re-stamp them. It is one more convergence pass in the
  # already two-phase deploy, not drift to chase; observed on the site rebuilt by
  # the #674 CE replacement.
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

  # Rebuild the site object whenever the CE VM instance it describes is rebuilt
  # (issue #674).
  #
  # THE FAILURE THIS PREVENTS. A CE's runtime registration is bound to one node
  # instance and holds the control plane's unique
  # (tenant, cluster_name, hostname) index. Destroying the VM does NOT retire
  # that registration, so the replacement node — same site, same hostname —
  # cannot create its own: the create fails with UniqueSecondaryIndexViolation
  # and retries on a ~65 s loop forever. Nothing recovers on its own, and worse,
  # nothing in the graph noticed: with no reference to the node's identity
  # anywhere, `terraform plan` reported "No changes" for the whole time the
  # fleet was down.
  #
  # WHY REPLACING THE SITE IS THE FIX. Deleting the site object takes its
  # registrations with it — observed live while replacing one CE: the site
  # 404ed and the registration bound to the outgoing instance disappeared in the
  # same poll — so the replacement node registers into a site whose index key is
  # free. Deleting only the registration is not enough: the site keeps a status
  # object that then rejects the node's workload request.
  #
  # THE ORDER IS THE POINT. Terraform runs this as: destroy site -> destroy VM
  # -> create VM -> create site. The stale registration is therefore gone before
  # the replacement node ever boots, and the site is back before the node
  # finishes booting and registers. The outgoing node cannot slip a fresh
  # registration into the gap: once its own registration is deleted it 404-loops
  # against the name it persisted in registration-obj.yml instead of creating a
  # new one.
  #
  # SAFE WHILE OTHER OBJECTS REFERENCE THE SITE. xcsh_bgp and the root HTTP load
  # balancer's advertise_where both name this site, and F5 XC resolves those
  # references lazily: deleting a site that both of them reference returns HTTP
  # 200 and leaves them intact, and re-creating it under the same name re-binds
  # them (verified against the live tenant with a throwaway site).
  lifecycle {
    replace_triggered_by = [terraform_data.ce_vm]
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
