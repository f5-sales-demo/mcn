#!/usr/bin/env python3
"""Enumerate the Customer Edge Site CLI command surface over SSH.

The `vpm/debug` API exposes 34 commands. The appliance itself offers many more,
and `scripts/capture-sitecli.sh` cannot see them because they are not on that
API at all. This drives the on-box CLI directly and writes down what it finds.

Access
------
`admin`'s login shell is `/opt/bin/vpmu`, the Site CLI, reachable over SSH once
cloud-init has written `/var/home/admin/.ssh/authorized_keys` (PR #672). Three
things about that path are not guessable:

  * `sshd` answers on the **SLI** address only. eth0 is renamed `a-i-eth0` and
    carries no host IP — the Argo data plane owns it — so the management address
    and the public address time out exactly as a closed security group would.
    Reach the SLI address from a VM inside the VNet; hence --jump.
  * `vpmu` panics without a tty (`go-prompt ... no such device or address`), so
    a pty is mandatory, Enter is CR, and stdin must stay open. Closing stdin
    ends the session before the command has rendered.
  * The command text and the Enter byte must be **separate writes**. In one
    write the newline lands in the buffer as a literal character and the CLI
    answers `unknown command`, which reads as though the command is absent.

Discovery
---------
`execcli` is a hidden command — it is not in the interactive menu — and takes a
command name. Typing `execcli ` then TAB opens a completion menu carrying the
appliance's own one-line description for each command. That menu is the
authoritative catalog for this build.

go-prompt caps the menu at six visible rows as an application setting, which a
larger terminal does not change. So a six-row read is indistinguishable from a
six-command surface: scroll with Down and accumulate until it stops yielding
anything new.

Safety
------
Execution is **default-denied**. Only names on READ_ONLY may be run; anything
else is enumerated and never executed.

This is deliberately an allow-list and not a deny-list. Argument arity is
discoverable by running a command bare, and during the manual enumeration that
preceded this script it was run against `vifdump` — packet capture, writing
.pcap into /tmp inside the Argo container, on a node with a 31 GiB disk that was
mid-registration. `vifdump` was on no deny-list because nobody had thought of
it. That is the failure mode an allow-list closes: a command nobody anticipated
is refused by default rather than permitted by omission.
"""

from __future__ import annotations

import argparse
import contextlib
import fcntl
import json
import os
import pty
import re
import select
import struct
import subprocess
import sys
import termios
import time
from pathlib import Path

# --- pure parsing ------------------------------------------------------------

# Menu rows are separated by a cursor-down, not a newline. Split before
# stripping ANSI or every row concatenates onto one line.
ROW_SEPARATOR = "\x1b[1B"

ANSI = re.compile(r"\x1b\[[0-9;?]*[a-zA-Z]|\x1b\][^\x07]*\x07|\x1b[=>DM]")

# Two or more spaces separate the padded name column from the description.
COLUMNS = re.compile(r"\s{2,}")

PROMPT = ">>> "


def strip_ansi(text: str) -> str:
    """Remove the escape sequences the Site CLI paints its output with."""
    return ANSI.sub("", text)


def parse_menu(raw: str) -> list[tuple[str, str]]:
    """Extract (name, description) from one rendered completion menu.

    Reads every row regardless of its colour codes: the selected row is drawn
    differently from the rest, and keying on one colour pair silently drops it.
    """
    rows: list[tuple[str, str]] = []
    for segment in raw.split(ROW_SEPARATOR):
        text = strip_ansi(segment).strip()
        if not text or text.startswith(PROMPT.strip()):
            continue
        parts = COLUMNS.split(text)
        name = parts[0].strip()
        # A command name is a single token. Anything else is prompt echo or a
        # wrapped fragment, not a menu row.
        if not name or " " in name:
            continue
        rows.append((name, parts[1].strip() if len(parts) > 1 else ""))
    return rows


def trim_command_output(raw: str) -> str:
    """Strip the Site CLI's own interface from a command's output.

    Two pieces of chrome travel with every captured command: the prompt line
    echoing what was typed, and the completion menu the CLI repaints once the
    command returns. Committed verbatim, those put `>>> execcli <name>` and the
    entire six-entry top-level menu into the documentation as though the command
    had printed them.

    Only lines that *begin* with the prompt are dropped, so real output that
    happens to contain `>>>` — usage text, for instance — survives.
    """
    lines = [ln.rstrip() for ln in strip_ansi(raw).splitlines()]
    lines = [ln for ln in lines if not ln.lstrip().startswith(PROMPT.strip())]
    while lines and not lines[0].strip():
        lines.pop(0)
    while lines and not lines[-1].strip():
        lines.pop()
    return "\n".join(lines)


