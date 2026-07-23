# Scaling tests for the pure ce-topology module: the per-CE node map must expand
# correctly at N=1 and N=3. No providers, no data sources -> fully hermetic.

run "n_equals_1" {
  command = plan

  module {
    source = "./modules/ce-topology"
  }

  variables {
    ce_count           = 1
    region_short       = "eastus"
    mgmt_subnet_prefix = "10.0.1.0/26"
  }

  assert {
    condition     = output.ce_count == 1
    error_message = "N=1 should expand to exactly 1 CE node."
  }

  assert {
    condition     = length(keys(output.ce_nodes)) == 1
    error_message = "N=1 should produce a single-entry map."
  }

  assert {
    condition     = output.ce_nodes["eastus01"].hostname == "f5-xc-ce-vm-01"
    error_message = "CE-01 hostname must be f5-xc-ce-vm-01."
  }

  assert {
    condition     = output.ce_nodes["eastus01"].site_name == "ar-bgp-eastus01"
    error_message = "CE-01 site name must be ar-bgp-eastus01."
  }

  assert {
    condition     = output.ce_nodes["eastus01"].slo_ip == "10.0.1.4"
    error_message = "CE-01 SLO IP must be 10.0.1.4."
  }

  assert {
    condition     = output.ce_nodes["eastus01"].az == "1"
    error_message = "CE-01 availability zone must be 1."
  }

  assert {
    condition     = output.ce_nodes["eastus01"].interface_name == "ves-io-securemesh-site-v2-ar-bgp-eastus01-network-f5-xc-ce-vm-01-eth0-0"
    error_message = "CE-01 interface name must match the XC auto-derived object name."
  }
}

run "n_equals_3" {
  command = plan

  module {
    source = "./modules/ce-topology"
  }

  variables {
    ce_count           = 3
    region_short       = "eastus"
    mgmt_subnet_prefix = "10.0.1.0/26"
  }

  assert {
    condition     = output.ce_count == 3
    error_message = "N=3 should expand to exactly 3 CE nodes."
  }

  assert {
    condition     = length(keys(output.ce_nodes)) == 3
    error_message = "N=3 should produce a three-entry map."
  }

  # Distinct SLO IPs .4/.5/.6
  assert {
    condition     = output.ce_nodes["eastus02"].slo_ip == "10.0.1.5" && output.ce_nodes["eastus03"].slo_ip == "10.0.1.6"
    error_message = "CE-02/03 SLO IPs must be 10.0.1.5 and 10.0.1.6."
  }

  # Zones spread across 1/2/3
  assert {
    condition     = output.ce_nodes["eastus02"].az == "2" && output.ce_nodes["eastus03"].az == "3"
    error_message = "CE-02/03 must land in AZ 2 and 3."
  }

  assert {
    condition     = output.ce_nodes["eastus03"].interface_name == "ves-io-securemesh-site-v2-ar-bgp-eastus03-network-f5-xc-ce-vm-03-eth0-0"
    error_message = "CE-03 interface name must match the XC auto-derived object name."
  }
}
