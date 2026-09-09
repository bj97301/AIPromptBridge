# Before you enable AIPromptBridge

Notice version: 2026-09-09.1

AIPromptBridge is experimental software that lets local programs operate parts of your Mac's user interface. An AI agent, script, or other program can make a mistake even when a command executes correctly. Read this notice and the accompanying Apache 2.0 LICENSE before enabling the app.

## What can go wrong

- Pressing a button can delete data, spend money, send information, install software, approve access, change security settings, or start another operation you did not intend. Exact labels and expiring IDs reduce mistakes; they do not determine whether an action is wise or authorized.
- Accessibility permission gives this app broad access to other apps. Programs running as your macOS user can call its local socket after you enable it. The socket is not an isolation boundary between trusted and untrusted programs on the same account.
- Passwords and other supplied text can reach the wrong destination if you choose the wrong dialog. Values remain briefly in process memory. Neither Swift nor Python guarantees that every copy is erased. Never put actual credentials in command arguments, source code, chat messages, logs, screenshots, or bug reports.
- Screen capture and OCR can expose everything visible on a display, including information unrelated to the target alert. Saved captures remain until you delete them. OCR can misread words and coordinates.
- A request can time out after an action has already happened. Retrying can repeat the effect. A successful command does not prove the intended business operation finished.
- Some macOS authentication and permission interfaces reject automation. This tool does not grant permission to bypass system protections, third-party terms, an agent's safety controls, or another person's consent.

## Your responsibility

Use this software only on systems and accounts you own or are authorized to control. Review each consequential action, limit the permissions you grant, keep recoverable backups, and verify outcomes in the target app. Do not rely on it where an incorrect action could cause physical injury or other serious harm. You are responsible for the agents and scripts you connect and for deciding whether this software is suitable for your use.

## No warranty; limits on liability

The software is provided on an AS IS basis, without warranties or conditions, as stated in Sections 7 and 8 of LICENSE. To the fullest extent permitted by applicable law, Bryan Joseph, the copyright holders, and contributors disclaim liability for losses, claims, and damages arising from use of, or inability to use, the software. This includes unintended actions, data loss, disclosure of information, credential misuse, financial loss, and interruption of service.

Nothing in this notice excludes or restricts a right, remedy, or liability that applicable law does not allow to be excluded or restricted. LICENSE governs the copyright and patent permissions. This notice explains risks and the license disclaimers; it does not add restrictions to those license grants.

## Acknowledgment in the supplied app

By checking the acknowledgment and choosing Enable AIPromptBridge, you confirm that you have read this notice and LICENSE, understand these risks, choose to proceed at your own risk, and acknowledge and accept the warranty disclaimers and liability limitations to the fullest extent permitted by applicable law. If you disagree, leave the app disabled and quit it.

The supplied app blocks operational CLI requests until this acknowledgment is recorded for the current notice and license. It stores only the document digest, notice version, method, and time locally. It does not transmit a signed agreement or verify a person's identity. A public source-code fork can alter or remove this behavior. No acknowledgment or disclaimer guarantees that a claim cannot be brought or that every limitation will be enforceable.
