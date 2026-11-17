# MeetMind test infrastructure

`MeetMindTests` is the XCTest target in `MeetMind.xcodeproj`. It covers models,
service contracts, view models, view construction, and integration workflows.
Tests use retained in-memory SwiftData containers and injected mocks. Hardware
behavior still requires device verification.

The launch-crash regression constructs all default container-owning view models,
yields, then fetches after initialization. A separate regression saves a meeting
with related notes and actions and reopens an on-disk SwiftData store.

Integration suites exercise local onboarding, persisted scheduling, action
completion and cascade deletion, recording completion/failure, transcript search,
playback seeking, local summaries, PDF generation, and preference persistence.
These are Swift integration tests, not automated physical-device UI sessions.

CI builds the Release app, validates the compiled Info.plist, compiles/runs
XCTest in a simulator, then checks onboarding and three main-tab cold launches.
The launch check records screenshots and verifies that each app process stays
alive. A successful workflow packages an unsigned IPA and release debug symbols.
Signing and device installation are separate operations.

`Scripts/run_unit_tests.py` is retained as a legacy host-side domain simulation.
Its counts and results cannot be used to certify native behavior or coverage.
`Scripts/verify_project.py` is a structural scan, not a Swift compiler.
