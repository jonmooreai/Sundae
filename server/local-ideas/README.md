# Local ideas service

Reference implementation of `GET /v1/ideas/local` (see `docs/API.md` and `docs/LOCAL_IDEAS.md`
at the repository root). A Cloudflare Worker with no dependencies: the edge cache in front, a
places index in R2 behind, a deterministic pick in the middle. It never sees who is asking.

```
npm test                              # node --test, no install needed
duckdb < scripts/places.sql           # places.ndjson from the public Overture release
node scripts/build-shards.mjs places.ndjson out/
for f in out/places/*.json; do npx wrangler r2 object put "sundae-places/places/$(basename "$f")" --file "$f"; done
npx wrangler deploy
```

Point the app at it with `SUNDAE_API_BASE_URL` (the path is `v1/ideas/local` under the base URL).

Rules the code keeps: Sundays answer `sunday_closed`; cells are 5 or 6 characters, never finer;
ids are `local:<day>:<n>`, never the cell; responses are `public, max-age=86400`; no logs.
