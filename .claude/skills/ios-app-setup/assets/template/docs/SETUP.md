# Setting up __APP_NAME__

Everything that needs your own logins, in order. Each step is a few minutes in a browser; the
rest is automated. Steps marked **once per account** were done for an earlier app and carry
over: reuse what you made then.

## Apple

**1. Developer agreement (once per account, then whenever Apple updates it).** Open
https://developer.apple.com/account and accept any agreement banner, then check
https://appstoreconnect.apple.com/agreements for anything pending. Until the Account Holder
accepts the latest agreement, Apple's API refuses every request with "A required agreement is
missing or has expired". The free apps agreement is enough.

**2. App Store Connect API key (once per account).** One key serves every app on the team.
https://appstoreconnect.apple.com/access/integrations/api, Team Keys, Generate, role **Admin**
(so it can create the signing certificate), download the `.p8`. Note the **Key ID** and the
**Issuer ID** above the list. The **Team ID** is at https://developer.apple.com/account under
Membership details.

**3. The app record (once per app).** https://appstoreconnect.apple.com/apps, the plus button,
New App:

- Platforms: iOS
- Name: __APP_NAME__ (any name if that one is taken; it can change before release)
- Primary language: English (U.S.)
- Bundle ID: __APP_NAME__ - __BUNDLE_ID__
- SKU: `__APP_SLUG__-ios`

If the bundle id is not in the list yet, run the TestFlight workflow once first: it registers
the App ID, turns on Sign in with Apple for it, and then stops with this same instruction.

## GitHub

**4. The certificates repository (once per account).** A private repository holds the signing
certificate, encrypted, so this one can be public. Every app shares it: the certificate is the
team's, and each app adds its own profiles next to it. If you have one already
(`__MATCH_GIT_URL__`), reuse it with the same passphrase. Otherwise create a private repository
and a fine-grained personal access token (github.com, Settings, Developer settings,
Fine-grained tokens) with Contents: Read and write on that one repository.

**5. Seven secrets (once per app).** https://github.com/__GITHUB_REPO__/settings/secrets/actions,
New repository secret, one at a time. GitHub never shows a secret again once saved, so these
come from wherever you keep them (a password manager), not from the other app's settings:

| Secret | Value |
| --- | --- |
| `APPLE_TEAM_ID` | The 10-character Team ID |
| `ASC_KEY_ID` | The API key's Key ID |
| `ASC_ISSUER_ID` | The Issuer ID |
| `ASC_KEY_CONTENT` | The `.p8` file's contents, pasted as text |
| `MATCH_PASSWORD` | The passphrase that encrypts the certificates repository |
| `MATCH_GIT_URL` | `__MATCH_GIT_URL__` |
| `MATCH_GIT_TOKEN` | The fine-grained token from step 4 |

Lost the `.p8`? Make a new key in step 2; the old one can be revoked. Lost the passphrase? The
stored certificate can't be opened: set any new `MATCH_PASSWORD`, then run the TestFlight
workflow by hand with `rotate_signing` ticked (below), which starts the store over.

**6. Keep Actions free.** github.com, Settings, Billing and licensing, Budgets and alerts:
leave the Actions budget at $0 with "Stop usage when budget limit is reached" ticked. While this
repository is public, Actions minutes cost nothing; if it ever goes private, running out pauses
builds instead of billing.

## Cloudflare

**7. Connect the Worker (once per app).** The database `__APP_SLUG__` already exists and is bound
in `wrangler.jsonc`; the server makes its own tables on first use. In the Cloudflare dashboard:

1. **Workers & Pages**, **Create application**, **Import a repository**, GitHub.
2. When it asks which repositories its GitHub app may read, add `__GITHUB_REPO__` to the ones
   it has already. It gets read access to those only.
3. Choose `__GITHUB_REPO__`, then:
   - **Project name:** `__APP_SLUG__-api` (it must match `name` in `wrangler.jsonc`)
   - **Build command:** empty
   - **Deploy command:** `npx wrangler deploy`
   - **Root directory:** `/`
   - **Production branch:** `main`
4. Under the advanced settings: **Builds for non-production branches** off, and **Build watch
   paths** `server/api/*` and `wrangler.jsonc`, so app-only pushes don't rebuild it.
5. **Deploy.**

Check it: `__API_BASE_URL__` shows `__APP_NAME__`, and `/privacy` shows the privacy page. Then
say so in the Claude session: the app gets the address in its next build.

## TestFlight

**8. Your phone.** After the first upload, open the app in App Store Connect, TestFlight,
Internal Testing, and create a group with "Enable automatic distribution" on. Add yourself.
Every build then reaches the TestFlight app on your phone a few minutes after processing.

**9. Friends and family, later.** External Testing, a new group, Public Link off: invite by
email only, since a public link works for anyone it is forwarded to. Fill in Test Information
(a one-line description, your feedback email, and `__API_BASE_URL__/privacy` as the privacy
policy). The first build goes through Beta App Review, usually within a day; the reviewer signs
up with their own Apple Account, so keep `SIGNUPS` open until it is approved.

## If the certificate store was ever exposed

Set a new `MATCH_PASSWORD` secret, then Actions, TestFlight, Run workflow, tick
`rotate_signing`. That run revokes the team's distribution certificates and profiles, creates new
ones encrypted with the new passphrase, and builds as usual. Builds already in TestFlight keep
working. It reaches every app on the team, so each other app needs one TestFlight run
afterwards (with the new `MATCH_PASSWORD` in its secrets too) before it can ship again. Only a
run started by hand with the box ticked does this; no commit message or push can.
