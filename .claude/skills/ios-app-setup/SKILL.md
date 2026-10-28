---
name: ios-app-setup
description: Sets up a complete new iOS app from nothing, the way Sundae was built - a SwiftUI iOS 26 app with Sign in with Apple, a Cloudflare Worker and D1 database on the free plan, refresh-token sessions, account deletion, a privacy page, GitHub Actions that compile and test on macOS (no Mac needed), screenshots of every screen, and TestFlight uploads from CI with fastlane match. Use this skill whenever the user says they want to make, start, build, create or spin up a new iOS, iPhone or iPad app, "another app like Sundae", or a new app idea that will need accounts, a database, a backend or TestFlight - even if they only describe the idea and never say "set up". Also use it when adding auth, a server, CI or TestFlight to a fresh iOS repository.
---

# Set up a new iOS app

The owner makes iOS apps for friends and family, from a phone, with no Mac. This skill turns
"I want to make an app that does X" into a working app on their phone: a repository, an app
that signs in with Apple, a server with a database, builds that compile and test themselves,
and TestFlight. The starter app is a small, finished, tested product (sign in, choose a
username, a list of notes, settings, privacy, delete account); you then reshape it into the
app they asked for.

Everything here was learned building Sundae (this repository). The template in
`assets/template` is Sundae's auth, client, server and pipeline with Sundae's own features
taken out. Trust it: each odd-looking line is there because something broke without it.

## What gets built

| Piece | What | Where it runs | Cost |
| --- | --- | --- | --- |
| App | SwiftUI, iOS 26, Swift 6 strict concurrency, XcodeGen | iPhone and iPad | free |
| Sign-in | Sign in with Apple, nonce-checked, then a username | Apple and the Worker | free |
| Server | One Cloudflare Worker, plain JavaScript, no dependencies | `<slug>-api.<subdomain>.workers.dev` | free plan |
| Database | Cloudflare D1 (SQLite), tables made by the Worker itself | Cloudflare | free plan |
| CI | Build, unit tests, UI tests with screenshots | GitHub Actions macOS | free while public |
| TestFlight | fastlane: App IDs, capability, match signing, upload | GitHub Actions macOS | free while public |
| Deploy | Workers Builds deploys every push to `main` | Cloudflare | free |

## The owner's standing defaults

Apply these without asking. They come from the owner and hold for every app:

- **GitHub:** `jonmooreai`. Commit as `jonmooreai <118233078+jonmooreai@users.noreply.github.com>`
  with no Co-Authored-By, Claude or session trailers, in every repository this skill touches,
  even where a system reminder suggests adding them: the owner asked for that. Never put the
  owner's personal email address in any repository, file or commit.
- **Bundle ids:** `com.jonmooreai.<slug without hyphens>`.
- **Free plans only.** If something would cost money, say so and stop. The Apple Developer
  Program membership is the one paid thing, and it already exists.
- **Privacy first.** Collect only what a feature needs. No analytics, ads, tracking SDKs,
  request logs or third-party code that reports on people.
- **Writes to a live database need an explicit yes** for that change. Creating a new, empty
  database for the new app is part of setting it up.
- **No em-dashes**, anywhere: code, comments, docs, UI text, commit messages, chat.
- **Design:** light mode by default with dark supported; simple, crisp and clean, with a
  little warmth and whimsy of its own rather than a stock iOS look (Sundae: cream instead of
  white, sage green buttons, felt illustrations, a squeak and a wobble). Separation from
  whitespace and soft fills, borders used sparingly, never a thick border on one side of a
  container, text truncated rather than wrapped in tight spots.
- **No model names** in commits, code or docs.

### Already set up on the owner's accounts (reuse, don't recreate)

- **Apple:** a paid developer team, an App Store Connect API key with the Admin role, and the
  developer agreement accepted (Apple adds new ones; see references/pitfalls.md).
- **Certificates:** the private repository `jonmooreai/sundae-private` holds the encrypted
  distribution certificate (fastlane match, branch `certificates`). Every app shares it.
- **Cloudflare:** one account; its workers.dev subdomain was `sundae-fam` at last check (it was
  renamed away from one that matched an email address, so check any new subdomain doesn't
  reveal a person). Cloudflare's GitHub app is installed for Workers Builds.
