#!/usr/bin/env python3
"""Exercise the packaged app's real test dialog and its CLI transport."""
import json
from pathlib import Path
import socket
import subprocess
import time
import unittest
import os

CLI = Path(__file__).resolve().parents[1] / "aipromptbridge"


def run(*args, secret=None):
    process = subprocess.run([str(CLI), *args], input=secret, text=True, capture_output=True, timeout=35)
    return process.returncode, json.loads(process.stdout), process.stdout + process.stderr


class Integration(unittest.TestCase):
    def setUp(self):
        _, state, _ = run("demo", "scan")
        if state.get("dialogs"):
            run("demo", "press", state["dialogs"][0]["id"], "--button", "Cancel")

    def tearDown(self):
        self.setUp()

    def dialog(self):
        code, _, _ = run("demo", "show")
        self.assertEqual(code, 0)
        _, result, _ = run("demo", "scan")
        return result["dialogs"][0]

    def test_native_continue_and_cancel(self):
        for label, expected in [("Continue", "continued"), ("Cancel", "cancelled")]:
            dialog = self.dialog()
            code, result, _ = run("demo", "press", dialog["id"], "--button", label)
            self.assertEqual(code, 0)
            self.assertEqual(result["result"], expected)
            _, after, _ = run("demo", "scan")
            self.assertEqual(after["dialogs"], [])

    def test_hidden_field_and_single_use(self):
        dialog = self.dialog()
        dummy = "bridge-test-dummy-\u2713-5827"
        code, result, raw = run("demo", "fill", dialog["id"], "--field", "field-1", "--secret-stdin", secret=dummy + "\n")
        self.assertEqual(code, 0)
        self.assertFalse(result["secret_returned"])
        self.assertNotIn(dummy, raw)
        code, stale, _ = run("demo", "press", dialog["id"], "--button", "Continue")
        self.assertEqual(code, 1)
        self.assertEqual(stale["status"], "stale")
        _, after, raw = run("demo", "scan")
        self.assertNotIn(dummy, raw)
        fresh = after["dialogs"][0]
        _, result, raw = run("demo", "press", fresh["id"], "--button", "Continue")
        self.assertTrue(result["field_was_nonempty"])
        self.assertNotIn(dummy, raw)

    def test_exact_label_and_closed_dialog_rejected(self):
        dialog = self.dialog()
        code, result, _ = run("demo", "press", dialog["id"], "--button", "continue")
        self.assertEqual(code, 1)
        self.assertEqual(result["status"], "not_found")
        _, state, _ = run("demo", "scan")
        self.assertEqual(len(state["dialogs"]), 1)
        run("demo", "press", state["dialogs"][0]["id"], "--button", "Cancel")
        code, result, _ = run("demo", "press", state["dialogs"][0]["id"], "--button", "Continue")
        self.assertEqual(code, 1)
        self.assertEqual(result["status"], "stale")

    def test_expired_request_cannot_open_dialog(self):
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
            connection.settimeout(5)
            connection.connect(f"/tmp/io.github.bj97301.aipromptbridge-{os.getuid()}/control.sock")
            connection.sendall(json.dumps({"op": "demo.show", "deadline": time.time() - 1}).encode() + b"\n")
            response = json.loads(connection.recv(4096))
        self.assertEqual(response["status"], "invalid_request")
        _, state, _ = run("demo", "scan")
        self.assertEqual(state["dialogs"], [])

    def test_missing_permissions_are_explicit(self):
        _, status, _ = run("status")
        if not status["accessibility"]:
            code, result, _ = run("scan")
            self.assertEqual(code, 1)
            self.assertEqual(result["status"], "permission_required")
        if not status["screen_recording"]:
            code, result, _ = run("capture")
            self.assertEqual(code, 1)
            self.assertEqual(result["status"], "permission_required")


if __name__ == "__main__":
    import sys
    _, setup, _ = run("status")
    if not setup.get("acknowledgment", {}).get("accepted"):
        print("SKIP: Review and acknowledge the notices in AIPromptBridge before operational tests.")
        sys.exit(77)
    unittest.main(verbosity=2)
