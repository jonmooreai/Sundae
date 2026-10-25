# Sundae on your iPhone via TestFlight

The `TestFlight` workflow builds a signed Release on a GitHub macOS runner and uploads it to
App Store Connect. No Mac needed. Two things need your Apple and GitHub logins; everything
else is automated.

## Your part, once

**0. Accept the current developer agreement.** Open https://developer.apple.com/account and
accept any agreement banner at the top, then check https://appstoreconnect.apple.com/agreements
for anything marked pending. Apple's API refuses every request ("A required agreement is
missing or has expired") until the Account Holder has accepted the latest Apple Developer
Program License Agreement. The free apps agreement is enough; paid apps is not needed.

**1. Create an App Store Connect API key.** Open
https://appstoreconnect.apple.com/access/integrations/api, choose Team Keys, and click
Generate (or the plus button). Name it anything, pick the **Admin** role so the key can create
the signing certificate on the first run, then download the `.p8` file. It can only be
downloaded once. Keep that page open: you need the **Key ID** of the new key and the
**Issuer ID** shown above the list. Your **Team ID** is at
https://developer.apple.com/account under Membership details.

**2. Create the app record** at https://appstoreconnect.apple.com/apps: the plus button, then
New App. Platforms iOS, Name Sundae (any name works if that one is taken; it can be changed before
release), Primary language English (U.S.), Bundle ID "Sundae - com.jonmooreai.sundae", SKU
`sundae-ios`. Apple's API can do everything else but not this; it is the one form that needs a
browser. If the bundle id is not in the list yet, run the workflow once first: it registers the
App IDs and then stops with this same instruction.

**3. Add five secrets** at https://github.com/jonmooreai/Sundae/settings/secrets/actions
(New repository secret, one at a time):

| Secret | Value |
| --- | --- |
| `APPLE_TEAM_ID` | Your 10-character Team ID |
| `ASC_KEY_ID` | The API key's Key ID |
| `ASC_ISSUER_ID` | The Issuer ID |
| `ASC_KEY_CONTENT` | The contents of the `.p8` file, pasted as text (open it in any text editor) |
| `MATCH_PASSWORD` | Any passphrase you choose; it encrypts the signing certificate |

That's it. Say so in the Claude session and the build will be started for you, or start it
yourself: Actions → TestFlight → Run workflow. Any push to the `testflight` branch starts one
too (`git push -f origin HEAD:testflight`), as does a commit whose message contains
`[testflight]`; the latter skips the ordinary CI build for that commit. A head commit whose
message contains `[skip ci]` never starts a build on any branch; push a new commit in that case.

## What the first run does

Registers the App IDs `com.jonmooreai.sundae` and `com.jonmooreai.sundae.widget`, checks that
the app record exists, creates a distribution certificate and provisioning profiles, then builds
and uploads. The certificate is stored encrypted with your `MATCH_PASSWORD` on a `certificates`
branch of this private repository, so later runs reuse it. Later runs take about 15 minutes and
only build and upload.

## After the first upload

In App Store Connect open the Sundae app, go to TestFlight, then Internal Testing, and create a
group with "Enable automatic distribution" on. Add yourself as a tester. Every build then
lands in the TestFlight app on your phone a few minutes after processing. The phone needs
iOS 26.

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
