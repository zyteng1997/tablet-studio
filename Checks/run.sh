#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
swiftc -emit-library -emit-module -module-name WacomdShared Sources/WacomdShared/Config.swift -module-cache-path "$check_dir/cache" -o "$check_dir/libWacomdShared.dylib" -emit-module-path "$check_dir/WacomdShared.swiftmodule"
swiftc -module-cache-path "$check_dir/cache" -I "$check_dir" -L "$check_dir" -lWacomdShared -Xlinker -rpath -Xlinker '@executable_path' Sources/wacomd/IntuosPro.swift Sources/wacomd/IntuosProParser.swift Sources/wacomd/ResolveControls.swift Sources/wacomd/PenState.swift Sources/wacomd/PenTouchGate.swift Sources/wacomd/ThreeFingerDrag.swift Checks/main.swift -o "$check_dir/check"
"$check_dir/check"
swiftc -module-cache-path "$check_dir/cache" -I "$check_dir" -L "$check_dir" -lWacomdShared -Xlinker -rpath -Xlinker '@executable_path' Sources/wacomd/TouchTracker.swift Sources/wacomd/IntuosProTouchParser.swift Sources/wacomd/Verbose.swift Sources/wacomd/PenTouchGate.swift Sources/wacomd/ThreeFingerDrag.swift Checks/Touch/main.swift -o "$check_dir/touch-check"
"$check_dir/touch-check"
swiftc -module-cache-path "$check_dir/cache" Sources/wacomd/KeyChord.swift Checks/Keys/main.swift -o "$check_dir/key-check"
"$check_dir/key-check"
