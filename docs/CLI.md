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
| `capture [--display ID] [--output-dir NEW_FOLDER]` | Capture and OCR displays; optionally save PNGs |
| `ocr IMAGE` | OCR an existing image, up to 32 MiB |
| `demo show`, `demo scan`, `demo result` | Operate a harmless built-in test dialog |
| `demo press ID --button Continue` | Press a button in the test dialog |
| `demo fill ID --field field-1 --secret-stdin` | Fill the test dialog with a dummy value |

Before acknowledgment, only `status`, `open`, and `risks` are available. The gate is enforced by the app, not just the CLI. Review and accept in the app's UI; there is no remote acknowledgment command. Pause CLI access removes the saved receipt and invalidates outstanding dialog IDs.

`scan` reports the owner app, static text, controls, field capabilities, and inspection coverage. Editable field contents are omitted. An empty result is not proof that no prompt exists. Some prompts are owned by `com.apple.UserNotificationCenter` or another system helper.

IDs expire after 60 seconds and an attempted action consumes the selected ID. Rescan after a field update before pressing a submission button. Watch mode refreshes unchanged IDs every 45 seconds. There is no automatic accept-all mode or mutation retry.

`delivered` means the target accepted the request. `unverified` means the outcome is uncertain. `permission_required`, `acknowledgment_required`, and `user_interaction_required` name missing prerequisites. If the target exits before replying, an action may occur even when the result is uncertain.

Exit codes: 0 for `ok` or `delivered`; 1 for failure or uncertainty; 2 for invalid CLI arguments; 130 for interruption.

Capture directories must be new and have an existing parent. Saved PNGs have mode 0600 inside a mode-0700 directory. OCR coordinates use a top-left origin. Live captures use global display coordinates; existing images use image pixels. OCR text is not a trusted control identity.
