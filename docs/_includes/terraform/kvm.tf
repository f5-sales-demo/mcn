# One supported KVM CE site. F5's KVM contract requires the F5-supplied QCOW2
# image and at least 8 vCPUs, 32 GB RAM, and 80 GB disk; a generic cloud image
# is deliberately not an option in this topology.
resource "libvirt_network" "kvm" {
  count     = var.enable_kvm ? 1 : 0
  name      = var.kvm_network_name
  mode      = "nat"
  domain    = "kvm.mcn.local"
  addresses = [var.kvm_network_cidr]
  bridge    = "virbr-mcn-kvm"
  autostart = true
  dhcp { enabled = false }
  dns { enabled = true }
}

resource "libvirt_volume" "kvm_ce" {
  count  = var.enable_kvm ? 1 : 0
  name   = "${var.kvm_domain_name}.qcow2"
  pool   = "default"
  source = var.kvm_ce_image_path
  format = "qcow2"
  size   = 85899345920
}

resource "libvirt_cloudinit_disk" "kvm_ce" {
  count     = var.enable_kvm ? 1 : 0
  name      = "${var.kvm_domain_name}-cloudinit.iso"
  pool      = "default"
  user_data = <<-CLOUD_INIT
    #cloud-config
    write_files:
      - path: /etc/vpm/user_data
        owner: root:root
        permissions: '0644'
        content: |
          token: ${local.ce_registration_token}
          slo_ip: ${var.kvm_ce_address}/${split("/", var.kvm_network_cidr)[1]}
          slo_gateway: ${var.kvm_frr_address}
          slo_dns: ${var.kvm_frr_address}
  CLOUD_INIT
  meta_data = "instance-id: ${var.kvm_domain_name}\nlocal-hostname: ${var.kvm_domain_name}\n"
}

resource "libvirt_domain" "kvm_ce" {
  count     = var.enable_kvm ? 1 : 0
  name      = var.kvm_domain_name
  memory    = 32768
  vcpu      = 8
  autostart = true
  cloudinit = libvirt_cloudinit_disk.kvm_ce[0].id

  network_interface {
    network_id     = libvirt_network.kvm[0].id
    addresses      = [var.kvm_ce_address]
    wait_for_lease = false
  }
  disk { volume_id = libvirt_volume.kvm_ce[0].id }
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

  lifecycle {
    precondition {
      condition     = var.kvm_ce_image_path != ""
      error_message = "The KVM CE VM needs the F5-provided QCOW2 image path."
    }
  }
}

# Docker uses macvlan on libvirt's bridge so FRR and the client are ordinary
# peers on the CE LAN, instead of reaching the CE through Docker's isolated NAT.
resource "docker_network" "kvm" {
  count   = var.enable_kvm ? 1 : 0
  name    = "${var.kvm_network_name}-macvlan"
  driver  = "macvlan"
  options = { parent = libvirt_network.kvm[0].bridge }
  ipam_config {
    subnet  = var.kvm_network_cidr
    gateway = var.kvm_frr_address
  }
}

resource "docker_container" "kvm_frr" {
  count = var.enable_kvm ? 1 : 0
  name  = "${var.component}-kvm-frr"
  image = "frrouting/frr:10.2.1"
  capabilities { add = ["NET_ADMIN", "NET_RAW"] }
  command = ["sh", "-ec", <<-SCRIPT
    printf '%s\\n' 'frr defaults traditional' 'hostname kvm-frr' 'service integrated-vtysh-config' 'router bgp ${var.kvm_frr_asn}' ' bgp router-id ${var.kvm_frr_address}' ' neighbor ${var.kvm_ce_address} remote-as ${var.kvm_ce_asn}' ' !' ' address-family ipv4 unicast' '  neighbor ${var.kvm_ce_address} activate' ' exit-address-family' > /etc/frr/frr.conf
    chown frr:frr /etc/frr/frr.conf
    /usr/lib/frr/frrinit.sh start
    tail -f /dev/null
  SCRIPT
  ]
  networks_advanced {
    name         = docker_network.kvm[0].name
    ipv4_address = var.kvm_frr_address
  }
  restart = "unless-stopped"
}

resource "docker_container" "kvm_client" {
  count   = var.enable_kvm ? 1 : 0
  name    = "${var.component}-kvm-client"
  image   = "curlimages/curl:8.12.1"
  command = ["sh", "-c", "trap : TERM INT; sleep infinity & wait"]
  networks_advanced {
    name         = docker_network.kvm[0].name
    ipv4_address = var.kvm_client_address
  }
  restart = "unless-stopped"
}
