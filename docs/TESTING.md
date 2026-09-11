# Tests

Build the app first. Read and acknowledge its notices in the UI before running the operational tests.

```sh
python3 tests/test_integration.py
python3 tests/test_accessibility.py
python3 tests/test_consent.py
python3 tests/test_skills.py
python3 tests/test_passwords.py
python3 tests/test_security_agent_flow.py
# Optional: actual Keychain round-trip with a unique temporary dummy item
python3 tests/test_passwords.py --keychain
```

The integration suite uses actual AppKit controls inside the app. It checks Continue, Cancel, hidden dummy input, exact labels, consumed IDs, expired requests, and explicit permission errors. Enable prompt buttons first. Its unattended input case skips when manual input is disabled or ask-first is enabled. It does not establish cross-app access.

The Accessibility suite builds a separate native fixture. It finds the fixture's real AX dialog, sets a dummy value in its secure field, verifies the exact dummy value reached that app, and tests Continue and Cancel. It exits 77 when Accessibility permission is missing or input settings require interaction. For this unattended fixture, enable buttons and manual input and disable ask-first; restore your preferred settings afterward. Its fixture waits briefly before exiting so macOS can return the AXPress response.

The consent suite checks notice digest and receipt handling in an isolated preferences suite. It does not accept notices for the installed app or change macOS permissions.

The skill suite uses a temporary home to check shared and T3 destinations, safe reinstall and updates, backups, preservation of customized skills, symlink refusal, missing resources, and partial failures. It also checks the portable ZIP for machine-specific paths and tests the exported CLI's app lookup and help. It never installs into the real account's skill folders.

The same suite checks CLI destination selection, validation before writes, configured homes, partial-result exit codes, and export without overwriting. `python3 tests/test_skill_cli.py` exercises the running packaged app through the actual CLI, using a temporary custom skills directory. It verifies install, repeat install, preservation of an edited copy, and ZIP export while leaving control permissions and password settings unchanged.

The password suite checks permission defaults, manual and saved input, native-only approval, denial, replay, cancellation, expiry, target changes, revoked access, and CLI polling. It uses isolated preferences and a fake credential store. With `--keychain`, it also saves, replaces, reads, and deletes a unique temporary dummy Keychain item. It never touches the app's saved password.

CI runs consent, skill, password policy, and simulated Finder password-flow suites on both Apple Silicon and Intel. It also runs `test_gate.py` against the fresh, unacknowledged app and `test_skill_cli.py` against a temporary destination. No workflow accepts notices or grants UI permissions. The native dialog, cross-app Accessibility, and real Keychain suites remain local checks. Before uploading a download, `test_distribution.py` extracts the ZIP and verifies its checksum, code signature, CPU architecture, CLI execution and app discovery, notices, and portable skill. Both architectures must pass before publication.

For native approval QA, use `aipromptbridge demo show`, scan its ID, and request `demo fill ID --field field-1 --saved` or manual dummy input. Verify Deny leaves the field empty, Allow once fills it, and the CLI returns only a result. Delete any test password stored through the app and restore ask-first afterward. Do not automate approval for a real credential.

Local development QA on 2026-09-09 verified the packaged storage form, saving a disposable dummy password, native denial with the test field remaining empty, and one-time approval of both saved and manual dummy input. The five native integration tests passed, including hidden input with ask-first temporarily disabled. Direct socket tests confirmed all disabled operation gates and the absence of approval, credential-export, and permission-change commands. The temporary password was deleted and ask-first restored. After removing and re-adding the current app in Accessibility, a separate native fixture received the exact dummy secure-field value and passed Continue and Cancel through the installed skill's CLI. No time-zone setting was changed.

A predecessor development build was also checked against a live macOS sign-in confirmation and a real System Settings password sheet. The sign-in confirmation closed after an exact CLI button press. The password sheet accepted a dummy value through AX and received one deliberately invalid submission. That earlier test did not verify successful authentication. Live full-display capture coverage is still pending; image OCR was verified separately.

## Real System Settings authentication

