# Sundae on your iPhone via TestFlight

The `TestFlight` workflow builds a signed Release on a GitHub macOS runner and uploads it to
App Store Connect. No Mac needed. One-time setup below, then every build is one button.

## One-time setup

**1. Apple Developer Program.** Enroll at developer.apple.com/programs (99 USD a year). Approval
can take a day or two. Note your Team ID from Membership details.

**2. App Store Connect API key.** At appstoreconnect.apple.com → Users and Access → Integrations
→ App Store Connect API → Team Keys → Generate. Role: Admin, so the key can create the signing
certificate and profiles on the first run. Download the `.p8` file once (it cannot be downloaded
again). Note the Key ID and the Issuer ID shown on that page.

**3. A private repo for signing certificates.** Create an empty private repository, for example
`sundae-certificates`. fastlane match keeps the distribution certificate and profiles there,
encrypted. Then create a fine-grained personal access token (github.com → Settings → Developer
settings → Fine-grained tokens) with Contents: read and write on that one repo.

**4. GitHub secrets on the Sundae repo** (Settings → Secrets and variables → Actions):

| Secret | Value |
| --- | --- |
| `APPLE_TEAM_ID` | Your 10-character Team ID |
| `ASC_KEY_ID` | The API key's Key ID |
| `ASC_ISSUER_ID` | The Issuer ID |
| `ASC_KEY_CONTENT` | The contents of the `.p8` file, pasted as-is (open it in any text editor) |
| `MATCH_GIT_URL` | `https://github.com/<you>/sundae-certificates.git` |
| `MATCH_GIT_TOKEN` | The fine-grained token from step 3 |
| `MATCH_PASSWORD` | Any passphrase you choose; it encrypts the certificates |

**5. Run the workflow.** Actions → TestFlight → Run workflow. Pick a bundle identifier that is
yours, like `com.jonmooreai.sundae`. The first run creates the App IDs, the App Store Connect
app record, the certificate and the profiles, then builds and uploads. Later runs reuse them.

**6. Add yourself as a tester.** In App Store Connect → your app → TestFlight → Internal Testing
→ create a group and add your Apple ID. Builds appear there a few minutes after upload, then
show up in the TestFlight app on your phone.

## What the build contains

Without a server, the app runs on its built-in demo data. Onboarding offers "Continue in demo
mode", and Settings has a Demo section with "Pretend it's Sunday" so you can see every screen on
any day of the week.

Sign in with Apple, push notifications and the shared widget state need capabilities on the App
ID that are not set up yet, so those entitlements are left out of this build. The widget still
shows the daily suggestion.

## Costs

Each TestFlight build uses about 15 minutes of macOS runner time, which counts 10x against the
free Actions allowance for a private repo. Builds are started by hand only.
