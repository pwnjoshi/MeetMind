# Manent Figma frame inventory

Source: Manent canvas `161:552`. Frame names and IDs are from Figma metadata. Presentation and implementation status need to be checked against each flow. Design resources, archived overlays, and reference-only fixtures are excluded from the runtime scope.


## 01 · Sign in

- Welcome and sign in (`161:554`)
- Verify email (`161:624`)
- Continue with Email (`1634:21`)
- Onboarding 1 · Record (`1797:12`)
- Onboarding 2 · Minutes (`1797:38`)
- Onboarding 3 · Vidur (`1797:64`)

## 02 · Meetings home

- Import audio (`231:727`)
- Meeting series (`788:1580`)
- Choose meeting series (`788:1659`)
- Series options (`788:1685`)
- Rename series (`788:1709`)
- Meetings home · First launch (empty) (`1343:2039`)
- Search · Idle (`1359:2430`)
- Search · Results (`1361:2387`)
- Search · No results (`1361:2712`)
- Meetings home (`1408:3209`)
- Search · Results · All (`1528:6995`)
- Search · Results · Meetings (`1528:7118`)
- Search · Results · Transcripts (`1528:7228`)
- Search · Results · Actions (`1528:7338`)
- Search · Focused (`1528:7580`)
- Menu · Import series (`1602:229`)
- Import · Recorded date popover (`1602:307`)
- Create meeting · Native menu (from floating +) (`1376:3223`)
- Series menu (`1727:7`)
- New Series · Alert (`1727:185`)

## 03 · Prepare a meeting

- Meeting details (`161:844`)
- Meeting title (`609:1917`)
- Meeting agenda (`609:1946`)
- Meeting date and time (`161:2420`)
- Add People · Sheet (`673:1591`)
- Connect Apple Calendar (`161:1005`)
- Calendar permission (`161:1034`)
- Discard meeting changes (`850:762`)
- Meeting save failed (`850:783`)
- New series · Alert (`1542:5322`)
- Menu · Series (`1542:5365`)
- Menu · Repeat (`1542:5515`)
- Menu · Coordinator (`1542:5653`)
- Schedule follow-up · Sheet (`1552:408`)
- Schedule follow-up · Date popover (`1554:704`)
- Meeting date · Calendar popover (`1559:527`)
- Discard changes · Meeting details (`1561:55`)
- New Person · Sheet (`1563:14`)
- Add People · Searching (`1563:863`)
- Schedule follow-up · Date popover · Ends (`1571:884`)
- Follow-up · Time entry · Starts (`1575:169`)
- Follow-up · Time entry · Ends (`1575:285`)
- Meeting details · Follow-up from minutes (`1871:2033`)

## 04 · Record

- Microphone check (`161:1089`)
- Live recording (`161:1171`)
- Finish recording (`161:1328`)
- Recording tools (`161:1234`)
- Attach a photo (`161:1308`)
- Microphone unavailable (`161:1151`)
- Notes Only (`161:1372`)
- Microphone permission (system prompt) (`1470:5874`)
- Camera · Attach Photo (system camera) (`1651:3`)
- Delete This Recording? · Sheet (`1715:2`)
- Add a Note · Compose bar (`1871:338`)

## 05 · Process and identify speakers


## 06 · Review and share minutes

- Meeting record (`411:661`)
- Choose recipients (`664:1652`)
- Delivery status (`161:1912`)
- Open shared minutes (`161:2135`)
- Shared minutes (`161:2150`)
- Meeting options (`602:1739`)
- Keep minutes private (`416:756`)
- People · Sheet (`1662:6`)
- Menu · Speaker 1 (`1662:491`)
- Menu · Speaker 2 (`1662:618`)
- Menu · Speaker 3 (`1662:743`)
- Edit Decision · Sheet (`1733:377`)
- Decision detail (`1823:16`)
- Menu · Decided by (`1849:421`)
- Share Minutes · Alert (`1854:88`)
- Edit Minutes · Sheet (all sections) (`1874:5`)

## 07 · Follow through

- Actions (`161:2056`)
- Task detail (`517:1285`)
- Edit assignment (`161:1755`)
- Choose task owner (`161:1782`)
- Choose task due date (`161:2532`)
- Confirm an assignment (`161:2096`)
- Request task correction (`161:2109`)
- Response recorded (`161:2124`)
- Repeat meeting (`161:2012`)
- Menu · Actions sort & filter (`1609:1111`)
- New Action · Sheet (`1614:2`)
- New Action · Due popover (`1614:439`)
- Menu · New Action meeting (`1614:635`)
- Menu · New Action owner (`1622:130`)
- Menu · Task assignee (`1839:7`)
- Task · Due popover (`1839:173`)

## 08 · Optional meeting tools

- Minutes Studio (`169:624`)
- Minutes meeting type (`169:642`)
- Minutes templates (`169:660`)
- Document format (`169:678`)
- Letterhead (`169:696`)
- Template saved (`605:1699`)
- Attendance (`169:714`)
- Attendance status (`169:732`)
- Minutes contents (`169:750`)
- Document preview (`169:768`)
- Vidur (`161:2230`)
- Answer with sources (`161:2245`)
- Compare a series (`161:2271`)
- Changes between meetings (`161:2291`)
- Submit for approval (`161:2475`)
- Approval submitted (`602:1712`)
- Approval requires review (`622:1715`)
- Vidur · This meeting and series (`1531:7386`)
- Answer · This meeting and series (`1531:7427`)

## 09 · Account and settings

- Settings (`161:2315`)
- Account (`161:2360`)
- Local recordings (`605:1723`)
- Notifications inbox (`405:638`)
- Workspaces (`161:639`)
- Create a workspace (`161:666`)
- Delete account (`161:2387`)
- Deletion requested (`161:2408`)
- Recording · Audio player (`735:1501`)
- Switch workspace (`1011:770`)
- Sign Out · Alert (`1794:13347`)
- Vidur Settings (`1887:826`)
- Menu · Vidur Model (`1887:1297`)
- Menu · Vidur Answer Length (`1887:1306`)
- Menu · Vidur Search Across (`1887:1315`)
- Clear Vidur History · Alert (`1887:1324`)

## Navigation contract

- Onboarding Continue advances one page. Get Started and Skip lead to local entry. Apple and email authentication frames conflict with account-free use.
- Meetings profile pushes Settings. The profile row pushes the local profile editor. Sign-out, account deletion, and verification screens do not apply to a local profile.
- Meetings plus opens the create menu. Quick Meet opens microphone check, then pushes recording. Schedule and Import open sheets.
- Recording close opens delete confirmation as a sheet. Stop presents save confirmation. Finishing opens the saved meeting review. Keep in Background returns to Meetings.
- Search is a native Search tab. Results push meeting detail. The system controls keyboard and dismissal behavior.
- Series selection uses a menu. New Series opens a naming alert.
- The People sheet, Vidur answers, minutes editing, task details, and sharing each require separate behavior and visual verification.
- Remote delivery and approval states need a local equivalent or a product decision. Explicit user-initiated export is available in the current app.
