#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
EGRESS_IF=$(ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -n1)
EGRESS_IF=${EGRESS_IF:-enp5s0}

echo "==> Enabling IPv4 Forwarding and SNAT on host interface ${EGRESS_IF}..."
sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -t nat -C POSTROUTING -s 10.100.0.0/24 -o "${EGRESS_IF}" -j MASQUERADE 2>/dev/null || sudo iptables -t nat -A POSTROUTING -s 10.100.0.0/24 -o "${EGRESS_IF}" -j MASQUERADE

echo "==> Stopping any existing frr-router container..."
docker rm -f frr-router 2>/dev/null || true

echo "==> Starting FRR router container attached to host network..."
docker run -d \
  --name frr-router \
  --restart unless-stopped \
  --net=host \
  --privileged \
  -v "${SCRIPT_DIR}/frr/daemons:/etc/frr/daemons:ro" \
  -v "${SCRIPT_DIR}/frr/frr.conf:/etc/frr/frr.conf:ro" \
  frrouting/frr:latest

echo "==> FRR Router Container Started."
docker exec frr-router vtysh -c "show ip bgp summary"
