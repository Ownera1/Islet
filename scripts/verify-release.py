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
assert app.name == 'Islet.app'
assert info['CFBundleName'] == info['CFBundleDisplayName'] == info['CFBundleExecutable'] == 'Islet'
assert info['LSMinimumSystemVersion'] == '15.0'
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
entitlements = plistlib.loads(subprocess.check_output(
    ['codesign', '-d', '--entitlements', ':-', str(app)], stderr=subprocess.DEVNULL))
assert entitlements.get('com.apple.security.app-sandbox') is True
assert not entitlements.get('com.apple.security.get-task-allow'), 'Do not distribute debugger access'
signing = subprocess.check_output(['codesign', '-dv', '--verbose=4', str(app)], stderr=subprocess.STDOUT, text=True)
assert 'Signature=adhoc' in signing
assert '(adhoc,runtime)' not in signing, 'Local signing has no Team ID for hardened library validation'
paths = [app / 'Contents/MacOS' / info['CFBundleExecutable'],
         app / 'Contents/XPCServices/BoringNotchXPCHelper.xpc/Contents/MacOS/BoringNotchXPCHelper',
         app / 'Contents/Resources/IntegrationResources/notch-agent-bridge']
for path in paths:
    archs = subprocess.check_output(['lipo', '-archs', str(path)], text=True).split()
    assert set(archs) == {'arm64', 'x86_64'}, (path.name, archs)
assert (app / 'Contents/Resources/IntegrationResources/boringnotch-pi.ts').is_file()
assert (app / 'Contents/Resources/LICENSE').is_file()
assert (app / 'Contents/Resources/THIRD_PARTY_LICENSES').is_file()
assert info['SUFeedURL'] == 'https://raw.githubusercontent.com/Ownera1/Islet/main/updater/appcast.xml'
assert info['SUPublicEDKey'] == plistlib.loads((root / 'boringNotch/Info.plist').read_bytes())['SUPublicEDKey']
assert info.get('SUEnableAutomaticChecks') is True
assert info.get('SUVerifyUpdateBeforeExtraction') is True
assert info.get('SUEnableInstallerLauncherService') is True
assert (app / 'Contents/Frameworks/Sparkle.framework').exists()
helper = plistlib.loads((app / 'Contents/XPCServices/BoringNotchXPCHelper.xpc/Contents/Info.plist').read_bytes())
helper_entitlements = plistlib.loads(subprocess.check_output(
    ['codesign', '-d', '--entitlements', ':-', str(app / 'Contents/XPCServices/BoringNotchXPCHelper.xpc')],
    stderr=subprocess.DEVNULL))
assert not helper_entitlements.get('com.apple.security.app-sandbox', False), 'Helper must perform privileged desktop operations outside the app sandbox'
assert not helper_entitlements.get('com.apple.security.get-task-allow'), 'Do not distribute Helper debugger access'
assert helper['CFBundleIdentifier'] == 'com.ownera1.agentusagenotch.helper'
assert helper.get('XPCService', {}).get('RunLoopType') == 'NSRunLoop', 'Helper must run CF sources for HUD media events'
assert helper.get('XPCService', {}).get('JoinExistingSession') is True, 'Helper must join the login session to read CLI keychain credentials'
revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
assert not subprocess.check_output(['git', 'status', '--porcelain'], cwd=root, text=True).strip(), 'Commit the released source before packaging'
with dmg.open('rb') as stream:
    digest = hashlib.sha256()
    for chunk in iter(lambda: stream.read(1024 * 1024), b''):
        digest.update(chunk)
manifest = {
    'name': 'Islet', 'version': info['CFBundleShortVersionString'],
    'build': info['CFBundleVersion'], 'bundleId': info['CFBundleIdentifier'],
    'sourceCommit': revision, 'repository': 'https://github.com/Ownera1/Islet',
    'architectures': ['arm64', 'x86_64'], 'minimumMacOS': '15.0',
    'signature': 'ad-hoc', 'notarized': False,
    'updateFeed': info['SUFeedURL'], 'updateSigning': 'Ed25519',
    'appSandbox': True, 'hardenedRuntime': False, 'debuggerAccess': False,
    'installer': dmg.name, 'size': dmg.stat().st_size,
    'sha256': digest.hexdigest(),
    'packagedAt': datetime.now(timezone.utc).isoformat(),
}
output.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({key: manifest[key] for key in ['version', 'sourceCommit', 'architectures', 'minimumMacOS', 'sha256']}, ensure_ascii=False))
