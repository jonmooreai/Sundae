# Putting Sundae's server online

One Cloudflare Worker, `sundae-api`, from `server/api` in this repository, with one D1
database for accounts, weeks, comments and tags, and photos in R2. It serves the API the app
talks to (docs/API.md) and the privacy page at `/privacy`, on a `workers.dev` address, so
there is no domain or website to set up.

It is built for a dozen friends and family on Cloudflare's free plan, and deployed the way
HeartCubby is: Workers Builds watches `main` and deploys every push to it. Work happens on
`claude/ios-app-scaffold`, and `main` is moved forward to it (a fast-forward, never a rewrite)
whenever the server should change, so `main` is always what is live. No Cloudflare token is
stored in GitHub.

Already done from the command line: the D1 database `sundae` exists with its tables, and the
private R2 bucket `sundae-photos` is made, both in North America East and both bound in
`wrangler.jsonc` at the top of the repository.

## Privacy and security

- **Who can get in.** Only people with the app: Apple issues Sign in with Apple tokens for
  this app to this app alone, and the app goes only to people invited by email in TestFlight
  (docs/TESTFLIGHT.md). Once everyone has joined, `SIGNUPS` closes the door to new accounts.
  Closing it also stops a blocked person rejoining with a new account.
- **Sign-in.** Apple only, so there are no passwords to leak and no SMS codes to intercept.
  Each identity token is checked against Apple's keys, this app's bundle id, its expiry, and a
  nonce the phone made for that attempt, and each nonce works once, so a copied token cannot
  be replayed. The server keeps Apple's private user id, never an email address. Someone
  coming back is signed straight in to the account they had. Someone new chooses a username
  first: until then there is no account, only a signed ticket that lasts an hour and can create
  that one account once.
- **Sessions.** Access tokens last 15 minutes. Refresh tokens are stored only as SHA-256
  hashes, change on every use, and a used one coming back more than a minute later signs that
  session out everywhere. A new one is only written while the old one is still live, so a
  refresh under way when someone signs out cannot outlast it.
- **Photos.** Location, camera details and comments are removed on the phone and again on the
  server. The server also refuses any photo over 4096 pixels a side, twice what the app sends,
  so nobody's phone is handed one too big to open. The R2 bucket is private; photos are only
  reachable through signed links that expire within seven hours.
- **The web.** Every response forbids MIME sniffing, framing, scripts and referrers, and
  insists on HTTPS. There are no CORS headers, so no website can read the API from a browser.
- **Nothing extra kept.** No request logs (observability is off), no analytics, no location.
  Deleting an account removes it at once, with reports they sent and reports about them; D1's
  own recovery history rolls past it in 7 days. Their upload records stay, with no owner, until
  the next daily cleanup, which deletes any photo that could not be deleted at that moment or
  was still arriving. The records hold only a file name, size and pixel dimensions.

## The privacy text

`Shared/privacy.json` is the only copy. The app shows it under Settings, then Privacy, and on
the sign-in screen, so it can be read any time without a browser; the Worker builds
`/privacy` from the same file for Apple's TestFlight form. A test fails if the two ever differ.

## What it costs

Nothing, for a group this size.

| | Free allowance | A dozen people |
|---|---|---|
| Worker requests | 100,000 a day | a few thousand on a Sunday |
| D1 database | 500 MB, 5 million rows read a day | a few MB a year |
| D1 queries | 50 per request | the busiest request makes 18 (the tests fail past 50) |
| R2 photos | 10 GB, a million uploads a month | about 1 MB a photo |

Past a free allowance, the Worker and D1 stop answering until the next day rather than bill.
R2 is the only piece that can bill, and only for storage. Every photo is read through the
Worker, whose 100,000 requests a day keep reads under R2's free 10 million a month, and there
are no download fees. Only posted photos are kept: uploads never posted are deleted daily,
each person can upload at most 150 a day, and a week holds at most 15. 10 GB is roughly ten
thousand photos; past that, storage is $0.015 per GB a month.

## 1. Switch on R2 (done)

Cloudflare only lets the account owner do this, in the dashboard: **R2 Object Storage**, get
started, add a payment method (Sundae stays inside the free tier). The bucket was then made
from the command line. Leave its public access off; nothing needs it.

Without the `PHOTOS` binding the server keeps photos in the database instead, which holds a
few hundred; if that ever happened, turning R2 back on would lose none of them.

## 2. Connect the Worker

Signed in to Cloudflare, about five minutes:

1. Open **Workers & Pages**, choose **Create application**, then **Import a repository**.
2. Choose GitHub. Cloudflare's GitHub app is already installed from HeartCubby; when it asks
   which repositories, add `jonmooreai/Sundae` alongside `jonmooreai/heartcubby`. It gets
   read access to those two only.
