#!/usr/bin/env python3
"""Check the actual downloadable archive after extraction to a path with spaces."""
import argparse
import hashlib
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import zipfile
from unittest.mock import patch

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('archive', type=Path)
parser.add_argument('--arch', required=True, choices=['arm64', 'x86_64'])
args = parser.parse_args()
archive = args.archive.resolve()
expected = archive.with_suffix('.zip.sha256').read_text().strip()
assert expected == f'{hashlib.sha256(archive.read_bytes()).hexdigest()}  {archive.name}'
with zipfile.ZipFile(archive) as zipped:
    assert zipped.testzip() is None
    names = zipped.namelist()
    assert all(name.startswith('AIPromptBridge/') and '..' not in Path(name).parts for name in names)
    assert not any('/.git/' in name or name.endswith(('app-location.json', '.DS_Store')) for name in names)

with tempfile.TemporaryDirectory(prefix='AIPromptBridge download test ') as temporary:
    subprocess.run(['ditto', '-x', '-k', str(archive), temporary], check=True)
    folder = Path(temporary) / 'AIPromptBridge'
    app = folder / 'AIPromptBridge.app'
    subprocess.run(['codesign', '--verify', '--strict', str(app)], check=True)
    binary = app / 'Contents/MacOS/AIPromptBridge'
    assert subprocess.check_output(['lipo', '-archs', str(binary)], text=True).strip() == args.arch
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert info['LSMinimumSystemVersion'] == '14.0'
    assert info['CFBundleIdentifier'] == 'io.github.bj97301.aipromptbridge'
    assert info['CFBundleIconFile'] == 'AppIcon'
    icon = app / 'Contents/Resources/AppIcon.icns'
    assert icon.read_bytes().startswith(b'icns') and icon.stat().st_size > 1024
    manifest = json.loads((folder / 'BUILD-INFO.json').read_text())
    assert manifest['architecture'] == args.arch
    if os.environ.get('GITHUB_ACTIONS') == 'true':
        assert manifest['commit'] == os.environ['GITHUB_SHA']
        assert manifest['working_tree_modified'] is False
    for name in ('LICENSE', 'NOTICE', 'RISK_NOTICE.md'):
        assert (folder / name).read_bytes() == (app / 'Contents/Resources' / name).read_bytes()
    assert (folder / 'docs/DOWNLOADS.md').is_file()
    cli = folder / 'aipromptbridge'
    assert cli.is_symlink() and os.readlink(cli) == 'cli/aipromptbridge'
    assert os.access(cli, os.X_OK)
    for command in (['--help'], ['skills', 'install', '--help'], ['fill', '--help']):
        result = subprocess.run([str(cli), *command], capture_output=True, text=True, check=True)
        assert 'usage:' in result.stdout
    loader = importlib.machinery.SourceFileLoader('download_cli', str(cli.resolve()))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    with patch.dict(os.environ, {}, clear=True):
        assert module.find_app().samefile(app)
    with zipfile.ZipFile(folder / 'aipromptbridge-skill.zip') as skill:
        assert skill.testzip() is None
        assert 'aipromptbridge/SKILL.md' in skill.namelist()
        assert 'aipromptbridge/scripts/aipromptbridge' in skill.namelist()
        assert not any(name.endswith('app-location.json') for name in skill.namelist())
        assert all(b'/Users/' not in skill.read(name) for name in skill.namelist())
print('PASS: download checksum, extraction, signature, architecture, notices, CLI launch and app lookup, and portable skill')