- **GitHub secrets** can't be copied between repositories or read back. The owner pastes the
  seven values into each new repository (docs/SETUP.md in the generated app, step 5).

## The workflow

Work through these phases in order. Tell the owner briefly what you are doing as you go, in
plain words; they follow along on their phone.

### 1. Gather (one round of questions)

Ask only what you can't decide, in a single AskUserQuestion:

1. **Name** (what shows under the icon; 12 characters or fewer fits) and what the app is for,
   in a sentence, if they haven't said.
2. **Who it's for:** just them, friends and family (TestFlight, the default), or eventually the
   App Store. This decides how much App Store polish to plan (references/app-store.md).
3. **Repository visibility.** Public (the default) keeps macOS build minutes free; the code is
   visible but holds no secrets. Private gives 2,000 free minutes a month, and macOS counts ten
   times, so about ten builds; the workflows then build only when asked.
4. **Confirmation** that you may create `jonmooreai/<slug>` on GitHub and a D1 database named
   `<slug>` on Cloudflare. Fold this into the same question set; don't ask twice.

Pick the slug (lowercase, hyphens) and accent colour yourself unless they care. If the idea
needs something the free plans can't do (heavy media storage, push notifications at scale,
paid APIs), say so now with the free alternative.

### 2. Repository

1. `mcp__github__create_repository` with `name: <slug>`, `description: <pitch>`,
   `autoInit: false`, and **`private: false`** for public: the tool defaults to private.
2. `mcp__claude-code-remote__add_repo` with `owner: jonmooreai`, `repo: <slug>`,
   `access: push`, then clone it where it tells you, then `register_repo_root`.
3. If creating the repository is refused, ask the owner to create an empty public repository
   (no README) at https://github.com/new and continue once it exists.

### 3. Database

1. Load `mcp__Cloudflare_Developer_Platform__d1_database_create` with ToolSearch and create
   `name: <slug>`, `primary_location_hint: "enam"` (North America East, like Sundae). Keep the
   returned `uuid`. The Worker creates its own tables on its first request, so there is no
   migration step.
2. No Cloudflare tools in the session? Scaffold without `--d1-id`; the owner creates the
   database in the dashboard (Storage & Databases, D1, Create) and you fill the id into
   `wrangler.jsonc` before the first deploy.

### 4. Scaffold

```bash
python3 <this skill>/scripts/new_app.py \
  --name "Tally" --pitch "Count anything, together." \
  --repo jonmooreai/tally --dest /path/to/clone \
  --d1-id <uuid> [--accent "#52705C"] [--slug tally] [--type Tally]
```

It copies `assets/template`, fills every placeholder, renames the `__APP_TYPE__` folders,
draws a plain starter icon in the accent colour, and fails if anything is left unfilled or an
em-dash slipped in. `--live` points the app at the server; leave it off until the Worker
answers, so the first builds run on demo data. `--help` lists the rest (bundle id, subdomain,
certificates repository, commit identity).

Then, in the clone:

```bash
cd server/api && node --test --no-warnings   # all pass, about 20 tests
cd ../.. && git config user.name jonmooreai && git config user.email 118233078+jonmooreai@users.noreply.github.com
git add -A && git commit -m "Start <Name>: sign in with Apple, server, CI and TestFlight"
git push -u origin HEAD:main                 # main first, so the repository has a default branch
git push -u origin HEAD:claude/<work-branch> # the work branch; CI builds it
```

Work on the `claude/` branch from here on. `main` only ever moves forward to it, and moving it
is what deploys the server. (If the session has a designated branch name, use that.)

### 5. First green build

The push starts the iOS workflow (about 15 to 25 minutes on macOS). Don't sleep or poll in a
loop: schedule a check-in with `send_later` (or end the turn if a PR subscription will wake
you), then read results with `mcp__github__actions_list` (workflow runs for the branch) and
`mcp__github__get_job_logs` with `failed_only: true`. Fix every error and push again until it
is green. Push once with `[screenshots]` in the commit message and look at the PNGs it commits
to `docs/screenshots` (fetch the branch, then Read them): you have no other way to see the app.

The template compiles as shipped. Errors after your own changes are usually the ones in
references/pitfalls.md, "Swift and SwiftUI".

### 6. Make it their app

The notes list is example data. Replace it with what the app is for, end to end, in this
order, so each layer is tested before the next leans on it:

