#!/usr/bin/env bash
# Hermetic test for scripts/sitecli-scrub.sh — the filter every captured CE
# command output passes through before it is written to the repository.
#
# The scrub has two jobs that pull against each other:
#
#   1. Never publish anything that identifies our tenant or our infrastructure:
#      API tokens, the tenant console hostname, our public addresses, private keys.
#   2. Never damage the diagnostic content that makes the capture worth publishing.
#      A naive "looks like a public IP" rule eats `0.0.0.0` from a default route,
#      `255.255.255.0` from a netmask, and `224.0.0.5` from an OSPF/BGP neighbour
#      line — which is most of the value of `rt`, `ip addr` and the BGP commands.
#
# Job 2 is why the address rules below are enumerated rather than inferred, and
# why the majority of these cases assert that something is *preserved*.
#
# No network. Operates on strings only.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="${REPO_ROOT}/scripts/sitecli-scrub.sh"

FAIL=0

# scrub <text> — run the filter over stdin, echo the result.
scrub() { printf '%s' "$1" | bash "$SCRIPT"; }

# assert_preserved <label> <text> <needle>
# The needle must survive the scrub verbatim.
assert_preserved() {
  local label="$1" text="$2" needle="$3" out
  out=$(scrub "$text")
  if printf '%s' "$out" | grep -qF -- "$needle"; then
    echo "[OK] $label -> preserved"
  else
    echo "[FAIL] $label — expected '$needle' to survive, got: $out"
    FAIL=1
  fi
}

# assert_removed <label> <text> <needle>
# The needle must not appear anywhere in the output.
assert_removed() {
  local label="$1" text="$2" needle="$3" out
  out=$(scrub "$text")
  if printf '%s' "$out" | grep -qF -- "$needle"; then
    echo "[FAIL] $label — expected '$needle' to be removed, got: $out"
    FAIL=1
  else
    echo "[OK] $label -> removed"
  fi
}

# --- secrets: the whole point of the filter ------------------------------------
assert_removed "API token in an Authorization header" \
  'Authorization: APIToken lwEqhg+Oqbq5fsHMc0m/gxeysrA=' 'lwEqhg+Oqbq5fsHMc0m/gxeysrA='
assert_removed "bare APIToken value" \
  'curl -H "Authorization: APIToken OULzp2FaqP1FTmgygm1dn5BDfYA=" https://x' 'OULzp2FaqP1FTmgygm1dn5BDfYA='
assert_removed "Bearer token" \
  'Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.abc.def' 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
assert_removed "private key body" \
  '-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEAx7Vk2mFakePrivateKeyMaterialHere
-----END RSA PRIVATE KEY-----' 'MIIEowIBAAKCAQEAx7Vk2mFakePrivateKeyMaterialHere'

# --- tenant identity -----------------------------------------------------------
assert_removed "tenant console hostname" \
  'endpoint https://f5-sales-demo.console.ves.volterra.io/api' 'f5-sales-demo.console'
assert_removed "second tenant console hostname" \
  'endpoint https://f5-amer-ent.console.ves.volterra.io/api' 'f5-amer-ent.console'

# --- our public addresses ------------------------------------------------------
assert_removed "CE public IPv4" 'inet 20.124.35.231/32 scope global' '20.124.35.231'
assert_removed "second CE public IPv4" 'peer 168.62.59.17 up' '168.62.59.17'
assert_removed "global unicast IPv6" 'inet6 2603:1030:c02:3::17/128' '2603:1030:c02:3::17'

# --- addresses that MUST survive: this is where a careless rule does damage ----
assert_preserved "default route prefix" '0.0.0.0/0 via 10.0.1.1 dev eth0' '0.0.0.0/0'
assert_preserved "unspecified address in a listen socket" \
  'tcp 0 0 0.0.0.0:22 0.0.0.0:* LISTEN' '0.0.0.0:22'
assert_preserved "netmask" 'inet 10.0.1.4 netmask 255.255.255.0' '255.255.255.0'
assert_preserved "all-ones broadcast" 'broadcast 255.255.255.255' '255.255.255.255'
assert_preserved "OSPF/BGP multicast group" 'join group 224.0.0.5' '224.0.0.5'
assert_preserved "RFC1918 ten-dot" 'inet 10.0.1.4/24' '10.0.1.4'
assert_preserved "RFC1918 172.16/12" 'inet 172.16.5.9/24' '172.16.5.9'
assert_preserved "RFC1918 192.168/16" 'inet 192.168.1.1/24' '192.168.1.1'
assert_preserved "loopback" 'inet 127.0.0.1/8 scope host lo' '127.0.0.1'
assert_preserved "link-local" 'inet 169.254.1.1/16' '169.254.1.1'
assert_preserved "XC carrier-grade NAT space" 'flow match 100.127.192.10:53' '100.127.192.10'
assert_preserved "IPv6 loopback" 'inet6 ::1/128 scope host' '::1'
assert_preserved "IPv6 link-local" 'inet6 fe80::20d:3aff:fe7c:1/64' 'fe80::20d:3aff:fe7c:1'
assert_preserved "IPv6 unique local" 'inet6 fd00:1::5/64' 'fd00:1::5'

# Public resolvers carry documentation value and disclose nothing about us.
assert_preserved "Google public DNS in dig output" 'SERVER: 8.8.8.8#53(8.8.8.8)' '8.8.8.8'
assert_preserved "Cloudflare public DNS" ';; SERVER: 1.1.1.1#53' '1.1.1.1'

# Azure's platform DNS / wireserver address is published by Microsoft and is
# identical for every VM in every subscription, so it identifies nothing. It shows
# up in real `diagnosis` and `dig` output and is meaningful there.
assert_preserved "Azure platform DNS address" \
  'nameserver 168.63.129.16' '168.63.129.16'

