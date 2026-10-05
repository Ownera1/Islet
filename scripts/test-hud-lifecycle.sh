#!/bin/sh
set -eu
TASK_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$TASK_ROOT"
TASK_PRODUCTS="build/DerivedData/Build/Products/${1:-Debug}"
mkdir -p build/HUDModuleCache
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path build/HUDModuleCache \
  -I "$TASK_PRODUCTS" "$TASK_PRODUCTS/Defaults.o" \
  boringNotch/observers/MediaKeyInterceptor.swift Tests/Support/HUDTestSupport.swift Tests/HUDLifecycleTests.swift \
  -o build/HUDLifecycleTests
exec build/HUDLifecycleTests
