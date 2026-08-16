# KVM is part of the default showcase, but every local-only resource remains
# independently disableable for focused cloud runs and CI plans.
mock_provider "azurerm" {}
mock_provider "azuread" {}
mock_provider "xcsh" {
  mock_data "xcsh_site_image" {
    defaults = {
      image_download_url     = "https://downloads.example.com/f5xc-ce.qcow2"
      image_md5_download_url = "https://downloads.example.com/f5xc-ce.qcow2.md5"
    }
  }
  mock_resource "xcsh_site_cloud_init" {
    defaults = {
      cloud_init_config = "#cloud-config\nwrite_files: []\n"
    }
  }
}
mock_provider "aws" {}
mock_provider "libvirt" {}
mock_provider "docker" {}
mock_provider "random" {
  mock_resource "random_password" {
    defaults = { result = "MockSitePassword-42!" }
  }
}

variables {
  subscription_id = uuidv5("dns", "example.com")
  component       = "mcn-ce-ha"
  deployer        = "tester"
  origin_ip       = "203.0.113.10"
  lb_domain       = "mcn-ce-ha.example.com"
  ssh_public_key  = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKzwDqvgRGHaZqbo57o/AxuuqRNPT9MqeYNYsK1Owh8l plan-test-only"
}

run "default_kvm_contract" {
  command = plan

  override_resource {
    target          = docker_image.kvm_frr[0]
    override_during = plan
    values = {
      image_id = "sha256:mock-frr-image"
    }
  }

  override_resource {
    target          = docker_image.kvm_client[0]
    override_during = plan
    values = {
      image_id = "sha256:mock-client-image"
    }
  }

  override_resource {
    target          = xcsh_site_cloud_init.kvm[0]
    override_during = plan
    values = {
      cloud_init_config = "#cloud-config\nwrite_files: []\n"
    }
  }

  assert {
    condition     = length(libvirt_domain.kvm_ce) == 1 && libvirt_domain.kvm_ce[0].vcpu >= 8 && libvirt_domain.kvm_ce[0].memory >= 32768 && libvirt_domain.kvm_ce[0].memory_unit == "MiB"
    error_message = "The KVM CE must use the current libvirt contract with at least 8 vCPUs and 32 GiB RAM."
  }

  assert {
    condition     = data.xcsh_site_image.kvm[0].provider_ref == "KVM" && libvirt_volume.kvm_ce_base[0].create.content.url == "https://downloads.example.com/f5xc-ce.qcow2" && libvirt_volume.kvm_ce[0].capacity >= 85899345920
    error_message = "The KVM CE must consume the generated F5 QCOW2 lookup and boot an 80 GiB overlay."
  }

  assert {
    condition = (
      length(xcsh_site_cloud_init.kvm) == 1 &&
      xcsh_site_cloud_init.kvm[0].provider_ref == "kvm" &&
      xcsh_site_cloud_init.kvm[0].site_name == "mcn-ce-ha-kvm-site" &&
      libvirt_cloudinit_disk.kvm_ce[0].user_data == "#cloud-config\nwrite_files: []\n"
    )
    error_message = "The KVM CE must boot with the site-scoped cloud-init response."
  }

  assert {
    condition = (
      xcsh_securemesh_site_v2.kvm[0].kvm.not_managed.node_list[0].hostname == "mcn-kvm-ce" &&
      xcsh_securemesh_site_v2.kvm[0].kvm.not_managed.node_list[0].interface_list[0].name == "eth0" &&
      xcsh_securemesh_site_v2.kvm[0].kvm.not_managed.node_list[0].interface_list[0].ethernet_interface.mac == libvirt_domain.kvm_ce[0].devices.interfaces[0].mac.address &&
      libvirt_network.kvm[0].ips[0].dhcp.hosts[0].ip == "172.30.10.10"
    )
    error_message = "The KVM site, VM, and DHCP reservation must describe the same eth0 interface."
  }

  assert {
    condition = (
      length(random_password.site_console_admin_kvm) == 1 &&
      xcsh_securemesh_site_v2.kvm[0].admin_user_credentials.ssh_key == var.ssh_public_key &&
      startswith(xcsh_securemesh_site_v2.kvm[0].admin_user_credentials.admin_password.clear_secret_info.url, "string:///")
    )
    error_message = "The KVM site must configure its node-local admin credential through the supported F5XC site contract."
  }

  assert {
    condition = (
      length(docker_image.kvm_frr) == 1 &&
      docker_image.kvm_frr[0].name == "quay.io/frrouting/frr:10.7.0@sha256:65e5967b922572c0565d968388fb06af69d7e9b3b3eea40ad7e3810687667f68" &&
      docker_image.kvm_frr[0].keep_locally == false &&
      length(docker_container.kvm_frr) == 1 &&
      docker_container.kvm_frr[0].image == docker_image.kvm_frr[0].image_id &&
      docker_container.kvm_frr[0].sysctls["net.ipv4.ip_forward"] == "1" &&
      strcontains(join(" ", docker_container.kvm_frr[0].command), "bgpd=yes") &&
      length(docker_image.kvm_client) == 1 &&
      docker_image.kvm_client[0].name == "alpine:3.22.1@sha256:4bcff63911fcb4448bd4fdacec207030997caf25e9bea4045fa6c8c44de311d1" &&
      docker_image.kvm_client[0].keep_locally == false &&
      length(docker_container.kvm_client) == 1 &&
      docker_container.kvm_client[0].image == docker_image.kvm_client[0].image_id &&
      docker_container.kvm_client[0].user == "0" &&
      strcontains(join(" ", docker_container.kvm_client[0].command), "ip route replace 198.51.100.20/32 via 172.30.10.2") &&
      length(docker_network.kvm) == 1
    )
    error_message = "KVM must use immutable FRR and Alpine images, start FRR forwarding, and route the macvlan test client through it to the advertised VIP."
  }

  assert {
    condition     = output.kvm_site_name == "mcn-ce-ha-kvm-site" && output.kvm_vip == "198.51.100.20" && output.kvm_lb_domain == "kvm.mcn-ce-ha.f5-sales-demo.com"
    error_message = "KVM must create its virtual site path and expose its domain and external advertised VIP."
  }

  assert {
    condition = (
      xcsh_http_loadbalancer.kvm[0].domains[0] == "kvm.mcn-ce-ha.f5-sales-demo.com" &&
      xcsh_http_loadbalancer.kvm[0].advertise_custom.advertise_where[0].virtual_site_with_vip.ip == "198.51.100.20" &&
      xcsh_http_loadbalancer.kvm[0].advertise_custom.advertise_where[0].virtual_site_with_vip.network == "SITE_NETWORK_SPECIFIED_VIP_OUTSIDE" &&
      xcsh_http_loadbalancer.kvm[0].advertise_custom.advertise_where[0].virtual_site_with_vip.virtual_site.name == "mcn-ce-ha-kvm-vsite"
    )
    error_message = "The KVM load balancer must advertise kvm_vip through its KVM virtual site."
  }
}

