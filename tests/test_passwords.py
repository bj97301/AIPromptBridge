#!/usr/bin/env python3
"""Policy/approval tests use an isolated preferences suite and a fake password store.
Pass --keychain to also create and remove one uniquely named real Keychain dummy item.
"""
from contextlib import redirect_stdout, redirect_stderr
import importlib.machinery
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="aipromptbridge-passwords-") as temporary:
    binary = Path(temporary) / "password-tests"
    sources = [ROOT / "Sources" / name for name in ["OperationPolicy.swift", "PasswordStore.swift", "PasswordRequests.swift"]]
    subprocess.run(["xcrun", "swiftc", *map(str, sources), str(ROOT / "tests/PasswordPolicyTests.swift"), "-o", str(binary), "-framework", "Security"], check=True)
    subprocess.run([str(binary)], check=True)
    if "--keychain" in sys.argv:
        keychain = Path(temporary) / "keychain-tests"
        subprocess.run(["xcrun", "swiftc", *map(str, sources[:2]), str(ROOT / "tests/KeychainTests.swift"), "-o", str(keychain), "-framework", "Security"], check=True)
        subprocess.run([str(keychain)], check=True)

loader = importlib.machinery.SourceFileLoader("password_cli", str(ROOT / "cli/aipromptbridge"))
spec = importlib.util.spec_from_loader(loader.name, loader)
cli = importlib.util.module_from_spec(spec)
loader.exec_module(cli)
setup = {"status": "ok", "acknowledgment": {"accepted": True}, "allowed_operations": {"saved_password": True, "manual_input": False}}
calls = []
def request(payload):
    calls.append(payload.copy())
    return setup if payload["op"] == "status" else {"status": "delivered", "secret_returned": False}
out = io.StringIO()
with patch.object(sys, "argv", ["bridge", "fill", "dialog-id", "--field", "field-1", "--saved"]), patch.object(cli, "request", request), patch.object(cli, "secret_from_args", side_effect=AssertionError("Saved input must not collect a secret")), redirect_stdout(out):
    assert cli.main() == 0
assert calls[-1] == {"op": "fill", "id": "dialog-id", "field": "field-1", "source": "saved"}
calls.clear()
with patch.object(sys, "argv", ["bridge", "fill", "dialog-id", "--field", "field-1", "--secret-stdin"]), patch.object(cli, "request", request), patch.object(cli, "secret_from_args", side_effect=AssertionError("Disabled input must not read stdin")), redirect_stdout(io.StringIO()):
    assert cli.main() == 1
assert len(calls) == 1
with patch.object(cli, "request", return_value={"status": "approval_denied"}) as poll, patch.object(cli.time, "sleep"), redirect_stderr(io.StringIO()):
    result = cli.wait_for_password_approval({"status": "approval_required", "request_id": "test", "expires_at": cli.time.time() + 50})
assert result["status"] == "approval_denied"
assert poll.call_args.args[0] == {"op": "approval.result", "id": "test"}
print("PASS: saved CLI request has no secret, disabled manual input is not collected, and approval polling cannot approve")
