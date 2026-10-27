# Sundae API contract (client view)

What the iOS client in `Sundae/Services/Live/` expects from the backend. The server is the
authority for every rule in the PRD; the client only decides what to draw.

## Conventions

- Base URL from `SUNDAE_API_BASE_URL`; all paths below are relative and start with `v1/`.
- JSON, snake_case keys. Timestamps are ISO 8601 with fractional seconds, UTC.
- `week_start` is a plain `YYYY-MM-DD` date (the Monday) in the user's stored time zone.
- Errors: `{"error": {"code": "sunday_closed", "message": "..."}}` with the HTTP status. Codes the client maps: `sunday_closed`, `dump_locked`, `too_many_photos`, `too_many_tags`, `caption_too_long`, `invalid_code`, `not_found`, `forbidden`, `username_taken`, `invalid_username`, `signups_closed`, `account_exists`. Anything else (`too_many_uploads` and `too_many_comments`, both 429, among them) falls back on the status.
- Auth: `Authorization: Bearer <access_token>`. Access tokens last 15 minutes; refresh tokens 30 days, rotated on every use, family revoked on reuse more than a minute later (a retry within the minute, after a lost reply, gets a fresh pair). The client refreshes once on expiry or 401 and signs out locally if the refresh answers 401. A server error or a rate limit on the refresh keeps the session for a later try.
- Photo URLs in responses are signed, bound to the requesting account, and expire in 10 minutes.
- Every write is checked against the user's stored time zone and server time. Tag approvals and settings are exempt from the Sunday gate; everything under "Sunday only" returns `sunday_closed` (HTTP 423) off-Sunday.

## Auth

| Method | Path | Body | Returns |
| --- | --- | --- | --- |
| POST | `auth/apple` | `identity_token`, `nonce`, `full_name?`, `timezone`, `profile_first: true` | session for an Apple ID with an account. For a new one, `{signup_ticket, expires_in}` and no account yet. 403 `signups_closed` for someone new while sign-ups are closed |
| POST | `auth/apple/signup` | `signup_ticket`, `username`, `name?`, `timezone` | session for the new account. 409 `username_taken` (choose again, the ticket still works), 409 `account_exists` (the ticket is spent: sign in again), 400 `invalid_username`, 401 once the hour is up |
| POST | `auth/phone/start` | `phone` | 204 |
| POST | `auth/phone/verify` | `phone`, `code`, `username?`, `name?`, `timezone` | session |
| POST | `auth/refresh` | `refresh_token` | `access_token`, `refresh_token`, `expires_in` |
| POST | `auth/signout` | `everywhere?` | 204, revokes this device's refresh token, or with `everywhere: true` every device's (their access tokens lapse within 15 minutes) |

`nonce` is the value whose SHA-256 (lowercase hex) the app set as the request's nonce, which Apple signs into the token. The server checks the pair and accepts each nonce once, so a captured token cannot be replayed.

Someone signing back in is signed straight in, and their account comes back as they left it. Someone new chooses a username before any account exists: the signup ticket is signed by the server, lasts an hour, and can only ever create that Apple ID's account, never sign in to one. Builds from before `profile_first` send `username?` and `name?` with the first request instead, and get an account at once.

A session is `{access_token, refresh_token, expires_in, user}`. App Attest assertions ride along on token issuance once the server supports them (header to be defined).

## Me

