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

**3. A private repository for the signing certificate**, for example `sundae-private`, and a
fine-grained personal access token (github.com → Settings → Developer settings → Fine-grained
tokens) with Contents: Read and write on that one repository. The certificate is stored there
encrypted, so this repository can be public.

**4. Add seven secrets** at https://github.com/jonmooreai/Sundae/settings/secrets/actions
(New repository secret, one at a time):

| Secret | Value |
| --- | --- |
| `APPLE_TEAM_ID` | Your 10-character Team ID |
| `ASC_KEY_ID` | The API key's Key ID |
| `ASC_ISSUER_ID` | The Issuer ID |
| `ASC_KEY_CONTENT` | The contents of the `.p8` file, pasted as text (open it in any text editor) |
| `MATCH_PASSWORD` | Any passphrase you choose; it encrypts the signing certificate |
| `MATCH_GIT_URL` | `https://github.com/jonmooreai/sundae-private.git` |
| `MATCH_GIT_TOKEN` | The fine-grained token from step 3 |

That's it. Say so in the Claude session and the build will be started for you, or start it
yourself: Actions → TestFlight → Run workflow. Any push to the `testflight` branch starts one
too (`git push -f origin HEAD:testflight`), as does a commit whose message contains
`[testflight]`; the latter skips the ordinary CI build for that commit. A head commit whose
message contains `[skip ci]` never starts a build on any branch; push a new commit in that case.

## What the first run does

Registers the App IDs `com.jonmooreai.sundae` and `com.jonmooreai.sundae.widget`, checks that
the app record exists, creates a distribution certificate and provisioning profiles, then builds
and uploads. The certificate is stored encrypted with your `MATCH_PASSWORD` on the
`certificates` branch of the private certificates repository, so later runs reuse it. Later
runs take about 15 minutes and only build and upload.

## After the first upload

In App Store Connect open the Sundae app, go to TestFlight, then Internal Testing, and create a
group with "Enable automatic distribution" on. Add yourself as a tester. Every build then
lands in the TestFlight app on your phone a few minutes after processing. The phone needs
iOS 26.

## Inviting friends and family

Invite people by email, never with the public link. An email invitation is tied to that
person's Apple ID; a public link works for anyone it is forwarded to. Only people with the app
can create an account, because Apple issues sign-in tokens for this app to this app alone, so
the invitation list is the guest list.

1. In App Store Connect open Sundae, then TestFlight, then the plus next to External Testing,
   and create a group named Friends and Family. Leave Public Link off.
2. Under Test Information fill in a one-line description ("A photo dump for a few friends,
   open on Sundays"), your email for feedback, and the privacy policy address,
   `https://sundae-api.sundae-fam.workers.dev/privacy`.
3. Add a build to the group. The first one goes through Beta App Review, usually within a day.
   The reviewer signs in with their own Apple ID, so keep sign-ups open until it is approved,
   and delete that account afterward if you like.
4. Add testers by email. Each gets an invitation to install TestFlight and then Sundae.

Once everyone is in, sign-ups can be closed (`SIGNUPS` in docs/SERVER.md) so nobody new can
make an account even with the app.

## If the certificate store was ever exposed

Set a new `MATCH_PASSWORD` secret, then open Actions, TestFlight, Run workflow, tick
`rotate_signing` and run it. That run revokes the distribution certificates and profiles,
creates new ones encrypted with the new passphrase, and builds as usual. Builds already in
TestFlight keep working.

It reaches the whole Apple team, not only Sundae: every distribution certificate is revoked,
and every App Store, Ad Hoc and Developer ID profile is deleted, so any other app signed by the
team needs signing again afterward. Only a run started by hand with the box ticked does this;
no commit message or push can.

## What the build contains

Without a server, the app runs on its built-in demo data; docs/SERVER.md puts the real one
online. Onboarding offers "Continue in demo
mode", and Settings has a Demo section with "Pretend it's Sunday" so you can see every screen on
any day of the week.

The lane turns Sign in with Apple on for the App ID through the API key, and makes new profiles
on the run that does it. Push notifications still need their capability, so that entitlement is
left out of this build.

## Costs

While the repository is public, GitHub Actions minutes are free. Once it is private, the free
plan includes 2,000 minutes a month, and macOS runners cost about ten times Linux, so the
workflows hold back on their own:

- TestFlight builds (about 15 minutes on macOS) run only when started on purpose, as always.
- The iOS build and unit tests (20 to 35 minutes on macOS) run on a push only when the commit
  message contains `[ios]` or `[screenshots]`, or when started by hand from the Actions tab.
  While public they still run on every push.
- The server checks run on Linux in under a minute, on every push that touches the server or
  the build setup (workflows, project.yml, the Fastfile).
- Nothing runs twice: `main` is a copy of the work branch, so workflows only watch the work
  branch and `testflight`.

Leave the Actions budget at $0 under GitHub's Settings, then Billing and licensing, then
Budgets and alerts, with "Stop usage when budget limit is reached" ticked, so running out of
minutes pauses builds instead of billing.
