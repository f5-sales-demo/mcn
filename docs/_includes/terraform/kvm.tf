# One supported KVM CE site. The generated XC data source retrieves F5's signed
# QCOW2 URL; a caller-supplied path or generic cloud image is deliberately not
# part of this clean-break contract.
data "xcsh_site_image" "kvm" {
  count        = var.enable_kvm ? 1 : 0
  provider_ref = "KVM"
}

locals {
  kvm_bridge_name     = "virbr-mcn-kvm"
  kvm_gateway_address = cidrhost(var.kvm_network_cidr, 1)
  kvm_ce_mac_address = join(":", concat(
    ["52", "54"],
    [for offset in [0, 2, 4, 6] : substr(md5(var.component), offset, 2)]
  ))
}

resource "xcsh_site_cloud_init" "kvm" {
  count        = var.enable_kvm ? 1 : 0
  provider_ref = "kvm"
  site_name    = xcsh_securemesh_site_v2.kvm[0].name
}

resource "libvirt_network" "kvm" {
  count = var.enable_kvm ? 1 : 0
  name  = var.kvm_network_name

  autostart = true

  forward = {
    mode = "nat"
  }
  bridge = {
    name = local.kvm_bridge_name
  }
  domain = {
    name = "kvm.mcn.local"
  }
  ips = [
    {
      address = local.kvm_gateway_address
      netmask = cidrnetmask(var.kvm_network_cidr)
      dhcp = {
        hosts = [{
          mac  = local.kvm_ce_mac_address
          name = var.kvm_domain_name
          ip   = var.kvm_ce_address
        }]
      }
    }
  ]
}

resource "libvirt_volume" "kvm_ce_base" {
  count = var.enable_kvm ? 1 : 0
  name  = "${var.kvm_domain_name}-base.qcow2"
  pool  = "default"

  target = {
    format = {
      type = "qcow2"
    }
  }
  create = {
    content = {
      url = data.xcsh_site_image.kvm[0].image_download_url
    }
  }
}

resource "libvirt_volume" "kvm_ce" {
  count    = var.enable_kvm ? 1 : 0
  name     = "${var.kvm_domain_name}.qcow2"
  pool     = "default"
  capacity = 85899345920

  target = {
    format = {
      type = "qcow2"
    }
  }
  backing_store = {
    path = libvirt_volume.kvm_ce_base[0].path
    format = {
      type = "qcow2"
    }
  }
}

resource "libvirt_cloudinit_disk" "kvm_ce" {
  count = var.enable_kvm ? 1 : 0
  name  = "${var.kvm_domain_name}-cloudinit"

  user_data = xcsh_site_cloud_init.kvm[0].cloud_init_config
  meta_data = "instance-id: ${var.kvm_domain_name}\nlocal-hostname: ${var.kvm_domain_name}\n"
}

resource "libvirt_volume" "kvm_ce_cloudinit" {
  count = var.enable_kvm ? 1 : 0
  name  = "${var.kvm_domain_name}-cloudinit.iso"
  pool  = "default"

  create = {
    content = {
      url = libvirt_cloudinit_disk.kvm_ce[0].path
    }
  }
}

resource "libvirt_domain" "kvm_ce" {
  count       = var.enable_kvm ? 1 : 0
  name        = var.kvm_domain_name
  type        = "kvm"
  memory      = 32768
  memory_unit = "MiB"
  vcpu        = 8
  autostart   = true
  running     = true

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
    boot_devices = [{ dev = "hd" }]
  }

  devices = {
    disks = [
      {
        source = {
          volume = {
            pool   = libvirt_volume.kvm_ce[0].pool
            volume = libvirt_volume.kvm_ce[0].name
          }
        }
        target = {
          dev = "vda"
          bus = "virtio"
        }
        driver = {
          type = "qcow2"
        }
      },
      {
        device = "cdrom"
        source = {
          volume = {
            pool   = libvirt_volume.kvm_ce_cloudinit[0].pool
            volume = libvirt_volume.kvm_ce_cloudinit[0].name
          }
        }
        target = {
          dev = "sda"
          bus = "sata"
        }
      }
    ]
    interfaces = [
      {
        type = "network"
        mac = {
          address = local.kvm_ce_mac_address
        }
        model = {
          type = "virtio"
        }
        source = {
          network = {
            network = libvirt_network.kvm[0].name
          }
        }
      }
    ]
  }
}

# Docker uses macvlan on libvirt's bridge so FRR and the client are ordinary
# peers on the CE LAN, instead of reaching the CE through Docker's isolated NAT.
resource "docker_network" "kvm" {
  count   = var.enable_kvm ? 1 : 0
  name    = "${var.kvm_network_name}-macvlan"
  driver  = "macvlan"
  options = { parent = libvirt_network.kvm[0].bridge.name }
  ipam_config {
    subnet  = var.kvm_network_cidr
    gateway = local.kvm_gateway_address
  }
}

resource "docker_image" "kvm_frr" {
  count        = var.enable_kvm ? 1 : 0
  name         = "quay.io/frrouting/frr:10.7.0@sha256:65e5967b922572c0565d968388fb06af69d7e9b3b3eea40ad7e3810687667f68"
  keep_locally = false
}

resource "docker_image" "kvm_client" {
  count        = var.enable_kvm ? 1 : 0
  name         = "alpine:3.22.1@sha256:4bcff63911fcb4448bd4fdacec207030997caf25e9bea4045fa6c8c44de311d1"
  keep_locally = false
}

resource "docker_container" "kvm_frr" {
  count = var.enable_kvm ? 1 : 0
  name  = "${var.component}-kvm-frr"
  image = docker_image.kvm_frr[0].image_id
  capabilities { add = ["NET_ADMIN", "NET_RAW"] }
  sysctls = {
    "net.ipv4.ip_forward" = "1"
  }
  command = ["sh", "-ec", <<-SCRIPT
    sed -i 's/^bgpd=no/bgpd=yes/' /etc/frr/daemons
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
  count = var.enable_kvm ? 1 : 0
  name  = "${var.component}-kvm-client"
  image = docker_image.kvm_client[0].image_id
  user  = "0"
  capabilities { add = ["NET_ADMIN"] }
  command = ["sh", "-ec", "apk add --no-cache curl iproute2 >/dev/null; ip route replace ${var.kvm_vip}/32 via ${var.kvm_frr_address}; trap : TERM INT; sleep infinity & wait"]
  networks_advanced {
    name         = docker_network.kvm[0].name
    ipv4_address = var.kvm_client_address
  }
  restart = "unless-stopped"
}