| Method | Path | Notes |
| --- | --- | --- |
| GET | `me` | user, plus `is_admin: true` for an admin only (never on anyone else's user) |
| PATCH | `me` | any of `name`, `username`, `bio`, or `avatar_upload_id` from an upload ticket (a square JPEG, 600 px). A name is kept on one line, without invisible formatting characters (the zero width joiner in emoji stays) |
| GET / PUT | `me/settings` | settings object below |
| DELETE | `me` | starts the 30-day deletion |
| GET | `me/taggable` | users the caller follows or who follow them |
| GET | `me/follow-requests` | users waiting on the caller |
| POST | `me/follow-requests/{user_id}` | `{accept: bool}` |
| GET | `me/followers` | users who follow the caller, accepted, by username, never anyone blocked either way |
| GET | `me/following` | users the caller follows, accepted, by username, never anyone blocked either way |
| DELETE | `me/followers/{user_id}` | removes that person's follow of the caller, or their request; 204, and 204 again if there is nothing to remove. Following again is a new request while the caller is private. Photos they already loaded, and photo addresses already sent (up to seven hours), are not taken back |
| GET | `me/tag-requests` | pending tag requests, every day |
| GET | `me/suggestions/done?week_start=` | `[{suggestion_id, done_on}]` |
| PUT | `me/suggestions/{id}/done` | `{done_on}` |

Settings: `is_public`, `auto_approve_user_ids`, `comments_enabled`, `hide_challenges`, `notify_sunday_reminder`, `notify_last_call`, `notify_tags`, `notify_follow_requests`, `notify_likes_and_comments`, `notify_tag_approved`. `auto_approve_user_ids` keeps only user ids, each once; anything else in the list is dropped.

`PUT me/settings` changes only the fields it is sent and keeps the rest. The client loads them fresh whenever Settings opens, sends only the fields that changed, one save at a time, keeps a change only once the server has taken it, and puts the switch back when a save fails. `auto_approve_user_ids` is replaced whole, so two devices editing that list at the same moment keep whichever saved last.

The client signs out after `DELETE me` only on a 2xx, or when the server says the session is gone (401 or 403), which then means an earlier try deleted the account and its reply was lost. Otherwise it stays signed in and asks the person to try again.

## Sunday only

| Method | Path | Notes |
| --- | --- | --- |
| GET | `feed?before=<iso>&limit=` | dumps from accepted follows, newest first, no ranking |
| GET | `dumps/{id}` | authorization on every read: owner, accepted follower, or public author |
| GET | `me/dumps/{week_start}` | 404 when nothing posted |
| PUT | `me/dumps/{week_start}` | create or update; see below |
| DELETE | `dumps/{id}` | allowed any day |
| PUT | `dumps/{id}/like` | `{liked: bool}`, returns the dump |
| PUT | `photos/{id}/cherry` | `{cherried: bool}`, the caller's cherry on one photo of a week they can open; returns the photo |
| GET / POST | `dumps/{id}/comments` | POST body `{body, parent_id?}`; `parent_id` makes it a reply, kept one level deep (a reply to a reply goes under the same comment), on the same week or 400. Up to 30 comments a person on each week, then 429 `too_many_comments`. Deleting a comment deletes its replies |
| PATCH | `comments/{id}` | `{body}`; author only; sets `edited_at` |
| DELETE | `comments/{id}` | author, even on a week they can no longer open, or the dump's author |
| PUT / DELETE | `comments/{id}/like` | returns the comment with `like_count` and `liked_by_me` |
| GET | `users/{id}/profile` | profile object below |
| GET | `users/{id}/followers` | `[user + {relationship: me|following|requested|none, follows_you}]`, accepted follows of that person, by username, at most 500. For whoever can see the profile: anyone when it is public, its followers when it is private, its owner; 404 otherwise. Never anyone blocked by or blocking the caller |
| GET | `users/{id}/following` | the same, for the people that person follows |
| GET | `users/search?q=` | name or username only |
| GET | `users/suggested` | public accounts the caller has not followed or asked to follow, newest first, up to 20; never built from who anyone follows |
| POST / DELETE | `users/{id}/follow` | POST returns `{relationship}`: `following` or `requested` |

### Saving a dump

`PUT me/dumps/{week_start}` with:

```json
{
  "caption": "Bikes and a very long lunch.",
  "comments_enabled": true,
  "photos": [
    {"id": "p_123", "order": 0, "width": 2048, "height": 1536, "alt_text": null, "caption": "", "tagged_user_ids": ["u_maya"]},
    {"upload_id": "up_9f2", "order": 1, "width": 1536, "height": 2048, "alt_text": "Theo's bread", "caption": "Bread at Juniper Bakery.", "tagged_user_ids": []}
  ]
}
```

Server rules: `week_start` must be the caller's current week and today must be Sunday in their zone, else `dump_locked`. 1 to 15 photos. Up to 10 `tagged_user_ids` per photo, each someone in `me/taggable`, else `too_many_tags` / dropped. Caption up to 300 characters. Each photo may have its own `caption`, up to 200 characters; empty clears it, and a photo sent without the key keeps the caption it has, so builds from before photo captions never wipe one. `width` and `height` are whole pixels from 1 to 20000; anything else is ignored, and every photo in a response has whole, positive sizes. A save leaves the week with exactly the photos it lists, so saves sent together never add up to more than 15. Existing tags on an existing photo keep their status when the same user is still tagged; new tags are `pending` unless the tagged user auto-approves the caller. The same `upload_id` sent twice must resolve to the same photo (idempotent), because the client retries after dropped connections.

### Uploads

`POST uploads` with `{content_type, byte_size, width, height}` returns `{upload_id, url, headers?, expires_at}`: a single-use pre-signed PUT for one object of that size and type. Once one PUT has stored a photo, any other on that ticket, even one sent earlier and still arriving, writes nothing. The client has already re-encoded to a 2048 px JPEG with metadata stripped; the server strips EXIF, XMP, IPTC and comments again, and refuses with 400 `invalid_photo` anything that is not a JPEG of one frame up to 4096 px a side. Up to 10 MB a photo and 150 tickets a person in any 24 hours, however many are asked for at once. The friends-and-family server (`server/api`, docs/SERVER.md) stops there; a public launch adds hash matching and the nudity model before a photo becomes visible.

## Ideas near you (opt in, weekdays only, anonymous)

| Method | Path | Notes |
| --- | --- | --- |
| GET | `ideas/local?cell=&day=` | `[local_idea]`, sent with **no** `Authorization` header; `sunday_closed` (423) when `day` is a Sunday |

`cell` is a geohash of 5 or 6 characters computed on the phone (about 5 km or about 1 km across). The phone never sends coordinates, and the client sends this request without a bearer token so the server cannot tie an area to an account. The answer depends only on `(cell, day)` and comes back with `Cache-Control: public, max-age=86400`, so every phone in a cell shares one cached answer. The server must not log `cell` next to an IP address or any other identifier, and must not add per-caller content. Ideas carry `id: "local:YYYY-MM-DD:n"`, which names the day and a slot and nothing about where; the client sends that id to `me/suggestions/{id}/done` like any other. See `docs/LOCAL_IDEAS.md` for the design and `server/local-ideas/` for a reference implementation.

## Tags (every day)

| Method | Path | Notes |
| --- | --- | --- |
| POST | `tags/{id}/respond` | `{approve: bool}`; only the tagged user; decline notifies nobody |
| DELETE | `tags/{id}` | tagged user removes the photo from their profile; status `removed` |

## Safety

| Method | Path | Notes |
| --- | --- | --- |
| POST | `users/{id}/block` | removes follows and tags both ways, and each one's comments and likes on the other's weeks and comments |
| POST | `reports` | `{target_type: photo|dump|comment|profile, target_id, reason, note?}` |

## Shapes

```
user:     {id, username, name?, bio?, avatar_url?, is_public, timezone?,
           birthday?: "MM-DD" (friends only, never a year), invited_by_me?}
                                                   timezone only on the caller's own account (me, sign-in), null for anyone else
tag:      {id, photo_id, tagger_id, tagged_user: user, status: pending|approved|declined|removed, responded_at?}
photo:    {id, dump_id, order, url, width, height, alt_text?, caption?, tags: [tag],
           cherry_count, cherried_by_me, cherried_by: [user]}     cherries from anyone the caller can see, oldest first
dump:     {id, author: user, week_start, caption?, created_at, locked_at?, photos: [photo],
           comments_enabled, liked_by: [user], liked_by_me, comment_count, is_authors_first?}
comment:  {id, dump_id, parent_id?, author: user, body, created_at, edited_at?, like_count, liked_by_me}
profile:  {user, relationship: me|following|requested|none|blocked, weeks: [week],
           follower_count?, following_count?}      counts for whoever can see the profile (its lists open to them too), null otherwise
week:     {week_start, dump?, tagged: [{photo, from: user, tag}]}
tag_request: {tag, photo, tagger: user, week_start}
local_idea: {id, text, reason, time_of_day: morning|afternoon|evening|any,
           place?: {name, walk_minutes?, distance_meters?, latitude?, longitude?}}
                                                   the place's position, never the caller's; walk_minutes only within a walk
```

`liked_by` carries names for the "Liked by Maya and Theo" line; the client switches to a count past 10. `liked_by`, photo tags, `comment_count` and comment lists leave out anyone blocked either way with the caller.
