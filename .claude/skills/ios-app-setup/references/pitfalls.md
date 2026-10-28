# Pitfalls

Everything that went wrong building Sundae, with the fix. Skim the section you're in before a
big change; search it when something breaks.

## Contents

1. Swift and SwiftUI (compile errors)
2. SwiftUI behaviour
3. Tests and the UI test walk
4. CI and GitHub
5. Signing and TestFlight
6. Cloudflare
7. Product and words
8. Working with the owner

## 1. Swift and SwiftUI: compile errors

There is no compiler in the session; CI finds these. Write code that avoids them.

| Error | Cause | Fix |
| --- | --- | --- |
| `call can throw, but it is not marked with 'try'` inside `#expect`/`#require` | the macro expands around a throwing or rethrowing call (e.g. `allSatisfy(\.flag)` on a throwing sequence, or a function that throws) | assign first (`let x = try f(); #expect(x == 1)`), or use a closure: `allSatisfy { $0.flag }` |
| `the compiler is unable to type-check this expression in reasonable time` | long modifier chains, ternaries building `Text`, big `ViewBuilder` bodies | split into small `@ViewBuilder` functions or computed views; wrap each ternary branch: `Text(a ? "x" : "y")`, not `a ? Text("x") : Text("y")` with modifiers |
| `static property 'x' is not concurrency-safe because non-'Sendable' type 'UserDefaults'` | a `static let` of a non-Sendable type | a computed `static var` that returns it, or a `Sendable` wrapper |
| `non-Sendable 'DTO.X'-typed result can not be returned from actor-isolated instance method` | a generic DTO (`LossyList<T>`) has no implicit `Sendable` | mark it `Sendable` (with `T: Sendable`) or make it non-generic |
| `actor-isolated instance method can not be referenced from a nonisolated context` in an actor's `init` | calling an isolated method from `init` | build the data with a `static func make...() -> Data` and assign it |
| `struct 'Body' must be as accessible as its enclosing type because it matches a requirement in protocol 'ButtonStyle'` | a `private` or nested type used in a `ButtonStyle` | make the style `struct` internal at file level |
| `type 'X' does not conform to protocol 'ButtonStyle'` when wrapping `.bordered` | `.bordered` is a `PrimitiveButtonStyle`, not a `ButtonStyle` | branch with `if/else` between two `.buttonStyle` calls, or write your own `ButtonStyle` |
| `ambiguous use of 'none'` | an enum case named `none` used through an `Optional` | rename the case (`.notFollowing`) |
| `cannot find type 'X' in scope` after adding a package | the file didn't `import` it | import in every file that uses it; prefer no packages at all |

Also: never `#if DEBUG` away code a test needs; tests build in Debug, TestFlight in Release, so
something only in Debug passes CI and is missing on the phone.

## 2. SwiftUI behaviour

- **`.lineHeight(.multiple(factor:))` clips descenders** (g, y, p) on iOS 26. Use
  `.leading(.tight)` for tighter lines.
- **Appearance changes don't reach an open sheet.** `.preferredColorScheme` on the root
  doesn't restyle a presented sheet; setting the window's `overrideUserInterfaceStyle` alone
  didn't either. Apply `.preferredColorScheme` inside the sheet as well (and walk
  `presentedViewController`s if UIKit presents anything).
- **A `ZStack` of panes hidden with `opacity(0)` still takes taps**, so the visible pane's
  buttons stop working. Use a `TabView` with its bar hidden, or `if` to remove hidden panes.
- **iOS 26's search tab** (`Tab(role: .search)`) collapsed the other tabs in Sundae's layout;
  a custom tab bar was simpler and matched the design.
- **Tapping the current tab** should return to its root; it doesn't by default (ios-app.md).
- **Swipe back** stops working when the navigation bar is hidden; re-enable the interactive pop
  gesture (Sundae's `swipeBackEnabled()`).
- **Widgets flash and snap back** when resized to large: the extension ran out of its 30 MB.
  Load less, downsample, `autoreleasepool` (ios-app.md, widgets).
- **The widget showed a different seasonal icon from the app** after an admin preview: the
  widget computed its own. The app writes what the widget shows; the widget only falls back.
- **MapKit Look Around is unreliable** (often no imagery); a plain `Map` with a marker and an
  "Open in Maps" link is better. Free place photos don't exist through official APIs (Yelp's
  API is paid); Apple's place card via a Maps link is free.
- **Location permission never appeared** because onboarding only said it would ask. Call
  `requestWhenInUseAuthorization()` at that moment, and the same for notifications.
- **An awaited permission prompt blocked sign-in** (and the UI tests): never await a
  permission request on the sign-in path; run it in a separate `Task` after.

## 3. Tests and the UI test walk

- **Keychain writes fail in unsigned simulator builds** (no entitlements): tests use
  `InMemorySecretStorage`; shared stores fall back to `UserDefaults`.
- **xcodebuild prints `TEST EXECUTE SUCCEEDED`** with `test-without-building`; match
  `TEST (EXECUTE )?SUCCEEDED`.
- **System alerts** stop UI tests: `addUIInterruptionMonitor`, grant photos up front with
  `xcrun simctl privacy <udid> grant photos <bundle id>` after installing, seed the camera
  roll with `xcrun simctl addmedia`.
