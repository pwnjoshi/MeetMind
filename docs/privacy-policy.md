# Manent Privacy Policy

> **SUBMISSION BLOCKER:** This policy is a template until the owner replaces `<DATE>`, `<YOUR NAME OR COMPANY>` and `<SUPPORT EMAIL>`. Do not host or submit this placeholder version as the production privacy policy.

Effective date: `<DATE>`
Developer: `<YOUR NAME OR COMPANY>`
Contact: `<SUPPORT EMAIL>`

Manent is an iPhone app that records meetings and writes minutes. It is built to keep your meeting content on your device.

## The short version

- Recordings, transcripts and minutes stay on this iPhone.
- Manent has no accounts, no analytics, no advertising and no tracking.
- The developer receives none of your data and has no server that could receive it.
- The only network use is downloading open AI model files, when you ask for them, from `huggingface.co`.

## What Manent stores on your device

Manent stores the following in its private app storage on your iPhone:

- Audio recordings of the meetings you record or import.
- Transcripts, speaker labels, minutes, decisions, action items and notes.
- Photos you attach to a meeting.
- Voice profiles you create when you name a speaker (numeric voice fingerprints, not recordings).
- Your name, title, signature, letterhead and logo for exported minutes.
- Questions you ask Vidur and its answers.
- App settings and the downloaded AI models.

This data is not uploaded by Manent. Manent has no iCloud sync. If you back up your device with iCloud or a computer, Apple's backup may include app data according to your device settings; Manent marks some temporary working files as excluded from backup.

## How your meetings are processed

- Live captions use Apple's speech recognition set to on-device mode. Audio is not sent to Apple for this.
- Transcription after a meeting uses OpenAI Whisper models running on your device.
- Speaker separation uses models running on your device.
- Minutes and Vidur answers are written by Qwen3 1.7B running on your device.

## Network use

Manent makes network requests for one purpose: downloading model files you chose to install, from `https://huggingface.co`. These are ordinary file downloads. Manent sends no meeting content, no account information and no identifiers with them. Hugging Face, like any web server, can see your IP address and the file requested. See Hugging Face's privacy policy at https://huggingface.co/privacy. After the models are installed, Manent works without an internet connection.

If you share minutes, you choose where they go: the iOS share sheet, Mail, Files or another app. Manent does not send them anywhere itself. Once you share a file, the receiving app or person controls it.

## Permissions

Manent asks for these only when needed. You can change them any time in iOS Settings.

| Permission | Used for | Required |
|---|---|---|
| Microphone | Recording meetings | Yes, to record |
| Speech Recognition | On-device live captions while you record | Optional |
| Calendars (full access) | Writing a follow-up event only when you ask; Manent does not read or show upcoming Calendar events | Optional |
| Reminders (full access) | Exporting selected Manent action items and sending later Manent completion updates to those exported reminders; Manent does not import reminder completion into the app | Optional |
| Camera | Photographing a whiteboard or slide to attach to a meeting | Optional |
| Photos | Attaching photos you pick to meeting notes or your letterhead | Optional |
| Notifications | Reminders about meetings and finished analysis | Optional |

Manent keeps recording when the screen locks or you switch apps (background audio). Analysis may continue in the background when iOS grants processing time, but iOS can suspend it; reopening Manent resumes saved work. Force-quitting Manent stops recording and analysis. iOS shows its recording indicator while the microphone is in use.

## Recording other people

Laws on recording conversations differ by country and region. You are responsible for telling participants and obtaining consent where the law requires it.

## Your control and deleting data

- Delete a single meeting inside the app.
- Settings (Profile) > Delete All Data erases everything Manent stored on the device, including recordings, minutes, voice profiles and Vidur history.
- Settings > Offline Analysis Models lets you remove downloaded models.
- Deleting the app removes its data from the device.
- Export All Minutes lets you keep a copy of your minutes before deleting.

Because the developer holds no copy of your data, the developer cannot access, recover or delete it for you.

## Children

Manent is not directed at children and collects no personal information from anyone, including children.

## Changes

If this policy changes, the new version will be posted at this address with a new effective date. A change that adds any collection of data off the device will also be shown inside the app before it takes effect.

## Contact

Questions about privacy: `<SUPPORT EMAIL>`.

## Open-source software

Manent includes open-source software and models. Licences are in the app under Settings > About and Licences.
