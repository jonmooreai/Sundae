# Sundae

Your week in photos, shared with a few friends, in an app that opens on Sundays. Read README.md
for the layout, docs/API.md for the contract with the server, and docs/SERVER.md before
changing the server.

## The owner's standing rules

- **Always ship.** Once CI is green on the work branch, ship it to TestFlight without asking:
  `git fetch origin testflight`, then push a `git commit-tree "HEAD^{tree}" -p origin/testflight`
  commit to `refs/heads/testflight`, check that run, and say which build number to install.
  Server deploys (moving `main`) and writes to the live database still need a yes each time.
- **Commits** are authored as `jonmooreai <118233078+jonmooreai@users.noreply.github.com>`, with
  no Co-Authored-By, Claude or session trailers and no model names. Never put a personal email
  address in the repository.
- **Warm words.** Every line of UI text is cozy, friendly, genuine and warm, like a friend
  talking: "Thanks for sharing your week", never "Your week is up". Errors say what happened
  and what to do, kindly. No system-speak, no exclamation marks.
- **No em-dashes**, anywhere.
- **Design:** light mode by default, dark supported; simple and clean with a little warmth
  (cream, sage, felt); borders used sparingly, never a thick border on one side of anything.
- **Free plans only**, and privacy first: collect only what a feature needs.
- **Made-up people only** in examples, tests and screenshots (Pat Doe, 555 numbers).

## Working without a Mac

There is no Swift compiler in the cloud session. GitHub Actions builds and tests every push to
the work branch; read results with the GitHub tools and fix what they report before calling
anything done. A plain push builds and runs the unit tests (about ten minutes). `[screenshots]`
in the commit message adds the iPhone walk through every screen (about fifteen more), and
`[duo]` adds the iPhone Duo in every pose (about an hour more): use it after a layout change,
not on every push. The ios-app-setup skill (`.claude/skills/ios-app-setup`) has the pitfalls that
broke the build before, in references/pitfalls.md.
