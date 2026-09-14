#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
kvm="$repo_root/terraform/kvm.tf"
frr="$repo_root/terraform/kvm_frr.tf"
onprem="$repo_root/terraform/onprem_kvm.tf"
variables="$repo_root/terraform/variables.tf"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
require() { grep -Fq "$1" "$2" || fail "missing $1 in $2"; }
reject() { ! grep -Fq "$1" "$2" || fail "unexpected $1 in $2"; }

require 'kvm_ce_nodes' "$kvm"
require 'kvm_enabled_nodes' "$kvm"
require 'count = var.enable_kvm ? 1 : 0' "$kvm"
require 'kvm_network_generation' "$kvm"
require 'kvm_network_name' "$kvm"
require 'kvm_network_bridge' "$kvm"
require 'local.kvm_bootstrap_generation}-disk.qcow2' "$kvm"
require 'local.kvm_bootstrap_generation}-cloudinit.iso' "$kvm"
require 'kvm_bootstrap_generation' "$kvm"
require 'Token: ${local.ce_registration_token}' "$kvm"
reject 'Token: ${xcsh_token.ce.id}' "$kvm"
require 'data "xcsh_site_image" "kvm"' "$kvm"
require 'provider_ref = "KVM"' "$kvm"
require 'source = data.xcsh_site_image.kvm[0].image_download_url' "$kvm"
reject 'base-cloud-noble.qcow2' "$kvm"
require '10.100.0.11' "$kvm"
require '10.100.0.12' "$kvm"
require '10.100.0.13' "$kvm"
require 'mac            = each.value.mac' "$kvm"
require 'enabled = true' "$kvm"
require 'option_name  = "dhcp-host"' "$kvm"
require 'option_value = "${options.value.mac},${options.value.address}"' "$kvm"
require 'resource "terraform_data" "kvm_network_identity"' "$kvm"
require 'replace_triggered_by = [terraform_data.kvm_network_identity[0]]' "$kvm"
reject 'network_config' "$kvm"
reject '/etc/netplan/60-mcn-ce-static.yaml' "$kvm"
require 'libvirt_cloudinit_disk.ce_cloudinit[each.key]' "$kvm"
require 'libvirt_network.ce_bgp_net' "$kvm"

require 'resource "docker_container" "kvm_frr"' "$frr"
require 'count = var.enable_kvm ? 1 : 0' "$frr"
require 'mcn-kvm-frr-router' "$frr"
require 'driver = "macvlan"' "$frr"
require 'parent = local.kvm_network_bridge' "$frr"
require 'ipv4_address = "10.100.0.2"' "$frr"
require 'frrouting/frr@sha256:990e83490108b686fd6df3b1cafa6bdbb2714acb00eedb9a89693946f46f45ce' "$frr"
require 'neighbor ${node.address} remote-as 64512' "$frr"
require 'maximum-paths 4' "$frr"
require 'depends_on = [libvirt_network.ce_bgp_net]' "$frr"
reject '/data/services/frr-router' "$frr"
reject 'name = "frr-router"' "$frr"
require 'address = "10.100.0.2"' "$onprem"
require 'count = var.enable_kvm ? 1 : 0' "$onprem"
require 'docker_container.kvm_frr' "$onprem"
require 'libvirt_domain.ce_node' "$onprem"
require 'variable "enable_kvm"' "$variables"
require 'no KVM image lookup occurs while disabled' "$variables"

printf 'PASS: KVM CE identity and FRR lifecycle are Terraform-owned\n'
