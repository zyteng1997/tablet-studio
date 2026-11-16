#!/bin/bash
# Additional release checks. No driver is installed or started and no input is posted.
set -euo pipefail
cd "$(dirname "$0")/.."
bash Checks/run.sh
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
swiftc -emit-library -emit-module -module-name WacomdShared Sources/WacomdShared/Config.swift -module-cache-path "$check_dir/cache" -o "$check_dir/libWacomdShared.dylib" -emit-module-path "$check_dir/WacomdShared.swiftmodule"
swiftc -module-cache-path "$check_dir/cache" -I "$check_dir" -L "$check_dir" -lWacomdShared -Xlinker -rpath -Xlinker '@executable_path' Checks/Pressure/main.swift -o "$check_dir/pressure-check"
"$check_dir/pressure-check" Mac/PTH451-settings.json
swiftc -sanitize=address -module-cache-path "$check_dir/cache" Sources/wacomd/IntuosProParser.swift Sources/wacomd/IntuosProTouchParser.swift Sources/wacomd/Verbose.swift Checks/Robustness/main.swift -o "$check_dir/parser-check"
"$check_dir/parser-check"
