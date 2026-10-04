#!/bin/sh
set -eu
TASK_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$TASK_ROOT"
TASK_PLATFORM=$(xcrun --sdk macosx --show-sdk-platform-path)
TASK_TEST_FRAMEWORKS="$TASK_PLATFORM/Developer/Library/Frameworks"
mkdir -p build/GestureModuleCache
xcrun swiftc -swift-version 5 -parse-as-library \
  -module-cache-path build/GestureModuleCache \
  -F "$TASK_TEST_FRAMEWORKS" -I "$TASK_PLATFORM/Developer/usr/lib" \
  -L "$TASK_PLATFORM/Developer/usr/lib" \
  -Xlinker -rpath -Xlinker "$TASK_TEST_FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$TASK_PLATFORM/Developer/usr/lib" \
  boringNotch/extensions/PanGesture.swift Tests/ScrollPanTests.swift \
  -o build/ScrollPanTests
exec build/ScrollPanTests
