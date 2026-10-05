#!/bin/sh
set -eu
TASK_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$TASK_ROOT"
TASK_PRODUCTS="build/DerivedData/Build/Products/${1:-Release}"
TASK_CORE=build/IntegrationPackage/out/Products/Debug
if [ -f "$TASK_CORE/CodeIslandCore.o" ]; then
  set -- "$TASK_CORE/NotchIntegrationCore.o" "$TASK_CORE/CodeIslandCore.o"
else
  # SwiftPM's native backend on older Xcode versions emits one object per source.
  TASK_CORE=$(xcrun swift build --package-path Packages/NotchIntegrations --scratch-path build/IntegrationPackage --show-bin-path)
  set -- "$TASK_CORE/NotchIntegrationCore.build/"*.o "$TASK_CORE/CodeIslandCore.build/"*.o
fi
mkdir -p build/AgentCompletionModuleCache
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path build/AgentCompletionModuleCache \
  -I "$TASK_PRODUCTS" -I "$TASK_CORE" -I "$TASK_CORE/Modules" "$TASK_PRODUCTS/Defaults.o" "$@" \
  boringNotch/Integrations/AgentMonitor.swift Tests/Support/AgentLyricsRenderSupport.swift \
  Tests/AgentCompletionTests.swift -o build/AgentCompletionTests
exec build/AgentCompletionTests
