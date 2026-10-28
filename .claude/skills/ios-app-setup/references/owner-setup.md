# The owner's one-time steps

Everything that needs the owner's own logins, why it can't be done from a cloud session, and
the error that shows up when it is missing. The generated `docs/SETUP.md` is the owner-facing
version; this file is for you, to know what to ask for and how to read the failures.

Most of this was done once for Sundae. Per new app, the owner does three things: the App
Store Connect record, the seven GitHub secrets, and connecting Workers Builds.

## Contents

1. Apple: agreement, API key, app record, capabilities
2. GitHub: repository, secrets, budget
3. Cloudflare: database, Workers Builds, subdomain
4. TestFlight groups
5. How to ask

## 1. Apple

### Developer agreement (account-wide, recurs)

Apple publishes new agreements a few times a year, and until the Account Holder accepts,
**every** App Store Connect API call fails:

```
A required agreement is missing or has expired. This request requires an in-effect agreement
that has not been signed or has expired.
```

The fix is always the owner's: https://developer.apple.com/account (banner at the top) and
https://appstoreconnect.apple.com/agreements. The free apps agreement is enough. Ask, then
re-run the workflow (Actions, TestFlight, Re-run failed jobs, or push a new commit to
`testflight`).

### App Store Connect API key (account-wide, done)

Admin role, so match can create the distribution certificate on a first run. Key ID, Issuer
ID and the `.p8` contents become the `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_CONTENT`
secrets. The `.p8` downloads once; if the owner lost it, they generate a new key (and may
revoke the old). A key with a lesser role fails at `match` with a permissions error.

### The app record (per app, needs a browser)

Apple's public API can register App IDs and capabilities, but it can't create an app record;
fastlane's `produce` does that through an Apple ID web session, which a CI runner can't open.
The Fastfile checks for the record and stops with exact instructions:

```
No App Store Connect record exists for com.jonmooreai.tally yet, and Apple's API does not allow creating one.
```

Fields: Platforms iOS, Name (any if taken, changeable before release), Primary language
English (U.S.), Bundle ID chosen from the list, SKU `<slug>-ios`, User Access full. The bundle
id is only in the list after the App ID exists, so the clean order is: run the TestFlight
workflow once (it registers the App ID, then stops), owner fills the form, run it again.
You can also ask for the record first and let the first run register the App ID; either way
works. Name taken? Any name works for TestFlight; the Home Screen name comes from
`CFBundleDisplayName` in the build, not the record (the Fastfile logs both).

### Capabilities

Sign in with Apple is turned on for the App ID by the Fastfile through the API key. Others
(push notifications, app groups, iCloud) need the owner in the developer portal, or code in
the Fastfile with `create_capability` (see references/ci-testflight.md). Turning a capability
on invalidates profiles, so the lane forces new ones that run.

## 2. GitHub

### The repository

Created from the session with `mcp__github__create_repository` (pass `private: false` for
public; the tool defaults to private) and attached with `add_repo` (`access: push`). If the
session's GitHub access refuses, the owner creates an empty repository at
https://github.com/new with no README, licence or .gitignore (the scaffold brings its own).

### Secrets (per app)

https://github.com/jonmooreai/<repo>/settings/secrets/actions, New repository secret:

| Secret | Value | Missing means |
| --- | --- | --- |
| `APPLE_TEAM_ID` | 10-character Team ID | "Check secrets" step fails, naming it |
| `ASC_KEY_ID` | API key id | same |
| `ASC_ISSUER_ID` | Issuer id | same |
| `ASC_KEY_CONTENT` | the `.p8` text (raw or base64) | same; a mangled one fails at the API key step |
| `MATCH_PASSWORD` | the certificates passphrase | wrong one: "Couldn't decrypt the repo" |
| `MATCH_GIT_URL` | `https://github.com/jonmooreai/sundae-private.git` | |
| `MATCH_GIT_TOKEN` | fine-grained token, Contents read/write on that repository only | clone fails with 403 or "Authentication failed" |

Secrets can't be read back or copied between repositories (personal accounts have no
account-wide Actions secrets), so the owner pastes them from wherever they keep them. A
fine-grained token expires (they pick the lifetime, a year at most); when match starts
failing to clone with an auth error on every app at once, that is the token.

The workflow's "Check secrets" step names each missing one. Never ask the owner to paste a
secret into the chat; they enter it on GitHub.

### Budget

Settings, Billing and licensing, Budgets and alerts: Actions budget $0 with "Stop usage when
budget limit is reached". With a public repository standard runners cost nothing; this guards
against a repository going private and quietly billing.

## 3. Cloudflare

### Database

Created from the session (`d1_database_create`). Free plan: 10 databases per account, 500 MB
each, 5 GB total. Each app gets one. The Worker makes its tables on its first request.

### Workers Builds (per app, needs the dashboard)

There is no API in the session for connecting a repository, and the owner prefers no
Cloudflare token stored in GitHub, so Workers Builds (Cloudflare pulling from GitHub) does the
deploys:

1. Workers & Pages, Create application, Import a repository, GitHub.
2. Cloudflare's GitHub app is already installed; add the new repository to the ones it can
   read (it asks, or: github.com, Settings, Applications, Cloudflare Workers and Pages,
   Configure, Repository access).
3. Project name `<slug>-api` (must equal `name` in `wrangler.jsonc`, or the build fails with
   a name mismatch), build command empty, deploy command `npx wrangler deploy`, root `/`,
   production branch `main`.
4. Advanced: non-production branch builds off; build watch paths `server/api/*` and
   `wrangler.jsonc`.

A failed deploy shows in the dashboard under the Worker, Deployments, and as a red check on
the `main` commit on GitHub (`mcp__github__get_commit` or the commit's check runs).

### Subdomain

Every Worker on the account is `<worker-name>.<account-subdomain>.workers.dev`. Sundae's
account subdomain was renamed to `sundae-fam` because the original matched an email address,
which every API address would have shown. For a new app, check it before telling testers any
address: `workers_get_worker` and the first deploy's URL show it. A custom domain is possible
later on the free plan if the owner has one on Cloudflare.

## 4. TestFlight groups

- **Internal Testing** (up to 100 people on the team): the owner creates a group with
  automatic distribution and adds themself. No review. Builds arrive minutes after processing.
- **External Testing** (friends and family): a group with Public Link off, invitations by
  email only. Test Information needs a description, feedback email and the privacy policy URL
  (`<worker>/privacy`). The first build of each version goes through Beta App Review (usually
  under a day); the reviewer signs up with their own Apple Account, so keep `SIGNUPS` open.

## 5. How to ask

The owner reads on a phone. One short numbered list, each step with its link and the exact
values to type, nothing they've already done. Say what you'll do the moment they reply
("say done and I'll start the TestFlight build"). Don't re-ask for something already on their
account. When a run fails on their side, quote the one line of the error that matters and the
one step that fixes it.
