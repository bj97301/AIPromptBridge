#!/usr/bin/env python3
"""Check an open Finder authentication prompt; --saved fills and submits it."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import time


CLI = Path(__file__).resolve().parents[1] / "aipromptbridge"
APP = "com.apple.SecurityAgent"


class TestFailure(RuntimeError):
    pass


class TestUnavailable(RuntimeError):
    pass


def require(condition, message):
    # These checks gate real input, so they must also run under python -O.
    if not condition:
        raise TestFailure(message)


def request(*args):
    # Allow the CLI's native password-approval wait to finish without resending.
    result = subprocess.run([str(CLI), *args], text=True, capture_output=True, timeout=80)
    state = json.loads(result.stdout)
    if state.get("status") in {"permission_required", "acknowledgment_required"}:
        raise TestUnavailable(state["message"])
    require(result.returncode == 0, f"CLI {args[0]} failed: {state.get('status')}")
    return state


def scan(call):
    state = call("scan", "--app", APP)
    require(state.get("status") == "ok", "The scan did not succeed")
    require(all(item.get("status") == "inspected" for item in state["coverage"]),
            "SecurityAgent could not be fully inspected; prompt closure is unverified")
    return state


def matching_dialogs(state, expect_text):
    return [dialog for dialog in state["dialogs"]
            if dialog.get("app") == APP and expect_text in "\n".join(dialog["text"])]


def select_dialog(state, expect_text):
    dialogs = matching_dialogs(state, expect_text)
    require(len(dialogs) == 1, f"Expected one matching SecurityAgent prompt, found {len(dialogs)}")
    dialog = dialogs[0]
    require(dialog["source"] == "accessibility", "The target is not an Accessibility dialog")
    secure = [field for field in dialog["fields"] if field["secure"]]
    require(len(secure) == 1 and secure[0]["writable"] and secure[0]["enabled"],
            "Expected one enabled, writable secure field")
    require(all("value" not in field for field in dialog["fields"]), "A field value was returned")
    for label in ("OK", "Cancel"):
        buttons = [button for button in dialog["buttons"] if button["label"] == label]
        require(len(buttons) == 1 and buttons[0]["enabled"] and buttons[0]["press_supported"],
                f"Expected one enabled {label} button exposing AXPress")
    return dialog, secure[0]


def run(expect_text, saved=False, call=request):
    require(bool(expect_text.strip()), "Specify a nonempty identifying text fragment")
    setup = call("status")
    if not setup.get("acknowledgment", {}).get("accepted") or not setup.get("accessibility"):
        raise TestUnavailable("AIPromptBridge needs acknowledgment and Accessibility access")
    if saved:
        allowed = setup.get("allowed_operations", {})
        if not allowed.get("saved_password") or not allowed.get("buttons"):
            raise TestUnavailable("Saved password input and prompt buttons must already be enabled")
        if not setup.get("saved_password", {}).get("saved"):
            raise TestUnavailable("No password is stored in AIPromptBridge")

    state = scan(call)
    if not state["dialogs"] and not any(item.get("windows", 0) for item in state["coverage"]):
        raise TestUnavailable("No live SecurityAgent prompt is open; no password was entered")
    dialog, field = select_dialog(state, expect_text)
    if not saved:
        print("PASS: live SecurityAgent prompt and writable secure field discovered; no input or button action performed")
        return

    if setup["allowed_operations"].get("ask_before_password", True):
        print("Approve this password use in AIPromptBridge if prompted. The test waits for your decision.", flush=True)
    filled = call("fill", dialog["id"], "--field", field["id"], "--saved")
    require(filled.get("status") == "delivered" and filled.get("secret_returned") is False,
            "Saved password input was not confirmed with a secret-free response; submission stopped")
    fresh, _ = select_dialog(scan(call), expect_text)
    require((fresh["pid"], fresh["fingerprint"]) == (dialog["pid"], dialog["fingerprint"]),
            "The target changed after filling; submission stopped")
    require(fresh["id"] != dialog["id"], "The rescan did not issue a fresh dialog ID")
    pressed = call("press", fresh["id"], "--button", "OK")
    require(pressed.get("status") == "delivered", "OK delivery was not confirmed; submission will not be retried")
    deadline = time.monotonic() + 5
    while True:
        if not matching_dialogs(scan(call), expect_text):
            print("PASS: stored password delivered without returning its value; fresh-ticket OK submitted once; prompt closed")
            return
        require(time.monotonic() < deadline, "Prompt remains open; authentication is unverified and will not be retried")
        time.sleep(0.25)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expect-text", required=True,
                        help="Exact text fragment identifying the already-open prompt")
    parser.add_argument("--saved", action="store_true",
                        help="Use the stored Keychain password, press OK once, and verify closure. This authorizes the operation shown in the matching prompt.")
    args = parser.parse_args()
    try:
        run(args.expect_text, saved=args.saved)
    except TestUnavailable as error:
        print(f"SKIP: {error}")
        return 77
    except (TestFailure, OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(f"FAIL: {error}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
