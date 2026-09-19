# Direct unit fixtures for the pure observed-registration to Terraform-owned
# KVM MAC join. Production callers cannot supply these records: the root module
# passes only the XC inventory data-source projection.

run "configured_kvm_mapping_is_exact" {
  command = plan

  module {
    source = "./modules/kvm-registration-mapping"
  }

  variables {
    enforce = true
    ce_nodes = {
      "01" = { address = "10.100.0.11", mac = "52:54:00:10:00:11" }
      "02" = { address = "10.100.0.12", mac = "52:54:00:10:00:12" }
      "03" = { address = "10.100.0.13", mac = "52:54:00:10:00:13" }
    }
    registration_records = [
      { hostname = "onprem-ce-01", provider = "KVM", mac = "52:54:00:10:00:11" },
      { hostname = "onprem-ce-02", provider = "KVM", mac = "52:54:00:10:00:12" },
      { hostname = "onprem-ce-03", provider = "KVM", mac = "52:54:00:10:00:13" },
    ]
  }

  assert {
    condition     = output.mapping_valid
    error_message = "The exact three observed KVM registration MACs must produce a valid mapping."
  }

  assert {
    condition = {
      for key, peer in output.expected_bgp_peers : key => peer.node
      } == {
      node_01_slo = "onprem-ce-01"
      node_02_slo = "onprem-ce-02"
      node_03_slo = "onprem-ce-03"
    }
    error_message = "The KVM BGP mapping must preserve the exact observed hostnames for each owned MAC."
  }
}

run "configured_kvm_mapping_rejects_missing_owned_mac" {
  command = plan

  module {
    source = "./modules/kvm-registration-mapping"
  }

  variables {
    enforce = true
    ce_nodes = {
      "01" = { address = "10.100.0.11", mac = "52:54:00:10:00:11" }
      "02" = { address = "10.100.0.12", mac = "52:54:00:10:00:12" }
      "03" = { address = "10.100.0.13", mac = "52:54:00:10:00:13" }
    }
    registration_records = [
      { hostname = "onprem-ce-01", provider = "KVM", mac = "52:54:00:10:00:11" },
      { hostname = "onprem-ce-02", provider = "KVM", mac = "52:54:00:10:00:12" },
    ]
  }

  expect_failures = [terraform_data.gate[0]]
}

run "configured_kvm_mapping_rejects_duplicate_owned_mac" {
  command = plan

  module {
    source = "./modules/kvm-registration-mapping"
  }

  variables {
    enforce = true
    ce_nodes = {
      "01" = { address = "10.100.0.11", mac = "52:54:00:10:00:11" }
      "02" = { address = "10.100.0.12", mac = "52:54:00:10:00:12" }
      "03" = { address = "10.100.0.13", mac = "52:54:00:10:00:13" }
    }
    registration_records = [
      { hostname = "onprem-ce-01", provider = "KVM", mac = "52:54:00:10:00:11" },
      { hostname = "duplicate-ce-01", provider = "KVM", mac = "52:54:00:10:00:11" },
      { hostname = "onprem-ce-02", provider = "KVM", mac = "52:54:00:10:00:12" },
      { hostname = "onprem-ce-03", provider = "KVM", mac = "52:54:00:10:00:13" },
    ]
  }

  expect_failures = [terraform_data.gate[0]]
}

run "configured_kvm_mapping_rejects_foreign_provider" {
  command = plan

  module {
    source = "./modules/kvm-registration-mapping"
  }

  variables {
    enforce = true
    ce_nodes = {
      "01" = { address = "10.100.0.11", mac = "52:54:00:10:00:11" }
      "02" = { address = "10.100.0.12", mac = "52:54:00:10:00:12" }
      "03" = { address = "10.100.0.13", mac = "52:54:00:10:00:13" }
    }
    registration_records = [
      { hostname = "onprem-ce-01", provider = "AWS", mac = "52:54:00:10:00:11" },
      { hostname = "onprem-ce-02", provider = "AWS", mac = "52:54:00:10:00:12" },
      { hostname = "onprem-ce-03", provider = "AWS", mac = "52:54:00:10:00:13" },
    ]
  }

  expect_failures = [terraform_data.gate[0]]
}
