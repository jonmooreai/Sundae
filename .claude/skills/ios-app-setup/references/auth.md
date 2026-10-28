# Accounts and sign-in

How the template signs people in, keeps them signed in, and lets them leave, and why each piece
is the way it is. Read this before changing anything in `AppleNonce`, `TokenStore`,
`HTTPClient`, `AppModel`'s session code, or the auth routes in `worker.js`.

## Contents

1. The flow, end to end
2. Threats and what stops each
3. Sessions: access and refresh tokens
4. The app side
5. Account deletion
6. Admins
7. Closing sign-ups
8. Extending it (sign out everywhere, profile edits, Apple token revocation)
9. Tests that guard it

## 1. The flow

```
Phone                                   Apple                      Worker (D1)
-----                                   -----                      -----------
nonce = 32 random bytes (AppleNonce.make)
request.nonce = sha256(nonce)  ───────▶ Face ID, consent
                               ◀─────── identity token (JWT) signed by Apple,
                                        aud = bundle id, nonce = sha256(nonce)
POST /v1/auth/apple {identity_token, nonce, full_name, timezone} ─────────────▶
                                                                   verify signature (Apple's JWKS),
                                                                   iss, aud == APPLE_BUNDLE_ID, exp,
                                                                   token.nonce == sha256(nonce)
                                                                   INSERT used_nonces (once only)
                                                                   user with this apple_sub?
            ◀── existing: {access_token, refresh_token, expires_in, user}
            ◀── new:      {signup_ticket, expires_in: 3600}
UsernameView: choose a username
POST /v1/auth/apple/signup {signup_ticket, username, name, timezone} ──────────▶
                                                                   verify ticket (HMAC, typ, exp)
                                                                   username free? apple_sub free?
            ◀── {access_token, refresh_token, expires_in, user}
```

Apple's `sub` (the private, per-team user id) is the account key. The server never asks for or
keeps an email address. `full_name` arrives only on the very first authorization of an Apple
Account for this app (Apple never sends it again), so the app passes it to the username step to
pre-fill the name field.

## 2. Threats and what stops each

| Threat | Defence |
| --- | --- |
| Someone posts a token from another app | `aud` must equal this app's bundle id |
| A token captured off a device or a log is replayed | the nonce: its hash is signed into the token, and `used_nonces` accepts each nonce once |
| A forged token | signature checked against Apple's published keys (`kid` match) |
| An old token | `exp` checked against the server clock |
| Stolen access token | lasts 15 minutes |
| Stolen refresh token | rotates on use; the second use of one (after a 60 s grace) revokes the whole family, so the thief and the owner are both signed out and the owner just signs in again |
| Refresh tokens leaked from the database | stored only as SHA-256 hashes |
| Sign-out racing a refresh | a new refresh token is written only while its parent is not revoked, in one statement |
| A phone's previous owner signed back in after a reinstall | `FreshInstall`: the Keychain survives app deletion, so the first launch of a fresh install clears it |
| Someone new taking an existing account | the ticket carries the `sub` it was issued for and can only create, never sign in |
| Two sign-ups racing for one username | `INSERT OR IGNORE` on a unique column, checked by `changes` |
| Browser-based attacks | no CORS headers, `default-src 'none'` CSP, `nosniff`, HSTS |
| Enumerating other people's data | every query is scoped by `user_id`; someone else's id answers 404 like a missing one |

## 3. Sessions

