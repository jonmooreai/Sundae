# CI and TestFlight

How the three workflows work, how to read their results from the session, how to ship, and
every first-run failure seen so far with its fix.

## Contents

1. The workflows and when they run
2. Reading results from the session
3. Waiting without polling
4. Shipping to TestFlight
5. What the TestFlight lane does
6. First-run failures and fixes
7. Adding an extension (widget) or capability
8. Costs and a private repository
9. Guards the tests enforce

## 1. The workflows

| Workflow | Runs on | When | Takes |
| --- | --- | --- | --- |
| `ios.yml` (job `build-and-test`) | macOS | every push to `claude/**` that touches app files; by hand | 15 to 25 min |
| `ios.yml` UI tests + screenshots | macOS, then Linux to commit | `[screenshots]` in the head commit message, or by hand | +5 to 10 min |
| `server.yml` | Linux | pushes touching `server/`, workflows, Fastfile, `project.yml`, `wrangler.jsonc` | under 1 min |
| `testflight.yml` | macOS | push to `testflight`, `[testflight]` in a message, or by hand | about 15 min |

`main` is never a trigger: it is always a fast-forward of the work branch, so it would build
everything twice. A head commit containing `[skip ci]` starts nothing anywhere; push another
commit. `[testflight]` in a work-branch message skips `build-and-test` for that commit (the
TestFlight build compiles it anyway).

## 2. Reading results from the session

- Runs: `mcp__github__actions_list` with `method: list_workflow_runs`, `owner`, `repo`,
  `workflow_runs_filter: {"branch": "<branch>"}`, `per_page: 5`. Match `head_sha` to your push.
- Jobs of a run: `method: list_workflow_jobs`, `resource_id: <run id>`.
- Logs: `mcp__github__get_job_logs` with `run_id` and `failed_only: true`, or `job_id`;
  `return_content: true` and `tail_lines: 300` to get the end. Search them for `error:`, then
  for `recorded an issue` (Swift Testing) and `XCTAssert` (UI tests).
- The build step pipes through `grep`, so the log shows errors, a few warnings and
  `BUILD SUCCEEDED/FAILED`; the full log is in the run's artifact (`build.log`).
- Fix every error in one push when you can. A failing unit test prints the expectation and the
  values; a type-check timeout names the line (see pitfalls).

## 3. Waiting without polling

Never `sleep` in a loop for CI. Either schedule one check-in with
`mcp__claude-code-remote__send_later` (`delay_minutes: 20` for a build, 18 for TestFlight)
and end the turn, or, when a PR is open and subscribed, let the PR events wake you. When the
check-in fires, read the run, fix or report, and schedule the next only if something is still
running. Tell the owner the result in one line: green with the build number, or what failed
and what you changed.

## 4. Shipping to TestFlight

The `testflight` branch only moves forward (protect it against force pushes in the repository
settings if the owner wants; Sundae's rules block them, which is why shipping is a new commit
on top rather than a reset). To ship exactly the work branch's files:

```bash
git fetch origin testflight
SHIP=$(git commit-tree "HEAD^{tree}" -p origin/testflight -m "Ship $(git rev-parse --short HEAD): <what changed>")
git push origin "$SHIP:refs/heads/testflight"
```

First time ever: `git push origin HEAD:refs/heads/testflight`.

The build number is the workflow's run number (`GITHUB_RUN_NUMBER`), which only goes up, so
each upload is accepted. The marketing version (`MARKETING_VERSION` in `project.yml`, 1.0)
changes only for App Store releases. Report the run number to the owner as the build number
they'll see in TestFlight.

## 5. What the TestFlight lane does

`fastlane ios beta` (`fastlane/Fastfile`), in order:

