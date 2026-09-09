# Building

Use macOS 14 or later, Python 3, and the Xcode command-line tools. No third-party Swift or Python packages are required.

```sh
python3 build.py
open AIPromptBridge.app
```

The script compiles for the current Mac's architecture, bundles the license and risk notice, and signs the local app. Without an explicit signing identity it uses an ad-hoc signature. This is a local development build, not a notarized distribution release.

For a stable identity across rebuilds, set `AIPROMPTBRIDGE_SIGNING_IDENTITY` to one of your own code-signing identities. Find them using `security find-identity -v -p codesigning`. Do not publish certificates, private keys, provisioning profiles, or credentials.

Quit AIPromptBridge before rebuilding. Ad-hoc signatures can change after a rebuild; macOS may require you to remove and re-add this app in Accessibility settings. Do not reset other apps' permissions. Moving the app can also require updating the permission entry.

The app and `aipromptbridge` launcher stay in the checkout, so no privileged installer is needed. To invoke it from elsewhere, use its absolute path or add the checkout directory to your shell's PATH. Keep the launcher and source checkout together.

The app bundles `RISK_NOTICE.md`, `LICENSE`, and `NOTICE`. Missing or modified notice/license resources invalidate the saved acknowledgment. A changed notice or license requires acknowledgment again. No CLI flag silently accepts the notices.
