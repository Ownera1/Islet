#!/bin/sh
set -eu
TASK_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$TASK_ROOT"
TASK_APP="$TASK_ROOT/build/DerivedData/Build/Products/Release/Islet.app"
TASK_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TASK_APP/Contents/Info.plist")
TASK_STAGE="$TASK_ROOT/build/dmg-stage-$TASK_VERSION"
TASK_DMG="$TASK_ROOT/dist/Islet-$TASK_VERSION-universal.dmg"
TASK_ZIP="$TASK_ROOT/dist/Islet-$TASK_VERSION-universal.zip"
if [ -e "$TASK_STAGE" ] || [ -e "$TASK_DMG" ] || [ -e "$TASK_ZIP" ]; then
  echo "This version is already staged or packaged. Use a new version or inspect the existing files."
  exit 1
fi
mkdir -p "$TASK_STAGE" "$TASK_ROOT/dist"
# A distributed local build must not expose Xcode's debugger entitlement.
TASK_HELPER="$TASK_APP/Contents/XPCServices/BoringNotchXPCHelper.xpc"
TASK_HELPER_ENTITLEMENTS="$TASK_ROOT/build/local-helper-release-entitlements.plist"
/usr/bin/codesign -d --entitlements :- "$TASK_HELPER" > "$TASK_HELPER_ENTITLEMENTS" 2>/dev/null
python3 - "$TASK_HELPER_ENTITLEMENTS" <<'PY'
import pathlib, plistlib, sys
path = pathlib.Path(sys.argv[1])
entitlements = plistlib.loads(path.read_bytes())
assert not entitlements.get('com.apple.security.app-sandbox', False)
entitlements.pop('com.apple.security.get-task-allow', None)
path.write_bytes(plistlib.dumps(entitlements))
PY
/usr/bin/codesign --force --sign - --entitlements "$TASK_HELPER_ENTITLEMENTS" "$TASK_HELPER"
TASK_ENTITLEMENTS="$TASK_ROOT/build/local-release-entitlements.plist"
/usr/bin/codesign -d --entitlements :- "$TASK_APP" > "$TASK_ENTITLEMENTS" 2>/dev/null
python3 - "$TASK_ENTITLEMENTS" <<'PY'
import pathlib, plistlib, sys
path = pathlib.Path(sys.argv[1])
entitlements = plistlib.loads(path.read_bytes())
assert entitlements.get('com.apple.security.app-sandbox') is True
entitlements.pop('com.apple.security.get-task-allow', None)
path.write_bytes(plistlib.dumps(entitlements))
PY
/usr/bin/codesign --force --sign - --entitlements "$TASK_ENTITLEMENTS" "$TASK_APP"
/usr/bin/codesign --verify --deep --strict "$TASK_APP"
/usr/bin/ditto "$TASK_APP" "$TASK_STAGE/Islet.app"
ln -s /Applications "$TASK_STAGE/Applications"
cp "$TASK_ROOT/INSTALL.md" "$TASK_STAGE/安装说明.txt"
cp "$TASK_ROOT/LICENSE" "$TASK_STAGE/LICENSE"
cp "$TASK_ROOT/THIRD_PARTY_LICENSES" "$TASK_STAGE/THIRD_PARTY_LICENSES"
/usr/bin/hdiutil create -volname "Islet $TASK_VERSION" -srcfolder "$TASK_STAGE" -format UDZO -ov "$TASK_DMG"
/usr/bin/hdiutil verify "$TASK_DMG"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$TASK_APP" "$TASK_ZIP"
(cd "$TASK_ROOT/dist" && /usr/bin/shasum -a 256 "$(basename "$TASK_DMG")" "$(basename "$TASK_ZIP")" > SHA256SUMS.txt)
python3 "$TASK_ROOT/scripts/verify-release.py" "$TASK_APP" "$TASK_DMG" "$TASK_ROOT/dist/release-manifest.json"
echo "Created $TASK_DMG"
