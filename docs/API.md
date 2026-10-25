# Sundae API contract (client view)

What the iOS client in `Sundae/Services/Live/` expects from the backend. The server is the
authority for every rule in the PRD; the client only decides what to draw.

## Conventions

- Base URL from `SUNDAE_API_BASE_URL`; all paths below are relative and start with `v1/`.
- JSON, snake_case keys. Timestamps are ISO 8601 with fractional seconds, UTC.
- `week_start` is a plain `YYYY-MM-DD` date (the Monday) in the user's stored time zone.
- Errors: `{"error": {"code": "sunday_closed", "message": "..."}}` with the HTTP status. Codes the client maps: `sunday_closed`, `dump_locked`, `too_many_photos`, `too_many_tags`, `caption_too_long`, `invalid_code`, `not_found`, `forbidden`. Anything else falls back on the status.
- Auth: `Authorization: Bearer <access_token>`. Access tokens last 15 minutes; refresh tokens 30 days, rotated on every use, family revoked on reuse. The client refreshes once on expiry or 401 and signs out locally if the refresh is rejected.
- Photo URLs in responses are signed, bound to the requesting account, and expire in 10 minutes.
- Every write is checked against the user's stored time zone and server time. Tag approvals and settings are exempt from the Sunday gate; everything under "Sunday only" returns `sunday_closed` (HTTP 423) off-Sunday.

## Auth

| Method | Path | Body | Returns |
| --- | --- | --- | --- |
| POST | `auth/apple` | `identity_token`, `full_name?`, `username?`, `name?`, `timezone` | session |
| POST | `auth/phone/start` | `phone` | 204 |
| POST | `auth/phone/verify` | `phone`, `code`, `username?`, `name?`, `timezone` | session |
| POST | `auth/refresh` | `refresh_token` | `access_token`, `refresh_token`, `expires_in` |
| POST | `auth/signout` | | 204, revokes this device's refresh token |

A session is `{access_token, refresh_token, expires_in, user}`. App Attest assertions ride along on token issuance once the server supports them (header to be defined).

## Me

| Method | Path | Notes |
| --- | --- | --- |
| GET | `me` | user |
| PATCH | `me` | any of `name`, `username`, `bio`, or `avatar_upload_id` from an upload ticket (a square JPEG, 600 px) |
| GET / PUT | `me/settings` | settings object below |
| DELETE | `me` | starts the 30-day deletion |
| GET | `me/taggable` | users the caller follows or who follow them |
| GET | `me/follow-requests` | users waiting on the caller |
| POST | `me/follow-requests/{user_id}` | `{accept: bool}` |
| GET | `me/tag-requests` | pending tag requests, every day |
| GET | `me/suggestions/done?week_start=` | `[{suggestion_id, done_on}]` |
| PUT | `me/suggestions/{id}/done` | `{done_on}` |

Settings: `is_public`, `auto_approve_user_ids`, `comments_enabled`, `hide_challenges`, `notify_sunday_reminder`, `notify_last_call`, `notify_tags`, `notify_follow_requests`, `notify_likes_and_comments`, `notify_tag_approved`.

## Sunday only

| Method | Path | Notes |
| --- | --- | --- |
| GET | `feed?before=<iso>&limit=` | dumps from accepted follows, newest first, no ranking |
| GET | `dumps/{id}` | authorization on every read: owner, accepted follower, or public author |
| GET | `me/dumps/{week_start}` | 404 when nothing posted |
| PUT | `me/dumps/{week_start}` | create or update; see below |
| DELETE | `dumps/{id}` | allowed any day |
| PUT | `dumps/{id}/like` | `{liked: bool}`, returns the dump |
| GET / POST | `dumps/{id}/comments` | POST body `{body}` |
| GET | `users/{id}/profile` | profile object below |
| GET | `users/search?q=` | name or username only |
| GET | `users/suggested` | friends of people the caller follows |
| POST / DELETE | `users/{id}/follow` | POST returns `{relationship}`: `following` or `requested` |

### Saving a dump

`PUT me/dumps/{week_start}` with:

```json
{
  "caption": "Bikes and a very long lunch.",
  "comments_enabled": true,
  "photos": [
    {"id": "p_123", "order": 0, "width": 2048, "height": 1536, "alt_text": null, "tagged_user_ids": ["u_maya"]},
    {"upload_id": "up_9f2", "order": 1, "width": 1536, "height": 2048, "alt_text": "Theo's bread", "tagged_user_ids": []}
  ]
}
```

Server rules: `week_start` must be the caller's current week and today must be Sunday in their zone, else `dump_locked`. 1 to 15 photos. Up to 10 `tagged_user_ids` per photo, each a mutual follow of the caller, else `too_many_tags` / dropped. Caption up to 300 characters. Existing tags on an existing photo keep their status when the same user is still tagged; new tags are `pending` unless the tagged user auto-approves the caller. The same `upload_id` sent twice must resolve to the same photo (idempotent), because the client retries after dropped connections.

### Uploads

`POST uploads` with `{content_type, byte_size, width, height}` returns `{upload_id, url, headers?, expires_at}`: a single-use pre-signed PUT for one object of that size and type. The client has already re-encoded to a 2048 px JPEG with metadata stripped; the server strips again and runs hash matching and the nudity model before the photo becomes visible.

## Contacts matching (opt in)

| Method | Path | Notes |
| --- | --- | --- |
| GET | `contacts/key` | `{key_id, key (base64, 32 bytes), expires_at}`; one per session, 15 minutes |
| POST | `contacts/match` | `{key_id, hashes: [hex HMAC-SHA256 of E.164 digits]}` returns `[user]` |

The server computes the same HMAC over its stored normalized numbers with that key, intersects in memory, and discards the uploaded hashes immediately. Nothing from the request is written to disk. A private set intersection protocol is the better design and is on the list for v1.1.

## Tags (every day)

| Method | Path | Notes |
| --- | --- | --- |
| POST | `tags/{id}/respond` | `{approve: bool}`; only the tagged user; decline notifies nobody |
| DELETE | `tags/{id}` | tagged user removes the photo from their profile; status `removed` |

## Safety

| Method | Path | Notes |
| --- | --- | --- |
| POST | `users/{id}/block` | removes follows and tags both ways |
| POST | `reports` | `{target_type: photo|dump|comment|profile, target_id, reason, note?}` |

## Shapes

```
user:     {id, username, name?, bio?, avatar_url?, is_public, timezone?}
tag:      {id, photo_id, tagger_id, tagged_user: user, status: pending|approved|declined|removed, responded_at?}
photo:    {id, dump_id, order, url, width, height, alt_text?, tags: [tag]}
dump:     {id, author: user, week_start, caption?, created_at, locked_at?, photos: [photo],
           comments_enabled, liked_by: [user], liked_by_me, comment_count}
comment:  {id, dump_id, author: user, body, created_at}
profile:  {user, relationship: me|following|requested|none|blocked, weeks: [week],
           follower_count?, following_count?}      counts only when relationship is "me"
week:     {week_start, dump?, tagged: [{photo, from: user, tag}]}
tag_request: {tag, photo, tagger: user, week_start}
```

`liked_by` carries names for the "Liked by Maya and Theo" line; the client switches to a count past 10.
