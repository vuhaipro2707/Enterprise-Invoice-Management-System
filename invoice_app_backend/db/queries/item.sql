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

-- name: GetItemByID :one
SELECT * FROM items
WHERE item_id = $1 AND deleted_at IS NULL;

-- name: GetUnitByID :one
SELECT * FROM units
WHERE unit_id = $1 AND deleted_at IS NULL;

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

-- name: PatchItem :one
UPDATE items
SET
  item_formal_name = CASE
    WHEN sqlc.arg(set_item_formal_name)::boolean THEN sqlc.arg(item_formal_name)
    ELSE item_formal_name
  END,
  item_short_names = CASE
    WHEN sqlc.arg(set_item_short_names)::boolean THEN sqlc.narg(item_short_names)
    ELSE item_short_names
  END,
  type_id = CASE
    WHEN sqlc.arg(set_type_id)::boolean THEN sqlc.narg(type_id)
    ELSE type_id
  END,
  updated_at = NOW()
WHERE item_id = sqlc.arg(item_id)
AND deleted_at IS NULL
RETURNING *;

-- name: PatchUnit :one
UPDATE units
SET
  unit_name = CASE
    WHEN sqlc.arg(set_unit_name)::boolean THEN sqlc.arg(unit_name)
    ELSE unit_name
  END,
  unit_price_default = CASE
    WHEN sqlc.arg(set_unit_price_default)::boolean THEN sqlc.arg(unit_price_default)
    ELSE unit_price_default
  END,
  item_id = CASE
    WHEN sqlc.arg(set_item_id)::boolean THEN sqlc.narg(item_id)
    ELSE item_id
  END,
  updated_at = NOW()
WHERE unit_id = sqlc.arg(unit_id)
AND deleted_at IS NULL
RETURNING *;

-- name: PatchType :one
UPDATE types
SET
  type_name = CASE
    WHEN sqlc.arg(set_type_name)::boolean THEN sqlc.arg(type_name)
    ELSE type_name
  END,
  updated_at = NOW()
WHERE type_id = sqlc.arg(type_id)
AND deleted_at IS NULL
RETURNING *;