class MenuAccumulator:
    """Collects rows across a scrolling menu, first-seen order, no duplicates.

    Consecutive pages overlap by all but one row, so de-duplication is not an
    optimisation — without it the count is meaningless.
    """

    def __init__(self) -> None:
        """Start with an empty, insertion-ordered set of commands."""
        self.commands: dict[str, str] = {}

    def absorb(self, raw: str) -> int:
        """Add any unseen rows from one rendered page; return how many were new."""
        added = 0
        for name, description in parse_menu(raw):
            if name not in self.commands:
                self.commands[name] = description
                added += 1
        return added


# --- safety ------------------------------------------------------------------

# Commands that only read. Anything absent from this set is refused, including
# commands from a future build that nobody has classified yet.
READ_ONLY = frozenset(
    {
        # Argo data plane
        "dropstats",
        "dropstats-non-zero",
        "flow-l",
        "flow-l-match",
        "nh",
        "rt",
        "vif",
        "mpls",
        # Routing and tunnels
        "show-ip-bgp",
        "show-ip-bgp-summary",
        "show-ip-bgp-neighbors",
        "show-ip-bgp-neighbors-advertised-route",
        "ipsec-status",
        "ipsec-statusall",
        # Vega control plane
        "vegactl-configuration-list",
        "vegactl-introspect-dump-table",
        "vegactl-introspect-get",
        "vegactl-introspect-list-tracebuffers",
        "vegactl-introspect-show-election",
        "vegactl-introspect-show-tracebuffer",
        # Envoy
        "envoy-clusters",
        "envoy-config-dump",
        "envoy-hc-config-dump",
        "envoy-listeners",
        # Container runtimes
        "crictl-ps",
        "crictl-ps-a",
        "crictl-images",
        "crictl-inspect",
        "crictl-logs",
        "docker-ps",
        "docker-ps-a",
        "docker-images",
        "docker-inspect",
        "docker-logs",
        # Service and cluster state
        "systemctl-status-vpm",
        "systemctl-status-crio",
        "systemctl-status-docker",
        "systemctl-status-kubelet",
        "systemctl-status-iscsid",
        "systemctl-status-multipathd",
        "etcdctl-cluster-member-status",
        "kubelet-get-params",
        # Host inspection
        "journalctl",
        "netstat",
        "lsof",
        "ip",
        "ip-link-show",
        "check-mem",
        "chronyc-sources",
        "ping",
        "tracepath",
        "curl-host",
        "curl-vega",
        # Site CLI top level
        "health",
        "diagnosis",
        # Present on 20260703-e2c462a and absent on crt-20250613-3382 (#710). Only
        # the five that read state are here: `marker-exists-*` test for a file,
        # `iptables-lv` lists rules, `collect-database-stats` reports counters. The
        # other two of that set — `systemctl-restart-NetworkManager` and
        # `systemctl-start-crio-prune` — are deliberately absent, and the
        # mutating-verb tripwire below would reject them anyway.
        "collect-database-stats",
        "iptables-lv",
        "marker-exists-NetworkManager",
        "marker-exists-crio",
        "marker-exists-kubelet",
    }
)


class RefusedCommandError(RuntimeError):
    """Raised rather than returned, so a refusal cannot be ignored by accident."""

    def __init__(self, name: str) -> None:
        """Build the refusal message from the command that was refused."""
        super().__init__(
            f"{name!r} is not on the read-only allow-list and will not be run. "
            "Enumeration records that it exists; execution is default-denied.",
        )
        self.name = name


def may_execute(name: str) -> bool:
    """Report whether a command is on the read-only allow-list."""
    return name in READ_ONLY


def guard(name: str) -> None:
    """Refuse any command that is not explicitly known to be read-only."""
    if not may_execute(name):
        raise RefusedCommandError(name)


# --- the live session --------------------------------------------------------


