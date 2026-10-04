#!/bin/sh
# Run locally only after the GitHub release and signed feed are verified.
set -eu
TASK_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TASK_DRY_RUN=false
case "${1:-}" in
  '') ;;
  --dry-run) TASK_DRY_RUN=true ;;
  *) echo "Usage: $0 [--dry-run]" >&2; exit 2 ;;
esac
if [ "$#" -gt 1 ]; then
  echo "Usage: $0 [--dry-run]" >&2
  exit 2
fi

# Keep Build/Products, release installers, source and diagnostic logs.
for TASK_RELATIVE in \
  build/DerivedData/Build/Intermediates.noindex \
  build/DerivedData/Index.noindex \
  build/DerivedData/ModuleCache.noindex \
  build/DerivedData/CompilationCache.noindex \
  build/DerivedData/SDKExplicitPrecompiledModules \
  build/DerivedData/SDKStatCaches.noindex \
  build/SourcePackages \
  build/IntegrationPackage \
  build/GestureModuleCache \
  build/SurfaceModuleCache \
  build/NotchSurfaceTests \
  build/OldNotchSurfaceTests \
  build/ScrollPanTests \
  .build \
  Packages/NotchIntegrations/.build
do
  TASK_PATH="$TASK_ROOT/$TASK_RELATIVE"
  if [ -e "$TASK_PATH" ] || [ -L "$TASK_PATH" ]; then
    if [ "$TASK_DRY_RUN" = true ]; then
      printf 'Would remove: %s\n' "$TASK_PATH"
    else
      rm -rf -- "$TASK_PATH"
      printf 'Removed: %s\n' "$TASK_PATH"
    fi
  fi
done
