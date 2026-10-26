# Ideas near you

Monday to Saturday the app shows one idea for the day. With this feature on, that idea can come
from the user's own neighborhood: a bakery to be first in line at, a lookout for the last light.
It is off by default, it never runs on Sunday, and it is built so the server never learns where
any one person is. This document is the design, the privacy argument, and the cost model.

## The promise, and where each part is enforced

The consent sheet (`LocationConsentSheet`) and the iOS permission string make three promises.
Each one is kept by code, not by policy.

| Promise | Where it is kept |
| --- | --- |
| Weekdays only. On Sunday it never looks, whatever is switched on. | `LocalIdeasStore.refresh` returns before touching location when `clock.isSunday()`. `LocalIdeasPolicy.shouldFetch` has a test for it. `MockSundaeAPI` and the reference server both answer `sunday_closed` for a Sunday `day`. The Sunday screens never call the store. |
| Your exact spot stays on this phone. Only a neighborhood-sized area is sent. | `LocationCell.currentCell()` turns the fix into a geohash cell (6 characters, about 1.2 km by 0.6 km; 5 characters when iOS grants approximate location) inside the same function and returns only the string. No property, log, or request ever holds coordinates. |
| Sent with no account attached. | `LiveSundaeAPI.localIdeas` calls the client with `authenticated: false`, so no bearer token goes out. A test checks the request has no `Authorization` header. Idea ids are `local:<day>:<n>`, so marking one done sends nothing about where. |
| Never on your photos. | `PhotoProcessor` already re-encodes every photo through a fresh bitmap, which drops EXIF and GPS. Nothing in this feature touches photos. |
| Never shown to friends, never saved. | The only thing stored is today's list of ideas (place names and the places' positions) and the time of the last look, in app defaults. Turning the switch off clears them. Nothing is sent to the social API. |

Other choices that follow from the promise: location is requested "when in use" only, never
"always"; there is no background location, no significant-change monitoring, no geofencing; one
fix per look, with the accuracy iOS gives when asked for a hundred meters; and at most a few looks a day
(`LocalIdeasPolicy.refreshInterval`), only when the app is open on the weekday screen.

## What an idea may never say or point to

Every idea passes `IdeaGuard` (Swift, `Shared/IdeaGuard.swift`) or its exact copy on the server
(`server/local-ideas/src/guard.js`) before it is stored or shown, and again when it is read back:
from Maps, from the demo backend, from a server, from the cache, from the bundled catalog.

- No violent words, including ones that only read as violent out of context. "Photograph" is
  the only verb for taking a picture; "shoot" and "shot" are refused outright.
- Cameras point at things, light and friends, never at strangers, staff, crowds or children.
- No alcohol, drugs or smoking. Nothing risky: no roofs, tracks, cliffs, trespassing, dares, or
  walking until the phone loses signal.
- No solemn or sensitive places, whatever the wording: memorials, cemeteries, places of
  worship, hospitals and clinics, schools, prisons and courts, police and military sites. Maps
  results in those categories or with those words in the name are dropped before picking.

Tests read every line the app and the server can write and fail the build if one does not
pass; a server test also keeps the two lists identical. When an idea fails at runtime it is
dropped and a catalog idea takes its place.

## How the phone does it

1. The user turns it on from the weekday screen ("Make today's idea local") or Settings. Sundae's
   own sheet comes first; the iOS prompt only appears on the first look, after they agreed.
2. On the weekday screen, `LocalIdeasStore.refresh` checks: on, not Sunday, nothing fresh for today.
3. It asks Core Location for one fix, reduces it to a cell, and discards the fix.
4. It asks `GET v1/ideas/local?cell=<cell>&day=<YYYY-MM-DD>` with no token.
5. It stores the day's ideas in app defaults and hands them to `WeekdayStore`, which swaps a
   nearby idea in for the automatic catalog pick (never over something the user shuffled to or
   finished). The widget shows the same idea.

## Where the places come from

Two sources, same shape, same rules:

- **On the phone, from Apple Maps (the default).** `NearbyIdeas` runs one plain-words search
  per kind of place (coffee shop, bakery, park, library, bookstore, record store, museum,
  gallery, market, diner, ice cream, trail, beach, viewpoint) around the middle of the cell,
  once within a walk and once within twenty miles, and merges the results. A single broad
  search came back mostly parks; a search per kind gives every kind a fair chance. Eight
  ideas a day, every kind before any kind repeats. The
  morning idea stays walkable; the afternoon and evening may be worth the drive, and the line
  under the idea shows the distance instead of a walking time. The same cell center goes to
  Open-Meteo, anonymously and without a key, so a wet day keeps to places with a roof. The pick is seeded by `cell:day`
  so the three ideas hold still all day. Apple sees a neighborhood center, not the fix, under the
  user's existing Apple Maps relationship; Sundae's servers see nothing, because there are none
  involved. Cost: zero at any scale. Limit: Apple throttles heavy MapKit use, and one search per
  user per day is far below that.
