# __APP_NAME__'s server

One Cloudflare Worker, `__APP_SLUG__-api`, from `server/api`, with one D1 database. It serves
the API the app talks to (docs/API.md) and the privacy page at `/privacy`, on
`__API_BASE_URL__`. Workers Builds deploys every push to `main` (docs/SETUP.md, step 7). Work
happens on a `claude/` branch, and `main` is moved forward to it (a fast-forward, never a
rewrite) whenever the server should change, so `main` is always what is live. No Cloudflare
token is stored in GitHub.

## Privacy and security

- **Sign-in.** Apple only: no passwords to leak, no codes to intercept. Each identity token is
  checked against Apple's keys, this app's bundle id, its expiry, and a nonce the phone made
  for that attempt; each nonce works once, so a copied token can't be replayed. The server keeps
  Apple's private user id, never an email address.
- **Someone new** chooses a username first. Until then there is no account, only a signed
  ticket that lasts an hour and makes that one account once.
- **Sessions.** Access tokens last 15 minutes. Refresh tokens are stored only as SHA-256
  hashes, change on every use, and one used again more than a minute later signs that session
  out everywhere. A new one is written only while the old one is live, so a refresh under way
  during sign-out can't outlast it.
- **The web.** Every response forbids MIME sniffing, framing, scripts and referrers, and insists
  on HTTPS. No CORS headers, so no website can read the API from a browser.
- **Nothing extra kept.** No request logs (observability is off), no analytics, no email.
  Deleting an account removes it and everything in it at once; D1's own recovery history rolls
  past it in 7 days.

## What it costs

Nothing on the free plan, for a group of friends and family.

| | Free allowance |
|---|---|
| Worker requests | 100,000 a day |
| D1 database | 500 MB, 5 million rows read and 100,000 written a day |
| D1 queries | 50 per request (the tests fail any request past that) |

Past a free allowance the Worker and D1 stop answering until the next day rather than bill.

## Admins

Admins see the Admin section in Settings. They live in the `admin_apple_ids` table by the private
id Sign in with Apple gives their Apple Account, so admin follows the person through a new
username or a deleted and remade account, and never passes to whoever takes a username later.
The API never writes the table. Add one from the D1 console once they have signed in:

```sql
INSERT INTO admin_apple_ids (apple_sub) SELECT apple_sub FROM users WHERE username = 'their-username';
```

## Settings

In `wrangler.jsonc`, under `vars`:

- `SIGNUPS`: `"closed"` once everyone invited has an account. Nobody new can sign up; everyone
  else signs in as usual. Keep it `"open"` while a build is in Beta App Review.
- `APPLE_BUNDLE_ID`: the app's bundle id, which every identity token must be issued to.

The key that signs sessions is made on first use and kept in the database. To keep it out of the
database, add a secret named `TOKEN_SECRET` (any long random text) under the Worker's Settings,
Variables and Secrets; everyone is signed out once when it changes.

## Changing the database

`server/api/src/schema.js` holds every table. Add a table with `CREATE TABLE IF NOT EXISTS`, a
column to `COLUMNS`, and bump `SCHEMA_VERSION`: the first request after a deploy brings the
database up to date. Never rename or drop a column people's data is in; add a new one and copy.
Every new table that holds someone's data joins the batch in `deleteMe` and, if it should not
be kept forever, `cleanUp`.

## Testing it here

```bash
cd server/api
node --test --no-warnings
```

Node 22 or later, no installs. The tests run the Worker unchanged against Node's built-in
SQLite standing in for D1, with a stand-in for Apple's keys, count queries the way D1 does, and
fail any request over the free plan's 50. They run in GitHub Actions on every push that touches
`server/` (the Server workflow).