run "kvm_disabled_has_no_local_resources" {
  command = plan

  variables { enable_kvm = false }

  assert {
    condition = (
      length(libvirt_network.kvm) == 0 &&
      length(libvirt_volume.kvm_ce_base) == 0 &&
      length(libvirt_volume.kvm_ce) == 0 &&
      length(libvirt_cloudinit_disk.kvm_ce) == 0 &&
      length(libvirt_volume.kvm_ce_cloudinit) == 0 &&
      length(libvirt_domain.kvm_ce) == 0 &&
      length(random_password.site_console_admin_kvm) == 0 &&
      length(xcsh_site_cloud_init.kvm) == 0 &&
      length(docker_network.kvm) == 0 &&
      length(docker_image.kvm_frr) == 0 &&
      length(docker_image.kvm_client) == 0 &&
      length(docker_container.kvm_frr) == 0 &&
      length(docker_container.kvm_client) == 0 &&
      output.kvm_site_name == null &&
      output.kvm_vip == null &&
      output.kvm_lb_domain == null
    )
    error_message = "enable_kvm = false must cleanly gate every libvirt, Docker, and F5 resource."
  }
}

run "kvm_vip_inside_local_network_is_rejected" {
  command = plan

  variables {
    kvm_vip = "172.30.10.100"
  }

  expect_failures = [check.kvm_vip_outside_local_network]
}

run "kvm_duplicate_peer_address_is_rejected" {
  command = plan

  variables {
    kvm_frr_address = "172.30.10.1"
  }

  expect_failures = [check.kvm_addresses_are_valid]
}
