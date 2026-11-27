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
# XCTest ran in this simulator's app container just before. Start from a clean install so
# leftovers from tests (for example recording-recovery records) cannot change what launches.
simctl uninstall "$device_id" "$bundle_id" 2>/dev/null || true
simctl install "$device_id" "$app_path"
collect_diagnostics() {
    local name="$1"
    simctl spawn "$device_id" log show --last 3m --predicate 'process == "MeetMind"' > "build/smoke/$name.log" 2>&1 || true
    find "$HOME/Library/Logs/DiagnosticReports" -name 'MeetMind*.ips' -mmin -5 -exec cp {} build/smoke/ \; || true
}
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
    if ! simctl io "$device_id" screenshot "build/smoke/$screenshot.png"; then
        # A hung app can stall the screenshot; keep its log and any hang report.
        collect_diagnostics "$screenshot-screenshot-timeout"
        echo "Screenshot of $screenshot did not complete"
        return 1
    fi
}
launch_and_check NO onboarding
launch_and_check YES meetings-first
launch_and_check YES meetings-second
launch_and_check YES meetings-third
simctl terminate "$device_id" "$bundle_id" 2>/dev/null || true
server_output=$(simctl launch "$device_id" "$bundle_id" --ui-home-populated)
home_pid="${server_output##*: }"
sleep 3
kill -0 "$home_pid"
simctl io "$device_id" screenshot build/smoke/home-populated.png
for screen in profile-long recording-active recording-paused recording-finish meeting-review meeting-draft meeting-finalized; do
    simctl terminate "$device_id" "$bundle_id" 2>/dev/null || true
    recording_output=$(simctl launch "$device_id" "$bundle_id" "--ui-$screen")
    recording_pid="${recording_output##*: }"
    sleep 3
    if ! kill -0 "$recording_pid"; then
        simctl spawn "$device_id" log show --last 1m --predicate 'process == "MeetMind"' > "build/smoke/$screen-failure.log" 2>&1 || true
        find "$HOME/Library/Logs/DiagnosticReports" -name 'MeetMind*.ips' -mmin -5 -exec cp {} build/smoke/ \; || true
        exit 1
    fi
    simctl io "$device_id" screenshot "build/smoke/$screen.png"
done
simctl terminate "$device_id" "$bundle_id" 2>/dev/null || true
minutes_sent_output=$(simctl launch "$device_id" "$bundle_id" "--ui-minutes-sent")
minutes_sent_pid="${minutes_sent_output##*: }"
sleep 4
if ! kill -0 "$minutes_sent_pid"; then
    simctl spawn "$device_id" log show --last 1m --predicate 'process == "MeetMind"' > "build/smoke/minutes-sent-failure.log" 2>&1 || true
    find "$HOME/Library/Logs/DiagnosticReports" -name 'MeetMind*.ips' -mmin -5 -exec cp {} build/smoke/ \; || true
    exit 1
fi
simctl io "$device_id" screenshot build/smoke/minutes-sent.png
echo "PASS: onboarding, Profile long-content, main tabs, recording, and post-meeting visual states stayed alive"
