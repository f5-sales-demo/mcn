# KVM / libvirt Network for On-Prem Customer Edge nodes
resource "libvirt_network" "ce_bgp_net" {
  name      = "ce-bgp-net"
  mode      = "nat"
  domain    = "ce.local"
  addresses = ["10.100.0.0/24"]

  bridge = "virbr-ce-bgp"

  autostart = true

  dhcp {
    enabled = true
  }

  dns {
    enabled = true
  }
}

# Base cloud OS image volume in libvirt
resource "libvirt_volume" "base_cloud" {
  name   = "base-cloud-noble.qcow2"
  pool   = "default"
  source = "${path.module}/../kvm/images/base-cloud.qcow2"
  format = "qcow2"
}

# Per-CE root overlay disks
resource "libvirt_volume" "ce_disk" {
  for_each       = toset(["01", "02", "03"])
  name           = "onprem-ce-${each.key}-disk.qcow2"
  pool           = "default"
  base_volume_id = libvirt_volume.base_cloud.id
  size           = 21474836480
  format         = "qcow2"
}

# Cloud-Init ISO seed disks per CE node
resource "libvirt_cloudinit_disk" "ce_cloudinit" {
  for_each  = toset(["01", "02", "03"])
  name      = "onprem-ce-${each.key}-cloudinit.iso"
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
            ClusterName: onprem-kvm-site
            Token: ${xcsh_token.ce.id}
            MauriceEndpoint: https://register.ves.volterra.io
            MauricePrivateEndpoint: https://register-tls.ves.volterra.io
            CertifiedHardwareEndpoint: https://vesio.blob.core.windows.net/releases/certified-hardware/azure.yml
          Kubernetes:
            EtcdUseTLS: true
            Server: vip
            CloudProvider: disabled
  EOF

  meta_data = <<-EOF
    instance-id: onprem-ce-${each.key}
    local-hostname: onprem-ce-${each.key}
  EOF
}

# Declarative KVM Virtual Machines managed by Terraform
resource "libvirt_domain" "ce_node" {
  for_each  = toset(["01", "02", "03"])
  name      = "onprem-ce-${each.key}"
  memory    = 2048
  vcpu      = 2
  autostart = true

  cloudinit = libvirt_cloudinit_disk.ce_cloudinit[each.key].id

  network_interface {
    network_id     = libvirt_network.ce_bgp_net.id
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
}
