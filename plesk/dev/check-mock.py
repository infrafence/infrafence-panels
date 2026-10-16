#!/usr/bin/env python3
"""Checks the mock agent against the agent's reference outputs (fixtures/, from the agent repository).

For every command it compares the reply with the reference: same keys at every level, same exit status,
and the same bytes where the reply carries no timestamp. Run: python3 dev/check-mock.py
"""

import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
MOCK = os.path.join(HERE, "mock-agent")

CASES = [
    # (mode, reference fixture, args, byte-exact)
    ("running", "status", ["status"], False),
    ("running", "bans", ["bans"], False),
    ("running", "allowlist", ["allowlist"], False),
    ("running", "findings", ["findings"], False),
    ("running", "events", ["events"], False),
    ("running", "coexistence", ["coexistence"], True),
    ("running", "sites", ["sites"], True),
    # lifted_until is 30 days from now for a permanent ban, so only the keys are compared.
    ("running", "unban", ["unban", "198.51.100.9", "--actor", "root"], False),
    ("running", "allow", ["allow", "198.51.100.77", "--actor", "root"], True),
    ("running", "disallow", ["disallow", "198.51.100.4", "--actor", "root"], True),
    ("running", "scan", ["scan", "/home/alice/public_html", "--actor", "root"], True),
    ("running", "error", ["unban", "203.0.113.99", "--actor", "root"], True),
    ("running", "error_invalid_ip", ["unban", "198.51.100.0/24", "--actor", "root"], True),
    ("stopped", "status_agent_not_running", ["status"], True),
    ("stopped", "error_agent_not_running", ["bans"], True),
    ("stopped", "error_agent_not_running", ["unban", "198.51.100.9", "--actor", "root"], True),
]


def shape(value):
    if isinstance(value, dict):
        return {k: shape(v) for k, v in value.items()}
    if isinstance(value, list):
        return [shape(value[0])] if value else []
    return None


def main():
    failed = 0
    with tempfile.TemporaryDirectory() as tmp:
        for mode, name, args, exact in CASES:
            env = dict(os.environ, INFRAFENCE_MOCK_MODE=mode, INFRAFENCE_MOCK_STATE=os.path.join(tmp, "state.json"))
            run = subprocess.run([sys.executable, MOCK, "panel", *args, "--json"], capture_output=True, text=True, env=env)
            with open(os.path.join(HERE, "fixtures", name + ".json")) as f:
                reference_text = f.read()
            reference = json.loads(reference_text)
            problems = []
            try:
                reply = json.loads(run.stdout)
            except ValueError:
                problems.append("not JSON: " + run.stdout[:80])
                reply = None
            if reply is not None and shape(reply) != shape(reference):
                problems.append("keys differ")
            if run.returncode != (0 if reference["ok"] else 1):
                problems.append("exit status %d" % run.returncode)
            if exact and run.stdout != reference_text:
                problems.append("bytes differ")
            if run.stderr:
                problems.append("stderr not empty")
            print("%-5s %-8s %-25s %s" % ("FAIL" if problems else "ok", mode, name, " ".join(args) + ("  " + "; ".join(problems) if problems else "")))
            failed += bool(problems)
    print("all checks passed" if not failed else "%d check(s) failed" % failed)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