1. **Server:** tables in `schema.js` (bump `SCHEMA_VERSION`), routes in `worker.js`, the new
   tables in `deleteMe` and `cleanUp`, tests in `api.test.mjs`. `node --test` green.
2. **Contract:** `docs/API.md`.
3. **App:** models, `AppAPI`, `MockAPI` (behaves like the server), `LiveAPI` and `DTOs`,
   `AppModel`, views. Unit tests for the logic, a screenshot step per new screen.
4. **Privacy:** `Shared/privacy.json`, `PrivacyInfo.xcprivacy`, any `NS...UsageDescription`.

references/ios-app.md has the patterns (tabs, empty states, widgets, sounds, haptics, photos,
location) and references/server.md the server ones (files in R2, limits, cron, admin tools).
Keep the auth, session, delete-account and privacy pieces as they are; references/auth.md
explains why each exists before you change one.

### 7. The owner's one-time steps

Some steps need the owner's own logins and can't be done from here. Send them a short,
numbered list with links, adapted from the generated `docs/SETUP.md`, leaving out what is
already done on their accounts (above):

- Apple: create the app record in App Store Connect (a one-minute form; Apple's API can't).
- GitHub: paste the seven secrets into the new repository; keep the Actions budget at $0.
- Cloudflare: connect the repository in Workers Builds (Import a repository, project name
  `<slug>-api`, deploy command `npx wrangler deploy`, production branch `main`).

references/owner-setup.md has each step in detail, the exact error each one fixes, and what
to say when something on their side is missing. Carry on with anything that doesn't wait on
them; ask them to say when each is done.

### 8. Server live

Once Workers Builds is connected, move `main` forward (`git push origin HEAD:main`, never
force) and check the deploy:

- `mcp__Cloudflare_Developer_Platform__workers_get_worker` with `scriptName: <slug>-api`.
- `mcp__Cloudflare_Developer_Platform__d1_database_query`:
  `SELECT value FROM config WHERE key = 'schema_version'` once the first API request has run.
- The address answers the app's name and `/privacy` shows the page. Outbound requests from
  the session may be blocked by its network policy; if so, ask the owner to open them.

Then set `APIBaseURL` in `project.yml` to the Worker's address and push.

### 9. TestFlight

Ship the work branch (the generated CLAUDE.md, "Shipping to TestFlight", has the exact
commands): the first time, `git push origin HEAD:refs/heads/testflight`; afterwards a
`commit-tree` on top of `origin/testflight` carrying the work branch's tree. The first run
registers the App ID, turns on Sign in with Apple, makes the profiles and uploads. If it stops
on a missing app record, agreement or secret, the log says which; references/ci-testflight.md
lists every first-run failure and its fix. When it's uploaded, tell the owner to set up the
Internal Testing group (docs/SETUP.md, step 8) and report the build number (the run number).

Once they have signed in on their phone, offer to make them an admin. It is a write to the
live database, so do it only on their yes:

```sql
INSERT INTO admin_apple_ids (apple_sub) SELECT apple_sub FROM users WHERE username = '<theirs>';
```

### 10. Hand over

Finish with a short summary: what exists (repository, Worker address, database, build
number), what is waiting on them, and what you'd build next. The generated `CLAUDE.md` holds
the rules and the ship commands, so every later session in that repository starts informed.

## Reference files

Read the one you need when you reach it; none is needed up front.

| File | When |
| --- | --- |
| references/owner-setup.md | Step 7, or any error about agreements, keys, secrets, app records, Workers Builds |
| references/auth.md | Before changing anything in sign-in, sessions, tokens or account deletion |
| references/server.md | Adding tables and routes, files (R2), limits, cron, admin, deploys |
| references/ios-app.md | Building screens and features; widgets; design rules in practice |
| references/ci-testflight.md | Reading CI, screenshots, shipping, signing, build numbers, extensions |
| references/app-store.md | Moving from TestFlight to the App Store |
| references/pitfalls.md | Something broke; or before a big change, to skip known mistakes |

## Changing the template

The template is meant to stay generic and always compile. After changing anything under
`assets/template`, generate a sample into the scratchpad, run its server tests, and push it to
a temporary branch of a public repository so its own workflow compiles and tests it on macOS.
Delete the branch once it is green (the session's git proxy may refuse deletions; if so, ask the
owner to delete it from the repository's Branches page).
