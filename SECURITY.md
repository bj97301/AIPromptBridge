# Security

AIPromptBridge is experimental local automation software. Treat an Accessibility-enabled instance as a privileged part of your desktop session. Read [RISK_NOTICE.md](RISK_NOTICE.md) before enabling it.

## Boundaries

- The app has no TCP listener, cloud API, telemetry, or automatic login item. Its Unix socket lives in an account-owned directory with mode 0700; the socket has mode 0600. The server checks the connecting user with `getpeereid`.
- Every operational request passes the app's acknowledgment gate. The receipt is local and tied to the SHA-256 digest of the notice and license. It is not a security boundary against processes that already control the same account, and is not identity-verified legal assent.
- A dialog action requires a fresh, single-use ID. The app rechecks the process, dialog identity, visible static text, and controls before an action. A matching label alone does not authorize the effect.
- The app does not read editable field values. Supplied values are sent through local IPC and can remain in process memory. Secret input is accepted through hidden terminal input or stdin, never a password argument.
- OCR and screenshots can contain unrelated private information. Capture is explicit. Selected image files and saved captures pass through private temporary directories, cleaned up by the CLI on ordinary completion. An abrupt process kill can leave temporary files; inspect the private socket directory if that occurs.
- Some macOS controls refuse Accessibility access. This project does not modify the TCC database, elevate privileges, synthesize input as a protected-control fallback, or bypass agent safety denials.

## Safe operation

Use explicit app and dialog targets, authorize the actual effect, and verify the result. Start with the built-in dummy dialog. Do not connect arbitrary downloaded scripts or expose the socket through a network bridge. Use a separate macOS account or test machine when evaluating an untrusted agent. Keep backups before testing consequential operations.

Pause CLI access or quit the app to stop new requests. An operation already delivered may still finish. The CLI can relaunch a quit app, so use Pause CLI access or revoke macOS permissions when you need persistent blocking.

## Report a vulnerability

Use this repository's private vulnerability reporting feature under the Security tab when available. Do not put credentials, screenshots of private windows, or exploit details involving another person's system in a public issue. If private reporting is unavailable, open a public issue containing only a request for a private contact channel.

No response time, security audit, or support commitment is promised. The absence of a reported vulnerability is not evidence that the software is secure.
