# Building the app

Patterns for the iOS side: how the template is put together, how to add a feature end to end,
the design rules in practice, and the extras most apps grow (tabs, empty states, widgets,
sounds, permissions). The code examples are trimmed from Sundae, where each one shipped.

## Contents

1. How the template is put together
2. Adding a feature end to end
3. Design in practice
4. Screens: tabs, navigation, empty states, loading, errors
5. Admin and preview switches
6. Permissions: photos, location, notifications
7. Widgets
8. Sound and haptics
9. Images and the app icon
10. Accessibility and phone fit
11. Screenshots from CI

## 1. How the template is put together

```
App/ <Name>App          @main; makes AppModel, puts it in the environment, calls start() and becameActive()
App/AppModel            @MainActor @Observable: session (currentUser, signupTicket), data (notes), actions
App/RootView            restoring → spinner; signupTicket → UsernameView; signed in → HomeView; else SignInView
Services/AppAPI         protocol: every call the app makes to its server
Services/MockAPI        actor: in-memory server with the same rules, for demo builds, previews and tests
Services/Live/*         HTTPClient (actor), TokenStore, LiveAPI (actor), DTOs, AppleNonce, APIConfiguration
Models/Models           Codable, Sendable value types; AppError with plain-words messages
Core/Theme              colour tokens (light and dark), radius, padding, display font
Features/<Area>/        one folder per area: views and anything only they use
```

Rules that keep it working under Swift 6 strict concurrency:

- `AppModel` is `@MainActor`; views read it with `@Environment(AppModel.self)`.
- Anything crossing an actor boundary (models, DTOs, errors) is a `Sendable` value type.
  Internal structs whose properties are all `Sendable` get it implicitly; generic wrappers
  don't, so mark them.
- Static helpers that tests call from outside the main actor are `nonisolated static`.
- No global mutable state. A shared `UserDefaults` or formatter is a computed property or a
  `let` of a `Sendable` type, never a `static var`.

## 2. Adding a feature end to end

Server first (references/server.md), then:

1. **Model** in `Models/` (`Codable, Hashable, Sendable, Identifiable`). Property names are the
   camelCase of the server's snake_case keys, so no `CodingKeys` are needed.
2. **`AppAPI`**: the new calls, in plain terms (`func lists() async throws -> [TodoList]`).
3. **`MockAPI`**: implement them with the same rules as the server (ownership, limits, errors).
   Seed a little made-up data if empty screens would hide the design.
4. **`LiveAPI`**: one `client.get/post/patch/delete` per call; request bodies as small structs
   in `DTOs.swift` when they differ from the model.
5. **`AppModel`**: state (`private(set) var lists: [TodoList] = []`), a `loadX()` that sets a
   `loadFailed` flag only when there is nothing to show, and actions that update state after
   the server agrees. Load it in `didSignIn` and `becameActive` if it should stay fresh. Clear
   it in `endSession`.
6. **Views** in `Features/<Area>/`. Small views; split anything long (see pitfalls).
7. **Tests**: logic in `<Name>Tests` with Swift Testing against `MockAPI`; new wire formats in
   `HTTPClientTests` against the stub; a step in `ScreenshotTests` for each new screen.
8. **Privacy**: `Shared/privacy.json`, `PrivacyInfo.xcprivacy`, usage strings in `project.yml`.

## 3. Design in practice

The owner's taste: light by default, simple, crisp and clean, but not a stock iOS app: each
app gets a little warmth and personality (Sundae had a cream background, sage green buttons,
felt illustrations, a cherry that squeaks and wobbles, faint film grain). In practice:

- **Colour:** every colour is a token in `Theme` (or an asset colour) with a light and a dark
  value. Warm off-white background, a slightly darker warm surface for fields and quiet
  containers, one accent. No hard-coded colours at call sites.
- **Separation from space and tone, not lines.** Group with padding and a surface fill.
  `List` with `.scrollContentBackground(.hidden)` on `Theme.background` and no white row
  backgrounds where the design wants an open page (`.listRowBackground(Color.clear)`). If a
  divider is needed, a hairline. Never a thick border on one side of anything.