On 2026-09-09, an explicitly authorized local test of AIPromptBridge 0.1.0 on macOS 26.6.2, build 25G83, successfully used the app's existing saved Keychain password to authenticate to System Settings. Accessibility, prompt buttons, and saved input were already enabled; ask-first was already off. The test preserved these choices.

1. Recorded automatic time zone as on and the current time zone.
2. Clicked **Set time zone automatically using your current location** to open the Date & Time password sheet.
3. Used the installed skill's CLI to scan `com.apple.systempreferences`. It found the sheet's writable secure Password field and exact Unlock button.
4. Called `fill DIALOG_ID --field field-2 --saved`. The app returned `delivered` with `secret_returned: false`.
5. Scanned again for a fresh dialog ID and called `press DIALOG_ID --button Unlock`.
6. Verified in System Settings that the authentication sheet closed and automatic time zone changed to off.
7. Restored automatic time zone to on and verified that the time zone, automatic date/time, and 24-hour display settings remained unchanged.

The password stayed inside the app's Keychain-to-field path and was not extracted, placed in command arguments, or returned to the CLI. No screenshot containing entered password text was saved. The saved-password status and the app's permissions were unchanged afterward. This verifies the tested Date & Time sheet; other system prompts still need individual compatibility checks.

The routine test suites need no real password, external account, or system setting change. Use their dummy fixtures for routine testing. The optional live Finder test below can use the app's stored password when explicitly requested with `--saved`.

## Finder authentication window regression

On 2026-09-10, the live Finder prompt to move `BatteryJesusDev.app` to the Trash was exposed by `com.apple.SecurityAgent` as `AXWindow` / `AXStandardWindow`, with `AXModal=false`. Its Password field was an enabled, writable `AXSecureTextField`. The old scanner returned no dialogs because it only recognized sheets, dialog subroles, and modal elements.

Discovery and action revalidation now also recognize SecurityAgent's windows. Ordinary windows owned by other apps retain the existing detection rules. Password delivery still uses the selected secure Accessibility field, the app's existing Keychain path, and the existing operation and approval settings.

With that specific Finder prompt already open, run the read-only regression check:

```sh
python3 tests/test_security_agent.py --expect-text 'BatteryJesusDev.app'
```

The default test checks the prompt's identity, secure-field availability, absence of returned field values, and OK/Cancel buttons without filling or submitting. It failed against the original running app with zero matching dialogs. It exits 77 if the app needs acknowledgment or Accessibility permission, or no live SecurityAgent window is open. An open window that the scanner fails to recognize remains a test failure. Use a specific text fragment from the actual target when testing another Finder prompt.

To include the stored password and submit the matching Finder operation:

```sh
python3 tests/test_security_agent.py --expect-text 'BatteryJesusDev.app' --saved
```

Use this mode only for an already-open prompt whose displayed operation you intend to authorize. For this example, pressing OK allows Finder to move the app to the Trash. The test checks that saved input and buttons are enabled and a password is stored. It calls `fill ... --saved`, checks `secret_returned: false`, then rescans and verifies the process and dialog fingerprint before pressing the exact OK button with a fresh ticket. It polls for closure for up to five seconds and never retries password entry or submission. An incomplete scan cannot count as closure. Verify the resulting file operation in Finder separately.

The saved password stays in the app's Keychain-to-field path. The test does not extract it, save a replacement, change permissions, or use it in a dummy fixture. If ask-first is enabled, the CLI waits for the user's native approval; denial stops the test. This live mode is not part of unattended CI. `test_security_agent_flow.py` checks the command sequence, changed or ambiguous targets, denial, and incomplete scans using fake responses without any credential access.

After the user authenticated the Accessibility permission change and the rebuilt app reported access restored, the same regression check passed against the live Finder prompt. The updated CLI then delivered the app's saved Keychain password to its secure Password field with `secret_returned: false`. A fresh scan supplied a new ticket for the exact `OK` press. The prompt closed, the next scan returned no SecurityAgent dialogs, and `/Users/Bryan/.Trash/BatteryJesusDev.app` existed while `/Applications/BatteryJesusDev.app` did not. This verifies successful password entry and authentication for this Finder prompt, including action-time ticket revalidation. The password was never extracted or returned to the CLI.
