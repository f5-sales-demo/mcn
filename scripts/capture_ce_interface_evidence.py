#!/usr/bin/env python3
"""Capture sanitized Azure NIC facts for the Secure Mesh interface contract.

This is a read-only diagnostic tool. It intentionally excludes public IPs,
credentials, registration material, and raw CE diagnostics. It never accepts
or emits guest device names; a separately captured, sanitized control-plane
reference is the only CE-side value it can join to Azure NIC identities.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


class EvidenceError(RuntimeError):
    """Raised when a source is incomplete or unsafe for the contract."""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--resource-group", required=True)
    parser.add_argument("--node", action="append", required=True, dest="nodes")
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--subscription", default=None)
    parser.add_argument(
        "--control-plane-references",
        type=Path,
        help="sanitized JSON with hostname, control_plane_interface_reference, and provenance",
    )
    return parser.parse_args()


def az_json(subscription: str | None, arguments: list[str]) -> Any:
    command = ["az", *arguments, "--output", "json", "--only-show-errors"]
    if subscription:
        command.extend(["--subscription", subscription])
    completed = subprocess.run(command, check=False, capture_output=True, text=True)
    if completed.returncode:
        raise EvidenceError(f"Azure read failed for {' '.join(arguments[:3])}: {completed.stderr.strip()}")
    try:
        return json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        raise EvidenceError("Azure CLI returned non-JSON data") from error


def require_string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise EvidenceError(f"missing required {label}")
    return value.strip()


def load_control_plane_references(path: Path | None) -> dict[str, dict[str, str]]:
    if path is None:
        return {}
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise EvidenceError(f"cannot read sanitized control-plane references: {path}") from error
    if not isinstance(document, dict) or document.get("schema_version") != 1:
        raise EvidenceError("control-plane references must declare schema_version 1")
    nodes = document.get("nodes")
    if not isinstance(nodes, list):
        raise EvidenceError("control-plane references must contain a nodes list")
    references: dict[str, dict[str, str]] = {}
    for item in nodes:
        if not isinstance(item, dict) or set(item) != {
            "node_hostname", "control_plane_interface_reference", "provenance"
        }:
            raise EvidenceError("control-plane reference records have an unsafe or incomplete shape")
        hostname = require_string(item.get("node_hostname"), "node_hostname")
        reference = require_string(item.get("control_plane_interface_reference"), "control_plane_interface_reference")
        provenance = require_string(item.get("provenance"), "provenance")
        if hostname in references:
            raise EvidenceError(f"duplicate control-plane reference for {hostname}")
        references[hostname] = {"reference": reference, "provenance": provenance}
    return references


def vm_nic_attachments(subscription: str | None, resource_group: str, hostname: str) -> list[dict[str, Any]]:
    attachments = az_json(
        subscription,
        ["vm", "show", "--resource-group", resource_group, "--name", hostname, "--query", "networkProfile.networkInterfaces"],
    )
    if not isinstance(attachments, list) or not attachments:
        raise EvidenceError(f"Azure VM {hostname} has no attached NICs")
    return attachments


def nic_inventory(subscription: str | None, resource_id: str) -> dict[str, Any]:
    nic = az_json(
        subscription,
        [
            "network",
            "nic",
            "show",
            "--ids",
            resource_id,
            "--query",
            "{id:id,name:name,mac:macAddress,ip_configurations:ipConfigurations}",
        ],
    )
    if not isinstance(nic, dict):
        raise EvidenceError(f"Azure NIC {resource_id} was not an object")
    return nic

def normalize_ip_configurations(nic: dict[str, Any], hostname: str, position: int) -> list[dict[str, Any]]:
    configurations = nic.get("ip_configurations")
    if not isinstance(configurations, list) or not configurations:
        raise EvidenceError(f"Azure NIC position {position} on {hostname} has no IP configurations")
    result = []
    for configuration in configurations:
        if not isinstance(configuration, dict):
            raise EvidenceError(f"Azure NIC position {position} on {hostname} has malformed IP configuration")
        subnet = configuration.get("subnet")
        if not isinstance(subnet, dict):
            raise EvidenceError(f"Azure NIC position {position} on {hostname} lacks a subnet identity")
        result.append(
            {
                "ip_configuration_name": require_string(configuration.get("name"), "ip configuration name"),
                "is_primary": bool(configuration.get("primary", False)),
                "private_ip": require_string(configuration.get("privateIPAddress"), "private IP"),
                "subnet_resource_id": require_string(subnet.get("id"), "subnet resource ID"),
            }
        )
    return result


def capture_node(
    subscription: str | None,
    resource_group: str,
    hostname: str,
    references: dict[str, dict[str, str]],
) -> dict[str, Any]:
    attachments = vm_nic_attachments(subscription, resource_group, hostname)
    nics = []
    for position, attachment in enumerate(attachments, start=1):
        if not isinstance(attachment, dict):
            raise EvidenceError(f"Azure VM {hostname} has a malformed NIC attachment")
        resource_id = require_string(attachment.get("id"), "Azure NIC resource ID")
        nic = nic_inventory(subscription, resource_id)
        nics.append(
            {
                "cloud_nic_position": position,
                "azure_nic_resource_id": require_string(nic.get("id"), "Azure NIC resource ID"),
                "azure_nic_name": require_string(nic.get("name"), "Azure NIC name"),
                "is_primary_attachment": bool(attachment.get("primary", False)),
                "nic_mac": require_string(nic.get("mac"), "Azure NIC MAC"),
                "ip_configurations": normalize_ip_configurations(nic, hostname, position),
            }
        )
    slo = nics[0]
    first_primary_ip = next((item for item in slo["ip_configurations"] if item["is_primary"]), slo["ip_configurations"][0])
    reference = references.get(hostname)
    return {
        "node_hostname": hostname,
        "azure_nics": nics,
        "slo_binding": {
            "role": "slo",
            "cloud_nic_position": slo["cloud_nic_position"],
            "nic_mac": slo["nic_mac"],
            "ip_configuration_name": first_primary_ip["ip_configuration_name"],
            "private_ip": first_primary_ip["private_ip"],
            "subnet_resource_id": first_primary_ip["subnet_resource_id"],
            "control_plane_interface_reference": reference["reference"] if reference else None,
            "control_plane_reference_provenance": reference["provenance"] if reference else None,
        },
        "optional_roles": {
            "external": {"bindable": False, "reason": "requires future contract and authoritative evidence"},
            "sli": {"bindable": False, "reason": "requires future contract and authoritative evidence"},
        },
    }


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as stream:
        stream.write(content)
        temporary = Path(stream.name)
    os.replace(temporary, path)


def matrix_markdown(document: dict[str, Any]) -> str:
    rows = [
        "# Secure Mesh interface evidence matrix",
        "",
        f"Captured: `{document['captured_at_utc']}`  ",
        f"Status: `{document['evidence_status']}`",
        "",
        "This matrix contains Azure identity facts and sanitized control-plane references only. Guest device names, CE diagnostics, public IPs, credentials, and registration material are intentionally excluded.",
        "",
        "| Node | NIC position | MAC | IP configuration | Private IP | Subnet | Role | Control-plane reference |",
        "| --- | ---: | --- | --- | --- | --- | --- | --- |",
    ]
    for node in document["nodes"]:
        binding = node["slo_binding"]
        rows.append(
            "| {node} | {position} | {mac} | {ipconfig} | {ip} | {subnet} | SLO | {reference} |".format(
                node=node["node_hostname"],
                position=binding["cloud_nic_position"],
                mac=binding["nic_mac"],
                ipconfig=binding["ip_configuration_name"],
                ip=binding["private_ip"],
                subnet=binding["subnet_resource_id"],
                reference=binding["control_plane_interface_reference"] or "MISSING",
            )
        )
    rows.extend(
        [
            "",
            "External and SLI remain disabled. This artifact does not establish their Azure-to-CE mappings.",
            "",
        ]
    )
    return "\n".join(rows)

def main() -> int:
    arguments = parse_args()
    hostnames = [require_string(value, "node hostname") for value in arguments.nodes]
    if len(hostnames) != len(set(hostnames)):
        raise EvidenceError("--node values must be unique")
    references = load_control_plane_references(arguments.control_plane_references)
    unexpected_references = sorted(set(references).difference(hostnames))
    if unexpected_references:
        raise EvidenceError("control-plane references include unknown nodes: " + ", ".join(unexpected_references))
    nodes = [capture_node(arguments.subscription, arguments.resource_group, hostname, references) for hostname in hostnames]
    reference_complete = all(node["slo_binding"]["control_plane_interface_reference"] for node in nodes)
    document = {
        "schema_version": 1,
        "captured_at_utc": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "evidence_status": "slo_reference_complete" if reference_complete else "diagnostic_only",
        "source": {
            "kind": "azure_arm_readonly",
            "resource_group": arguments.resource_group,
            "subscription": arguments.subscription,
        },
        "nodes": nodes,
        "role_contract": {
            "slo": {"bindable": True, "cloud_nic_position": 1},
            "external": {"bindable": False},
            "sli": {"bindable": False},
        },
    }
    output_dir = arguments.output_dir.resolve()
    atomic_write(output_dir / "securemesh-ce-interface-evidence.json", json.dumps(document, indent=2, sort_keys=True) + "\n")
    atomic_write(output_dir / "securemesh-ce-interface-matrix.md", matrix_markdown(document))
    print(f"Wrote sanitized evidence to {output_dir}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except EvidenceError as error:
        print(f"evidence capture failed: {error}", file=sys.stderr)
        raise SystemExit(2)
