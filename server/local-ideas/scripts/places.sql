-- Export the places the ideas know about from the public Overture Maps release, as NDJSON for
-- build-shards.mjs. Run with DuckDB (https://duckdb.org): duckdb < scripts/places.sql
-- Swap the release path for the current one at https://docs.overturemaps.org/release/.
-- Category names follow the Overture taxonomy; build-shards.mjs maps them onto the idea themes.

INSTALL spatial; LOAD spatial;
INSTALL httpfs; LOAD httpfs;
SET s3_region = 'us-west-2';

COPY (
  SELECT
    id,
    names.primary AS name,
    categories.primary AS category,
    ST_Y(geometry) AS lat,
    ST_X(geometry) AS lon
  FROM read_parquet('s3://overturemaps-us-west-2/release/2025-09-24.0/theme=places/type=place/*', hive_partitioning = 1)
  WHERE confidence >= 0.6
    AND names.primary IS NOT NULL
    AND categories.primary IN (
      'cafe', 'coffee_shop', 'tea_room',
      'bakery', 'patisserie',
      'park', 'dog_park', 'playground', 'plaza', 'public_plaza',
      'scenic_lookout', 'scenic_point', 'observation_deck', 'lookout',
      'library', 'public_library',
      'bookstore', 'used_bookstore', 'comic_book_store',
      'farmers_market', 'public_market', 'market',
      'museum', 'art_museum', 'history_museum', 'science_museum',
      'art_gallery', 'gallery',
      'botanical_garden', 'community_garden', 'garden',
      'hiking_trail', 'trail', 'trailhead',
      'beach', 'pier', 'boardwalk', 'waterfront', 'promenade', 'marina',
      'diner', 'breakfast_restaurant',
      'record_store', 'music_store', 'vinyl_record_store',
      'ice_cream_shop', 'gelato_shop'
    )
) TO 'places.ndjson' (FORMAT JSON);
