#!/usr/bin/env python3
"""Build and sign a native macOS app with the installed Xcode tools."""
import os
from pathlib import Path
import plistlib
import platform
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parent
APP = ROOT / "AIPromptBridge.app"
CONTENTS = APP / "Contents"
BINARY = CONTENTS / "MacOS" / "AIPromptBridge"
BINARY.parent.mkdir(parents=True, exist_ok=True)
(CONTENTS / "Resources").mkdir(exist_ok=True)

identity = os.environ.get("AIPROMPTBRIDGE_SIGNING_IDENTITY") or "-"
architecture = platform.machine()
if architecture not in {"arm64", "x86_64"}:
    raise SystemExit(f"Unsupported build architecture: {architecture}")

icon_tool = ROOT / ".build" / "make-icon"
icon_tool.parent.mkdir(exist_ok=True)
iconset = icon_tool.parent / "AIPromptBridge.iconset"
subprocess.run(["xcrun", "swiftc", "-swift-version", "5", str(ROOT / "Sources/Branding.swift"),
                str(ROOT / "scripts/MakeIcon.swift"), "-o", str(icon_tool), "-framework", "AppKit"], check=True)
subprocess.run([str(icon_tool), str(iconset)], check=True)
subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(CONTENTS / "Resources/AppIcon.icns")], check=True)

for name in ("LICENSE", "NOTICE", "RISK_NOTICE.md"):
    if not (ROOT / name).is_file():
        raise SystemExit(f"Missing required legal resource: {name}")
    shutil.copyfile(ROOT / name, CONTENTS / "Resources" / name)

skill = CONTENTS / "Resources" / "aipromptbridge-skill"
if skill.exists():
    shutil.rmtree(skill)
shutil.copytree(ROOT / "skills" / "aipromptbridge", skill)
(skill / "scripts").mkdir(exist_ok=True)
shutil.copyfile(ROOT / "cli" / "aipromptbridge", skill / "scripts" / "aipromptbridge")
(skill / "scripts" / "aipromptbridge").chmod(0o755)
(skill / "references").mkdir(exist_ok=True)
for name in ("LICENSE", "NOTICE", "RISK_NOTICE.md"):
    shutil.copyfile(ROOT / name, skill / "references" / name)
with zipfile.ZipFile(CONTENTS / "Resources" / "aipromptbridge-skill.zip", "w", zipfile.ZIP_DEFLATED) as archive:
    for file in sorted(skill.rglob("*")):
        if file.is_file():
            archive.write(file, Path("aipromptbridge") / file.relative_to(skill))

subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-O", "-target", f"{architecture}-apple-macos14.0",
                *map(str, sorted((ROOT / "Sources").glob("*.swift"))), "-o", str(BINARY),
                "-framework", "AppKit", "-framework", "ApplicationServices", "-framework", "ScreenCaptureKit", "-framework", "Vision", "-framework", "Security"], check=True)
info = {
    "CFBundleIdentifier": "io.github.bj97301.aipromptbridge",
    "CFBundleName": "AIPromptBridge", "CFBundleDisplayName": "AIPromptBridge",
    "CFBundleExecutable": "AIPromptBridge", "CFBundlePackageType": "APPL",
    "CFBundleIconFile": "AppIcon",
    "CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1",
    "LSMinimumSystemVersion": "14.0", "LSUIElement": True,
    "NSHighResolutionCapable": True,
    "NSScreenCaptureUsageDescription": "Capture displays on request to find alerts and recognize their text locally.",
    "NSPrincipalClass": "NSApplication",
}
with (CONTENTS / "Info.plist").open("wb") as file:
    plistlib.dump(info, file)
subprocess.run(["codesign", "--force", "--sign", identity, "--options", "runtime", "--timestamp=none", str(APP)], check=True)
subprocess.run(["codesign", "--verify", "--strict", "--verbose=2", str(APP)], check=True)
cli = ROOT / "cli" / "aipromptbridge"
cli.chmod(0o755)
link = ROOT / "aipromptbridge"
if not link.exists():
    link.symlink_to("cli/aipromptbridge")
print(f"Built {APP}")
print(f"CLI: {link}")
if identity == "-":
    print("Ad-hoc signature used. For stable Accessibility permission across rebuilds, set AIPROMPTBRIDGE_SIGNING_IDENTITY.")
