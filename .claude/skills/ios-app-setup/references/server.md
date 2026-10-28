# The server

One Cloudflare Worker in plain JavaScript (ES modules, no dependencies, no build step) with one
D1 database. This file covers how it is laid out, how to add to it, how to test it, the free
plan's limits, and deploying and checking it from the session.

## Contents

1. Layout
2. Adding a feature: the checklist
3. The schema and changing it
4. Testing
5. Free plan limits and staying inside them
6. Files and photos (R2)
7. Scheduled work
8. Deploying and checking
9. Working with the live database

## 1. Layout

```
wrangler.jsonc            at the repository root, so Workers Builds deploys from "/"
server/api/
  package.json            "type": "module", test script only; nothing to install
  src/worker.js           fetch + scheduled handlers, routing, every endpoint
  src/schema.js           SCHEMA_VERSION, SCHEMA (CREATE ... IF NOT EXISTS), COLUMNS
  src/crypto.js           ids, random tokens, sha256, HMAC tokens, Apple token verification
  src/privacy.js          the /privacy page, built from Shared/privacy.json at import time
  test/harness.mjs        D1 on node:sqlite with a query counter, a fake Apple, server()
  test/api.test.mjs       the API's tests
  test/ci.test.mjs        guards on the workflows and Fastfile (permissions, signing rotation)
```

`worker.js` reads top to bottom: response helpers and security headers, the entry points,
`handle` (pages, then `/v1/` with `ensureSchema` and the clock), `route`, auth, me, the app's
own routes, input cleaning, cleanup. Keep that order as it grows; split into more files under
`src/` only when a section passes a few hundred lines.

Errors: `fail(status, code, message)` throws an `HttpError`; `handle` turns it into
`{"error":{"code","message"}}`. Anything else becomes a 500 `server_error` with nothing
internal in the body. Every new `code` gets a case in the app's `HTTPClient.mapError` and
`AppError`, and a row in docs/API.md.

## 2. Adding a feature: the checklist

1. **Tables** in `SCHEMA` (`CREATE TABLE IF NOT EXISTS`), with an index for every `WHERE` you
   will run often. Bump `SCHEMA_VERSION` with a one-line note above it.
2. **Routes** in `route()`. Authenticated routes go after `await auth(ctx)`. Read input with
   `body()`; clean every string (`clean(value, max)`, `cleanName`, `normalizeUsername`); cap
   lengths and counts. Scope every query by `ctx.me.id`. Someone else's thing answers 404,
   exactly like a missing one.
3. **Limits** per person (how many rows, how big), enforced in the same statement that writes
   (`INSERT ... SELECT ... WHERE (SELECT COUNT(*) ...) < ?`) so two requests at once can't
   both slip past.
4. **Deletion:** the new table joins the `deleteMe` batch. Rows that expire join `cleanUp`.
5. **Tests** in `api.test.mjs`: the happy path, someone else's data, bad input, the limit, and
   that deleting the account empties the table.
6. **Contract** in docs/API.md; then the app (references/ios-app.md).
7. **Privacy:** if it stores a new kind of data, `Shared/privacy.json` says so (the privacy
   page test checks the page shows every section).

A response shape is snake_case JSON. Dates are ISO strings from `ctx.now.toISOString()`, never
`new Date()` directly, so tests can move the clock (`s.setNow`).

## 3. The schema and changing it

`ensureSchema` runs once per isolate: it reads `schema_version` from `config` and, if it
differs, runs every `SCHEMA` statement (all idempotent), adds each missing `COLUMNS` entry,
and stores the new version. So:

- **New table or index:** add to `SCHEMA`, bump the version.
- **New column on an existing table:** add it to the table's `CREATE` (for fresh databases)
  **and** to `COLUMNS` (for the live one), bump the version. SQLite's `ADD COLUMN` needs a
  default for `NOT NULL`.
- **Removing a feature:** `DROP TABLE IF EXISTS` in `SCHEMA` and bump (Sundae did this when
  cherry reactions went). Tell the owner first: it deletes live data.
- **Never** rename or drop a column holding data in place. Add the new one, copy across in a
  statement the owner approves, then stop using the old one.

## 4. Testing

```bash
cd server/api && node --test --no-warnings
```

Node 22+ (it uses the built-in `node:sqlite`). The harness:

- `server({ signups })` gives `{ call, appleSignIn, signUp, setNow, now, env, apple }`, a fresh
  in-memory database each time.
- `call(method, path, { token, json, raw })` returns `{ status, headers, body }` and **throws if
  the request made more than 50 D1 queries**, the free plan's per-request limit. A batch counts
  each statement.
- `signUp(sub, username)` does the whole Apple sign-in and ticket flow and returns
  `{ token, refresh, user }`.
