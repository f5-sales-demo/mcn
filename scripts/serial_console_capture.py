#!/usr/bin/env python3
"""Capture Azure Serial Console output from a Customer Edge without a terminal.

    python3 scripts/serial_console_capture.py --resource-group RG --vm-name NAME

Why this exists: serial console is the only way into a CE that never registered,
because the vpm/debug API is reached through the F5 Distributed Cloud control plane
and answers only once the node is ONLINE. But ``az serial-console connect`` drives a
raw TTY, so it cannot run from a pipeline — it dies client-side with
``(19, 'Operation not supported by device')``. Driving the websocket directly gets the
same bytes with no terminal, which makes boot evidence collectable by automation.

Two things about the handshake are not documented anywhere and cost real time:

1. The gateway's FIRST frame is a challenge, not output. The client answers it with a
   bearer token; everything after that is the node's serial port.
2. The gateway refuses roughly every other attempt with
   ``1011 Connection not trusted``. Measured across repeated attempts on three nodes it
   alternates — a refusal is followed by a success on the same node — which fits a
   previous session still being held and the refused attempt clearing it. It is NOT a
   credential problem despite the message, so this script retries.

   A single token is used for both the session request and the challenge, matching the
   ``az`` extension. That is correct practice but is not what causes the refusals.

This is a workstation script. It needs an interactive ``az`` login; the F5 corporate
Entra tenant does not permit provisioning a service principal, so no runner can hold
the credential.
"""

from __future__ import annotations

import argparse
import contextlib
import json
import re
import shutil
import subprocess
import sys
import threading
import time
import urllib.request

try:
    import websocket  # provided by the azure-cli serial-console extension
except ImportError:  # pragma: no cover - environment guard
    sys.exit(
        "websocket-client is required.\n"
        "  az extension add --name serial-console\n"
        "and run this with the azure-cli python, e.g.\n"
        "  $(brew --prefix azure-cli)/libexec/bin/python3 scripts/serial_console_capture.py ..."
    )

ANSI = re.compile(r"\x1b\[[0-9;?]*[a-zA-Z]")
API_VERSION = "2018-05-01"


def arm_url(subscription: str, resource_group: str, vm_name: str) -> str:
    """The serial port connect endpoint for one VM."""
    return (
        f"https://management.azure.com/subscriptions/{subscription}"
        f"/resourceGroups/{resource_group}/providers/Microsoft.Compute"
        f"/virtualMachines/{vm_name}/providers/Microsoft.SerialConsole"
        f"/serialPorts/0/connect?api-version={API_VERSION}"
    )


def az(*args: str) -> str:
    """Run an az command and return stdout, failing loudly."""
    exe = shutil.which("az")
    if exe is None:
        sys.exit("the azure-cli (az) is required and was not found on PATH")
    result = subprocess.run(  # noqa: S603 - fixed argv, resolved executable, no shell
        [exe, *args], capture_output=True, text=True, check=True
    )
    return result.stdout.strip()


def capture(
    subscription: str, resource_group: str, vm_name: str, seconds: float
) -> str:
    """Attach to the serial port and return whatever it emits."""
    # One token for BOTH the grant and the challenge. See the module docstring.
    token = az(
        "account",
        "get-access-token",
        "--resource",
        "https://management.azure.com/",
        "--query",
        "accessToken",
        "-o",
        "tsv",
    )

    url = arm_url(subscription, resource_group, vm_name)
    # S310 exists to catch attacker-controlled schemes. This URL is built from a fixed
    # https ARM prefix, and the guard makes that an enforced invariant rather than a
    # claim in a comment.
    if not url.startswith("https://management.azure.com/"):
        msg = f"refusing a non-ARM URL: {url}"
        raise ValueError(msg)

    request = urllib.request.Request(  # noqa: S310 - scheme asserted https above
        url,
        data=b"{}",
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(request, timeout=60) as response:  # noqa: S310 - see above
        ws_url = json.load(response)["connectionString"]

    print(f"[grant] {ws_url.split('/')[2]}", file=sys.stderr)

    frames: list[str] = []
    state = {"challenged": False}

    def on_message(ws: websocket.WebSocketApp, message: str | bytes) -> None:
        if not state["challenged"]:
            state["challenged"] = True
            ws.send(token)
            print("[auth] challenge answered", file=sys.stderr)

            # A newline makes an idle login prompt redraw. Harmless to a running node.
            def nudge() -> None:
                # Best effort: the socket may already have closed.
                with contextlib.suppress(Exception):
                    ws.send("\r\n")

            threading.Timer(2.0, nudge).start()
            threading.Timer(5.0, nudge).start()
            return
        frames.append(
            message if isinstance(message, str) else message.decode("utf-8", "replace")
        )

    def on_close(_ws: object, code: object, reason: object) -> None:
        print(f"[close] code={code} reason={reason or '(none)'}", file=sys.stderr)

    ws_app = websocket.WebSocketApp(ws_url, on_message=on_message, on_close=on_close)
    threading.Timer(seconds, ws_app.close).start()
    ws_app.run_forever(skip_utf8_validation=True)

    return ANSI.sub("", "".join(frames)).replace("\r", "")


def main() -> int:
    """Parse arguments, capture serial output, and print it to stdout."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--subscription", help="defaults to the active az subscription")
    parser.add_argument("--resource-group", required=True)
    parser.add_argument("--vm-name", required=True)
    parser.add_argument(
        "--seconds",
        type=float,
        default=16.0,
        help="how long to stay attached (default 16)",
    )
    parser.add_argument(
        "--attempts",
        type=int,
        default=3,
        help="retries when the gateway answers 1011 not-trusted (default 3)",
    )
    args = parser.parse_args()

    subscription = args.subscription or az(
        "account", "show", "--query", "id", "-o", "tsv"
    )

    output = ""
    for attempt in range(1, args.attempts + 1):
        output = capture(subscription, args.resource_group, args.vm_name, args.seconds)
        if output.strip():
            break
        if attempt < args.attempts:
            print(f"[retry] attempt {attempt} refused, retrying", file=sys.stderr)
            time.sleep(5)

    if not output.strip():
        print(
            "no serial output captured.\n"
            "Check boot diagnostics is enabled on the VM — Azure requires it:\n"
            "  az vm show -g <rg> -n <vm> --query diagnosticsProfile",
            file=sys.stderr,
        )
        return 1

    print(output.strip())
    return 0


if __name__ == "__main__":
    sys.exit(main())