- **Element not found** after layout changes: give important controls a stable
  `accessibilityIdentifier` and wait with `waitForExistence(timeout:)`.
- **`Multiple matching elements found`** when tapping by label: the first time a keyboard
  appears on a fresh simulator, iOS shows a "slide to type" tip with its own **Continue**
  button, which collided with the template's own Continue on its first run. Tap by
  `accessibilityIdentifier`, and add `.firstMatch` to every query.
- **Attachment names with quotes** broke the artifact upload; name screenshots
  `<device>-<nn>-<name>.png` with plain characters only (the collector keeps only those).

## 4. CI and GitHub

- **`[skip ci]` anywhere in a head commit message** (even quoted, even explaining it) skips
  every workflow. Same for `[testflight]` and `[screenshots]`: they act wherever they appear.
  Never write a marker you don't mean.
- **Job logs 404 while a job is still running.** List the jobs to see step status; read logs
  once the job is done.
- **Artifacts can't be downloaded** through the session's proxy (Azure blob storage is
  blocked). That is why screenshots come back as a commit on the branch.
- **The screenshot commit moves the branch.** Pull (`git pull --rebase`) before pushing again,
  or the push is rejected.
- **`xcodebuild ... | head -1` aborted the build** (SIGPIPE). Use `awk 'NR==1'`, which reads
  everything.
- **`main` in the push triggers** runs everything twice, since `main` is a fast-forward of the
  work branch. Workflows watch `claude/**` and `testflight` only.
- **Force pushes to `testflight` are blocked** (GH013): ship with `commit-tree` on top.
- **Private repositories pay for macOS at 10x.** Sundae was made public for free minutes; keep
  the workflows' private-repository guards and the $0 budget.
- **Never mark something as compiled before CI says so.** Once Sundae's status was reported
  green before the run finished; it wasn't. Wait for the run.

## 5. Signing and TestFlight

- **`produce` doesn't accept an API key** (it needs an Apple ID): App IDs go through Spaceship
  (`Spaceship::ConnectAPI::BundleId.create`).
- **Apple's API can't create the app record.** One form for the owner (owner-setup.md).
- **"A required agreement is missing or has expired"** on every call: the owner accepts the
  new agreement. It comes back whenever Apple publishes one.
- **`No profile for team 'X' matching 'match AppStore ...'`**: the `APPLE_TEAM_ID` secret
  didn't match the key's team. The lane now trusts the profile's team.
- **The Home Screen showed the wrong name**: the name under the icon is the build's
  `CFBundleDisplayName`, not the App Store Connect record (which may differ when the name
  was taken). Set it in `project.yml`; the lane fails a build whose name is wrong.
- **Build numbers** read as `1.0 (183)`: the marketing version and the run number. That is
  expected; only App Store releases change `1.0`.
- **Builds feel slow** (about 15 minutes, then processing): don't wait for processing, skip
  the index store, don't run screenshots on TestFlight builds. Ship less often rather than
  trying to make each faster.
- **Capability turned on, old profiles invalid**: the lane forces new profiles that run.

## 6. Cloudflare

- **The workers.dev subdomain matched an email address** (`<name>.workers.dev` is the account
  subdomain, shown in every API address). Renamed it (`sundae-fam`). Check it for any new
  account before an address goes anywhere.
- **Workers Builds' non-production branch builds** ran a preview command that failed (no
  previews configured). Turn non-production builds off; `preview_urls: false` in
  `wrangler.jsonc` keeps preview addresses off too.
- **Project name must equal `name` in `wrangler.jsonc`.**
- **Workers Builds makes its own API token** (named after the project, e.g.
  `sundae-api-token`); it isn't a secret to copy anywhere.
- **Cache settings** in the dashboard aren't needed; the API sends `cache-control: no-store`.
- **R2 needs a payment method on the account** to turn on, even within the free tier. Ask.
- **50 D1 queries per request** on the free plan: the test harness fails past it. Batch, join,
  and avoid a query per item in a loop.
- **A returning person had to make their profile again** (an early Sundae bug): sign-in must
  look up the account by Apple `sub` first and sign straight in. The template does; keep it.

## 7. Product and words

- **The privacy text** should be plain, accurate and calm: what is used, what never is, how to
  delete. Don't name vendors (Cloudflare) where "our server" is true and clearer. Don't say
  "we keep your photos" when the meaning is "they're stored so your friends can see them".
- **Copy in the app** says the specific action ("Take a photo"), never slang or jokes that
  could land badly. Suggestions shown to people go through a content guard if generated.
- **Don't assume business features** (subscriptions, ads, teams). These are apps for friends
  and family unless the owner says otherwise.
- **Demo content** uses made-up people and free images from properly licensed sources, only in
  the mock; nothing in the repository from the owner's real data.
- **On-device generation** (Apple's Foundation Models) is free and private where available;
  check availability and fall back to curated text.

## 8. Working with the owner

- They read on a phone: short replies, one line per result, links they can tap.
- When something needs them, one numbered list with exact values, and what you'll do when they
  reply. Never ask them to paste a secret into the chat.
- They prefer recommendations to options. Pick, say why in a clause, and go.
- Ship to TestFlight when they ask; they test on their phone and send screenshots.
- Before a change that deletes data, costs money, or is hard to undo, ask once, clearly.
