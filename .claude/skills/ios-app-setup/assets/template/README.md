# __APP_NAME__

__APP_PITCH__

Native iOS 26, SwiftUI, Swift 6 with complete concurrency checking, for iPhone and iPad. Sign in
with Apple, a small server on Cloudflare's free plan, and TestFlight builds from GitHub Actions,
so no Mac is needed.

## Layout

```
project.yml              XcodeGen spec: the app, unit tests, UI tests (screenshots)
Shared/privacy.json      The privacy text, shown in the app and served at /privacy
__APP_TYPE__/
  App/                   The App, AppModel (session and data), RootView
  Core/                  Theme, Keychain, FreshInstall
  Models/                User, Note, AppError
  Services/              AppAPI protocol, MockAPI (built-in demo data)
  Services/Live/         HTTPClient (bearer auth, one refresh at a time), TokenStore, LiveAPI, DTOs, AppleNonce
  Features/              SignIn (Apple, then a username), Home, Settings (privacy, sign out, delete account)
__APP_TYPE__Tests/       Swift Testing: nonce, tokens, sign-up ticket, HTTP client against a stub
__APP_TYPE__UITests/     Walks every screen on demo data and saves screenshots
server/api/              The Worker: src/worker.js, schema.js, crypto.js; tests on Node's built-in SQLite
wrangler.jsonc           The Worker's settings, at the top so Workers Builds deploys from the root
fastlane/Fastfile        TestFlight from CI: App IDs, Sign in with Apple, signing, build, upload
docs/                    SETUP.md (your one-time steps), SERVER.md, API.md, screenshots/
```

## Build

The Xcode project is generated from `project.yml`, so it never conflicts in git.

```sh
brew install xcodegen
xcodegen generate
open __APP_TYPE__.xcodeproj
```

With no server address in `project.yml` (`APIBaseURL`) the app runs on `MockAPI`, and the
sign-in screen offers "Try the demo". `-mockAPI` as a launch argument forces it either way.

## Server

```sh
cd server/api && node --test --no-warnings
```

Deployed by Workers Builds from `main`. See docs/SERVER.md.

## Shipping

GitHub Actions builds and tests every push to a `claude/` branch (`.github/workflows/ios.yml`).
A commit on the `testflight` branch builds a signed Release and uploads it (docs/SETUP.md for
the one-time steps).