1. `setup_ci` (a temporary keychain).
2. The App Store Connect API key from the secrets (raw `.p8` or base64).
3. App IDs for the app and every entry in `EXTENSIONS`, through Spaceship, skipping existing
   ones. (`produce` can't: it needs an Apple ID login.)
4. Stops with instructions if there is no App Store Connect record.
5. Turns on Sign in with Apple (`APPLE_ID_AUTH`) for the App ID if it's off, and marks the
   profiles stale.
6. `match_nuke` only when `ROTATE_SIGNING` is true **and** the run was started by hand.
7. `match` (appstore): the shared distribution certificate and this app's profiles, from the
   private certificates repository, made on first use; `force` when a capability changed.
8. Uses the team id from the profile if the `APPLE_TEAM_ID` secret disagrees (a common typo).
9. Manual signing per target, `build_app` with the run number, no indexing.
10. Checks the built `CFBundleDisplayName` equals the app name, and logs the record's name.
11. `upload_to_testflight` without waiting for processing (saves runner minutes).

## 6. First-run failures and fixes

| Log says | Cause | Fix |
| --- | --- | --- |
| `Missing secret X (see docs/SETUP.md)` | a secret not added | owner adds it (owner-setup.md) |
| `A required agreement is missing or has expired` | Apple's new agreement | owner accepts it; re-run |
| `No App Store Connect record exists for ...` | app record not made | owner fills the New App form; re-run |
| `Could not turn on Sign in with Apple through the API` | API refused the capability | owner ticks it in the portal (the message says where); re-run |
| `Couldn't decrypt the repo` / `Invalid password` | wrong `MATCH_PASSWORD` | the passphrase the store was made with; if lost, see SETUP "certificate store" |
| `Authentication failed` / 403 cloning the match repo | token expired or wrong scope | new fine-grained token with Contents read/write on that repository |
| `No profile for team 'X' matching 'match AppStore ...'` | profile made for another team id | handled by step 8; if it persists, the secret and the key's team differ: fix `APPLE_TEAM_ID` |
| `Provisioning profile doesn't include signing certificate` | certificate rotated, old profiles | run once by hand (profiles regenerate) or set `force: true` once |
| `You have already reached the maximum allowed number of certificates` | too many distribution certs | match reuses the stored one; only rotation makes new ones. Revoke unused ones in the portal |
| `Invalid Bundle. The bundle ... does not support the minimum OS` / icon errors | Info.plist or icon problem | icon must be 1024 px, no alpha; display name and versions set |
| `The bundle version must be higher than the previously uploaded version` | build number reused | build numbers come from the run number; never pass a lower `BUILD_NUMBER` |
| `GH013: Repository rule violations` pushing `testflight` | force push blocked | ship with `commit-tree` on top (section 4) |
| Upload ok, build never appears | processing, or Missing Compliance | wait 10 to 30 minutes; `ITSAppUsesNonExemptEncryption false` avoids the compliance question |

## 7. Adding an extension or capability

**Widget or other extension:** add the target to `project.yml` (with its own Info.plist
properties: `CFBundleDisplayName`, versions from the build settings, `NSExtension`), embed it
in the app (`dependencies: - target: <Ext>  embed: true`), add it to the scheme, and add
`["widget", "<Name>Widget", "<Name> Widget"]` to `EXTENSIONS` in the Fastfile. The next
TestFlight run registers its App ID and makes its profile.

**A capability** (push, App Groups, iCloud, HealthKit): add the entitlement in `project.yml`,
then enable it on the App ID. Some can be done in the Fastfile like Sign in with Apple:

```ruby
app_bundle.create_capability("PUSH_NOTIFICATIONS")   # then profiles_stale = true
```

App Groups and iCloud containers also need their identifiers made in the portal first, which
the owner does. Prefer designs that avoid them (references/ios-app.md, widgets with a keychain
group).

## 8. Costs and a private repository

Public repository: standard GitHub-hosted runners, macOS included, are free and unlimited.
Private: 2,000 minutes a month on the free plan, macOS billed at 10x, so roughly 200 macOS
minutes, about ten builds. The iOS workflow already holds back when private: it runs on a push
only with `[ios]` or `[screenshots]` in the message, or by hand. Keep the Actions budget at $0
so running out pauses instead of billing.

Keep builds lean either way: `paths-ignore` for files that don't change the binary, unit tests
on every push and UI tests only on request, `cancel-in-progress` for superseded pushes, no
waiting for TestFlight processing.

## 9. Guards the tests enforce

`server/api/test/ci.test.mjs` reads the workflows and Fastfile and fails if:

- any workflow is not read-only by default (`permissions: contents: read`);
- a job that can write runs on anything but Linux, uses anything but GitHub's own checkout and
  artifact actions, or runs project code (xcodebuild, fastlane, scripts, node, python);
- the build job leaves the GitHub token in `.git/config` (`persist-credentials: false`);
- a Swift package in `project.yml` is pinned to a version range instead of a commit;
- signing rotation can be triggered by anything but a by-hand run with the box ticked, or the
  docs mention a commit-message trigger for it.

These keep a compromised dependency or a crafted commit message from pushing code or revoking
certificates. Keep them passing when editing workflows.
