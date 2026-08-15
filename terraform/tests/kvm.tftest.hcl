# KVM is part of the default showcase, but every local-only resource remains
# independently disableable for focused cloud runs and CI plans.
mock_provider "azurerm" {}
mock_provider "azuread" {}
mock_provider "xcsh" {}
mock_provider "aws" {}
mock_provider "libvirt" {}
mock_provider "docker" {}

variables {
  deployer          = "tester"
  origin_ip         = "203.0.113.10"
  lb_domain         = "mcn-ce-ha.example.com"
  ssh_public_key    = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKzwDqvgRGHaZqbo57o/AxuuqRNPT9MqeYNYsK1Owh8l plan-test-only"
  kvm_ce_image_path = "/tmp/f5xc-ce.qcow2"
}

run "default_kvm_contract" {
  command = plan

  assert {
    condition     = length(libvirt_domain.kvm_ce) == 1 && libvirt_domain.kvm_ce[0].vcpu >= 8 && libvirt_domain.kvm_ce[0].memory >= 32768
    error_message = "The KVM CE must use the F5 image with at least 8 vCPUs and 32 GB RAM."
  }

  assert {
    condition     = libvirt_volume.kvm_ce[0].source == "/tmp/f5xc-ce.qcow2" && libvirt_volume.kvm_ce[0].size >= 85899345920
    error_message = "The KVM CE must consume the supplied F5 QCOW2 image with at least 80 GB disk."
  }

  assert {
    condition     = length(docker_container.kvm_frr) == 1 && length(docker_container.kvm_client) == 1 && length(docker_network.kvm) == 1
    error_message = "KVM must provision the macvlan-attached FRR peer and local test client."
  }

  assert {
    condition     = output.kvm_site_name == "mcn-ce-ha-kvm-site" && output.kvm_vip == "198.51.100.20"
    error_message = "KVM must create its virtual site path and expose an external advertised VIP."
  }
}

run "kvm_disabled_has_no_local_resources" {
  command = plan

  variables {
    enable_kvm        = false
    kvm_ce_image_path = ""
  }

  assert {
    condition     = length(libvirt_domain.kvm_ce) == 0 && length(docker_container.kvm_frr) == 0 && output.kvm_site_name == null
    error_message = "enable_kvm = false must cleanly gate the VM, FRR, client, and F5 site."
  }
}

run "kvm_vip_inside_local_network_is_rejected" {
  command = plan

  variables {
    kvm_vip = "172.30.10.100"
  }

  expect_failures = [check.kvm_vip_outside_local_network]
}