# The Azure-assigned VNet DNS label, by contrast, is unique to our deployment.
# Taken from real `diagnosis` output.
assert_removed "Azure VNet DNS label" \
  'search w5yqtxiwsjfexcydw1s2fwarwa.bx.internal.cloudapp.net' \
  'w5yqtxiwsjfexcydw1s2fwarwa'
assert_preserved "Azure VNet DNS label keeps its shape" \
  'search w5yqtxiwsjfexcydw1s2fwarwa.bx.internal.cloudapp.net' \
  'internal.cloudapp.net'

# --- diagnostic content that is not secret and must not be mangled -------------
assert_preserved "CE software build string" \
  'Software Version: crt-20250613-3382' 'crt-20250613-3382'
assert_preserved "container id" \
  '89a5bee1ab6ce  feec7a48f9b4  2 days ago  Running' '89a5bee1ab6ce'
assert_preserved "site and node names" \
  'site ar-bgp-eastus01 node f5-xc-ce-vm-01 ONLINE' 'ar-bgp-eastus01'
assert_preserved "interface names" 'eth0 eth1 vhost0 tunnel0' 'vhost0'
assert_preserved "BGP AS numbers" 'BGP neighbor is 10.0.1.5, remote AS 65001' '65001'

# MAC addresses contain colons. A MAC whose first octet begins 2 or 3 is exactly
# what a "global unicast IPv6 starts with 2 or 3" rule mistakes for an address,
# so both the safe and the dangerous first octets are pinned here.
assert_preserved "MAC address, first octet 7c" \
  'link/ether 7c:1e:52:7f:f8:12 brd ff:ff:ff:ff:ff:ff' '7c:1e:52:7f:f8:12'
assert_preserved "MAC address, first octet 2c" \
  'link/ether 2c:54:91:88:c9:e3 brd ff:ff:ff:ff:ff:ff' '2c:54:91:88:c9:e3'
assert_preserved "MAC address, first octet 3a" \
  'link/ether 3a:0d:52:11:0e:07 brd ff:ff:ff:ff:ff:ff' '3a:0d:52:11:0e:07'
assert_preserved "all-ones MAC broadcast" \
  'link/ether 00:0d:3a:7c:00:01 brd ff:ff:ff:ff:ff:ff' 'ff:ff:ff:ff:ff:ff'

# --- whitespace normalisation --------------------------------------------------
# The repository .editorconfig requires LF endings, no trailing whitespace and a
# final newline, and the check is enforced in CI. Captured CLI output violates all
# three: tables are column-padded with trailing spaces and `curl -v` echoes HTTP
# headers with CRLF. Normalising here is the source fix. It costs no evidence —
# trailing padding and carriage returns are invisible in a rendered code block —
# and it also makes re-captures diff far more cleanly.
trailing=$(printf 'IF RX Discard   5   \nnext line\n' | bash "$SCRIPT" | grep -c ' $' || true)
if [ "$trailing" = "0" ]; then
  echo "[OK] trailing whitespace stripped"
else
  echo "[FAIL] $trailing line(s) still end in whitespace"
  FAIL=1
fi

if printf 'HTTP/1.1 200 OK\r\nServer: nginx\r\n' | bash "$SCRIPT" | grep -q $'\r'; then
  echo "[FAIL] carriage returns survived"
  FAIL=1
else
  echo "[OK] CRLF normalised to LF"
fi

# A final newline must be present exactly once, whether or not the input had one.
for probe in 'no trailing newline' 'has trailing newline
'; do
  out=$(printf '%s' "$probe" | bash "$SCRIPT" | od -c | tail -2 | head -1)
  case "$out" in
  *'\n'*) : ;;
  *)
    echo "[FAIL] no final newline for input: ${probe%%$'\n'*}"
    FAIL=1
    ;;
  esac
done
echo "[OK] final newline present"

# Interior blank lines are content and must not be collapsed: BGP output opens
# with one, and several captures separate tables that way.
blanks=$(printf 'a\n\n\nb\n' | bash "$SCRIPT" | wc -l | tr -d ' ')
if [ "$blanks" = "4" ]; then
  echo "[OK] interior blank lines preserved"
else
  echo "[FAIL] interior blank lines altered: expected 4 lines, got $blanks"
  FAIL=1
fi

# --- idempotence: capture re-runs must not re-rewrite already-scrubbed text ----
once=$(scrub 'inet 20.124.35.231/32 and https://f5-sales-demo.console.ves.volterra.io/api')
twice=$(printf '%s' "$once" | bash "$SCRIPT")
if [ "$once" = "$twice" ]; then
  echo "[OK] scrubbing is idempotent"
else
  echo "[FAIL] scrubbing is not idempotent"
  echo "  once:  $once"
  echo "  twice: $twice"
  FAIL=1
fi

# --- structure is preserved ----------------------------------------------------
lines_in=$(printf 'a\nb\nc\n' | bash "$SCRIPT" | wc -l | tr -d ' ')
if [ "$lines_in" = "3" ]; then
  echo "[OK] line count preserved"
else
  echo "[FAIL] line count changed: expected 3, got $lines_in"
  FAIL=1
fi

empty_rc=0
printf '' | bash "$SCRIPT" >/dev/null 2>&1 || empty_rc=$?
if [ "$empty_rc" -eq 0 ]; then
  echo "[OK] empty input succeeds"
else
  echo "[FAIL] empty input exited $empty_rc"
  FAIL=1
fi

if [ "$FAIL" -ne 0 ]; then
  echo "sitecli-scrub tests FAILED"
  exit 1
fi
echo "sitecli-scrub tests passed"