- `fakeApple()` signs identity tokens with a local key and serves it as Apple's JWKS, so the
  real verification code runs.

Pattern for a test:

```js
test('lists are each person\'s own', async () => {
  const s = await server();
  const pat = await s.signUp('apple-pat', 'patdoe');
  const sam = await s.signUp('apple-sam', 'samdoe');
  const made = await s.call('POST', 'v1/lists', { token: pat.token, json: { title: 'Groceries' } });
  assert.equal(made.status, 200);
  assert.equal((await s.call('DELETE', `v1/lists/${made.body.id}`, { token: sam.token })).status, 404);
});
```

The Server workflow runs these on every push that touches `server/`, the workflows, the
Fastfile or `project.yml`.

## 5. Free plan limits and staying inside them

| Limit (Workers Free) | Value | What happens past it |
| --- | --- | --- |
| Worker requests | 100,000 a day | errors until midnight UTC; never a bill |
| CPU per request | 10 ms | the request fails; avoid heavy work (image processing) in the Worker |
| D1 queries per request | 50 | the request fails; the harness catches this in tests |
| D1 rows read / written | 5 million / 100,000 a day | errors until the next day |
| D1 storage | 500 MB a database, 5 GB total, 10 databases | writes fail |
| Cron triggers | 5 per account on Free | deploy fails; Sundae and each new app use one each |

Watch the cron count: each app's daily cleanup takes one of the account's five. Past five,
drop the cron from the newest app and run its cleanup at the start of an ordinary request
once a day instead (store the last run in `config`).

Rows read matter more than requests: an unindexed `WHERE` scans the table and every row
scanned counts. Index what you filter on, `LIMIT` every list, and page with a cursor (a
`created_at` and `id` pair) rather than `OFFSET`.

## 6. Files and photos (R2)

The template has no file storage. If the app needs it (Sundae stored photos):

- R2's free tier is 10 GB storage, 1 million writes and 10 million reads a month, no egress
  fees. Turning R2 on needs a payment method on the Cloudflare account even to stay free:
  that is the owner's call; ask before planning around it.
- Bucket private (the default). Bind it in `wrangler.jsonc` (`r2_buckets`), create it with
  `mcp__Cloudflare_Developer_Platform__r2_bucket_create`.
- Upload through the Worker or through signed, short-lived URLs the Worker issues; serve
  through the Worker with an HMAC-signed link that expires, so nothing is public.
- Shrink on the phone (Sundae sent 2048 px JPEGs), strip location and camera metadata on the
  phone and again on the server, cap size and pixel dimensions server-side, and cap uploads
  per person per day. Delete uploads that never got attached, daily.
- Storage is the only thing that can bill. Keep a per-person cap and say in docs/SERVER.md
  roughly how many files fit in 10 GB.

## 7. Scheduled work

`scheduled()` runs `cleanUp(env)` from the cron in `wrangler.jsonc` (daily, 09:17 UTC by
default; pick an odd minute). Use it for expiring rows and orphaned uploads. Keep it to a few
batched statements: it has the same limits as a request.

## 8. Deploying and checking

Workers Builds deploys every push to `main`, running `npx wrangler deploy` at the root. Work
happens on the `claude/` branch; to deploy, fast-forward `main`:

```bash
git push origin HEAD:main     # fails if main has moved; never force it
```

Then check:

1. The deploy: `mcp__github__get_commit` on the pushed sha (the Workers Builds check run
   appears on it) or ask the owner to look at Workers & Pages, the Worker, Deployments.
2. The code that is live: `mcp__Cloudflare_Developer_Platform__workers_get_worker_code` with
   `scriptName: <slug>-api`, and search it for something from your change.
3. The schema: `d1_database_query` with
   `SELECT value FROM config WHERE key = 'schema_version'` (it updates on the first API request
   after deploy; ask the owner to open the app, or wait).

`wrangler.jsonc` changes (vars, cron, bindings) also apply on deploy. `preview_urls` stays
`false` (preview addresses would be public and share the real database) and observability
stays off (no request logs; the privacy page says so).

## 9. Working with the live database

`mcp__Cloudflare_Developer_Platform__d1_database_query` with the database id from
`wrangler.jsonc`. Reads are fine to run to check something. **Every write needs the owner's
explicit yes for that exact change**: show them the SQL, say what it changes and for whom,
and wait. That includes adding an admin, cleaning up rows after a feature change, and backfills.
D1 keeps 7 days of point-in-time history (Time Travel) on the free plan, but treat that as a
last resort, not a plan.

Never paste personal data from the live database into the repository, tests, docs or
screenshots. Use made-up people (Pat Doe, 555 numbers).
