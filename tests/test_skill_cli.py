#!/usr/bin/env python3
"""Run the real CLI installer against the packaged app and a temporary folder."""
import json
from pathlib import Path
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "aipromptbridge"


def run(*args, code=0):
    process = subprocess.run([str(CLI), *args], capture_output=True, text=True, timeout=35)
    assert process.returncode == code, (args, process.returncode, process.stdout, process.stderr)
    return json.loads(process.stdout)


before = run("status")
listed = run("skills", "list")
assert any(target["id"] == "shared" for target in listed["targets"])
assert all(Path(target["destination"]).name == "aipromptbridge" for target in listed["targets"])
unknown = run("skills", "install", "--target", "unknown-qa-target", code=1)
assert unknown["status"] == "invalid_request"
with tempfile.TemporaryDirectory(prefix="aipromptbridge-cli-skills-") as temporary:
    scratch = Path(temporary)
    folder = scratch / "custom skills"
    result = run("skills", "install", "--folder", str(folder))
    assert result["results"][0]["state"] == "installed", result
    installed = folder / "aipromptbridge"
    bundled = ROOT / "AIPromptBridge.app/Contents/Resources/aipromptbridge-skill"
    for source in bundled.rglob("*"):
        if source.is_file():
            assert (installed / source.relative_to(bundled)).read_bytes() == source.read_bytes()
    result = run("skills", "install", "--folder", str(folder))
    assert result["results"][0]["state"] == "already_installed", result
    customized = installed / "SKILL.md"
    customized.write_text("User-customized QA instructions\n")
    result = run("skills", "install", "--folder", str(folder), code=1)
    assert result["status"] == "partial_failure" and result["results"][0]["state"] == "skipped", result
    assert customized.read_text() == "User-customized QA instructions\n"
    exported = scratch / "portable skill.zip"
    result = run("skills", "export", "--output", str(exported))
    assert result["bytes"] == exported.stat().st_size
    with zipfile.ZipFile(exported) as archive:
        assert archive.testzip() is None
        assert "aipromptbridge/SKILL.md" in archive.namelist()
        assert not any(name.endswith("app-location.json") for name in archive.namelist())
    original = exported.read_bytes()
    refused = run("skills", "export", "--output", str(exported), code=1)
    assert refused["status"] == "cli_error" and exported.read_bytes() == original
after = run("status")
for key in ["acknowledgment", "allowed_operations", "saved_password", "accessibility", "screen_recording"]:
    assert before[key] == after[key], f"Skill setup changed {key}"
print("PASS: packaged CLI lists targets, installs, repeats, preserves customized copies, exports ZIPs without overwriting, and leaves control and password settings unchanged")