- Access token: HMAC-signed JSON (`signToken` in `crypto.js`), `{sub, fam, typ: 'a', exp}`,
  15 minutes. Checked on every authenticated request (`auth()` also loads the user, so a
  deleted account's token stops working at once).
- Refresh token: 32 random bytes, 30 days, stored as `sha256` in `refresh_tokens` with a
  `family` (one sign-in on one device). Refresh marks the row `used` and issues a child in the
  same family.
- Grace: a used token presented again within 60 seconds still works (a reply lost on a bad
  connection would otherwise sign the person out). Later, it means the token was copied: the
  family is revoked.
- The signing secret is `TOKEN_SECRET` if set as a Worker secret, otherwise generated on first
  use and stored in `config`. Changing it signs everyone out once.

## 4. The app side

- `AppleNonce.make()` uses the system CSPRNG; `sha256` must produce lowercase hex, because the
  server compares strings.
- `TokenStore` writes to the Keychain with this-device-only accessibility (`Keychain.swift`), so
  tokens never land in backups or iCloud Keychain. Tests and unsigned simulator builds use
  `InMemorySecretStorage`, since the Keychain refuses writes without entitlements.
- `HTTPClient` refreshes 30 seconds before expiry or on a 401, one refresh at a time however
  many requests wait (`refreshTask`). Only a 401 from `/auth/refresh` ends the session; a 429
  or 5xx leaves it alone (an outage must never sign everyone out). When the session ends it
  yields on `onSessionExpired`, and `AppModel.watchForEndedSession` returns to sign-in.
- `AppModel.start` restores the session with `GET /v1/me`; offline, it trusts the cached user
  until the server answers, so the app opens normally on a plane.
- The demo (`MockAPI`) is used when `APIBaseURL` is empty or `-mockAPI` is passed. It keeps the
  same rules as the server (ticket spent only on success, unique usernames), so screens built on
  it behave the same live.

## 5. Account deletion

Apple requires apps with accounts to let people delete them from inside the app (App Store
Review Guideline 5.1.1(v)). Settings, Delete account, confirm: `DELETE /v1/me` removes the
user and everything they made in one `batch`, plus their refresh tokens. **Every new table
that holds someone's data must join that batch**, and the server test for deletion should
check the new table is empty afterwards.

Things other people hold that point at the deleted person (comments on others' posts,
follows) need a decision per app: delete them, or keep them with no owner. Sundae deleted
reports and follows, and kept nothing that could identify them.

## 6. Admins

`admin_apple_ids` holds Apple `sub`s, filled only from the Cloudflare side (D1 console or a
`d1_database_query` the owner approves). `USER_WITH_ADMIN` adds `is_admin` to every user
read, so `/v1/me` tells the app. Because it is keyed by Apple id, admin survives a username
change or a deleted and remade account and never passes to whoever takes a username later.
The app shows an Admin section in Settings when `isAdmin`; put debug switches there (Sundae
had "Pretend it's Sunday" and holiday previews) rather than in hidden gestures.

## 7. Closing sign-ups

`SIGNUPS: "closed"` in `wrangler.jsonc` refuses tickets and new sign-ups with 403
`signups_closed`; existing accounts sign in as usual. Only people with the app can sign up at
all (Apple issues identity tokens for this bundle id only to this app), and the app goes only
to people invited in TestFlight, so the TestFlight list is the guest list and closing sign-ups
locks the door once everyone is in. Keep it open while a build is in Beta App Review.

## 8. Extending it

- **Sign out everywhere:** the server supports `{"everywhere": true}` on `/v1/auth/signout`.
  Add `signOut(everywhere:)` to `AppAPI` and a button under Settings when the app is worth it.
- **Editing the profile:** `PATCH /v1/me` with `username` and/or `name` is ready; add it to
  `AppAPI`, `LiveAPI` (`client.patch`), `MockAPI`, and a screen.
- **Apple token revocation (before the App Store):** Apple asks apps that use Sign in with
  Apple to revoke the person's Apple tokens when they delete their account. That needs a Sign
  in with Apple private key (developer portal, Keys, a key with Sign in with Apple), the
  `authorizationCode` from the credential sent to the server at sign-in, an exchange at
  `https://appleid.apple.com/auth/token` for a refresh token kept with the user, and a call to
  `https://appleid.apple.com/auth/revoke` in `deleteMe`. The key becomes a Worker secret. It
  is not needed for TestFlight; plan it with the owner before App Store submission
  (references/app-store.md).
- **Another sign-in method:** don't, unless the owner asks. Passwords and SMS codes are what
  Sign in with Apple spares everyone. If they insist (Android friends, say), passkeys are the
  next best.

## 9. Tests that guard it

Server (`server/api/test/api.test.mjs`, with `fakeApple` signing tokens with a local key):
ticket flow, returning user, taken username, nonce reuse, wrong audience, expired token, closed
sign-ups, refresh rotation, grace and reuse, access expiry, sign out per device and everywhere,
ownership, delete account, admin, cleanup, schema version. App (`AuthTests`,
`HTTPClientTests`): the nonce hash vector, token storage, the mock ticket flow, the refresh
and session-ending rules against a stub server. Keep them green; add to them with each change.
