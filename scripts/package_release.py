#!/usr/bin/env python3
"""Package an already-built app without changing its code signature."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', type=Path, default=ROOT / 'dist')
    args = parser.parse_args()
    app = ROOT / 'AIPromptBridge.app'
    binary = app / 'Contents/MacOS/AIPromptBridge'
    subprocess.run(['codesign', '--verify', '--strict', str(app)], check=True)
    architecture = subprocess.check_output(['lipo', '-archs', str(binary)], text=True).strip()
    if architecture not in {'arm64', 'x86_64'}:
        raise SystemExit(f'Expected one supported architecture, got {architecture!r}')
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    dirty = bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True))
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    archive = output / f'AIPromptBridge-macos-{architecture}.zip'
    with tempfile.TemporaryDirectory(prefix='aipromptbridge-package-') as temporary:
        folder = Path(temporary) / 'AIPromptBridge'
        folder.mkdir()
        subprocess.run(['ditto', '--norsrc', '--noextattr', str(app), str(folder / app.name)], check=True)
        for name in ('README.md', 'LICENSE', 'NOTICE', 'RISK_NOTICE.md', 'SECURITY.md'):
            shutil.copyfile(ROOT / name, folder / name)
        shutil.copytree(ROOT / 'docs', folder / 'docs', ignore=shutil.ignore_patterns('.DS_Store'))
        (folder / 'cli').mkdir()
        shutil.copyfile(ROOT / 'cli/aipromptbridge', folder / 'cli/aipromptbridge')
        (folder / 'cli/aipromptbridge').chmod(0o755)
        (folder / 'aipromptbridge').symlink_to('cli/aipromptbridge')
        shutil.copyfile(app / 'Contents/Resources/aipromptbridge-skill.zip', folder / 'aipromptbridge-skill.zip')
        (folder / 'BUILD-INFO.json').write_text(json.dumps({
            'commit': commit, 'working_tree_modified': dirty,
            'architecture': architecture, 'minimum_macos': info['LSMinimumSystemVersion'],
            'app_version': info['CFBundleShortVersionString'],
        }, indent=2) + '\n')
        subprocess.run(['codesign', '--verify', '--strict', str(folder / app.name)], check=True)
        subprocess.run(['ditto', '-c', '-k', '--norsrc', '--noextattr', '--keepParent', str(folder), str(archive)], check=True)
    checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
    archive.with_suffix('.zip.sha256').write_text(f'{checksum}  {archive.name}\n')
    print(f'Packaged {archive.name} ({archive.stat().st_size:,} bytes)')


if __name__ == '__main__':
    main()
