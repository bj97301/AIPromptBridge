# Download and open

These are automated development builds for **macOS 14 or later**. Both architectures pass the CI tests before a release is published.

Choose the ZIP for your Mac under **Assets**:

- **AIPromptBridge-macos-arm64.zip** for Apple Silicon, such as M1, M2, M3, or later.
- **AIPromptBridge-macos-x86_64.zip** for Intel Macs.

Unzip it and keep the extracted `AIPromptBridge` folder together in a permanent location. Quit older copies, then open `AIPromptBridge.app` inside the folder. Read and acknowledge the risk notice and enable Accessibility for that copy. Python 3 is required for the CLI; downloading a build does not require Xcode.

The app is **ad-hoc signed and not notarized**. If macOS blocks it as an unidentified developer, review the source and [Apple's instructions for Open Anyway](https://support.apple.com/en-us/102445). Do not disable Gatekeeper. A new build may require removing and re-adding its Accessibility entry.

From Terminal in the extracted folder:

```sh
./aipromptbridge status
./aipromptbridge skills install --all
./aipromptbridge scan
```

The download includes the app, CLI, portable AI skill ZIP, documentation, and legal notices. `BUILD-INFO.json` records the source commit and architecture. Download the matching `.zip.sha256` file alongside the ZIP and run `shasum -a 256 -c AIPromptBridge-macos-arm64.zip.sha256`, substituting `x86_64` for Intel.

CI covers acknowledgment, allowed actions, password approval policy, skill installation, the packaged app's IPC gate, and the extracted download. Protected system prompts, live screen capture, and real-password authentication are not established by CI. Tests use dummy data and do not grant macOS permissions or accept the app's notices.

This app gives local software powerful control of your Mac. Read the bundled risk notice and license before enabling it. Password input and capture start disabled; password use asks first by default. Use **Pause CLI access** or quit the app to stop new requests.

[Full instructions](https://github.com/bj97301/AIPromptBridge#readme) · [Report a bug](https://github.com/bj97301/AIPromptBridge/issues/new) · [Security reporting](https://github.com/bj97301/AIPromptBridge/blob/main/SECURITY.md)
