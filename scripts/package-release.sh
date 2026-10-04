#!/bin/sh
set -eu
TASK_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$TASK_ROOT"
TASK_APP="$TASK_ROOT/build/DerivedData/Build/Products/Release/Agent Usage Notch.app"
TASK_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TASK_APP/Contents/Info.plist")
TASK_STAGE="$TASK_ROOT/build/dmg-stage-$TASK_VERSION"
TASK_DMG="$TASK_ROOT/dist/Agent-Usage-Notch-$TASK_VERSION-universal.dmg"
if [ -e "$TASK_STAGE" ] || [ -e "$TASK_DMG" ]; then
  echo "This version is already staged or packaged. Use a new version or inspect the existing files."
  exit 1
fi
mkdir -p "$TASK_STAGE" "$TASK_ROOT/dist"
/usr/bin/codesign --verify --deep --strict "$TASK_APP"
/usr/bin/ditto "$TASK_APP" "$TASK_STAGE/Agent Usage Notch.app"
ln -s /Applications "$TASK_STAGE/Applications"
cp "$TASK_ROOT/INSTALL.md" "$TASK_STAGE/安装说明.txt"
cp "$TASK_ROOT/LICENSE" "$TASK_STAGE/LICENSE"
cp "$TASK_ROOT/THIRD_PARTY_LICENSES" "$TASK_STAGE/THIRD_PARTY_LICENSES"
/usr/bin/hdiutil create -volname "Agent Usage Notch $TASK_VERSION" -srcfolder "$TASK_STAGE" -format UDZO -ov "$TASK_DMG"
/usr/bin/hdiutil verify "$TASK_DMG"
(cd "$TASK_ROOT/dist" && /usr/bin/shasum -a 256 "$(basename "$TASK_DMG")" > SHA256SUMS.txt)
python3 "$TASK_ROOT/scripts/verify-release.py" "$TASK_APP" "$TASK_DMG" "$TASK_ROOT/dist/release-manifest.json"
echo "Created $TASK_DMG"
