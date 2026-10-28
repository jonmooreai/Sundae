# Tally API

The contract between the app (`Services/Live/LiveAPI.swift`) and the server
(`server/api/src/worker.js`). JSON over HTTPS. Keys are snake_case on the wire; the app converts
them to camelCase. Dates are ISO 8601 with milliseconds, in UTC.

Base address: `https://tally-api.sundae-fam.workers.dev`

## Errors

Every error has the same shape, and the app maps `code` to `AppError` (`HTTPClient.mapError`):

```json
{ "error": { "code": "username_taken", "message": "That username is taken." } }
```

| Status | Code | Meaning |
| --- | --- | --- |
| 400 | `bad_request` | The body is missing or malformed |
| 400 | `invalid_username` | Not 2 to 24 of `a-z 0-9 . _` |
| 400 | `too_many` | A per-account limit is reached |
| 401 | `unauthorized` | No session, or it ran out: refresh, then sign in again |
| 403 | `signups_closed` | `SIGNUPS` is `"closed"` and this Apple Account has no account |
| 404 | `not_found` | Missing, or someone else's (the two answer the same) |
| 409 | `username_taken` | Someone has that username |
| 409 | `account_exists` | The ticket already made an account: sign in with Apple again |
| 500 | `server_error` | Anything unexpected. Nothing about it is sent back |

## Sessions

An access token lasts 15 minutes and goes in `Authorization: Bearer <token>`. A refresh token
lasts 30 days, changes on every use, and is kept on the server only as its SHA-256. Using one
twice, more than a minute apart, revokes that whole session on every device that shares it.

### `POST /v1/auth/apple`

After Sign in with Apple on the phone. `nonce` is the raw value whose SHA-256 the app gave
Apple. Each nonce works once.

```json
{ "identity_token": "eyJ...", "nonce": "q2Z...", "full_name": "Pat Doe", "timezone": "America/New_York" }
```

Someone coming back gets a session:

```json
{ "access_token": "...", "refresh_token": "...", "expires_in": 900,
  "user": { "id": "u_...", "username": "patdoe", "name": "Pat Doe", "is_admin": false } }
```

Someone new gets a ticket instead, good for an hour, which makes their one account once:

```json
{ "signup_ticket": "...", "expires_in": 3600 }
```

### `POST /v1/auth/apple/signup`

```json
{ "signup_ticket": "...", "username": "patdoe", "name": "Pat Doe", "timezone": "America/New_York" }
```

Answers with a session, like a returning sign-in. A taken or invalid username leaves the ticket
usable, so they can choose again.

### `POST /v1/auth/refresh`

```json
{ "refresh_token": "..." }
```

Answers `{ "access_token", "refresh_token", "expires_in" }`. A 401 here means the session is
over; the app signs out. Any other failure keeps the session for a later try.

### `POST /v1/auth/signout`

Signed in. Ends this device's session; `{ "everywhere": true }` ends every device's. 204.

## The account

### `GET /v1/me`

`{ "id", "username", "name", "is_admin" }`. `is_admin` comes from the `admin_apple_ids` table,
which only the owner writes (docs/SERVER.md).

### `PATCH /v1/me`

Any of `{ "username", "name" }`. Answers the updated account. 409 `username_taken` if someone has it.

### `DELETE /v1/me`

Deletes the account and everything in it, at once. 204. Apple requires this be possible from
inside the app.

## Notes (the example data)

Replace these with the app's own. Each account sees only its own.

- `GET /v1/notes`: `[{ "id", "text", "created_at" }]`, newest first, at most 500.
- `POST /v1/notes` with `{ "text" }`: the new note. Up to 1,000 characters; 500 notes an account.
- `DELETE /v1/notes/:id`: 204, or 404 for a note that is missing or someone else's.

## Pages

- `GET /` answers the app's name, so the address can be checked in a browser.
- `GET /privacy` is the privacy policy, built from `Shared/privacy.json`, for App Store Connect's
  privacy policy field.
