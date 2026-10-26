# Putting Sundae's server online

One Cloudflare Worker, `sundae-api`, from `server/api` in this repository, with one D1
database for accounts, weeks, comments and tags. Photos go in R2 once it is switched on. It
serves the API the app talks to (docs/API.md) and the privacy page at `/privacy`, on a
`workers.dev` address, so there is no domain or website to set up.

It is built for a dozen friends and family on Cloudflare's free plan, the same way HeartCubby
is deployed: Workers Builds watches this repository and deploys on every push that changes
the server.

## What it costs

Nothing, for a group this size.

| | Free allowance | A dozen people |
|---|---|---|
| Worker requests | 100,000 a day | a few thousand on a Sunday |
| D1 database | 500 MB, 5 million rows read a day | a few MB a year, photos aside |
| D1 queries | 50 per request | the busiest request makes 17 (the tests fail past 50) |
| R2 photos | 10 GB, a million uploads a month | about 1 MB a photo |

Past a free allowance, the Worker and D1 stop answering until the next day rather than bill.
R2 is the only piece that can bill, and only for storage. Every photo is read through the
Worker, whose 100,000 requests a day keep reads under R2's free 10 million a month, and there
are no download fees. Only posted photos are kept: uploads never posted are deleted daily, and
each person can upload at most 150 a day. 10 GB is roughly ten thousand photos; past that,
storage is $0.015 per GB a month.

## 1. Connect the Worker

Signed in to Cloudflare, about five minutes:

1. Open **Workers & Pages**, choose **Create application**, then **Import a repository**.
2. Choose GitHub. Cloudflare's GitHub app is already installed from HeartCubby; when it asks
   which repositories, add `jonmooreai/Sundae` alongside `jonmooreai/heartcubby`.
3. Choose `jonmooreai/Sundae`, then set:
   - **Project name:** `sundae-api` (it must match the `name` in `server/api/wrangler.jsonc`)
   - **Build command:** leave it empty
   - **Deploy command:** `npx wrangler deploy`
   - **Root directory:** `server/api`
   - **Production branch:** `claude/ios-app-scaffold` (change it to `main` once the pull
     request merges)
4. Under the advanced settings, if they are offered:
   - **Builds for non-production branches:** off. A preview would share the real database.
   - **Build watch paths:** include `server/api/*`, so app-only pushes don't rebuild it.
5. **Deploy.** The first deploy creates the D1 database, named `sundae`, and keeps it linked
   after that. If the build log says it could not, open **Storage & Databases**, then **D1**,
   create a database named `sundae`, and put its ID in `server/api/wrangler.jsonc` as
   `"database_id"` next to `"database_name"`. The push that adds it deploys again.

## 2. Check it

The build log ends with the Worker's address, `https://sundae-api.<your-subdomain>.workers.dev`.

- The address itself shows `Sundae`.
- `/privacy` shows the privacy page.
- `/v1/feed` answers `{"error":{"code":"unauthorized",...}}`, which means it is up and
  waiting for a signed-in phone.

Send the address over; the app gets it in its next TestFlight build.

## 3. Sign in with Apple

The server signs people in with Apple only; there is no SMS to pay for.

1. At developer.apple.com, open **Certificates, IDs & Profiles**, then **Identifiers**.
2. Open `com.jonmooreai.sundae`, tick **Sign in with Apple**, and **Save**.

That invalidates the app's provisioning profiles; the next TestFlight build regenerates them.

## 4. Photos in R2, before inviting people

Until this step photos are kept in the database, which holds a few hundred, enough to try
everything out. Before sending invites:

1. In the dashboard, open **R2 Object Storage** and switch it on. Cloudflare asks for a payment
   method even for the free tier; Sundae stays inside it (see the table above).
2. Say so, and the line in `server/api/wrangler.jsonc` that binds the bucket gets switched on.
   The next deploy creates the `sundae-photos` bucket. Photos already in the database keep
   loading, and deleting one clears it from both places.

## Settings

In `server/api/wrangler.jsonc`, under `vars`:

- `SUNDAY_EVERY_DAY`: `"true"` opens the Sunday-only parts every day, for trying the feed and
  posting midweek. Back to `"false"` before inviting people.

The sign-in signing key is made on first use and kept in the database. To set your own
instead, add a secret named `TOKEN_SECRET` under the Worker's **Settings**, then
**Variables and Secrets**; everyone is signed out once when it changes.

## Testing it here

```bash
cd server/api
node --test --no-warnings
```

Node 22 or later, no installs. The tests run the Worker unchanged against Node's built-in
SQLite standing in for D1, count queries the way D1 does, and fail any request over the free
plan's 50. They run in GitHub Actions on every push that touches `server/`.
