#!/usr/bin/env python3
"""Create the private, checksummed AWS SMSv2 bootstrap device mapping.

Inputs are intentionally files outside the repository: a sanitized bootstrap
registration projection and Terraform-owned ENI facts.  This tool prints no
MAC addresses or device names and writes the final mapping mode 0600.
"""
import argparse
import hashlib
import json
import os
import re
import sys

MAC = re.compile(r"^[0-9a-f]{2}(?::[0-9a-f]{2}){5}$")

def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)

def fail(reason):
    print(f"error: {reason}", file=sys.stderr)
    raise SystemExit(2)

def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()

def owned_enis(enis):
    if not isinstance(enis, list):
        fail("eni_input_must_be_list")
    owned = {}
    for item in enis:
        if not isinstance(item, dict):
            fail("eni_mapping_invalid")
        key = (item.get("site_key"), item.get("role"))
        mac = str(item.get("mac", "")).lower()
        if key[0] not in {"01", "02", "03"} or key[1] not in {"slo", "sli"} or not MAC.fullmatch(mac) or key in owned:
            fail("eni_mapping_invalid")
        owned[key] = mac
    if len(owned) != 6 or len(set(owned.values())) != 6:
        fail("eni_mapping_not_one_to_one")
    return owned

def validate_document(document, owned):
    if not isinstance(document, dict) or document.get("schema_version") != 1:
        fail("mapping_schema_invalid")
    entries = document.get("entries")
    if not isinstance(entries, list):
        fail("mapping_entries_invalid")
    payload = {"schema_version": document["schema_version"], "entries": entries}
    if document.get("checksum") != hashlib.sha256(canonical(payload)).hexdigest():
        fail("mapping_checksum_mismatch")
    observed = {}
    for item in entries:
        if not isinstance(item, dict):
            fail("mapping_entry_invalid")
        key = (item.get("site_key"), item.get("role"))
        mac, device = str(item.get("mac", "")).lower(), str(item.get("device", "")).strip()
        if key not in owned or mac != owned[key] or not MAC.fullmatch(mac) or not device or key in observed:
            fail("mapping_entry_invalid")
        observed[key] = device
    if set(observed) != set(owned) or any(
        observed[(site, "slo")] == observed[(site, "sli")]
        for site in ("01", "02", "03")
    ):
        fail("mapping_not_one_to_one")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--registration-file")
    parser.add_argument("--eni-file", required=True)
    parser.add_argument("--output")
    parser.add_argument("--verify-file")
    args = parser.parse_args()
    if bool(args.verify_file) == bool(args.registration_file):
        fail("choose_generate_or_verify")
    if args.verify_file and args.output:
        fail("verify_does_not_write_output")
    if args.registration_file and not args.output:
        fail("output_required")
    owned = owned_enis(load(args.eni_file))
    if args.verify_file:
        validate_document(load(args.verify_file), owned)
        return
    registrations = load(args.registration_file)
    if not isinstance(registrations, list):
        fail("registration_input_must_be_list")
    observed = {}
    for item in registrations:
        if not isinstance(item, dict):
            fail("registration_mapping_invalid")
        site_key = item.get("site_key")
        mac, device = str(item.get("mac", "")).lower(), str(item.get("device", "")).strip()
        matching_keys = [key for key, owned_mac in owned.items() if key[0] == site_key and owned_mac == mac]
        if len(matching_keys) != 1 or not MAC.fullmatch(mac) or not device:
            fail("registration_mapping_invalid")
        key = matching_keys[0]
        if key in observed:
            fail("registration_mapping_invalid")
        observed[key] = {"site_key": key[0], "role": key[1], "mac": mac, "device": device}
    if set(observed) != set(owned) or any(
        observed[(site, "slo")]["device"] == observed[(site, "sli")]["device"]
        for site in ("01", "02", "03")
    ):
        fail("registration_mapping_not_one_to_one")
    payload = {"schema_version": 1, "entries": [observed[key] for key in sorted(observed)]}
    document = dict(payload, checksum=hashlib.sha256(canonical(payload)).hexdigest())
    fd = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(document, handle, sort_keys=True, separators=(",", ":"))
        handle.write("\n")

if __name__ == "__main__":
    main()