- **From a server, when `SUNDAE_API_BASE_URL` is set.** `LiveSundaeAPI.localIdeas` asks the
  anonymous endpoint below. This is for curated or licensed places data, or for copy that changes
  without an app update.

The store switches between them at launch (`LocalIdeasStore(onDevice:)`). Everything above
about the Sunday rule, the cell, and the ids holds for both.

## How the server does it cheaply

The whole cost argument is one observation: **the answer is a function of (cell, day), not of
the user.** A six-character geohash cell is a few blocks. Everyone standing in it on the same day
should get the same three ideas, and that is also the best privacy design, because the server
never has to know who asked. So:

- **The request is anonymous and the response is public**, with `Cache-Control: public,
  max-age=86400`. Cloudflare's edge serves repeats for free. A city of a million people is a few
  thousand cells, so the number of distinct answers per day is bounded by geography, not by users.
- **Generation is deterministic.** A seeded random pick keyed on `cell:day` chooses places and
  copy, so every edge location computes the same answer without coordination or a database write.
  Nothing needs to be stored to be consistent.
- **The data is static and pre-sharded.** Places come from an open dataset (Overture Maps Places
  or Foursquare Open Source Places, both free), filtered once to the dozen categories the copy
  knows about, and written as one JSON file per four-character geohash cell (about 39 km by
  20 km) in R2. A miss reads the cell's shard and the ones a twenty-mile box touches, usually
  two or three, filters to twenty miles around the cell's center, and picks. A few milliseconds
  of CPU.
- **No model in the request path.** The copy is a template catalog written once per category and
  time of day. An LLM can be used offline to write or refresh that catalog, which costs the
  same whether there are ten users or ten million.
- **No per-user state on the server.** Personalization, if it ever comes, happens on the phone,
  which can filter the three ideas against what the user already did this week.

The reference implementation is a Cloudflare Worker in `server/local-ideas/` (no dependencies,
tests run with `node --test`). Any platform with an edge cache and object storage works the same
way; the shape matters, not the vendor.

### Cost model

Assumptions: a user opens the app about 1.5 times a day on weekdays, 26 weekdays a month, and about
20 percent of requests miss the edge cache and recompute (each miss is one or two R2 reads and a
few milliseconds of CPU). Cloudflare list prices as of 2025: Workers $5 a month with 10M requests
included then $0.30 per million; R2 reads $0.36 per million, egress free.

| Daily weekday users | Requests a month | Estimated monthly cost |
| --- | --- | --- |
| 5,000 | 200,000 | $0 (free tier: 100,000 requests a day, 10M R2 reads a month) |
| 50,000 | 2M | $0 to $5 |
| 1,000,000 | 39M | about $15 to $20 |
| 10,000,000 | 390M | about $150 |

Storage is a rounding error: the filtered world dataset is a few hundred megabytes of JSON.
Rebuilding the shards is a monthly batch job on a laptop. Nothing here needs to be provisioned,
scaled, or paged for.

What it would cost done the obvious way, for contrast: an authenticated endpoint that takes
coordinates, queries a geospatial database per request, logs it, and maybe asks a model for copy,
runs to dollars per thousand users per day and gets worse with scale.

## Operating it

- Build shards with `server/local-ideas/scripts/places.sql` (DuckDB, straight from the public
  Overture release) and `scripts/build-shards.mjs`, then `wrangler r2 object put` them.
- Deploy with `wrangler deploy`. There is nothing to migrate.
- Logs: keep invocation logs off, or at least never log `cell` with the client IP. The Worker
  itself logs nothing. If you want usage numbers, count requests per day; do not keep cells.
- Rotate the places data monthly; the cache key does not include a data version, so a day's
  answers can change mid-day on a deploy. That is fine for ideas.

## Edges

- **Quiet areas.** A rural cell may have nothing within twenty miles that the copy knows about.
  The server returns an empty list and the app shows a catalog idea with a footnote.
- **Approximate location.** If the user granted only approximate location, the cell is five
  characters (about 5 km) and the walking times are rough. The app does not ask for temporary
  precise location; the user can grant it in iOS Settings if they want tighter ideas.
- **Travel.** Ideas refresh after four hours or on a new day, so a trip across town shows up by
  the afternoon. Ids are per day and slot, so a done mark from the morning can shadow a different
  afternoon idea in the same slot once in a long while. Accepted.
- **Time zones.** The phone sends its local date. The server accepts dates within two days of
  its own clock and checks the weekday of the date it was given.
