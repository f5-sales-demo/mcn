#!/usr/bin/env bash

set -euo pipefail

repository_root=$(git rev-parse --show-toplevel)

if rg -n 'resource "aws_key_pair"|from_port[[:space:]]*=[[:space:]]*22|to_port[[:space:]]*=[[:space:]]*22' \
  "$repository_root/terraform/aws_ce.tf" "$repository_root/terraform/aws_vpc.tf"; then
  echo "AWS showcase must not create an SSH key pair or expose TCP 22" >&2
  exit 1
fi

if rg -n 'resource "azurerm_public_ip"|resource "azurerm_network_security_group"|destination_port_range[[:space:]]*=[[:space:]]*"22"' \
  "$repository_root/terraform/modules/client-vm/main.tf"; then
  echo "Azure test client must remain private and have no inbound SSH rule" >&2
  exit 1
fi

grep -qF 'AmazonSSMManagedInstanceCore' "$repository_root/terraform/aws_ce.tf" || {
  echo "AWS test client must retain its Systems Manager execution channel" >&2
  exit 1
}

echo "Public management entry points are absent"
