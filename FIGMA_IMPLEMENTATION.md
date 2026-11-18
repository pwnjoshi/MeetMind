# Native screen implementation and verification

Primary reference: the eight iPhone screenshots supplied in this chat (welcome, empty/populated Meetings, microphone idle/sample, recording/paused/finish).

The welcome layout uses local Continue and Not Now actions, as explicitly confirmed by the user. No sign-in is added.

Secondary reference: https://www.figma.com/design/Tar6q6zhuhMDIOBlSKzkdI/MeetMind?node-id=161-552

Status: in progress. Existing views and passing unit tests do not prove visual fidelity.
Each flow needs reference inspection, implementation, simulator comparison, accessibility
checks, and a working navigation path before it can be marked verified.

| Flow | Figma reference | Current implementation / remaining work |
| --- | --- | --- |
| Meetings home | 1408:3209 | Native grouped rows and independent Search tab added in 6502a1f; CI and visual comparison pending |
| First launch | 1343:2039 | Inspect and match empty state and creation entry points |
| Create menu | 1376:3223 | Quick Meet, Schedule Meet, Import Audio wired; verify native menu placement |
| Search | 1359:2430, 1361:2387, 1361:2712 | Native search field wired; match idle, focused, scopes, results, and no results |
| Import audio | 231:727 | Native form, file replacement, editable title, recorded date, local series selection/creation and save protection implemented; native and visual validation pending |
| Meeting series | 788:1580, 788:1659, 788:1685, 788:1709 | Local membership, import selection/creation, timeline, Add Meeting and rename implemented; native, migration and visual checks pending |
| Meeting details | 161:844 | Match title, agenda, date/time, participants, series, repeat, coordinator, save and discard |
| Participants | 673:1591, 1563:14, 1563:863 | Match add, search, create person, and inline edits |
| Follow-up | 1552:408 | Implement date/time, series selection, and saved occurrence |
| Calendar | 161:1005, 161:1034 | Inspect integration against local-only requirement; system permission UI must be native |
| Microphone | User screenshots 4–5; 161:1089, 161:1151 | Temporary record/play/retry, actual input route and error recovery implemented; simulator render and physical playback checks pending |
| Recording | User screenshots 6–8; 161:1171, 161:1328 | Dark console, timer, real waveform, transcript toggle, pause/resume, bookmark and native Finish alert implemented; rendered comparison and device checks pending |
| Recording tools | 161:1234, 161:1270, 161:1287, 161:1308 | Match notes, parked topics, and photo attachment with persistence |
| Notes only | 161:1372 | Implement complete manual minutes flow |
| Speakers | 161:1482, 161:1524, 1568:183 | Match anonymous speaker review, sample playback, name selection and search |
| Meeting record | 411:661 | Match minutes, transcript, decisions, tasks, review state, options and finalization |
| Source review | 161:1610, 161:2494 | Match source playback, timestamps and accessible larger text |
| Decision editing | 161:2516, 161:1705 | Match editing, wording review and persistent changes |
| Share minutes | 664:1652, 161:1912, 161:2135, 161:2150 | Resolve local-only adaptation; never simulate delivery or recipient acknowledgements |
| Actions | 161:2056 | Match list, completion, filtering, sorting, assignment scopes and empty states |
| Task detail / edit | 517:1285, 161:1755, 161:1782, 161:2532 | Match owner, due date, evidence, task state and durable edits |
| New action | 1614:2 | Match manual action sheet, due picker and meeting selection |
| Task responses | 161:2096, 161:2109, 161:2124 | Resolve local-only interpretation; no invented remote responses |
| Minutes Studio | 169:624 through 169:768 | Implement type, templates, document format, letterhead, attendance, contents and document preview |
| Decision Explorer | 161:1573 | Inspect reference and implement source-grounded navigation |
| MeetIQ | 161:2230, 161:2245 | Existing local Q&A; match question/answer UI, evidence and unavailable states |
| Series comparison | 161:2271, 161:2291 | Implement grounded comparison and changes between meetings |
| Approvals | 161:2475, 161:2171 | Resolve local review adaptation; no simulated network approval |
| Settings / profile | 161:2315, 161:2360 | Match local profile, preferences, privacy and model management |
| Local recordings | 605:1723, 735:1501 | Match storage list and playback; verify update preserves recordings |
| Notifications | 405:638 | Inspect local notification/inbox scope and truthful status |
| Account / workspaces | 161:554, 161:624, 161:639, 161:666 | Adapt to user's explicit no-account, on-iPhone requirement; flag differences before implementation |

Archived variants and design-resource frames are references, not additional active
destinations. Working-copy speaker/task variants must be compared with the primary
flows before choosing their final presentation.

## Platform verification

The last completed CI used Xcode 26.6 and the iOS 26.5 SDK. The physical test phone
runs iOS 26.5.2. iOS 27-specific behavior requires an available matching toolchain
and simulator; it has not been verified. Use native controls and availability guards.

## Acceptance for each screen

- Match reference hierarchy, spacing, typography, assets, content and presentation.
- Verify every action reaches its actual destination and saves/reloads real data.
- Check empty, loading, failure, cancellation and unsaved-change states.
- Check Dynamic Type, VoiceOver labels, contrast, Reduce Motion and dark appearance.
- Compare simulator renders against the reference; preserve private phone content.
- Record the source commit and build tested. Keep unfinished rows explicitly pending.