class PtyProcess:
    """A child process on a pty, with a teardown that cannot block forever.

    Split out from SiteCliSession so the process lifecycle is testable without a
    Customer Edge. That separation is not cosmetic: an earlier version of close()
    let ExitStack unwind Popen.__exit__, which calls wait() with no timeout, and
    an `ssh -tt` session in a pty does not reliably die on SIGTERM. A harvest that
    had already collected every command hung for 26 minutes and then lost the lot,
    because the catalog is written after close() returns. Nothing in the hermetic
    tests could see that, because nothing exercised a real child.
    """

    #: Grace period for each stage of teardown. Bounded on purpose.
    TERMINATE_GRACE = 5.0

    def __init__(self, argv: list[str], rows: int = 120, cols: int = 220) -> None:
        """Spawn argv on a fresh pty with an explicit window size."""
        master, slave = pty.openpty()
        # Declare a large window before the child starts. It does not widen
        # go-prompt's six-row completion menu, but it stops long usage text from
        # being wrapped mid-token.
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
        self._stack = contextlib.ExitStack()
        # The child must outlive this constructor, so it cannot sit in a `with`
        # block here. An ExitStack gives the same guaranteed cleanup — but note
        # Popen.__exit__ calls wait() with NO timeout, so close() reaps the child
        # itself, with deadlines, before unwinding this. Reversing that order is
        # what hung a finished harvest for 26 minutes.
        self.proc = self._stack.enter_context(
            subprocess.Popen(  # noqa: S603 - fixed argv, resolved executable, no shell
                argv,
                stdin=slave,
                stdout=slave,
                stderr=slave,
                close_fds=True,
            ),
        )
        os.close(slave)
        self.fd = master

    def send(self, keys: str) -> None:
        """Write keystrokes to the pty."""
        os.write(self.fd, keys.encode())

    def close(self) -> None:
        """End the child and release the pty, in bounded time.

        SIGTERM, then a bounded wait, then SIGKILL, then a bounded wait. Every
        stage has a deadline, so this returns whether or not the child cooperates.
        """
        self.proc.terminate()
        try:
            self.proc.wait(timeout=self.TERMINATE_GRACE)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            with contextlib.suppress(subprocess.TimeoutExpired):
                self.proc.wait(timeout=self.TERMINATE_GRACE)
        # Safe now: the child is reaped, so the unwind's wait() returns at once.
        self._stack.close()
        with contextlib.suppress(OSError):
            os.close(self.fd)


def ssh_argv(node: str, jump: str, key: str, user: str = "admin") -> list[str]:
    """Build the ssh command line for one CE.

    Note that -o options are NOT inherited by the ProxyJump leg: ssh builds an
    implicit `ProxyCommand ssh -W ... <jump>` that uses your own defaults. So a
    jump host whose key is unknown, or has changed, fails the whole connection
    with a message that points at the CE.
    """
    argv = [
        "ssh",
        "-tt",
        "-o",
        "BatchMode=yes",
        "-o",
        "StrictHostKeyChecking=accept-new",
        "-o",
        "ConnectTimeout=10",
        "-i",
        key,
    ]
    if jump:
        argv += ["-o", f"ProxyJump={jump}"]
    argv.append(f"{user}@{node}")
    return argv


