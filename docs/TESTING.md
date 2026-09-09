# Tests

Build the app first. Read and acknowledge its notices in the UI before running the operational tests.

```sh
python3 tests/test_integration.py
python3 tests/test_accessibility.py
python3 tests/test_consent.py
python3 tests/test_skills.py
python3 tests/test_passwords.py
# Optional: actual Keychain round-trip with a unique temporary dummy item
python3 tests/test_passwords.py --keychain
```

The integration suite uses actual AppKit controls inside the app. It checks Continue, Cancel, hidden dummy input, exact labels, consumed IDs, expired requests, and explicit permission errors. Enable prompt buttons first. Its unattended input case skips when manual input is disabled or ask-first is enabled. It does not establish cross-app access.

The Accessibility suite builds a separate native fixture. It finds the fixture's real AX dialog, sets a dummy value in its secure field, verifies the exact dummy value reached that app, and tests Continue and Cancel. It exits 77 when Accessibility permission is missing or input settings require interaction. For this unattended fixture, enable buttons and manual input and disable ask-first; restore your preferred settings afterward. Its fixture waits briefly before exiting so macOS can return the AXPress response.

The consent suite checks notice digest and receipt handling in an isolated preferences suite. It does not accept notices for the installed app or change macOS permissions.

The skill suite uses a temporary home to check shared and T3 destinations, safe reinstall and updates, backups, preservation of customized skills, symlink refusal, missing resources, and partial failures. It also checks the portable ZIP for machine-specific paths and tests the exported CLI's app lookup and help. It never installs into the real account's skill folders.

The same suite checks CLI destination selection, validation before writes, configured homes, partial-result exit codes, and export without overwriting. `python3 tests/test_skill_cli.py` exercises the running packaged app through the actual CLI, using a temporary custom skills directory. It verifies install, repeat install, preservation of an edited copy, and ZIP export while leaving control permissions and password settings unchanged.

The password suite checks permission defaults, manual and saved input, native-only approval, denial, replay, cancellation, expiry, target changes, revoked access, and CLI polling. It uses isolated preferences and a fake credential store. With `--keychain`, it also saves, replaces, reads, and deletes a unique temporary dummy Keychain item. It never touches the app's saved password.

CI runs consent, skill, and password policy suites on both Apple Silicon and Intel. It also runs `test_gate.py` against the fresh, unacknowledged app and `test_skill_cli.py` against a temporary destination. No workflow accepts notices or grants UI permissions. The native dialog, cross-app Accessibility, and real Keychain suites remain local checks. Before uploading a download, `test_distribution.py` extracts the ZIP and verifies its checksum, code signature, CPU architecture, CLI execution and app discovery, notices, and portable skill. Both architectures must pass before publication.

For native approval QA, use `aipromptbridge demo show`, scan its ID, and request `demo fill ID --field field-1 --saved` or manual dummy input. Verify Deny leaves the field empty, Allow once fills it, and the CLI returns only a result. Delete any test password stored through the app and restore ask-first afterward. Do not automate approval for a real credential.

Local development QA on 2026-09-09 verified the packaged storage form, saving a disposable dummy password, native denial with the test field remaining empty, and one-time approval of both saved and manual dummy input. The five native integration tests passed, including hidden input with ask-first temporarily disabled. Direct socket tests confirmed all disabled operation gates and the absence of approval, credential-export, and permission-change commands. The temporary password was deleted and ask-first restored. After removing and re-adding the current app in Accessibility, a separate native fixture received the exact dummy secure-field value and passed Continue and Cancel through the installed skill's CLI. No time-zone setting was changed.

A predecessor development build was also checked against a live macOS sign-in confirmation and a real System Settings password sheet. The sign-in confirmation closed after an exact CLI button press. The password sheet accepted a dummy value through AX and received one deliberately invalid submission. Successful authentication with a real password was not verified. Live full-display capture coverage is still pending; image OCR was verified separately.

No test needs an actual password, external account, or permission change. Use the provided fixtures instead of submitting invalid credentials to a real account.
