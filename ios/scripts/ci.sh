#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  echo "DEVELOPER_DIR must select a full Xcode installation" >&2
  exit 1
fi

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repository_root"

xcodebuild \
  -project ios/Planner.xcodeproj \
  -scheme Planner \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build

device_id="$({
  xcrun simctl list devices available --json |
    python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
for runtime_devices in devices.values():
    for device in runtime_devices:
        if device["isAvailable"] and device["name"].startswith("iPhone"):
            print(device["udid"])
            raise SystemExit
raise SystemExit("No available iPhone Simulator")
'
})"

xcrun simctl boot "$device_id" 2>/dev/null || true
xcrun simctl bootstatus "$device_id" -b

xcodebuild \
  -project ios/Planner.xcodeproj \
  -scheme Planner \
  -destination "platform=iOS Simulator,id=$device_id" \
  CODE_SIGNING_ALLOWED=NO \
  test
