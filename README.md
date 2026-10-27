# Sundae

Your week in photos, shared with a few friends, in an app that only opens on Sundays. Native iOS, SwiftUI, one universal binary for iPhone, iPhone Duo and iPad.

The product requirements live in the PRD (Oct 24, 2026). This repo is the iOS client.

## Build

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen) so the project file never conflicts in git.

```sh
brew install xcodegen
xcodegen generate
open Sundae.xcodeproj
```

Requirements: Xcode 26, iOS 26 deployment target, Swift 6 with complete concurrency checking.

Pick the `Sundae` scheme and run on any iPhone or iPad simulator. Tests run with Cmd-U.

There is no backend yet. By default the app runs against `MockSundaeAPI`, an in-memory backend seeded with six friends, eight weeks of posts, pending tag requests and a follow request. The mock enforces the same rules the real server will (Sunday gate, one dump per week, edit lock, photo and tag caps, follows-only tagging), so the app behaves honestly before the API exists.

To point at a server, set `SUNDAE_API_BASE_URL` in the scheme's environment (or `SundaeAPIBaseURL` in Info.plist). `LiveSundaeAPI` then speaks the contract in [docs/API.md](docs/API.md). Pass `-mockAPI` as a launch argument to force the mock.

### Working on Sunday screens during the week

Debug builds have a **Developer** section in Settings with "Pretend it's Sunday" and "Pretend it's Wednesday". It shifts the app's clock and the mock's clock together, so the gate still holds. The debug switch is compiled out of release builds.

## Layout

```
project.yml              XcodeGen spec: app, widget extension, tests
Shared/                  Compiled into both the app and the widget
  SundayClock.swift      Week math: Monday 00:00 to Sunday 23:59, local time
  Suggestion.swift       Suggestion model and catalog (deterministic daily pick, shuffle)
  SharedDefaults.swift   App-group state for the widget (current suggestion, approvals badge)
  suggestions.json       Curated list of photographable suggestions, 122 so far (target ~200)
Sundae/
  App/                   SundaeApp, AppModel (session, phase, clock), RootView and the tab shell, App Intents
  Core/                  Theme, Icon, Haptics, Keychain
  Models/                User, Dump, Photo, Tag, Follow, Comment, Profile, DumpDraft, settings
  Services/              SundaeAPI protocol, MockSundaeAPI, PhotoProcessor, ImageDownsampler, PhotoLibrary, notifications,
                         NetworkMonitor, PendingPostStore (offline compose queue)
  Services/Live/         HTTPClient (bearer auth, single-flight refresh), TokenStore (Keychain),
                         DTOs, LiveSundaeAPI, BackgroundUploader (background URLSession to pre-signed URLs)
  Components/            PhotoView, AvatarView, PhotoCarousel, LikesLabel, UserRow, buttons
  Features/
    Weekday/             The weekday screen and its store
    Feed/                Sunday feed, post card, "Post your week" card
    Compose/             Compose screen, tag picker, reorder, alt text, this-week library grid
    Approvals/           Tag approvals (open every day)
    Profile/             Profile, week rows, collapsed empty weeks, edit profile
    Search/              People search, follow requests, suggested people, invite link
    Detail/              Post detail with comments, report sheet
    Settings/            Settings, auto-approve list, followers
    Onboarding/          Welcome, sign in, profile, invite your group
SundaeWidget/            Home Screen and Lock Screen widget: today's idea, days until Sunday
SundaeTests/             Swift Testing: week math, suggestion catalog, mock gate rules
docs/API.md              The REST contract the live client expects
```

## How the pieces fit

**The Sunday gate.** `SundayClock` decides what to draw from the device clock and zone. `AppModel.phase` is `.sunday` or `.weekday(daysUntilSunday:)` and flips itself at the next midnight boundary. `RootView` shows the weekday screen or the Sunday tab shell from that. The server (and the mock) is the authority for every read and write; the client never relies on its own gate for security.

