# KVM / libvirt Network for On-Prem Customer Edge nodes.
#
# The CE addresses are routing identities: FRR peers with them and SMSv2 renders
# one peer configuration across the site.  Do not derive them from DHCP lease
# ordering; a restart must not silently leave FRR peering with former tenants.
locals {
  kvm_ce_nodes = {
    "01" = { address = "10.100.0.11", mac = "52:54:00:10:00:11" }
    "02" = { address = "10.100.0.12", mac = "52:54:00:10:00:12" }
    "03" = { address = "10.100.0.13", mac = "52:54:00:10:00:13" }
  }

  kvm_network_generation = substr(sha256(jsonencode(local.kvm_ce_nodes)), 0, 8)
  kvm_network_name       = "ce-bgp-net-${local.kvm_network_generation}"
  # Linux bridge device names are limited to 15 bytes.
  kvm_network_bridge       = "vbgp-${local.kvm_network_generation}"
  kvm_bootstrap_generation = nonsensitive(substr(sha256(local.ce_registration_token), 0, 8))
  kvm_enabled_nodes        = var.enable_kvm ? local.kvm_ce_nodes : {}
}

# Provider refresh cannot reconcile dnsmasq host entries after a libvirt-side
# reservation drift.  A changed declarative identity generation must therefore
# replace the network, which transitively tears down and recreates dependent CE
# domains and the FRR fabric in Terraform order.
resource "terraform_data" "kvm_network_identity" {
  count = var.enable_kvm ? 1 : 0

  input = sha256(jsonencode(local.kvm_ce_nodes))
}

# The Sales Demo tenant issues the currently supported KVM CE appliance as a
# signed image URL. Never substitute a generic cloud OS: it has no VPM runtime.
data "xcsh_site_image" "kvm" {
  count = var.enable_kvm ? 1 : 0

  provider_ref = "KVM"
}

resource "libvirt_network" "ce_bgp_net" {
  count = var.enable_kvm ? 1 : 0

  name      = local.kvm_network_name
  mode      = "nat"
  domain    = "ce.local"
  addresses = ["10.100.0.0/24"]

  bridge = local.kvm_network_bridge

  autostart = true

  dhcp {
    enabled = true
  }

  dnsmasq_options {
    dynamic "options" {
      for_each = local.kvm_ce_nodes
      content {
        option_name  = "dhcp-host"
        option_value = "${options.value.mac},${options.value.address}"
      }
    }
  }

  dns {
    enabled = true
  }

  lifecycle {
    replace_triggered_by = [terraform_data.kvm_network_identity[0]]
  }
}

# Base cloud OS image volume in libvirt
resource "libvirt_volume" "base_cloud" {
  count = var.enable_kvm ? 1 : 0

  name   = "f5xc-kvm-ce.qcow2"
  pool   = "default"
  source = data.xcsh_site_image.kvm[0].image_download_url
  format = "qcow2"
}

# Per-CE root overlay disks
resource "libvirt_volume" "ce_disk" {
  for_each       = local.kvm_enabled_nodes
  name           = "onprem-ce-${each.key}-${local.kvm_network_generation}-${local.kvm_bootstrap_generation}-disk.qcow2"
  pool           = "default"
  base_volume_id = libvirt_volume.base_cloud[0].id
  size           = 21474836480
  format         = "qcow2"
}

# Cloud-Init ISO seed disks per CE node
resource "libvirt_cloudinit_disk" "ce_cloudinit" {
  for_each  = local.kvm_enabled_nodes
  name      = "onprem-ce-${each.key}-${local.kvm_network_generation}-${local.kvm_bootstrap_generation}-cloudinit.iso"
  pool      = "default"
  user_data = <<-EOF
    #cloud-config
    hostname: onprem-ce-${each.key}
    write_files:
      - path: /etc/vpm/config.yaml
        permissions: '0600'
        owner: root:root
        content: |
          Vpm:
            ClusterType: ce
            ClusterName: ${local.kvm_site_name}
            Token: ${local.ce_registration_token}
            MauriceEndpoint: https://register.ves.volterra.io
            MauricePrivateEndpoint: https://register-tls.ves.volterra.io
            CertifiedHardwareEndpoint: https://vesio.blob.core.windows.net/releases/certified-hardware/azure.yml
          Kubernetes:
            EtcdUseTLS: true
            Server: vip
            CloudProvider: disabled
  EOF

  meta_data = <<-EOF
    instance-id: onprem-ce-${each.key}-${local.kvm_bootstrap_generation}
    local-hostname: onprem-ce-${each.key}
  EOF

}

# Declarative KVM Virtual Machines managed by Terraform
resource "libvirt_domain" "ce_node" {
  for_each  = local.kvm_enabled_nodes
  name      = "onprem-ce-${each.key}"
  memory    = 2048
  vcpu      = 2
  autostart = true

  cloudinit = libvirt_cloudinit_disk.ce_cloudinit[each.key].id

  network_interface {
    network_id     = libvirt_network.ce_bgp_net[0].id
    mac            = each.value.mac
    wait_for_lease = false
  }

  disk {
    volume_id = libvirt_volume.ce_disk[each.key].id
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  graphics {
    type        = "vnc"
    listen_type = "address"
    autoport    = true
  }

  # A changed seed ISO is not consumed by an already-running CE.  Replace the
  # domain so cloud-init applies the declared MAC and static routing identity
  # on first boot rather than leaving an old DHCP lease in the BGP fabric.
  lifecycle {
    replace_triggered_by = [
      libvirt_cloudinit_disk.ce_cloudinit[each.key],
      libvirt_network.ce_bgp_net[0],
    ]
  }
}
