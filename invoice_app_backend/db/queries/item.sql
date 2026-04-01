-- name: CreateType :one
INSERT INTO types (
  type_name
) VALUES (
  $1
)
RETURNING *;

-- name: ListTypes :many
SELECT * FROM types
WHERE deleted_at IS NULL
ORDER BY created_at DESC;

-- name: CreateUnit :one
INSERT INTO units (
  unit_name,
  unit_price_default,
  item_id
) VALUES (
  $1,
  $2,
  $3
)
RETURNING *;

-- name: ListUnits :many
SELECT * FROM units
WHERE deleted_at IS NULL
ORDER BY created_at DESC;

-- name: CreateItem :one
INSERT INTO items (
  item_formal_name,
  item_short_names,
  type_id
) VALUES (
  $1,
  $2,
  $3
)
RETURNING *;

-- name: ListItems :many
SELECT * FROM items
WHERE deleted_at IS NULL
ORDER BY created_at DESC;

-- name: AssignUnitToItem :one
UPDATE units
SET item_id = $1, updated_at = NOW()
WHERE unit_id = $2
RETURNING *;

-- name: SearchItems :many
SELECT * FROM items
WHERE deleted_at IS NULL
AND (
  -- ILIKE and trigram similarity can use pg_trgm index on item_formal_name
  item_formal_name ILIKE '%' || $1 || '%'
  OR item_formal_name % $1
  -- Exact short-name match on JSONB array can use GIN index
  OR (my_unaccent(item_short_names::text)) ILIKE '%' || my_unaccent($1) || '%' -- Note: Make JsonB into part treat it as text for index usage
)
ORDER BY
  -- Rank exact formal-name match highest
  CASE WHEN item_formal_name = $1 THEN 0 ELSE 1 END,
  -- Then prefix match
  CASE WHEN item_formal_name ILIKE $1 || '%' THEN 0 ELSE 1 END,
  -- Then exact short-name match
  CASE WHEN (my_unaccent(item_short_names::text)) ILIKE '%' || my_unaccent($1) || '%' THEN 0 ELSE 1 END,
  -- Then fuzzy relevance for remaining formal-name matches
  similarity(item_formal_name, $1) DESC,
  created_at DESC
LIMIT $2;
