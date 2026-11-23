# Pricing and launch checklist

## Pricing recommendation

Launch free, with no in-app purchase, for version 1.0.

Reasons: there is no server cost to recover (everything is on-device), a free no-account app has the lowest review friction (no StoreKit review, no paywall rules), and early reviews matter more than early revenue. You can add one non-consumable "Manent Pro" later (for example PDF letterhead, unlimited Vidur history, larger models) at a one-time price such as 799 INR / 9.99 USD. Do not take payment for features that were free in 1.0 without telling users.

If you want revenue at launch: free download plus a one-time Pro unlock. Needs a Paid Applications agreement, tax and banking details in App Store Connect, and a StoreKit implementation that does not exist yet.

## Checklist

### One-time setup (user must do personally)

- [ ] Enrol in the Apple Developer Program: 99 USD per year (about 8,900 INR). Individual enrolment takes from minutes to a few days. An organisation needs a D-U-N-S number (free, takes days to weeks).
- [ ] In the developer portal, register the explicit App ID `com.meetmind.app` (Certificates, Identifiers & Profiles). Enable no extra capabilities (the app needs none beyond defaults; Background Modes are plist-only). If `com.meetmind.app` is taken, choose a new id and tell the engineering lead to change `PRODUCT_BUNDLE_IDENTIFIER` and the `BGTaskSchedulerPermittedIdentifiers` patterns in Info.plist.
- [ ] Create an "Apple Distribution" certificate. Export it from Keychain Access as `.p12` with a password.
- [ ] Create an "App Store" provisioning profile for `com.meetmind.app` using that certificate. Download the `.mobileprovision`.
- [ ] In App Store Connect: My Apps > New App. Platform iOS, name, primary language, bundle id, SKU (any unique string, for example `manent-ios-1`).
- [ ] Create an App Store Connect API key (Users and Access > Integrations > App Store Connect API, role App Manager). Save the Key ID, Issuer ID and the one-time `.p8` download.
- [ ] Add the GitHub secrets listed in `.github/workflows/release.yml`.
- [ ] Host `docs/privacy-policy.md` and `docs/support.md` (GitHub Pages is enough), fill in the contact email, and note both URLs.

### Build and test

- [ ] Run the `Release to TestFlight` workflow (Actions tab, Run workflow). Build number is the run number.
- [ ] Wait for "Processing" to finish in App Store Connect (5 to 30 minutes) and answer the export compliance question if it appears (the plist already answers "No").
- [ ] Internal testing (up to 100 people on your team) needs no review. External testing needs a short Beta App Review.
- [ ] Install on at least one older and one newer iPhone. Record a 10 minute meeting, check minutes, kill the app mid analysis and relaunch, test airplane mode after models are downloaded, test low storage.

### Submission

- [ ] Fill in the listing from `listing.md`, privacy answers from `privacy-labels.md`, screenshots from `screenshots.md`.
- [ ] Paste `review-notes.md` into App Review Information.
- [ ] Select the processed build, set "Release manually" for the first version.
- [ ] Add for Review. First review usually takes 24 to 48 hours. Expect at least one round of questions about background audio and model downloads.
- [ ] Release, then run `launch-post.md`.

## Costs

| Item | Cost |
|---|---|
| Apple Developer Program | 99 USD per year |
| Hosting policy and support page (GitHub Pages) | 0 |
| GitHub Actions macOS minutes | free tier is limited for private repositories (macOS minutes count 10x). A release build takes about 20 to 40 minutes. Public repositories are free. |
| Custom domain (optional) | about 10 to 15 USD per year |
