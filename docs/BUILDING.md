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

## CI and downloadable builds

GitHub Actions builds and tests on both Apple Silicon and Intel macOS 15 runners for every branch push and pull request. The workflow can also be started manually. After both architectures pass on `main`, it publishes a new development pre-release under [Releases](https://github.com/bj97301/AIPromptBridge/releases), with ZIP downloads and SHA-256 checksums. Pull requests and other branches only upload Actions artifacts, retained for 30 days.

Each release has an immutable build tag tied to the tested commit. Only the publishing job has repository write access. The workflow uses ad-hoc signing without developer credentials and does not notarize the app. [Download instructions](DOWNLOADS.md).

To create and verify the same package locally after building:

```sh
python3 scripts/package_release.py
python3 tests/test_distribution.py dist/AIPromptBridge-macos-arm64.zip --arch arm64
```

Use `x86_64` in both places on an Intel Mac. Packaging preserves the app signature, includes the CLI and portable skill, and records the source commit and whether the working tree had modifications. Distribution tests extract into a path with spaces and verify the signature, CPU architecture, CLI execution and app lookup, checksums, skill package, and legal resources.
