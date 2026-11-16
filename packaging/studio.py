#!/usr/bin/env python3
"""Build the community settings app and installer using Apple command-line tools."""
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
output = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else root / 'dist'
output.mkdir(parents=True, exist_ok=True)
build = root.parent / 'wacomd-universal'
subprocess.run(['swift', 'build', '-c', 'release', '--arch', 'arm64', '--arch', 'x86_64', '--scratch-path', str(build)], cwd=root, check=True)
products = build / 'out/Products/Release'
if not products.exists():
    products = build / 'apple/Products/Release'
if not products.exists():
    raise RuntimeError('Swift build product directory not found')

def bundle(path, name, identity, executable):
    (path / 'Contents/MacOS').mkdir(parents=True)
    (path / 'Contents/Resources').mkdir()
    shutil.copy2(products / executable, path / 'Contents/MacOS' / executable)
    (path / 'Contents/MacOS' / executable).chmod(0o755)
    with (path / 'Contents/Info.plist').open('wb') as file:
        plistlib.dump(dict(CFBundleName=name, CFBundleDisplayName=name, CFBundleIdentifier=identity, CFBundleExecutable=executable, CFBundlePackageType='APPL', CFBundleShortVersionString='1.1.4', CFBundleVersion='8', LSMinimumSystemVersion='13.0', NSHighResolutionCapable=True, LSUIElement=executable == 'wacomd'), file)
    shutil.copy2(root / 'LICENSE', path / 'Contents/Resources/LICENSE')

with tempfile.TemporaryDirectory(prefix='tablet-studio-') as temporary:
    stage = Path(temporary) / 'root'
    app = stage / 'Applications/Tablet Studio.app'
    bundle(app, 'Tablet Studio', 'com.local.tabletstudio', 'wacomd-config')
    driver = app / 'Contents/Resources/Wacom PTH-451 Driver.app'
    bundle(driver, 'Wacom PTH-451 Driver', 'com.local.wacomd.pth451', 'wacomd')
    for item in (driver, app):
        subprocess.run(['codesign', '--force', '--sign', '-', str(item)], check=True)
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(item)], check=True)
    destination = output / app.name
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(app, destination)
    components = Path(temporary) / 'components.plist'
    subprocess.run(['pkgbuild', '--analyze', '--root', str(stage), str(components)], check=True)
    with components.open('rb') as file:
        entries = plistlib.load(file)
    for entry in entries:
        entry['BundleIsRelocatable'] = False
    with components.open('wb') as file:
        plistlib.dump(entries, file)
    subprocess.run(['pkgbuild', '--root', str(stage), '--component-plist', str(components), '--identifier', 'com.local.tabletstudio.installer', '--version', '1.1.4', '--install-location', '/', str(output / 'Tablet-Studio-Mac.pkg')], check=True)
    subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(destination), str(output / 'Tablet-Studio-Mac.zip')], check=True)
print(output)
