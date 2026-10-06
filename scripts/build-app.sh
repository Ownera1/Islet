#!/bin/sh
set -eu
TASK_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$TASK_ROOT"
TASK_CONFIGURATION=${1:-Debug}
shift "$(( $# > 0 ? 1 : 0 ))"
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch \
  -configuration "$TASK_CONFIGURATION" -derivedDataPath build/DerivedData \
  -clonedSourcePackagesDirPath build/SourcePackages \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= CODE_SIGNING_REQUIRED=NO \
  ENABLE_HARDENED_RUNTIME=NO "$@" build

# Ad-hoc signatures are pinned to a cdhash, so every rebuild silently voids the
# Accessibility grant the HUD needs. Re-sign with a stable local identity when one
# exists (override with ISLET_SIGN_IDENTITY, or set it to "-" to stay ad-hoc).
TASK_IDENTITY=${ISLET_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -n 1)}
[ -n "$TASK_IDENTITY" ] && [ "$TASK_IDENTITY" != "-" ] || exit 0
TASK_APP="$TASK_ROOT/build/DerivedData/Build/Products/$TASK_CONFIGURATION/Islet.app"
TASK_HELPER="$TASK_APP/Contents/XPCServices/BoringNotchXPCHelper.xpc"
for TASK_TARGET in "$TASK_HELPER" "$TASK_APP"; do
  TASK_ENTITLEMENTS="$TASK_ROOT/build/resign-$(basename "$TASK_TARGET").plist"
  /usr/bin/codesign -d --entitlements :- "$TASK_TARGET" > "$TASK_ENTITLEMENTS" 2>/dev/null
  /usr/bin/codesign --force --sign "$TASK_IDENTITY" --entitlements "$TASK_ENTITLEMENTS" "$TASK_TARGET"
done
/usr/bin/codesign --verify --strict "$TASK_APP"
echo "Signed with $TASK_IDENTITY"
