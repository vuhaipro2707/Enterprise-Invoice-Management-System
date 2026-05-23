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
  item_id,
  ratio,
  is_base_unit
) VALUES (
  $1,
  $2,
  $3,
  $4,
  $5
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
       COALESCE(JSON_AGG(DISTINCT JSONB_BUILD_OBJECT(
         'item_other_name_id', ion.item_other_name_id,
         'name_string', ion.name_string
       )) FILTER (WHERE ion.item_other_name_id IS NOT NULL), '[]')::JSONB AS item_other_names,
       COALESCE(JSON_AGG(DISTINCT JSONB_BUILD_OBJECT(
         'unit_id', u.unit_id,
         'unit_name', u.unit_name,
         'unit_price_default', u.unit_price_default,
         'ratio', u.ratio,
         'is_base_unit', u.is_base_unit
       )) FILTER (WHERE u.unit_id IS NOT NULL), '[]')::JSONB AS units
FROM items i
LEFT JOIN item_other_names ion ON i.item_id = ion.item_id
LEFT JOIN units u ON i.item_id = u.item_id AND u.deleted_at IS NULL
WHERE i.deleted_at IS NULL
GROUP BY i.item_id
ORDER BY i.created_at DESC;

-- name: GetItemByID :one
SELECT i.*,
       COALESCE(JSON_AGG(DISTINCT JSONB_BUILD_OBJECT(
         'item_other_name_id', ion.item_other_name_id,
         'name_string', ion.name_string
       )) FILTER (WHERE ion.item_other_name_id IS NOT NULL), '[]')::JSONB AS item_other_names,
       COALESCE(JSON_AGG(DISTINCT JSONB_BUILD_OBJECT(
         'unit_id', u.unit_id,
         'unit_name', u.unit_name,
         'unit_price_default', u.unit_price_default,
         'ratio', u.ratio,
         'is_base_unit', u.is_base_unit
       )) FILTER (WHERE u.unit_id IS NOT NULL), '[]')::JSONB AS units
FROM items i
LEFT JOIN item_other_names ion ON i.item_id = ion.item_id
LEFT JOIN units u ON i.item_id = u.item_id AND u.deleted_at IS NULL
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
       COALESCE(JSON_AGG(DISTINCT JSONB_BUILD_OBJECT(
         'item_other_name_id', ion.item_other_name_id,
         'name_string', ion.name_string
       )) FILTER (WHERE ion.item_other_name_id IS NOT NULL), '[]')::JSONB AS item_other_names,
       COALESCE(JSON_AGG(DISTINCT JSONB_BUILD_OBJECT(
         'unit_id', u.unit_id,
         'unit_name', u.unit_name,
         'unit_price_default', u.unit_price_default,
         'ratio', u.ratio,
         'is_base_unit', u.is_base_unit
       )) FILTER (WHERE u.unit_id IS NOT NULL), '[]')::JSONB AS units
FROM items i
LEFT JOIN item_other_names ion ON i.item_id = ion.item_id
LEFT JOIN units u ON i.item_id = u.item_id AND u.deleted_at IS NULL
WHERE i.deleted_at IS NULL
AND (sqlc.narg('type_id')::UUID IS NULL OR i.type_id = sqlc.narg('type_id')::UUID)
AND (
  -- ILIKE and trigram similarity can use pg_trgm index on item_default_name
  my_unaccent(i.item_default_name) ILIKE '%' || my_unaccent(sqlc.arg('keyword')) || '%'
  OR my_unaccent(i.item_default_name) % my_unaccent(sqlc.arg('keyword'))
  -- Exact search on other names
  OR EXISTS (
    SELECT 1 FROM item_other_names ion2 
    WHERE ion2.item_id = i.item_id 
    AND my_unaccent(ion2.name_string) ILIKE '%' || my_unaccent(sqlc.arg('keyword')) || '%'
  )
)
GROUP BY i.item_id
ORDER BY
  -- Rank exact default-name match highest
  CASE WHEN my_unaccent(i.item_default_name) = my_unaccent(sqlc.arg('keyword')) THEN 0 ELSE 1 END,
  -- Then prefix match
  CASE WHEN my_unaccent(i.item_default_name) ILIKE my_unaccent(sqlc.arg('keyword')) || '%' THEN 0 ELSE 1 END,
  -- Then fuzzy relevance for remaining default-name matches
  similarity(my_unaccent(i.item_default_name), my_unaccent(sqlc.arg('keyword'))) DESC,
  i.created_at DESC
LIMIT sqlc.arg('limit_val');

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
  ratio = CASE
    WHEN sqlc.arg(set_ratio)::boolean THEN sqlc.arg(ratio)
    ELSE ratio
  END,
  is_base_unit = CASE
    WHEN sqlc.arg(set_is_base_unit)::boolean THEN sqlc.arg(is_base_unit)
    ELSE is_base_unit
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

-- name: ListItemsFiltered :many
SELECT i.*, 
       COALESCE(JSON_AGG(DISTINCT JSONB_BUILD_OBJECT(
         'item_other_name_id', ion.item_other_name_id,
         'name_string', ion.name_string
       )) FILTER (WHERE ion.item_other_name_id IS NOT NULL), '[]')::JSONB AS item_other_names,
       COALESCE(JSON_AGG(DISTINCT JSONB_BUILD_OBJECT(
         'unit_id', u.unit_id,
         'unit_name', u.unit_name,
         'unit_price_default', u.unit_price_default,
         'ratio', u.ratio,
         'is_base_unit', u.is_base_unit
       )) FILTER (WHERE u.unit_id IS NOT NULL), '[]')::JSONB AS units
FROM items i
LEFT JOIN item_other_names ion ON i.item_id = ion.item_id
LEFT JOIN units u ON i.item_id = u.item_id AND u.deleted_at IS NULL
WHERE i.deleted_at IS NULL
AND (sqlc.narg('type_id')::UUID IS NULL OR i.type_id = sqlc.narg('type_id')::UUID)
GROUP BY i.item_id
ORDER BY 
  CASE WHEN sqlc.arg('sort_by')::text = 'item_default_name' AND sqlc.arg('sort_order')::text = 'asc' THEN i.item_default_name END ASC,
  CASE WHEN sqlc.arg('sort_by')::text = 'item_default_name' AND sqlc.arg('sort_order')::text = 'desc' THEN i.item_default_name END DESC,
  i.created_at DESC
LIMIT sqlc.arg('limit_val')
OFFSET sqlc.arg('offset_val');

-- name: DeleteUnit :exec
UPDATE units
SET deleted_at = NOW(),
    updated_at = NOW()
WHERE unit_id = $1;

-- name: DeleteItem :exec
UPDATE items
SET deleted_at = NOW(),
    updated_at = NOW()
WHERE item_id = $1;

-- name: RestoreItem :exec
UPDATE items
SET deleted_at = NULL,
    updated_at = NOW()
WHERE item_id = $1;

-- name: ListDeletedItems :many
SELECT i.*, 
       COALESCE(JSON_AGG(DISTINCT JSONB_BUILD_OBJECT(
         'item_other_name_id', ion.item_other_name_id,
         'name_string', ion.name_string
       )) FILTER (WHERE ion.item_other_name_id IS NOT NULL), '[]')::JSONB AS item_other_names,
       COALESCE(JSON_AGG(DISTINCT JSONB_BUILD_OBJECT(
         'unit_id', u.unit_id,
         'unit_name', u.unit_name,
         'unit_price_default', u.unit_price_default,
         'ratio', u.ratio,
         'is_base_unit', u.is_base_unit
       )) FILTER (WHERE u.unit_id IS NOT NULL), '[]')::JSONB AS units
FROM items i
LEFT JOIN item_other_names ion ON i.item_id = ion.item_id
LEFT JOIN units u ON i.item_id = u.item_id AND u.deleted_at IS NULL
WHERE i.deleted_at IS NOT NULL
GROUP BY i.item_id
ORDER BY i.deleted_at DESC;
