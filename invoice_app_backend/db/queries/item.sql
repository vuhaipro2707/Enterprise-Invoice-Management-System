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
