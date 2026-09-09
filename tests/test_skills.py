#!/usr/bin/env python3
"""Isolated installer checks; never writes to the real user's skill folders."""
import base64
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import zipfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="aipromptbridge-skills-") as temporary:
    scratch = Path(temporary)
    binary = scratch / "skill-tests"
    subprocess.run(["xcrun", "swiftc", str(ROOT / "Sources/SkillInstaller.swift"),
                    str(ROOT / "Sources/SkillCommands.swift"),
                    str(ROOT / "tests/SkillInstallerTests.swift"), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)

    resources = ROOT / "AIPromptBridge.app/Contents/Resources"
    with zipfile.ZipFile(resources / "aipromptbridge-skill.zip") as archive:
        names = archive.namelist()
        assert all(name.startswith("aipromptbridge/") for name in names)
        assert "aipromptbridge/SKILL.md" in names
        assert "aipromptbridge/scripts/aipromptbridge" in names
        assert "aipromptbridge/references/LICENSE" in names
        assert not any(name.endswith("app-location.json") for name in names)
        for name in names:
            content = archive.read(name)
            assert b"/Users/" not in content, f"Personal path in exported skill: {name}"
        archive.extractall(scratch)
    script = scratch / "aipromptbridge/scripts/aipromptbridge"
    loader = importlib.machinery.SourceFileLoader("bridge_skill", str(script))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    cli = importlib.util.module_from_spec(spec)
    loader.exec_module(cli)
    app = scratch / "Mac's Apps with spaces/AIPromptBridge.app"
    app.mkdir(parents=True)
    (script.parent / "app-location.json").write_text(json.dumps({"appPath": str(app)}))
    with patch.dict(os.environ, {}, clear=True):
        assert cli.find_app() == app
    with patch.dict(os.environ, {"AIPROMPTBRIDGE_APP": str(app)}, clear=True):
        assert cli.find_app() == app
    with patch.dict(os.environ, {"AIPROMPTBRIDGE_APP": "relative.app"}, clear=True):
        try:
            cli.find_app()
            raise AssertionError("Relative override was accepted")
        except RuntimeError:
            pass
    help_result = subprocess.run(["python3", str(script), "--help"], capture_output=True, text=True, check=True)
    assert "scan" in help_result.stdout and "fill" in help_result.stdout
    print("PASS: portable ZIP structure and privacy, installed CLI app lookup, explicit override, and executable help")

    def command(*arguments, result=None, environment=None):
        with patch.object(cli, "request", return_value=result or {"status": "ok"}) as called, \
             patch.object(cli, "output") as output, \
             patch.dict(os.environ, environment or {}, clear=True), \
             patch("sys.argv", [str(script), "skills", *arguments]):
            code = cli.main()
            return code, called, output

    code, called, _ = command("list", environment={"CLAUDE_CONFIG_DIR": "~/.alternate"})
    assert code == 0 and called.call_args.args[0] == {"op": "skills.list", "claude_config_dir": "~/.alternate"}
    assert called.call_count == 1, "Setup must not require the control acknowledgment preflight"
    code, called, _ = command("install", "--all")
    assert code == 0 and called.call_args.args[0] == {"op": "skills.install", "all": True}
    code, called, _ = command("install", "--target", "shared", "--target", "claude")
    assert code == 0 and called.call_args.args[0]["targets"] == ["shared", "claude"]
    code, called, _ = command("install", "--folder", str(scratch / "a custom skills folder"))
    assert code == 0 and called.call_args.args[0]["folder"] == str(scratch / "a custom skills folder")
    code, _, emitted = command("install", "--all", result={"status": "partial_failure", "results": [{"state": "skipped"}]})
    assert code == 1 and emitted.call_args.args[0]["status"] == "partial_failure"
    data = (resources / "aipromptbridge-skill.zip").read_bytes()
    exported = scratch / "portable export.zip"
    code, called, emitted = command("export", "--output", str(exported), result={"status": "ok", "archive_base64": base64.b64encode(data).decode()})
    assert code == 0 and exported.read_bytes() == data
    assert (exported.stat().st_mode & 0o777) == 0o600
    assert "archive_base64" not in emitted.call_args.args[0]
    code, called, _ = command("export", "--output", str(exported))
    assert code == 1 and called.call_count == 0 and exported.read_bytes() == data
    code, _, _ = command("export", "--output", str(scratch / "invalid.zip"), result={"status": "ok", "archive_base64": "!!invalid!!"})
    assert code == 1 and not (scratch / "invalid.zip").exists()
    print("PASS: CLI setup works before acknowledgment, routes exact selectors, returns nonzero for partial results, and exports private files without overwriting")
