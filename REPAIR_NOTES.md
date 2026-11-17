# Launch crash investigation

## Confirmed failure

28 locally synced iPhone crash reports dated 17 November 2026 show the same
`EXC_BREAKPOINT` / `SIGTRAP` in SwiftData, called by
`ActionItemsViewModel.fetchActionItems()` during `ActionItemsViewModel.init` as
`MainTabView` is constructed. Reports cover debug and release builds on an
iPhone 15 (`iPhone15,4`), iOS 26.5.2. Raw reports are intentionally excluded from
Git because they contain device and signing identifiers.

The default initializer created a local in-memory `ModelContainer`, kept its
`mainContext`, then fetched after the container went out of scope. The same
lifetime pattern existed in Home, MeetingSetup, FolderTag, and AudioImport view
models. All five now retain containers they create. The Actions tab also receives
the app's persistent context directly. A regression test constructs the default
view models and fetches after initialization, and another reopens an on-disk store.

The first launch displayed onboarding without constructing the main tabs. Once
onboarding was saved, subsequent launches constructed those tabs immediately.
This explains the observed first-launch versus relaunch behavior. Permission
granting itself is not the stack location of the reported crash.

## Other defects addressed

- Startup storage errors now show a retry screen and preserve the store instead
  of silently switching to volatile storage or calling `fatalError`.
- Sample meetings are no longer injected into production on every empty store.
- Recording now binds to the saved meeting and real audio engine, requests mic
  permission, saves to Documents/Recordings, updates timer/meter, and feeds live
  speech recognition with copied audio buffers. Stop failures are shown.
- Processing now resolves the persisted meeting and injects real speech and
  extractive summarization services. Transcription failures are shown instead
  of navigating to an apparently successful result.
- Playback/export services are injected into the meeting detail screen; PDF
  output can be shared, and the delete button now confirms and deletes a meeting.
- Audio import fails if its persistent copy cannot be written.
- Home Schedule/Import menu entries route directly to their workflows; the
  previously inert filter button opens a filter selection sheet.
- Unsupported background-processing declaration removed; background audio stays.
- CI validates the compiled plist, runs XCTest on a simulator, preserves result
  bundles, and identifies the generated IPA as unsigned and requiring re-signing.
- Tracked Python bytecode removed and cache files ignored.

## Build and installation

The pre-existing `build/MeetMind.ipa` is stale. Its actual bundled plist lacks
`NSCalendarsFullAccessUsageDescription` and `NSRemindersFullAccessUsageDescription`
even though the source already contained them. It is not a rebuilt deliverable.
`python Scripts/validate_ipa.py build/MeetMind.ipa` rejects it. Always download the
artifact for the new commit from GitHub Actions after the complete workflow passes.

GitHub's generated IPA has code signing disabled. An authorized sideloading tool
must sign it for the device; preserve the existing bundle ID/signing identity when
updating if retaining the installed app's data is required.

## Verification limits and remaining product gaps

Windows cannot execute Xcode, the iOS simulator, or Swift XCTest. The Python
`run_unit_tests.py` script executes a separate simulation, not the Swift app.
The actual Swift tests run in GitHub Actions. The previously noncompiling E2E
suites referenced nonexistent APIs; they have been replaced with 14 concrete
Swift integration tests, while unit suites were updated for actor isolation and
asynchronous recording startup. Passing a compile or simulation
does not establish physical microphone, background, or device launch behavior.

The Figma home reference reviewed is file `Tar6q6zhuhMDIOBlSKzkdI`, node `161:777`.
Rendered app comparison on iOS is still required; exact visual parity has not
been certified.

Per the user's decision, onboarding is now local and account-free. The welcome
artwork remains, with an optional name and a Continue on this iPhone action.
Simulated authentication, voice-enrollment UI, and the unimplemented iCloud toggle
are removed from the active flow. Speech locale, on-device mode, audio quality,
and noise suppression now configure the recording/processing services. Reminders
sync uses EventKit and displays errors. Physical-device verification remains
required for these integrations. Calendar synchronization and automatic speaker
diarization are not implemented; speaker attribution is manual.

Physical-device acceptance should cover fresh install, onboarding with denied and
granted permissions, repeated force-quit/relaunch, recording/pause/resume/stop,
background/interruption, playback after relaunch, import, export, deletion, and
storage failure. Do not uninstall the existing app solely to troubleshoot this
crash: doing so can remove its saved meetings.