- **Type:** system fonts; a serif display face for titles (`Theme.display`). Keep one title
  size per screen; truncate with `lineLimit` and `.truncationMode(.tail)` rather than
  shrinking text to fit. For tighter title lines use `.leading(.tight)`, never
  `.lineHeight(.multiple(...))` (it clips descenders on iOS 26).
- **Controls:** system ones (`.borderedProminent`, `.capsule`, `.controlSize(.large)`), 44 pt
  targets, `ContentUnavailableView` or the `EmptyState` below for empty screens.
- **Words:** short, specific and kind. Errors say what to do next ("You're offline. Try again
  when you're connected."). No exclamation marks, no jargon, no em-dashes.
- **Motion:** small and meaningful; honour Reduce Motion (`@Environment(\.accessibilityReduceMotion)`).

## 4. Screens

### Tabs that go back to the top when tapped again

People expect tapping the current tab to pop back to its first screen. Count taps on the
selected tab and clear that tab's path:

```swift
struct RouteStack: View {
    let root: Route
    var reselects = 0                       // bumped by the tab bar when its tab is tapped again
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            RouteView(route: root)
                .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
        .onChange(of: reselects) { _, _ in path.removeAll() }
    }
}
```

With a `TabView(selection:)`, a custom `Binding` that sees the same tab set twice increments
that tab's counter. On iPad's split view, do the same for the detail column.

### Empty states, centred in the space

An empty screen shows an icon, a title, a line and maybe a button, centred both ways on the
screen's own background, never in a card or a list row:

```swift
struct EmptyState<Actions: View>: View {
    var symbol: String?; var title: String?; var message: String?; var actions: Actions?
    var body: some View {
        VStack(spacing: 10) {
            if let symbol { Image(systemName: symbol).font(.system(size: 36)).foregroundStyle(.secondary) }
            if let title { Text(title).font(Theme.display(24)) }
            if let message { Text(message).font(.subheadline).foregroundStyle(.secondary) }
            if let actions { actions.padding(.top, 6) }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 360)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

Inside a `ScrollView` with a header above, `maxHeight: .infinity` has nothing to fill; give
the content the viewport's height with `containerRelativeFrame(.vertical)` measured in a
background and applied as `frame(minHeight:)`. As an overlay on a `List`, it centres itself.

### Loading and errors

`RootView` shows a spinner only while restoring the session. Lists show cached content while
refreshing (`.refreshable`), an empty state when there is truly nothing, and a quiet "Couldn't
load" state with "pull to try again" only when loading failed and there is nothing cached.
Never block a screen on a network call it doesn't need.

## 5. Admin and preview switches

Put testing switches in Settings, in an Admin section shown only when `model.isAdmin` (the
server decides; see references/auth.md). Sundae had "Pretend it's Sunday", a holiday picker
and "Birthday week", each an `@Observable` property whose `didSet` also updates anything that
mirrors it (the widget). This lets the owner see every state on a real phone with real data,
which matters when nobody has a Mac. Admin switches must never change what others see.

## 6. Permissions

Ask in context, at the moment the feature needs it, after a sentence of your own that says
what it is for. Usage strings in `project.yml` are plain and specific:

- **Photos:** prefer `PhotosPicker`, which needs no permission at all. Ask for library access
  only when the app must read photos by itself (Sundae showed this week's photos first).
  Handle Limited access. Strip location and camera metadata before anything leaves the phone.
- **Location:** When In Use only, the coarsest that works (`CLLocationManager` with reduced
  accuracy is often enough). Say exactly when it is used.
- **Notifications:** needs the Push capability on the App ID and an APNs key, and a server
  that sends; plan it with the owner (it is free, but more setup). Local notifications need
  only the user's permission.
- **Contacts, camera, microphone:** each needs its usage string and a reason a reviewer
  would accept.

Every permission added means: usage string, `PrivacyInfo.xcprivacy` if data is collected,
`Shared/privacy.json`, and the App Store privacy answers.

## 7. Widgets

A widget is an app extension target (`app-extension`, `com.apple.widgetkit-extension`) with its
own bundle id (`<app>.widget`), its own App ID and profile (add it to `EXTENSIONS` in the
Fastfile), and its own `NSPhotoLibraryUsageDescription` if it reads photos.

**Sharing state without portal setup.** An app group needs a group id made in the developer
portal. A keychain access group needs nothing: every App Store profile already allows the
team's `TEAMID.*` wildcard. Sundae shared a small key-value store as one keychain item:

- `project.yml`: both targets list `keychain-access-groups` with
  `$(AppIdentifierPrefix)<bundle id>.shared` (the app's own group first, so its tokens stay
  where they were), and an Info.plist key with the same value for the code to read.
- `SharedStore`: reads and writes one dictionary as a keychain item in that group, behind a
  lock; falls back to the process's own `UserDefaults` when the keychain refuses (unsigned
  simulator builds), so CI still runs.
- The app writes what the widget shows (a small `Codable` snapshot, not raw data) and calls
  `WidgetCenter.shared.reloadAllTimelines()` when it changes.

**Memory.** A widget extension is killed past about 30 MB. The symptom is the widget flashing
and snapping back when resized to large. Load only what the family shows, downsample images
with `CGImageSourceCreateThumbnailAtIndex` to the exact pixel size, use `PHImageManager` with
`.exact` resize mode and `deliveryMode: .highQualityFormat`, wrap each image in
`autoreleasepool`, and ship small (240 px) copies of decorative images in the widget's own
asset catalog.

**Matching the app.** Anything the app shows that the widget also shows (a seasonal icon, a
theme) is written to the shared store by the app, including admin previews, so the two never
disagree. The widget falls back to computing it only when nothing is stored.

**Buttons.** `Link` with a custom URL scheme (`CFBundleURLTypes` in `project.yml`) opens the
app at a place; `Button(intent:)` with an App Intent runs code. Icon-only buttons need an
`accessibilityLabel`.

## 8. Sound and haptics

- Haptics: a tiny `Haptics` enum over `UIImpactFeedbackGenerator` /
  `UINotificationFeedbackGenerator`; one tap for a pick, success for a completion.
- Sound: a short `.caf` or `.m4a` in Resources, one `AVAudioPlayer` made once (`static let`),
  `AVAudioSession` category `.ambient` so it respects the silent switch and never stops the
  person's music. Pair it with a small motion (Sundae's squeak and wobble) and keep it quiet.

## 9. Images and the app icon

- Decorative images go in the asset catalog as image sets (PNG, with transparency), `@2x`/`@3x`
  or a single large one with "Preserve Vector Data" off and `resizable()` in code. Keep the
  originals small; a 4 MB PNG costs launch time and widget memory.
- Images the owner sends in the chat arrive as files: crop and size them with Python (stdlib
  `zlib` PNG writing, or Pillow if installed), check them by reading the PNG back, and add
  them to `Contents.json` by hand.
- The app icon is one 1024 x 1024 PNG with **no alpha channel** (App Store Connect rejects
  one), in `AppIcon.appiconset` with a single universal entry. Optional dark and tinted
  variants are extra entries with `appearances` (see Sundae's). `new_app.py` draws a plain
  starter; replace it before inviting people.

## 10. Accessibility and phone fit

- Dynamic Type: system text styles or `relativeTo:`; test the largest size in a screenshot
  (`-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityL` as a launch
  argument).
- Every icon-only button has an `accessibilityLabel`; decorative images are
  `.accessibilityHidden(true)`.
- iPhone SE (375 pt wide) and iPad both work: no fixed widths beyond `maxWidth` caps, readable
  line length on iPad (`.frame(maxWidth: 520)` for forms).

## 11. Screenshots from CI

There is no simulator in the session, so screenshots are how you see the app. `ScreenshotTests`
launches with `-mockAPI`, walks the screens, and saves `iPhone-<nn>-<name>.png`. Push with
`[screenshots]` in the commit message; the workflow commits them to `docs/screenshots` on the
branch. Pull, then Read the PNGs. Add a step for every new screen, and take light and dark
(launch with `-appearance dark`) for anything colour-sensitive. When the owner sends a phone
screenshot of a bug, compare it against these to find what differs.
