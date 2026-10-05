#!/bin/sh
set -eu
TASK_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$TASK_ROOT"
TASK_PRODUCTS="build/DerivedData/Build/Products/${1:-Release}"
mkdir -p build/CalendarFocusModuleCache
xcrun swiftc -swift-version 5 -parse-as-library \
  -module-cache-path build/CalendarFocusModuleCache \
  -I "$TASK_PRODUCTS" "$TASK_PRODUCTS/Defaults.o" \
  boringNotch/Integrations/AutomaticLyricsFocusCheck.swift \
  boringNotch/managers/CalendarManager.swift \
  Tests/Support/CalendarFocusTestSupport.swift Tests/CalendarFocusTests.swift \
  -o build/CalendarFocusTests
exec build/CalendarFocusTests