3. Choose `jonmooreai/Sundae`, then set:
   - **Project name:** `sundae-api` (it must match the `name` in `wrangler.jsonc`)
   - **Build command:** leave it empty
   - **Deploy command:** `npx wrangler deploy`
   - **Root directory:** leave it as `/` (the config is at the top of the repository)
   - **Production branch:** `main`, the default
4. Under the advanced settings, if they are offered:
   - **Builds for non-production branches:** off. They are not needed, and `wrangler.jsonc`
     already turns preview addresses off, since a preview would share the real database.
   - **Build watch paths:** `server/api/*` and `wrangler.jsonc`, so app-only pushes don't
     rebuild it.
5. **Deploy.** Each push to `main` deploys with `npx wrangler deploy`, which also applies
   `wrangler.jsonc`: the workers.dev address on, preview addresses off, the daily cron.

## 3. Check it

The Worker's address is `https://sundae-api.sundae-fam.workers.dev` (the account's workers.dev
subdomain was renamed from one that matched an email address).

- The address itself shows `Sundae`.
- `/privacy` shows the privacy page.
- `/v1/feed` answers `{"error":{"code":"unauthorized",...}}`: it is up, and waiting for a
  signed-in phone.

Send the address over; the app gets it in its next TestFlight build. That same build turns on
Sign in with Apple for the App ID (the lane does it through the App Store Connect API key) and
makes new provisioning profiles, so there is nothing to tick in the developer portal.

## Admins

An admin can open the Sunday screens any day, to try things on the real server, and sees an
Admin section in Settings with "Pretend it's Sunday". Nobody else sees the section, and the
server keeps everyone else to Sunday. Admins live in the database's `admins` table, which the
API never writes: add one from the Cloudflare side (the D1 console, or the command line) with
the person's user id, once they have signed in:

```sql
INSERT INTO admins (user_id) SELECT id FROM users WHERE username = 'their-username';
```

Delete the row to take it away; their phone drops back to the real day on its next launch.

## After deploying

Blocking now also removes tags between the two people and each one's comments and likes on
the other's weeks and comments. Blocks made before that left those rows behind. Once the new
Worker is live, clear them once from the D1 console:

```sql
DELETE FROM tags WHERE EXISTS (SELECT 1 FROM blocks b WHERE
  (b.blocker_id = tags.tagger_id AND b.blocked_id = tags.tagged_user_id) OR
  (b.blocker_id = tags.tagged_user_id AND b.blocked_id = tags.tagger_id));
DELETE FROM comment_likes WHERE EXISTS (SELECT 1 FROM comments c JOIN dumps d ON d.id = c.dump_id JOIN blocks b ON
  (b.blocker_id = c.author_id AND b.blocked_id IN (d.author_id, comment_likes.user_id)) OR
  (b.blocked_id = c.author_id AND b.blocker_id IN (d.author_id, comment_likes.user_id))
  WHERE c.id = comment_likes.comment_id);
DELETE FROM comments WHERE EXISTS (SELECT 1 FROM dumps d JOIN blocks b ON
  (b.blocker_id = comments.author_id AND b.blocked_id = d.author_id) OR (b.blocker_id = d.author_id AND b.blocked_id = comments.author_id)
  WHERE d.id = comments.dump_id);
DELETE FROM likes WHERE EXISTS (SELECT 1 FROM dumps d JOIN blocks b ON
  (b.blocker_id = likes.user_id AND b.blocked_id = d.author_id) OR (b.blocker_id = d.author_id AND b.blocked_id = likes.user_id)
  WHERE d.id = likes.dump_id);
```

Until then nobody blocked either way sees the other in likes, tags or comment counts, but
someone else could still see those old rows.

## Settings

In `wrangler.jsonc` at the top of the repository, under `vars`:

- `SIGNUPS`: `"closed"` once everyone invited has an account. Nobody new can sign up, even
  with the app; everyone else signs in as usual. Keep it `"open"` while a build is in Beta App
  Review, since the reviewer signs in too.
- `SUNDAY_EVERY_DAY`: `"true"` opens the Sunday-only parts every day, for trying the feed and
  posting midweek. Back to `"false"` before inviting people.

The key that signs sessions is made on first use and kept in the database. To keep it out of
the database instead, add a secret named `TOKEN_SECRET` (any long random text) under the
Worker's **Settings**, then **Variables and Secrets**; everyone is signed out once when it
changes.

## Testing it here

```bash
cd server/api
node --test --no-warnings
```

Node 22 or later, no installs. The tests run the Worker unchanged against Node's built-in
SQLite standing in for D1, count queries the way D1 does, and fail any request over the free
plan's 50. They run in GitHub Actions on every push that touches `server/`.
