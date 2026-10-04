#!/bin/sh
set -eu
TASK_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$TASK_ROOT"
mkdir -p build/SurfaceModuleCache
xcrun swiftc -swift-version 5 -parse-as-library \
  -module-cache-path build/SurfaceModuleCache \
  boringNotch/components/Notch/NotchShape.swift Tests/NotchSurfaceTests.swift \
  -o build/NotchSurfaceTests
exec build/NotchSurfaceTests
