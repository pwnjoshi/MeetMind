#!/bin/bash
set -euo pipefail
device_id="$1"
app_path="build/DerivedData/Build/Products/Debug-iphonesimulator/MeetMind.app"
bundle_id="com.meetmind.app"
mkdir -p build/smoke
test -d "$app_path"
xcrun simctl boot "$device_id" 2>/dev/null || true
xcrun simctl bootstatus "$device_id" -b
xcrun simctl install "$device_id" "$app_path"
launch_and_check() {
    local completed="$1"
    local screenshot="$2"
    xcrun simctl terminate "$device_id" "$bundle_id" 2>/dev/null || true
    local output
    output=$(xcrun simctl launch "$device_id" "$bundle_id" -MeetMind_IsOnboardingCompleted "$completed")
    echo "$output"
    local process_id="${output##*: }"
    sleep 5
    if ! kill -0 "$process_id" 2>/dev/null; then
        xcrun simctl spawn "$device_id" log show --last 1m --predicate 'process == "MeetMind"' > build/smoke/failed-launch.log 2>&1 || true
        echo "MeetMind terminated unexpectedly on launch"
        return 1
    fi
    xcrun simctl io "$device_id" screenshot "build/smoke/$screenshot.png"
}
launch_and_check NO onboarding
launch_and_check YES meetings-first
launch_and_check YES meetings-second
launch_and_check YES meetings-third
echo "PASS: onboarding and three completed-onboarding launches stayed alive"
