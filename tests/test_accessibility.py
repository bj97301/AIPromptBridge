#!/usr/bin/env python3
"""Build a separate AppKit fixture and verify cross-app AX. Needs Accessibility."""
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "aipromptbridge"


def request(*args, secret=None, check=True):
    process = subprocess.run([str(CLI), *args], input=secret, text=True, capture_output=True, timeout=35)
    value = json.loads(process.stdout)
    if check and process.returncode:
        raise RuntimeError(json.dumps(value))
    return value


def main():
    setup = request("status")
    if not setup.get("acknowledgment", {}).get("accepted"):
        print("SKIP: Review and acknowledge the notices in AIPromptBridge first.")
        return 77
    if not setup["accessibility"]:
        print("SKIP: AIPromptBridge Accessibility permission is not enabled.")
        return 77
    with tempfile.TemporaryDirectory(prefix="aipromptbridge-ax-test-") as folder:
        root = Path(folder)
        app = root / "AIPromptBridge Fixture.app"
        binary = app / "Contents" / "MacOS" / "Fixture"
        binary.parent.mkdir(parents=True)
        subprocess.run(["xcrun", "swiftc", "-swift-version", "5", str(ROOT / "tests" / "Fixture.swift"), "-o", str(binary), "-framework", "AppKit"], check=True)
        with (app / "Contents" / "Info.plist").open("wb") as file:
            plistlib.dump({"CFBundleIdentifier": "io.github.bj97301.aipromptbridge.fixture", "CFBundleName": "AIPromptBridge Fixture", "CFBundleExecutable": "Fixture", "CFBundlePackageType": "APPL"}, file)
        subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True, capture_output=True)
        for label, expected in [("Continue", "continued"), ("Cancel", "cancelled")]:
            result_path = root / f"{expected}.json"
            process = subprocess.Popen([str(binary), "--result", str(result_path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            try:
                dialog = None
                for _ in range(30):
                    state = request("scan", "--pid", str(process.pid))
                    found = [item for item in state.get("dialogs", []) if "AIPromptBridge external test" in " ".join(item.get("text", [])) or item.get("title") == "AIPromptBridge external test"]
                    if found:
                        dialog = found[0]
                        break
                    time.sleep(0.2)
                assert dialog, f"No fixture dialog found: {state}"
                assert dialog["source"] == "accessibility"
                assert {b["label"] for b in dialog["buttons"]} >= {"Continue", "Cancel"}
                field = next(f for f in dialog["fields"] if f["secure"])
                assert field["writable"], field
                if label == "Continue":
                    filled = request("fill", dialog["id"], "--field", field["id"], "--secret-stdin", secret="fixture-dummy-input\n")
                    assert filled["status"] == "delivered"
                    stale = request("press", dialog["id"], "--button", "Continue", check=False)
                    assert stale["status"] == "stale"
                    dialog = request("scan", "--pid", str(process.pid))["dialogs"][0]
                    assert "fixture-dummy-input" not in json.dumps(dialog)
                delivered = request("press", dialog["id"], "--button", label)
                assert delivered["status"] == "delivered", delivered
                process.wait(timeout=10)
                result = json.loads(result_path.read_text())
                assert result["result"] == expected, result
                assert result["dummy_matched"] == (label == "Continue"), result
                print(f"PASS: cross-app AX {label}; secure input matched={result['dummy_matched']}; value never returned")
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=5)
    return 0


if __name__ == "__main__":
    sys.exit(main())
