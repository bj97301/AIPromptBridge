#!/usr/bin/env python3
"""Verify the native IPC gate while the app is unacknowledged or paused."""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
setup = json.loads(subprocess.check_output([str(ROOT / "aipromptbridge"), "status"]))
if setup.get("acknowledgment", {}).get("accepted"):
    print("SKIP: Use Pause CLI access in the app before testing the unacknowledged gate.")
    sys.exit(77)

path = f"/tmp/io.github.bj97301.aipromptbridge-{os.getuid()}/control.sock"
for op in ("apps", "scan", "press", "fill", "capture", "ocr", "demo.show", "demo.scan", "demo.press", "demo.fill", "demo.result", "risks.accept", "skills.approve", "skills.permissions"):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(5)
        connection.connect(path)
        connection.sendall(json.dumps({"op": op, "deadline": time.time() + 10}).encode() + b"\n")
        response = b""
        while b"\n" not in response:
            chunk = connection.recv(4096)
            if not chunk:
                raise RuntimeError("App closed connection without a response")
            response += chunk
        value = json.loads(response)
    assert value["status"] == "acknowledgment_required", (op, value)
print("PASS: direct IPC requests cannot bypass the native acknowledgment gate")