**State lives in stores, not views.** `FeedStore`, `ComposeStore`, `ApprovalsStore` and `WeekdayStore` hang off `AppModel`, so switching tabs, moving between the iPad sidebar and the iPhone tab bar, or unfolding an iPhone Duo mid-compose keeps the draft, the scroll position's data and the selection.

**Size classes, not device checks.** `TabView` with `.sidebarAdaptable` gives a bottom bar in compact width and a sidebar in regular width. The feed is a `NavigationSplitView` in regular width (feed left, open dump or profile right) and a `NavigationStack` in compact. Compose puts the caption beside the grid in regular width.

**Photos.** `PhotosPicker` needs no permission. `PhotoProcessor` re-encodes every picked photo on device to a 2048 px JPEG through a fresh bitmap, which drops EXIF and GPS before upload. On the way back, `ImageDownsampler` decodes photos and avatars from the server at the size they are drawn, never in full, and refuses anything far larger than the app makes. Full library access is only requested for the "this week" filter and the "add Thursday's photos" prompt, with an explanation, and the picker keeps working if declined.

**Tags are consent-based.** A tag creates a pending request. The photo shows in the poster's week with the tag visible, but lands on the tagged person's profile only when approved. Decline removes the tag everywhere and nobody is told. Approvals, and the followers list in Settings, are the social screens open on weekdays.

**Offline compose.** Saving a post while offline writes the draft to Application Support and shows "will post when you're back online". `NetworkMonitor` watches the path; when it returns on the same Sunday the queued post goes up and lands at the top of the feed. If Sunday ended first the queue is dropped, because a missed week stays empty by design.

**Icons.** Phosphor Icons (MIT, THIRD_PARTY_NOTICES.md), only the ones in use, copied into `Assets.xcassets/Icons` in regular, bold and fill. `Core/Icon.swift` is the single place icon names live. The PhosphorSwift package used to bring all 9,108 icon files into every build, which cost minutes each time; to add an icon, copy its three imagesets from that release and add a case to `Ph`.

## What is in this scaffold and what is not

Built, against the mock:

- Weekday screen with curated suggestions, shuffle, done, countdown, approvals badge, settings
- Sunday feed, unranked, newest first, pull to refresh, infinite scroll, likes as names, comments
- Compose: 1 to 15 photos, chronological default, reorder, per-photo tags (up to 10), alt text, 300-char caption, comments toggle, post and edit until midnight, delete
- This-week camera roll filter and the Sunday "you marked this done on Thursday" prompt
- Tag approvals, open every day
- Profiles with week rows, own then tagged photos with "from Maya" chips, collapsed empty weeks, owner-only counts
- Search by name or username, follow and follow requests, suggested people, invite link
- Post detail with comments, report and block everywhere
- Settings: appearance, public account, followers you can remove, auto-approve list, comments, notification preferences, sign out everywhere, delete with fresh Face ID
- Onboarding: Sign in with Apple, phone fallback (labeled as weakest), 16+ check, invite your group
- Local Sunday 9 am reminder and 8 pm last call (cancelled on post)
- Widget (small, medium, Lock Screen rectangular and inline)
- Light and dark mode, Dynamic Type, VoiceOver labels on photos, Reduce Motion on the carousel, light haptics on post, approve, decline

- Live HTTP client with Keychain token storage (cleared on a fresh install, since the Keychain outlives a deleted app), rotating refresh tokens, background upload to pre-signed URLs, and an offline compose queue
- No contacts access: friends find each other by username, and the app never asks for the address book
- App Intents: "Show today's suggestion" and "Mark today's suggestion done" for Siri and Shortcuts
- iPad: drag photos into compose from Photos or Files, pointer hover on photos, Cmd-N to post, arrow keys through a carousel, Space for full screen

Not yet:

- A real backend. `docs/API.md` is the contract the client speaks.
- Passkeys (WebAuthn), App Attest. Sign in with Apple is wired through the UI to `auth/apple`.
- Live Activity, StandBy, Share Sheet extension
- App icon artwork
