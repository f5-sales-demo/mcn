# Plan-level test focused on the BGP half of the xc-site module: two external
# peers (one per Route Server IP), CE ASN 64512 peering to RS ASN 65515.
#
# NOTE: this run uses a SHORTENED interface_name so the xcsh_bgp resource plans.
# The real XC-derived name is 71 chars and exceeds the provider's 63-char
# object-ref validator (a confirmed provider bug — see modules/xc-site/main.tf).
# This run therefore verifies the bgp HCL/schema wiring (where/bgp_parameters/
# peers/external/interface) is correct; the length cap is an external provider
# constraint that blocks the real binding until the provider is fixed.

mock_provider "xcsh" {}

run "bgp_two_peers" {
  command = plan

  module {
    source = "./modules/xc-site"
  }

  variables {
    site_name      = "ar-bgp-eastus02"
    hostname       = "f5-xc-ce-vm-02"
    interface_name = "ves-io-smsv2-slo-eth0-0" # shortened; see file header
    mgmt_nic_mac   = "60:45:bd:ef:07:9f"
    rs_peer_ips    = ["10.0.4.4", "10.0.4.5"]
    ce_asn         = 64512
    rs_asn         = 65515
    enable_bgp     = true
  }

  assert {
    condition     = output.bgp_name == "ar-bgp-eastus02-bgp"
    error_message = "BGP object name should be <site>-bgp."
  }

  assert {
    condition     = output.peer_count == 2
    error_message = "There must be exactly two external BGP peers (one per Route Server IP)."
  }

  assert {
    condition     = xcsh_bgp.this[0].namespace == "system"
    error_message = "The bgp object must be created in the system namespace."
  }
}
