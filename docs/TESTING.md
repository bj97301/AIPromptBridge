# Tests

Build the app first. Read and acknowledge its notices in the UI before running the operational tests.

```sh
python3 tests/test_integration.py
python3 tests/test_accessibility.py
python3 tests/test_consent.py
```

The integration suite uses actual AppKit controls inside the app. It checks Continue, Cancel, hidden dummy input, exact labels, consumed IDs, expired requests, and explicit permission errors. It does not establish cross-app access.

The Accessibility suite builds a separate native fixture. It finds the fixture's real AX dialog, sets a dummy value in its secure field, verifies the exact dummy value reached that app, and tests Continue and Cancel. It exits 77 when Accessibility permission is missing. Its fixture waits briefly before exiting so macOS can return the AXPress response.

The consent suite checks notice digest and receipt handling in an isolated preferences suite. It does not accept notices for the installed app or change macOS permissions.

A predecessor development build was also checked against a live macOS sign-in confirmation and a real System Settings password sheet. The sign-in confirmation closed after an exact CLI button press. The password sheet accepted a dummy value through AX and received one deliberately invalid submission. Successful authentication with a real password was not verified. Live full-display capture coverage is still pending; image OCR was verified separately.

No test needs an actual password, external account, or permission change. Use the provided fixtures instead of submitting invalid credentials to a real account.
