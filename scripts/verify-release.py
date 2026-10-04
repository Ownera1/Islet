#!/usr/bin/env python3
"""Validate the actual release bundle and record source and installer provenance."""
import hashlib
import json
import pathlib
import plistlib
import subprocess
import sys
from datetime import datetime, timezone

app, dmg, output = map(pathlib.Path, sys.argv[1:])
root = pathlib.Path(__file__).resolve().parents[1]
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'com.ownera1.agentusagenotch'
assert info['LSMinimumSystemVersion'] == '15.0'
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
paths = [app / 'Contents/MacOS' / info['CFBundleExecutable'],
         app / 'Contents/XPCServices/BoringNotchXPCHelper.xpc/Contents/MacOS/BoringNotchXPCHelper',
         app / 'Contents/Resources/IntegrationResources/notch-agent-bridge']
for path in paths:
    archs = subprocess.check_output(['lipo', '-archs', str(path)], text=True).split()
    assert set(archs) == {'arm64', 'x86_64'}, (path.name, archs)
assert (app / 'Contents/Resources/IntegrationResources/boringnotch-pi.ts').is_file()
assert (app / 'Contents/Resources/LICENSE').is_file()
assert (app / 'Contents/Resources/THIRD_PARTY_LICENSES').is_file()
assert 'SUFeedURL' not in info, 'Upstream update feed must not replace this integration'
helper = plistlib.loads((app / 'Contents/XPCServices/BoringNotchXPCHelper.xpc/Contents/Info.plist').read_bytes())
assert helper['CFBundleIdentifier'] == 'com.ownera1.agentusagenotch.helper'
revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
assert not subprocess.check_output(['git', 'status', '--porcelain'], cwd=root, text=True).strip(), 'Commit the released source before packaging'
with dmg.open('rb') as stream:
    digest = hashlib.sha256()
    for chunk in iter(lambda: stream.read(1024 * 1024), b''):
        digest.update(chunk)
manifest = {
    'name': 'Agent Usage Notch', 'version': info['CFBundleShortVersionString'],
    'build': info['CFBundleVersion'], 'bundleId': info['CFBundleIdentifier'],
    'sourceCommit': revision, 'repository': 'https://github.com/Ownera1/agent-usage-notch',
    'architectures': ['arm64', 'x86_64'], 'minimumMacOS': '15.0',
    'signature': 'ad-hoc', 'notarized': False,
    'installer': dmg.name, 'size': dmg.stat().st_size,
    'sha256': digest.hexdigest(),
    'packagedAt': datetime.now(timezone.utc).isoformat(),
}
output.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({key: manifest[key] for key in ['version', 'sourceCommit', 'architectures', 'minimumMacOS', 'sha256']}, ensure_ascii=False))
