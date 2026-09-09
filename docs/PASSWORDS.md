# Allowed actions and passwords

Open **Allowed actions…** in the app or menu. Inspection remains available after risk acknowledgment. Button presses default to on; manual field input, saved-password input, and capture/OCR default to off. These are separate app-enforced permissions. CLI callers cannot change them.

Enabling manual input offers a secure password form. Enter the password and confirmation, then choose **Save & allow CLI use**, or keep the current settings for manual input only. The app never displays the saved value afterward. Saving enables saved-password input; it does not disable approval.

## Choose the source

```sh
./aipromptbridge fill ID --field field-1 --secret-prompt
./aipromptbridge fill ID --field field-1 --secret-stdin
./aipromptbridge fill ID --field field-1 --saved
```

Use exactly one source. `--secret-prompt` collects hidden terminal input. `--secret-stdin` reads a trusted provider's pipe. `--saved` sends no password through the CLI: the app reads its own Keychain item and fills the selected secure field. There is no CLI command to retrieve, save, replace, or delete the stored password.

Saved-password input is restricted to fields identified as secure by Accessibility. Manual input covers both password and ordinary text fields so an incorrectly classified field cannot evade the permission or approval checks. A secure field does not establish that the receiving app is trustworthy.

## Ask before each use

**Ask me before each password use** defaults to on and applies to manual and saved input. The app displays a separate approval window identifying the target and source, with **Deny** and **Allow once**. An AI agent must ask the user and wait for their choice; it must not operate the approval window on their behalf.

The CLI prints a waiting message to stderr and keeps its final JSON result on stdout. Direct IPC clients receive `approval_required` with a random request ID and expiration, then poll `approval.result`. The only other approval operation is `approval.cancel`. There is no approve operation or request flag that can override the setting.

Each approval applies to one consumed dialog ID and field, and expires with that ID, at most 60 seconds from scanning. The app rechecks the target before accessing the saved credential and before writing. Denial, expiry, cancellation, changed permissions, or revoked acknowledgment prevents delivery. Changing access settings cancels pending requests and invalidates dialog IDs. Only one password request can wait at a time. A completed result can be collected once.

Disable Ask first only if you intend to let permitted local software enter values without an additional app confirmation. Keychain access controls and system restrictions still apply. This setting does not authorize a consequential action or submit the target's dialog.

## Storage

The app uses a local, non-synchronizing macOS Keychain generic-password item with an access list restricted to the creating app. It uses the file-based Keychain implementation so locally signed builds can work without Apple team entitlements. [Apple's Keychain implementation notes](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains) describe the distinction.

Only non-secret capability settings are stored in preferences. Passwords are not written into skill packages, logs, command arguments, or response JSON. They exist briefly in app memory and then in the destination field; complete erasure of every Swift/Python memory copy is not guaranteed.

A locked Keychain or changed app signature can refuse access. The app reports an error rather than bypassing access controls. Use a stable signing identity for repeated builds and resolve Keychain authorization directly in macOS if needed. **Delete saved password** removes only AIPromptBridge's own item and disables saved input.

App preferences and native approval windows are not an isolation boundary against software that already controls the same macOS account or UI. Keep agent approval rules in place and connect only tools you trust.
