# App Privacy answers (App Store Connect, "App Privacy")

## Answer

**Data Not Collected.** In App Store Connect choose "No, we do not collect data from this app". Tracking: No.

Apple defines "collect" as transmitting data off the device in a way that lets you or a third party keep it longer than needed to service the request. Manent never transmits user data off the device, so nothing is collected.

## Evidence (verified in the code)

| Question | Finding | Where |
|---|---|---|
| Does the app make network requests? | One use: downloading public model files from `huggingface.co` with an ephemeral `URLSession` and a plain GET per file. No cookies, no identifiers, no body. | `OfflineEngineKit/Sources/OfflineEngineKit/ResumableModelDownloader.swift`, URLs in `Resources/models.json` (every URL is `https://huggingface.co/...`) |
| Do the models load anything else from the network? | WhisperKit is created with `download: false` and a local model folder. FluidAudio models are loaded from local folders. | `LocalSpeech.swift` (`WhisperKitConfig(... download: false)`, `loadDiarizerModels(folder:)`) |
| Analytics, crash reporting, ads, attribution SDKs? | None. The only dependencies are WhisperKit (argmax-oss-swift), FluidAudio and the llama.cpp binary. | `OfflineEngineKit/Package.swift` |
| Speech recognition sent to Apple? | No. Live captions require on-device recognition. | `request.requiresOnDeviceRecognition = true` in `SpeechTranscriptionService.swift` and `LiveCaptionEngines.swift` |
| Accounts or identifiers? | None. No sign-in, no IDFA, no `identifierForVendor` use. | Search for `ASIdentifierManager`, `identifierForVendor`: no results |
| Data synced to a server or iCloud by the app? | No. | No CloudKit, no iCloud entitlement |

## If Apple asks about specific types

| Data type | Collected | Note |
|---|---|---|
| Audio data | No | Recorded and processed on the device only. |
| User content (notes, photos, minutes) | No | Stays in the app container. |
| Contacts | No | Manent has its own name directory and does not read the Contacts database. |
| Calendar and reminders | No | Manent writes Calendar follow-up events on request. It exports selected Manent actions to Reminders and can update those exported reminders from Manent. It does not read upcoming Calendar events or import reminder completion. EventKit operations stay on the device. |
| Identifiers, usage data, diagnostics | No | None gathered. |
| Location, health, financial, browsing | No | Not accessed. |

## Re-check before each release

Any of these changes the answer. Update the label before shipping:

- Adding crash reporting or analytics (MetricKit data forwarded to a server counts).
- Adding a cloud backup, sync, or sharing server.
- Adding a web view or remote configuration.
- Adding sign-in.

Apple's own TestFlight and App Store crash data is collected by Apple and does not need declaring.
