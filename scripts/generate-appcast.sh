#!/bin/sh
# Run after package-release.sh. Prior ZIPs may be placed in build/update-archives for deltas.
set -eu
TASK_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TASK_APP="$TASK_ROOT/build/DerivedData/Build/Products/Release/Islet.app"
TASK_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TASK_APP/Contents/Info.plist")
TASK_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$TASK_APP/Contents/Info.plist")
TASK_TAG=${1:-v$TASK_VERSION}
if [ "$TASK_TAG" != "v$TASK_VERSION" ]; then
    echo 'The release tag must match the built application version.' >&2
    exit 1
fi
TASK_TOOLS="$TASK_ROOT/build/SourcePackages/artifacts/sparkle/Sparkle/bin"
TASK_ARCHIVES="$TASK_ROOT/build/update-archives"
TASK_ZIP="Islet-$TASK_VERSION-build$TASK_BUILD-universal.zip"
mkdir -p "$TASK_ARCHIVES"
cp "$TASK_ROOT/dist/$TASK_ZIP" "$TASK_ARCHIVES/$TASK_ZIP"
cp "$TASK_ROOT/updater/appcast.xml" "$TASK_ARCHIVES/appcast.xml"
if [ -f "$TASK_ROOT/updater/release-notes/$TASK_TAG.md" ]; then
    cp "$TASK_ROOT/updater/release-notes/$TASK_TAG.md" "$TASK_ARCHIVES/${TASK_ZIP%.zip}.md"
fi
set -- --versions "$TASK_BUILD" --maximum-versions 5 --maximum-deltas 3 \
    --download-url-prefix "https://github.com/Ownera1/Islet/releases/download/$TASK_TAG/" \
    --link 'https://github.com/Ownera1/Islet/releases' --embed-release-notes
if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
    printf '%s' "$SPARKLE_PRIVATE_KEY" | "$TASK_TOOLS/generate_appcast" --ed-key-file - "$@" "$TASK_ARCHIVES"
else
    "$TASK_TOOLS/generate_appcast" --account com.ownera1.agentusagenotch "$@" "$TASK_ARCHIVES"
fi
cp "$TASK_ARCHIVES/appcast.xml" "$TASK_ROOT/dist/appcast.xml"
find "$TASK_ARCHIVES" -maxdepth 1 -name '*.delta' -exec cp {} "$TASK_ROOT/dist/" \;
python3 "$TASK_ROOT/scripts/verify-appcast.py" "$TASK_ROOT/dist/appcast.xml" "$TASK_ROOT/dist" "$TASK_BUILD"
(cd "$TASK_ROOT/dist" && /usr/bin/shasum -a 256 ./*.dmg ./*.zip ./*.xml > SHA256SUMS.txt)
for TASK_DELTA in "$TASK_ROOT"/dist/*.delta; do
    [ -f "$TASK_DELTA" ] || continue
    (cd "$TASK_ROOT/dist" && /usr/bin/shasum -a 256 "$(basename "$TASK_DELTA")") >> "$TASK_ROOT/dist/SHA256SUMS.txt"
done
echo "Signed feed: $TASK_ROOT/dist/appcast.xml"
