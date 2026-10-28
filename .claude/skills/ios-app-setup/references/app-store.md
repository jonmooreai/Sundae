# From TestFlight to the App Store

Most of the owner's apps stay in TestFlight for friends and family, which needs nothing in
this file. Read it when an app is going to the public App Store, and plan the work with the
owner: several items need their logins, and some change the app.

## Contents

1. What changes when an app goes public
2. Before submitting: the app
3. Before submitting: the server
4. App Store Connect: the listing
5. App Privacy answers
6. Review notes and common rejections
7. After release

## 1. What changes

- Strangers can sign up. Consider whether `SIGNUPS` stays open, and whether the app needs
  reporting and blocking (any app where people see each other's content does: Guideline 1.2).
- Load is unknown. The free plan stops rather than bills, which is safe, but a popular app
  will hit 100,000 requests a day. Say so to the owner before release, with what it would
  take (Workers Paid is $5 a month); don't assume they'll pay.
- Review reads everything: privacy policy, permissions, account deletion, and Sign in with
  Apple behaviour.

## 2. Before submitting: the app

- [ ] **Account deletion** in the app (template has it: Settings, Delete account).
- [ ] **Apple token revocation** on deletion (references/auth.md, section 8). Apple asks for
      it for Sign in with Apple apps; build it before submission.
- [ ] **Real app icon** (1024 px, no alpha), not the generated starter.
- [ ] **No demo shortcuts** visible to the public: the "Try the demo" button only appears with
      no server address, so a live build never shows it. Admin sections only for admins.
- [ ] **Every permission** asked in context with a clear usage string.
- [ ] **Launch screen** colour matches the first screen in both modes.
- [ ] **Version**: `MARKETING_VERSION` set (1.0 for the first release), build numbers keep
      coming from the run number.
- [ ] **iPad**: the template supports iPad, so App Store needs iPad screenshots too, or set
      `TARGETED_DEVICE_FAMILY: "1"` for iPhone only before the first submission (it can't be
      removed later for that app).
- [ ] **Content reporting and blocking** if people see each other's content.
- [ ] **Age rating** answers ready (user-generated content raises it).

## 3. Before submitting: the server

- [ ] `/privacy` matches what the app does now (`Shared/privacy.json`; the test checks the page
      shows each section).
- [ ] A support page or address. The privacy page can carry a "Contact" section; a mailto link
      needs an address the owner chooses for this (never their personal one without asking).
- [ ] Per-person limits on everything that writes, so one account can't fill the database.
- [ ] `SIGNUPS` open.

## 4. App Store Connect: the listing

The owner fills these in App Store Connect (the API key could, but text this public is theirs
to approve). Draft them for the owner in plain, kind words:

- Name (30 characters), subtitle (30), description, keywords (100 characters, comma
  separated, no spaces needed), promotional text.
- Support URL and privacy policy URL (`https://<worker>/privacy`).
- Category, price Free, availability.
- Screenshots: 6.9" iPhone (1320 x 2868 or 1290 x 2796) and 13" iPad (2064 x 2752) if iPad is
  supported. The UI tests can produce them: run on those simulators with made-up data
  and save without status bar clutter (`xcrun simctl status_bar <udid> override --time 9:41
  --batteryLevel 100 --cellularBars 4 --wifiBars 3`). Make sure every person and number shown
  is made up.

## 5. App Privacy answers

App Store Connect, App Privacy. They must agree with `PrivacyInfo.xcprivacy` and the privacy
page. For the template as shipped:

| Data type | Collected | Linked to the person | Tracking | Purpose |
| --- | --- | --- | --- | --- |
| User ID (Apple's private id) | yes | yes | no | App Functionality |
| Name (optional, theirs to give) | yes | yes | no | App Functionality |
| Other User Content (notes) | yes | yes | no | App Functionality |

Everything else: not collected. No tracking, so no App Tracking Transparency prompt. Add a row
for each new kind of data (photos: Photos or Videos; location: Coarse/Precise Location;
contacts: Contacts; and so on), in all three places at once.

## 6. Review notes and common rejections

Review notes: "Sign in with Apple is the only sign-in. The reviewer can create an account
with their own Apple Account; nothing else is needed." If features depend on time or other
people (Sundae opened only on Sundays), explain how to see them, and consider an
admin-only switch the owner can grant the reviewer's account after it is created, or a server
setting like Sundae's `SUNDAY_EVERY_DAY` for the review window.

Rejections seen often for apps like these:

- 2.1 Information needed: the reviewer couldn't reach a feature. Fix with review notes.
- 4.8 Login services: Sign in with Apple only is fine; offering Google without Apple is not.
- 5.1.1(v) Account deletion: must be in the app, not by email.
- 5.1.1 Permissions: usage strings must say why, specifically.
- 1.2 User-generated content: needs report, block and a way to act on reports.
- 2.3.3 Screenshots: must show the app in use, not just a splash or sign-in.

## 7. After release

- Releases: a TestFlight build is promoted to a version in App Store Connect; the owner
  submits. Bump `MARKETING_VERSION` for each public version.
- Keep the server backward compatible: old app versions stay installed for months. Add fields
  and routes; never remove or rename one an old build uses without a version check.
- Watch the free plan limits in the Cloudflare dashboard after launch.
