# Verification status

Use the current GitHub Actions run for `codex/offline-intelligence` as the
source of build/test results. A green Release build alone is not a passing suite.

The old report of 646 passing executions described a separate Python simulation.
It did not execute Swift or catch the device launch crash. It is not release
acceptance evidence.

Run native tests on macOS with Xcode 26+ / Swift 6.2+:

```sh
bash Scripts/prepare_llama.sh
xcodebuild test -project MeetMind.xcodeproj -scheme MeetMind \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -resultBundlePath build/TestResults.xcresult
```

Choose an installed simulator shown by `xcrun simctl list devices available`.
The workflow selects an available iPhone automatically. It preserves XCTest
result bundles and simulator launch screenshots as artifacts.

Cross-platform structural and package checks:

```sh
python -X utf8 Scripts/verify_project.py
python Scripts/validate_ipa.py MeetMind/Resources/Info.plist
python Scripts/validate_ipa.py path/to/MeetMind.ipa
```

These checks validate source/project structure and bundled declarations; they do
not execute the app. See REPAIR_NOTES.md for device acceptance checks and known
product limitations.
