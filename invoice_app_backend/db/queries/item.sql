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
  item_default_name,
  type_id
) VALUES (
  $1,
  $2
)
RETURNING *;

-- name: CreateItemOtherName :one
INSERT INTO item_other_names (
  item_id,
  name_string
) VALUES (
  $1, $2
)
RETURNING *;

-- name: ListItemOtherNames :many
SELECT * FROM item_other_names
WHERE item_id = $1;

-- name: DeleteItemOtherName :exec
DELETE FROM item_other_names
WHERE item_other_name_id = $1;

-- name: ListItems :many
SELECT i.*, 
       COALESCE(JSON_AGG(ion.name_string) FILTER (WHERE ion.name_string IS NOT NULL), '[]')::JSONB AS item_other_names
FROM items i
LEFT JOIN item_other_names ion ON i.item_id = ion.item_id
WHERE i.deleted_at IS NULL
GROUP BY i.item_id
ORDER BY i.created_at DESC;

-- name: GetItemByID :one
SELECT i.*,
       COALESCE(JSON_AGG(ion.name_string) FILTER (WHERE ion.name_string IS NOT NULL), '[]')::JSONB AS item_other_names
FROM items i
LEFT JOIN item_other_names ion ON i.item_id = ion.item_id
WHERE i.item_id = $1 AND i.deleted_at IS NULL
GROUP BY i.item_id;

-- name: GetUnitByID :one
SELECT * FROM units
WHERE unit_id = $1 AND deleted_at IS NULL;

-- name: AssignUnitToItem :one
UPDATE units
SET item_id = $1, updated_at = NOW()
WHERE unit_id = $2
RETURNING *;

-- name: SearchItems :many
SELECT i.*,
       COALESCE(JSON_AGG(ion.name_string) FILTER (WHERE ion.name_string IS NOT NULL), '[]')::JSONB AS item_other_names
FROM items i
LEFT JOIN item_other_names ion ON i.item_id = ion.item_id
WHERE i.deleted_at IS NULL
AND (
  -- ILIKE and trigram similarity can use pg_trgm index on item_default_name
  my_unaccent(i.item_default_name) ILIKE '%' || my_unaccent($1) || '%'
  OR my_unaccent(i.item_default_name) % my_unaccent($1)
  -- Exact search on other names
  OR EXISTS (
    SELECT 1 FROM item_other_names ion2 
    WHERE ion2.item_id = i.item_id 
    AND my_unaccent(ion2.name_string) ILIKE '%' || my_unaccent($1) || '%'
  )
)
GROUP BY i.item_id
ORDER BY
  -- Rank exact default-name match highest
  CASE WHEN my_unaccent(i.item_default_name) = my_unaccent($1) THEN 0 ELSE 1 END,
  -- Then prefix match
  CASE WHEN my_unaccent(i.item_default_name) ILIKE my_unaccent($1) || '%' THEN 0 ELSE 1 END,
  -- Then fuzzy relevance for remaining default-name matches
  similarity(my_unaccent(i.item_default_name), my_unaccent($1)) DESC,
  i.created_at DESC
LIMIT $2;

-- name: PatchItem :one
UPDATE items
SET
  item_default_name = CASE
    WHEN sqlc.arg(set_item_default_name)::boolean THEN sqlc.arg(item_default_name)
    ELSE item_default_name
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
