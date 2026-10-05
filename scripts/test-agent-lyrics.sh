#!/bin/sh
set -eu
TASK_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$TASK_ROOT"
# Run after build-app.sh and the IntegrationPackage tests have built these modules.
TASK_APP_PRODUCTS="build/DerivedData/Build/Products/${1:-Debug}"
TASK_CORE_PRODUCTS=build/IntegrationPackage/out/Products/Debug
mkdir -p build/AgentLyricsModuleCache build/agent-lyrics-previews
xcrun swiftc -swift-version 5 -parse-as-library \
  -module-cache-path build/AgentLyricsModuleCache \
  -I "$TASK_APP_PRODUCTS" -I "$TASK_CORE_PRODUCTS" \
  "$TASK_APP_PRODUCTS/Defaults.o" \
  "$TASK_CORE_PRODUCTS/NotchIntegrationCore.o" "$TASK_CORE_PRODUCTS/CodeIslandCore.o" \
  boringNotch/Integrations/AgentMonitor.swift \
  boringNotch/Integrations/AgentPanelView.swift \
  boringNotch/Integrations/AgentMarkdownView.swift \
  boringNotch/Integrations/CollapsedLyricsView.swift \
  Tests/Support/AgentLyricsRenderSupport.swift Tests/AgentLyricsRenderingTests.swift \
  -o build/AgentLyricsRenderingTests
exec build/AgentLyricsRenderingTests "$TASK_ROOT/build/agent-lyrics-previews"
