#!/bin/sh
set -eu
TASK_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$TASK_ROOT"
TASK_CONFIGURATION=${1:-Debug}
shift "$(( $# > 0 ? 1 : 0 ))"
exec xcodebuild -project boringNotch.xcodeproj -scheme boringNotch \
  -configuration "$TASK_CONFIGURATION" -derivedDataPath build/DerivedData \
  -clonedSourcePackagesDirPath build/SourcePackages \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= CODE_SIGNING_REQUIRED=NO \
  ENABLE_HARDENED_RUNTIME=NO "$@" build
