# CLI reference

Run `./aipromptbridge --help` for arguments. Commands return JSON, except usage help. `accept` and `reject` are aliases for `press`; an exact `--button` label is still required.

| Command | Purpose |
| --- | --- |
| `status` | App version, permissions, and acknowledgment state |
| `open` | Show the app's setup window |
| `risks` | Read the bundled notice, license, and acknowledgment state |
| `apps` | List running apps and process IDs |
| `scan [--app BUNDLE_ID \| --pid PID]` | Inspect exposed sheets and dialogs |
| `watch [--app BUNDLE_ID \| --pid PID] [--interval 2]` | Report changes and refresh expiring IDs |
| `press ID --button 'Exact label'` | Press one enabled, uniquely labeled button |
| `fill ID --field field-1 --secret-prompt` | Prompt for hidden field input |
| `fill ID --field field-1 --secret-stdin` | Read field input from a pipe |
| `fill ID --field field-1 --saved` | Ask the app to fill a secure field from Keychain |
| `skills list` | List detected skill destinations with stable target IDs |
| `skills install --all` | Install or update the skill in all detected destinations |
| `skills install --target ID [--target ID]` | Install in selected destinations from the list |
| `skills install --folder PATH` | Add `aipromptbridge` inside an explicit skills directory |
| `skills export --output NEW_ZIP` | Export the portable skill without overwriting a file |
| `capture [--display ID] [--output-dir NEW_FOLDER]` | Capture and OCR displays; optionally save PNGs |
| `ocr IMAGE` | OCR an existing image, up to 32 MiB |
| `demo show`, `demo scan`, `demo result` | Operate a harmless built-in test dialog |
| `demo press ID --button Continue` | Press a button in the test dialog |
| `demo fill ID --field field-1 --secret-stdin` | Fill the test dialog with a dummy value |

Before acknowledgment, only `status`, `open`, `risks`, skill setup commands, and polling/cancellation of an existing approval are available. The gate is enforced by the app, not just the CLI. Review and accept in the app's UI; there is no remote acknowledgment command. Pause CLI access removes the saved receipt and invalidates outstanding dialog IDs and pending password input.

Skill setup shares the GUI installer and preserves edited copies. `skills install` returns `partial_failure` and exit code 1 if any selected destination was skipped or failed. It does not enable computer control or change password settings. [Installer details](AI-SKILL.md).

`status.allowed_operations` reports `buttons`, `manual_input`, `saved_password`, `capture`, and `ask_before_password`. Disabled actions return `operation_not_allowed` before collecting manual input. Saved input sends `source: saved` with no `secret` value. The native app independently checks both the policy and source. [Password approvals](PASSWORDS.md) require Allow once in the app by default; the CLI waits automatically and returns one final JSON response. Denied or expired approvals return `approval_denied` or `expired` without typing. There is no CLI approval command.

`scan` reports the owner app, static text, controls, field capabilities, and inspection coverage. Editable field contents are omitted. An empty result is not proof that no prompt exists. Some prompts are owned by `com.apple.UserNotificationCenter` or another system helper.

IDs expire after 60 seconds and an attempted action consumes the selected ID. Rescan after a field update before pressing a submission button. Watch mode refreshes unchanged IDs every 45 seconds. There is no automatic accept-all mode or mutation retry.

`delivered` means the target accepted the request. `unverified` means the outcome is uncertain. `permission_required`, `acknowledgment_required`, and `user_interaction_required` name missing prerequisites. If the target exits before replying, an action may occur even when the result is uncertain.

Exit codes: 0 for `ok` or `delivered`; 1 for failure or uncertainty; 2 for invalid CLI arguments; 130 for interruption.

Capture directories must be new and have an existing parent. Saved PNGs have mode 0600 inside a mode-0700 directory. OCR coordinates use a top-left origin. Live captures use global display coordinates; existing images use image pixels. OCR text is not a trusted control identity.
