#!/bin/bash
set -euo pipefail
device_id="$1"
app_path="build/DerivedData/Build/Products/Debug-iphonesimulator/MeetMind.app"
bundle_id="com.meetmind.app"
# simctl can stall if the simulator service stops responding after XCTest.
# Bound every operation so CI reports the failing command instead of hanging.
simctl() {
    python3 -c 'import subprocess,sys; subprocess.run(["xcrun", "simctl", *sys.argv[1:]], check=True, timeout=90)' "$@"
}
mkdir -p build/smoke
test -d "$app_path"
simctl boot "$device_id" 2>/dev/null || true
python3 -c 'import subprocess,sys; subprocess.run(["xcrun", "simctl", "bootstatus", sys.argv[1], "-b"], check=True, timeout=180)' "$device_id"
simctl install "$device_id" "$app_path"
launch_and_check() {
    local completed="$1"
    local screenshot="$2"
    simctl terminate "$device_id" "$bundle_id" 2>/dev/null || true
    local output
    output=$(simctl launch "$device_id" "$bundle_id" -MeetMind_IsOnboardingCompleted "$completed")
    echo "$output"
    local process_id="${output##*: }"
    sleep 5
    if ! kill -0 "$process_id" 2>/dev/null; then
        simctl spawn "$device_id" log show --last 1m --predicate 'process == "MeetMind"' > build/smoke/failed-launch.log 2>&1 || true
        echo "MeetMind terminated unexpectedly on launch"
        return 1
    fi
    simctl io "$device_id" screenshot "build/smoke/$screenshot.png"
}
launch_and_check NO onboarding
launch_and_check YES meetings-first
launch_and_check YES meetings-second
launch_and_check YES meetings-third
simctl terminate "$device_id" "$bundle_id" 2>/dev/null || true
microphone_output=$(simctl launch "$device_id" "$bundle_id" --ui-microphone)
microphone_pid="${microphone_output##*: }"
sleep 5
kill -0 "$microphone_pid"
simctl io "$device_id" screenshot build/smoke/microphone-idle.png
for recording_state in active paused finish; do
    simctl terminate "$device_id" "$bundle_id" 2>/dev/null || true
    recording_output=$(simctl launch "$device_id" "$bundle_id" "--ui-recording-$recording_state")
    recording_pid="${recording_output##*: }"
    sleep 3
    kill -0 "$recording_pid"
    simctl io "$device_id" screenshot "build/smoke/recording-$recording_state.png"
done
echo "PASS: onboarding, main tabs, microphone, and recording visual states stayed alive"
