# AIPromptBridge

[![Test, build, and publish](https://github.com/bj97301/AIPromptBridge/actions/workflows/build.yml/badge.svg)](https://github.com/bj97301/AIPromptBridge/actions/workflows/build.yml)

A small macOS menu bar app that lets AI agents and scripts **read alerts, press an exact button, and fill a password or text field through a local CLI**. It uses Apple's Accessibility APIs. Optional screen capture adds on-device OCR when a prompt is hard to inspect.

**This gives local software powerful control of your Mac.** A mistaken command can approve access, expose data, or trigger a destructive action. Read the [risk notice](RISK_NOTICE.md) and [license](LICENSE). The app requires an explicit acknowledgment before its CLI controls work. It is provided as is, without warranties, with liability limited as the license and applicable law permit.

## Install

**[Download a tested app build](https://github.com/bj97301/AIPromptBridge/releases)** for macOS 14 or later. Choose `arm64` for Apple Silicon or `x86_64` for Intel. Unzip it, keep the extracted folder together in a permanent location, quit older copies, and open `AIPromptBridge.app`. Python 3 is required for the CLI; Xcode is not needed for downloads.

Downloads are ad-hoc signed and **not notarized**. macOS may require you to use its **Open Anyway** approval. [Download, checksum, and first-open instructions](docs/DOWNLOADS.md).

To build from source instead, install **Python 3 and Xcode Command Line Tools**. Run `xcode-select --install` if the tools are missing.

```sh
git clone https://github.com/bj97301/AIPromptBridge.git
cd AIPromptBridge
python3 build.py
open AIPromptBridge.app
```

1. Read the notices, check the acknowledgment, and click **Enable AIPromptBridge**.
2. Click **Enable Accessibility** and enable the app in System Settings. Add `AIPromptBridge.app` with the + button if needed.
3. Enable **Screen Recording** only if you want live capture and OCR.
4. Open **Allowed actions…** to allow password input or capture/OCR. Ask-first is enabled for passwords by default.

The app stays in your menu bar. Run the CLI from the extracted or source folder; it starts the app when needed. [Build and signing details](docs/BUILDING.md).

## Use

To teach your AI apps how to use it, run:

```sh
./aipromptbridge skills list
./aipromptbridge skills install --all
```

This installs the skill for local Codex, Cursor, compatible ChatGPT desktop versions, Claude Code, and T3 Code's detected Claude profiles. OpenCode can discover the shared skill too. Use `skills install --target shared` for just the shared agents, or choose IDs from `skills list`. Start a new AI session afterward. Setup works before enabling computer control and preserves customized skills.

The app's **Install AI skill…** button offers the same installer. Use `skills install --folder /path/to/skills` for another compatible app, or `skills export --output ./aipromptbridge-skill.zip` for manual import. Web apps require their own setup; a skill alone cannot connect a cloud agent to your Mac. [Compatibility and details](docs/AI-SKILL.md).

```sh
./aipromptbridge status                 # Check setup and acknowledgment
./aipromptbridge scan                   # Find exposed dialogs and controls
./aipromptbridge press DIALOG_ID --button 'Continue'
./aipromptbridge press DIALOG_ID --button 'Cancel'
./aipromptbridge fill DIALOG_ID --field field-1 --secret-prompt
```

Copy the dialog and field IDs from `scan`. Password entry is hidden in the terminal. For a credential provider, pipe its output to `fill ... --secret-stdin`; never put a password in a shell command. Filling a field does **not** submit it. Scan again, then choose the exact button.

```sh
./aipromptbridge scan --app com.example.app
./aipromptbridge watch --interval 2
./aipromptbridge capture                       # OCR all displays
./aipromptbridge capture --output-dir ./capture-001
./aipromptbridge ocr /path/to/screenshot.png     # No Screen Recording needed
```

Commands return JSON. IDs last 60 seconds and are single-use. `delivered` means the app accepted the request, not that the operation finished. Inspect fresh state before retrying a timeout. System prompts may belong to a macOS helper rather than the requesting app, so try an unfiltered scan if an app-specific scan is empty.

## Choose allowed actions

Open **Allowed actions…** to enable prompt buttons, manual password/text input, saved-password input, or screenshots/OCR separately. Input and capture are off by default. These limits are enforced inside the app, including for direct socket requests.

Enabling manual input offers to save a password in **macOS Keychain**. Saving is optional. **Ask me before each password use** is on by default for both manual and saved input. The app shows the target and requires **Allow once**; the CLI waits and cannot approve itself.

```sh
./aipromptbridge fill DIALOG_ID --field field-1 --secret-prompt  # Manual, hidden input
./aipromptbridge fill DIALOG_ID --field field-1 --saved          # App reads Keychain
```

Saved input is limited to secure fields, and the password is never returned to the CLI. Manage or delete it in **Allowed actions…**. Filling and submitting remain separate actions. [Password and approval details](docs/PASSWORDS.md).

## Limits and stopping

Some custom dialogs, protected password fields, and system permission prompts cannot be automated. OCR identifies text; it does not authorize actions or provide a click fallback. No cloud service or model is included. Other processes running as your user can use the socket after acknowledgment, so connect only tools you trust.

Use **Pause CLI access** in the app to block new requests, or quit it. Revoke Accessibility and Screen Recording in System Settings when no longer needed. [Security details](SECURITY.md) · [Command reference](docs/CLI.md) · [Tests](docs/TESTING.md).

## Report a bug

Choose **Report a bug…** in the app or [open a GitHub issue](https://github.com/bj97301/AIPromptBridge/issues/new). Include your macOS version, steps to reproduce, and what you expected to happen. Reports are public, so remove passwords and private information. Report security vulnerabilities through [private reporting](SECURITY.md#report-a-vulnerability).

Licensed under [Apache 2.0](LICENSE). Copyright 2026 Bryan Joseph and contributors. An acknowledgment cannot waive rights or liabilities that the law makes non-waivable.
