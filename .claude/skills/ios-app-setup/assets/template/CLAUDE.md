# __APP_NAME__

__APP_PITCH__

Read README.md for the layout, docs/API.md for the contract between app and server, and
docs/SERVER.md before changing the server.

## House rules

- **Privacy first.** Collect only what a feature needs. No analytics, ads, tracking, third-party
  SDKs or request logs. Every change to what is collected updates `Shared/privacy.json`,
  `__APP_TYPE__/Resources/PrivacyInfo.xcprivacy` and the App Store privacy answers together.
- **Free plans only.** Cloudflare free (Workers, D1, and R2 only within its free tier), GitHub
  Actions free (public repository), no paid services, APIs or add-ons. If something would cost
  money, say so and stop.
- **Live data needs a yes.** Never write to, migrate or delete from the live D1 database without
  the owner's explicit approval for that change. Reading it to check something is fine.
- **Commits** are authored as `__GIT_NAME__ <__GIT_EMAIL__>`, with no Co-Authored-By, Claude or
  session trailers, and no model names anywhere in commits, code or docs. Never put a personal
  email address in the repository.
- **No em-dashes**, anywhere: code, comments, docs, UI text. Use commas, colons or a rewrite.
- **Design.** Light mode by default, dark mode supported. Simple and clean, in the spirit of
  Apple's own apps: system controls, generous spacing, separation from whitespace and fills
  rather than borders, and never a thick border on one side of a container. Every colour lives
  in `Core/Theme.swift` or the asset catalog with a dark value.
- **Plain words** in the UI: short, specific and kind. Errors say what to do next.
- **Made-up people only** in examples, tests and screenshots: Pat Doe, 555 numbers.

## No Mac here

There is no Swift compiler in the cloud session. GitHub Actions on macOS compiles and tests
every push to a `claude/` branch; read the results with the GitHub tools (`actions_list`, then
`get_job_logs` for a failed job) and fix what they report before calling anything done. Push
with `[screenshots]` in the commit message to get every screen saved to `docs/screenshots`, and
look at them.

Things that have broken the build before:

- `#expect` or `#require` wrapped around a call that throws or rethrows fails to build. Assign
  the result first, or use a closure (`allSatisfy { $0.isDone }`) instead of a key path.
- Long SwiftUI modifier chains or ternaries inside `Text` time out the type checker. Split the
  view into smaller functions or properties.
- `.lineHeight(.multiple(...))` clips descenders on iOS 26. Use `.leading(.tight)`.
- A widget extension has a 30 MB memory limit: downsample images, load only what is shown.

## Server

`cd server/api && node --test --no-warnings` before every push that touches `server/`. A new
table joins `deleteMe` and the schema version goes up (docs/SERVER.md, "Changing the database").
Deploying is moving `main` forward to the work branch: `git push origin HEAD:main` (a
fast-forward; never force). Check the deploy afterwards with the Cloudflare tools.

## Shipping to TestFlight

The `testflight` branch only moves forward. To ship the work branch as it is now:

```bash
git fetch origin testflight
git push origin "$(git commit-tree "HEAD^{tree}" -p origin/testflight -m "Ship $(git rev-parse --short HEAD)"):refs/heads/testflight"
```

(The very first time, when there is no `testflight` branch yet: `git push origin HEAD:refs/heads/testflight`.)
The build takes about 15 minutes and lands in TestFlight a few minutes after that. Its build
number is the workflow's run number. Rotating the signing certificate is only ever a box ticked
in a run started by hand.