class SiteCliSession:
    """A pty-backed SSH session to the Site CLI."""

    def __init__(self, node: str, jump: str, key: str, user: str = "admin") -> None:
        """Open a pty and start an SSH session to the node's Site CLI."""
        self.pty = PtyProcess(ssh_argv(node, jump, key, user))
        self.fd = self.pty.fd
        self.proc = self.pty.proc

    def read_until_idle(self, idle: float = 2.0, hard: float = 30.0) -> str:
        """Read until the stream goes quiet.

        The Site CLI repaints its prompt continuously and prints no
        end-of-output marker, so silence is the only usable completion signal.
        """
        deadline = time.time() + hard
        last = time.time()
        out = ""
        while time.time() < deadline:
            ready, _, _ = select.select([self.fd], [], [], 0.3)
            if ready:
                try:
                    chunk = os.read(self.fd, 65536)
                except OSError:
                    break
                if not chunk:
                    break
                out += chunk.decode("utf-8", "replace")
                last = time.time()
            elif time.time() - last > idle:
                break
        return out

    def send(self, keys: str) -> None:
        """Write keystrokes to the pty."""
        self.pty.send(keys)

    def wait_for_prompt(self, hard: float = 60.0) -> str:
        """Read until the prompt appears.

        The banner queries vpm for system info and is slow, so waiting for the
        prompt string beats guessing a delay.
        """
        deadline = time.time() + hard
        out = ""
        while time.time() < deadline:
            out += self.read_until_idle(idle=1.5, hard=8)
            if PROMPT in strip_ansi(out):
                return out
        message = "Site CLI prompt never appeared"
        raise TimeoutError(message)

    def scroll_menu(
        self,
        opener: str,
        label: str = "menu",
        max_scrolls: int = 200,
        patience: int = 20,
    ) -> dict[str, str]:
        """Open a completion menu and scroll it to exhaustion.

        Reports progress, because this is the slow part and silence is
        indistinguishable from a stall. The Site CLI repaints continuously, so a
        read can consume its whole `hard` budget rather than ending on idle; with
        an over-generous max_scrolls that turns into tens of minutes of nothing.

        max_scrolls is sized from the largest menu actually observed — 82 commands
        needing about 101 scrolls — plus headroom, not from an arbitrary ceiling.
        """
        self.send(opener)
        self.read_until_idle(idle=1.5, hard=10)
        self.send("\t")
        acc = MenuAccumulator()
        acc.absorb(self.read_until_idle(idle=3.0, hard=20))
        print(f"[{label}] first page: {len(acc.commands)} commands")
        barren = 0
        for index in range(max_scrolls):
            self.send("\x1b[B")
            if acc.absorb(self.read_until_idle(idle=0.4, hard=5)):
                barren = 0
            else:
                barren += 1
                if barren >= patience:
                    print(
                        f"[{label}] exhausted after {index + 1} scrolls: "
                        f"{len(acc.commands)} commands"
                    )
                    break
            if (index + 1) % 25 == 0:
                print(f"[{label}] {index + 1} scrolls, {len(acc.commands)} commands")
        else:
            print(
                f"[{label}] hit the {max_scrolls}-scroll ceiling with "
                f"{len(acc.commands)} commands — the menu may be truncated"
            )
        # Abandon the half-typed line rather than submitting it.
        self.send("\x03")
        self.read_until_idle(idle=1.0, hard=5)
        return acc.commands

    def run(self, command: str, idle: float = 5.0, hard: float = 60.0) -> str:
        """Run one allow-listed command and return its output, stripped of ANSI."""
        guard(command)
        self.send(
            f"execcli {command}" if command not in {"health", "diagnosis"} else command
        )
        self.read_until_idle(idle=0.8, hard=5)
        self.send("\r")  # separate write, or the newline becomes a literal
        return strip_ansi(self.read_until_idle(idle=idle, hard=hard))

    def close(self) -> None:
        """Interrupt any half-typed line, then end the session in bounded time."""
        with contextlib.suppress(OSError):
            self.send("\x03")
            self.read_until_idle(idle=0.5, hard=3)
        self.pty.close()


# --- entry point -------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    """Enumerate the command surface of one node and write the catalog."""
    parser = argparse.ArgumentParser(
        description=(__doc__ or "").split("\n", maxsplit=1)[0]
    )
    parser.add_argument("--node", required=True, help="CE SLI address, e.g. 10.0.3.5")
    parser.add_argument(
        "--jump", default="", help="jump host inside the VNet, e.g. azureuser@1.2.3.4"
    )
    parser.add_argument("--key", default=str(Path("~/.ssh/id_ed25519").expanduser()))
    parser.add_argument("--site", default="", help="recorded as provenance only")
    parser.add_argument("--build", default="", help="recorded as provenance only")
    parser.add_argument(
        "--site-state",
        default="",
        help="site_state at capture time. A menu read while PROVISIONING may be "
        "a reduced set, so an absent command is not evidence of absence.",
    )
    parser.add_argument("--out", default="sitecli/exec-catalog.json")
    args = parser.parse_args(argv)

    session = SiteCliSession(args.node, args.jump, args.key)
    try:
        session.wait_for_prompt()
        top_level = session.scroll_menu("", label="top-level")
        exec_commands = session.scroll_menu("execcli ", label="execcli")
    finally:
        session.close()

    catalog = {
        "_provenance": {
            "node": args.node,
            "site": args.site,
            "build": args.build,
            "site_state": args.site_state,
            "source": "Site CLI completion menu over SSH",
        },
        "top_level": dict(sorted(top_level.items())),
        "execcli": dict(sorted(exec_commands.items())),
        "counts": {"top_level": len(top_level), "execcli": len(exec_commands)},
    }
    with Path(args.out).open("w", encoding="utf-8") as handle:
        json.dump(catalog, handle, indent=2, sort_keys=False)
        handle.write("\n")
    print(
        f"{len(top_level)} top-level and {len(exec_commands)} execcli commands "
        f"-> {args.out}"
    )
    if not args.site_state:
        print("warning: --site-state not recorded; absence of a command proves nothing")
    return 0


if __name__ == "__main__":
    sys.exit(main())
