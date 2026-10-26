# Putting Sundae's server online

One Cloudflare Worker, `sundae-api`, from `server/api` in this repository, with one D1
database for accounts, weeks, comments and tags, and photos in R2. It serves the API the app
talks to (docs/API.md) and the privacy page at `/privacy`, on a `workers.dev` address, so
there is no domain or website to set up.

It is built for a dozen friends and family on Cloudflare's free plan, and deployed the way
HeartCubby is: Workers Builds watches this repository and deploys every push that changes the
server. No Cloudflare token is stored in GitHub.

Already done from the command line: the D1 database `sundae` (North America East) exists with
its tables, and its id is in `server/api/wrangler.jsonc`.

## Privacy and security

- **Who can get in.** Only people with the app: Apple issues Sign in with Apple tokens for
  this app to this app alone, and the app goes only to people invited by email in TestFlight
  (docs/TESTFLIGHT.md). Once everyone has joined, `SIGNUPS` closes the door to new accounts.
- **Sign-in.** Apple only, so there are no passwords to leak and no SMS codes to intercept.
  Each identity token is checked against Apple's keys, this app's bundle id, its expiry, and a
  nonce the phone made for that attempt, and each nonce works once, so a copied token cannot
  be replayed. The server keeps Apple's private user id, never an email address.
- **Sessions.** Access tokens last 15 minutes. Refresh tokens are stored only as SHA-256
  hashes, change on every use, and a used one coming back more than a minute later signs that
  session out everywhere.
- **Photos.** Location, camera details and comments are removed on the phone and again on the
  server. The R2 bucket is private; photos are only reachable through signed links that expire
  within seven hours.
- **The web.** Every response forbids MIME sniffing, framing, scripts and referrers, and
  insists on HTTPS. There are no CORS headers, so no website can read the API from a browser.
- **Nothing extra kept.** No request logs (observability is off), no analytics, no location.
  Deleting an account removes it at once; D1's own recovery history rolls past it in 7 days.

## What it costs

Nothing, for a group this size.

| | Free allowance | A dozen people |
|---|---|---|
| Worker requests | 100,000 a day | a few thousand on a Sunday |
| D1 database | 500 MB, 5 million rows read a day | a few MB a year |
| D1 queries | 50 per request | the busiest request makes 17 (the tests fail past 50) |
| R2 photos | 10 GB, a million uploads a month | about 1 MB a photo |

Past a free allowance, the Worker and D1 stop answering until the next day rather than bill.
R2 is the only piece that can bill, and only for storage. Every photo is read through the
Worker, whose 100,000 requests a day keep reads under R2's free 10 million a month, and there
are no download fees. Only posted photos are kept: uploads never posted are deleted daily, and
each person can upload at most 150 a day. 10 GB is roughly ten thousand photos; past that,
storage is $0.015 per GB a month.

## 1. Switch on R2

Cloudflare only lets the account owner do this, in the dashboard, about two minutes. Do it
first, so photos never sit in the database (where D1's recovery history would keep a deleted
photo for 7 days).

1. Open **R2 Object Storage** and choose to get started. Cloudflare asks for a payment method
   even for the free tier; Sundae stays inside it (the table above).
2. Don't create a bucket or turn on public access. The private `sundae-photos` bucket is made
   from the command line, and the binding in `server/api/wrangler.jsonc` switched on with it.

Until then photos go in the database, which holds a few hundred, and turning R2 on later loses
none of them.

## 2. Connect the Worker

Signed in to Cloudflare, about five minutes:

1. Open **Workers & Pages**, choose **Create application**, then **Import a repository**.
2. Choose GitHub. Cloudflare's GitHub app is already installed from HeartCubby; when it asks
   which repositories, add `jonmooreai/Sundae` alongside `jonmooreai/heartcubby`. It gets
   read access to those two only.
3. Choose `jonmooreai/Sundae`, then set:
   - **Project name:** `sundae-api` (it must match the `name` in `server/api/wrangler.jsonc`)
   - **Build command:** leave it empty
   - **Deploy command:** `npx wrangler deploy`
   - **Root directory:** `server/api`
   - **Production branch:** `claude/ios-app-scaffold` (change it to `main` once the pull
     request merges)
4. Under the advanced settings, if they are offered:
   - **Builds for non-production branches:** off. A preview would share the real database.
   - **Build watch paths:** `server/api/*`, so app-only pushes don't rebuild it.
5. **Deploy.**

## 3. Check it

The build log ends with the Worker's address, `https://sundae-api.<your-subdomain>.workers.dev`.

- The address itself shows `Sundae`.
- `/privacy` shows the privacy page.
- `/v1/feed` answers `{"error":{"code":"unauthorized",...}}`: it is up, and waiting for a
  signed-in phone.

Send the address over; the app gets it in its next TestFlight build. That same build turns on
Sign in with Apple for the App ID (the lane does it through the App Store Connect API key) and
makes new provisioning profiles, so there is nothing to tick in the developer portal.

## Settings

In `server/api/wrangler.jsonc`, under `vars`:

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
