# Screenshot plan

Manent is iPhone-only (`TARGETED_DEVICE_FAMILY = 1`). Do not upload an iPad screenshot set or describe the app as iPad-compatible.

## Sizes to capture

| Device | Pixels (portrait) | Required |
|---|---|---|
| iPhone 6.9" (iPhone 16/17 Pro Max) | 1320 x 2868 | Yes. Apple scales it down for smaller iPhones. |
| iPhone 6.5" (iPhone 11 Pro Max / XS Max) | 1284 x 2778 | Only if you do not supply 6.9". Supplying both is fine. |

Use the Simulator (Xcode > Window > Devices and Simulators) for exact sizes, with Status Bar set to 9:41, full battery, full signal (`xcrun simctl status_bar booted override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4`). Use the in-app fixtures where they exist: they work in Simulator through launch arguments `--ui-home-populated`, `--ui-meeting-finalized`, `--ui-recording-active`, `--ui-minutes-sent`. Do not show real people's names or real meeting content. Use the sample data.

Capture 6 screenshots per size, in this order. The first three decide most installs.

| # | Screen | Launch state | Caption (max about 40 characters, large type) |
|---|---|---|---|
| 1 | Finished minutes: summary, decisions, action items | `--ui-meeting-finalized` | Minutes written for you |
| 2 | Active recording with live captions and waveform | `--ui-recording-active` | Records and captions live |
| 3 | Onboarding or Settings > About showing "Recordings, transcripts and minutes stay on this iPhone" | Real build | Private. Stays on this iPhone. |
| 4 | Transcript with speaker names (and a Hindi or Hinglish passage) | `--ui-meeting-review` | Knows who said what |
| 5 | Vidur answering a question with a source link | Real build with sample meeting | Ask Vidur about any meeting |
| 6 | Export: PDF preview with letterhead, or Reminders export | `--ui-minutes-sent` | Share polished minutes |

Optional 7th: Home list (`--ui-home-populated`), caption "All your meetings, searchable".

## Rules

- Captions must describe what the build does. Do not claim "no internet needed" on the first download screen, because the models are downloaded once.
- No device frames are required. Plain full-bleed screenshots with a caption band are accepted.
- Keep text in the screenshot readable at thumbnail size.
- Localised sets: add Hindi captions later if you localise the listing.
- App Preview video (optional, 15 to 30 s): record a real flow on device with QuickTime, no music claims of features that do not exist.
