#!/usr/bin/env python3
"""Credential-free tests for sanitized Secure Mesh evidence capture."""

from __future__ import annotations

import importlib.util
import json
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch


SCRIPT = Path(__file__).with_name("capture_ce_interface_evidence.py")
SPEC = importlib.util.spec_from_file_location("capture_ce_interface_evidence", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class Completed:
    returncode = 0
    stderr = ""

    def __init__(self, payload: object):
        self.stdout = json.dumps(payload)


def fake_az(command: list[str], **_: object) -> Completed:
    if command[1:3] == ["vm", "show"]:
        return Completed([
            {"id": "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Network/networkInterfaces/ce01-mgmt", "primary": True},
            {"id": "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Network/networkInterfaces/ce01-external", "primary": False},
        ])
    nic_id = command[command.index("--ids") + 1]
    if nic_id.endswith("ce01-mgmt"):
        return Completed({
            "id": nic_id,
            "name": "ce01-mgmt",
            "mac": "00-11-22-33-44-55",
            "ip_configurations": [{
                "name": "ipconfig1",
                "primary": True,
                "privateIPAddress": "10.0.1.4",
                "subnet": {"id": "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/hub/subnets/mgmt"},
            }],
        })
    if nic_id.endswith("ce01-external"):
        return Completed({
            "id": nic_id,
            "name": "ce01-external",
            "mac": "00-11-22-33-44-66",
            "ip_configurations": [{
                "name": "ipconfig1",
                "primary": True,
                "privateIPAddress": "10.0.2.4",
                "subnet": {"id": "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/hub/subnets/external"},
            }],
        })
    raise AssertionError(command)


class CaptureEvidenceTests(unittest.TestCase):
    @patch.object(MODULE.subprocess, "run", side_effect=fake_az)
    def test_first_azure_nic_is_the_only_slo_binding(self, _: object) -> None:
        node = MODULE.capture_node(None, "rg", "ce01", {})
        self.assertEqual(node["slo_binding"]["cloud_nic_position"], 1)
        self.assertEqual(node["slo_binding"]["nic_mac"], "00-11-22-33-44-55")
        self.assertEqual(node["slo_binding"]["private_ip"], "10.0.1.4")
        self.assertIsNone(node["slo_binding"]["control_plane_interface_reference"])
        self.assertFalse(node["optional_roles"]["external"]["bindable"])
        self.assertFalse(node["optional_roles"]["sli"]["bindable"])
        self.assertNotIn("eth", json.dumps(node).lower())

    def test_references_reject_guest_device_fields(self) -> None:
        with TemporaryDirectory() as directory:
            path = Path(directory) / "references.json"
            path.write_text(json.dumps({
                "schema_version": 1,
                "nodes": [{
                    "node_hostname": "ce01",
                    "control_plane_interface_reference": "network-interface-ref-01",
                    "provenance": "sanitized control-plane export",
                    "guest_device": "eth0",
                }],
            }), encoding="utf-8")
            with self.assertRaises(MODULE.EvidenceError):
                MODULE.load_control_plane_references(path)

    @patch.object(MODULE.subprocess, "run", side_effect=fake_az)
    def test_matrix_omits_guest_names_and_public_addresses(self, _: object) -> None:
        node = MODULE.capture_node(None, "rg", "ce01", {
            "ce01": {"reference": "network-interface-ref-01", "provenance": "sanitized control-plane export"}
        })
        document = {
            "captured_at_utc": "2026-08-13T00:00:00Z",
            "evidence_status": "slo_reference_complete",
            "nodes": [node],
        }
        matrix = MODULE.matrix_markdown(document)
        self.assertIn("network-interface-ref-01", matrix)
        self.assertIn("External and SLI remain disabled", matrix)
        self.assertNotIn("eth0", matrix)
        self.assertNotIn("203.0.113.", matrix)


if __name__ == "__main__":
    unittest.main()
