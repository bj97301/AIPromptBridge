#!/usr/bin/env python3
"""Check live-test orchestration without accessing a real password or prompt."""
from copy import deepcopy
import unittest
from unittest.mock import Mock, call, patch

from test_security_agent import APP, TestFailure, TestUnavailable, run


SETUP = {
    "acknowledgment": {"accepted": True}, "accessibility": True,
    "allowed_operations": {"saved_password": True, "buttons": True, "ask_before_password": False},
    "saved_password": {"saved": True},
}
FILLED = {"status": "delivered", "secret_returned": False}


def scan_result(ticket="before", fingerprint="same", pid=123):
    return {
        "status": "ok", "coverage": [{"status": "inspected", "windows": 1}],
        "dialogs": [{
            "id": ticket, "app": APP, "source": "accessibility", "pid": pid,
            "fingerprint": fingerprint, "text": ["Finder wants to move Fixture.app to the Trash."],
            "fields": [{"id": "field-2", "secure": True, "enabled": True, "writable": True}],
            "buttons": [{"label": label, "enabled": True, "press_supported": True}
                        for label in ("OK", "Cancel")],
        }],
    }


class SavedPasswordFlow(unittest.TestCase):
    def setUp(self):
        # Keep simulated delivery messages out of the live-test evidence stream.
        self.output = patch("test_security_agent.print")
        self.output.start()
        self.addCleanup(self.output.stop)

    def test_saved_flow_uses_app_storage_and_fresh_ticket_then_verifies_closure(self):
        bridge = Mock(side_effect=[SETUP, scan_result(), FILLED, scan_result("after"),
                                   {"status": "delivered"}, {"status": "ok", "coverage": [], "dialogs": []}])
        run("Fixture.app", saved=True, call=bridge)
        self.assertEqual(bridge.call_args_list, [
            call("status"), call("scan", "--app", APP),
            call("fill", "before", "--field", "field-2", "--saved"),
            call("scan", "--app", APP), call("press", "after", "--button", "OK"),
            call("scan", "--app", APP),
        ])

    def test_default_is_read_only(self):
        bridge = Mock(side_effect=[SETUP, scan_result()])
        run("Fixture.app", call=bridge)
        self.assertEqual(bridge.call_count, 2)

    def test_missing_stored_password_stops_before_input(self):
        setup = deepcopy(SETUP)
        setup["saved_password"]["saved"] = False
        bridge = Mock(return_value=setup)
        with self.assertRaises(TestUnavailable):
            run("Fixture.app", saved=True, call=bridge)
        self.assertEqual(bridge.call_args_list, [call("status")])

    def test_no_live_prompt_is_unavailable_and_never_filled(self):
        bridge = Mock(side_effect=[SETUP, {"status": "ok", "coverage": [], "dialogs": []}])
        with self.assertRaises(TestUnavailable):
            run("Fixture.app", saved=True, call=bridge)
        self.assertEqual(bridge.call_count, 2)

    def test_unrecognized_or_ambiguous_open_prompt_fails_before_input(self):
        for count in (0, 2):
            with self.subTest(dialogs=count):
                state = scan_result()
                state["dialogs"] *= count
                bridge = Mock(side_effect=[SETUP, state])
                with self.assertRaises(TestFailure):
                    run("Fixture.app", saved=True, call=bridge)
                self.assertEqual(bridge.call_count, 2)

    def test_denial_or_unverified_input_never_submits(self):
        for result in ({"status": "denied"}, {"status": "unverified"}, {"status": "delivered"}):
            with self.subTest(result=result):
                bridge = Mock(side_effect=[SETUP, scan_result(), result])
                with self.assertRaises(TestFailure):
                    run("Fixture.app", saved=True, call=bridge)
                self.assertEqual(bridge.call_count, 3)

    def test_replaced_dialog_or_reused_ticket_never_submits(self):
        for fresh in (scan_result("after", fingerprint="changed"),
                      scan_result("after", pid=999), scan_result("before")):
            with self.subTest(fresh=fresh):
                bridge = Mock(side_effect=[SETUP, scan_result(), FILLED, fresh])
                with self.assertRaises(TestFailure):
                    run("Fixture.app", saved=True, call=bridge)
                self.assertEqual(bridge.call_count, 4)

    def test_incomplete_scan_cannot_claim_prompt_closed(self):
        uncertain = {"status": "ok", "dialogs": [], "coverage": [{"status": "unavailable"}]}
        bridge = Mock(side_effect=[SETUP, scan_result(), FILLED, scan_result("after"),
                                   {"status": "delivered"}, uncertain])
        with self.assertRaises(TestFailure):
            run("Fixture.app", saved=True, call=bridge)
        self.assertEqual(sum(args.args[0] == "press" for args in bridge.call_args_list), 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
