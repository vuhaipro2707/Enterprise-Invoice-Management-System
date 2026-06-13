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
         'itemOtherNameId', ion.item_other_name_id,
         'nameString', ion.name_string
       )) FILTER (WHERE ion.item_other_name_id IS NOT NULL), '[]')::JSONB AS item_other_names,
       COALESCE(JSON_AGG(DISTINCT JSONB_BUILD_OBJECT(
         'unitId', u.unit_id,
         'unitName', u.unit_name,
         'unitPriceDefault', u.unit_price_default,
         'ratio', u.ratio,
         'isBaseUnit', u.is_base_unit
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
         'itemOtherNameId', ion.item_other_name_id,
         'nameString', ion.name_string
       )) FILTER (WHERE ion.item_other_name_id IS NOT NULL), '[]')::JSONB AS item_other_names,
       COALESCE(JSON_AGG(DISTINCT JSONB_BUILD_OBJECT(
         'unitId', u.unit_id,
         'unitName', u.unit_name,
         'unitPriceDefault', u.unit_price_default,
         'ratio', u.ratio,
         'isBaseUnit', u.is_base_unit
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
         'itemOtherNameId', ion.item_other_name_id,
         'nameString', ion.name_string
       )) FILTER (WHERE ion.item_other_name_id IS NOT NULL), '[]')::JSONB AS item_other_names,
       COALESCE(JSON_AGG(DISTINCT JSONB_BUILD_OBJECT(
         'unitId', u.unit_id,
         'unitName', u.unit_name,
         'unitPriceDefault', u.unit_price_default,
         'ratio', u.ratio,
         'isBaseUnit', u.is_base_unit
       )) FILTER (WHERE u.unit_id IS NOT NULL), '[]')::JSONB AS units
FROM items i
LEFT JOIN item_other_names ion ON i.item_id = ion.item_id
LEFT JOIN units u ON i.item_id = u.item_id AND u.deleted_at IS NULL
LEFT JOIN types t ON i.type_id = t.type_id AND t.deleted_at IS NULL
WHERE i.deleted_at IS NULL
AND (sqlc.narg('type_id')::UUID IS NULL OR i.type_id = sqlc.narg('type_id')::UUID)
AND (
  -- Check if all words from keyword are present or highly similar in my_unaccent(item_default_name)
  (
    SELECT COALESCE(bool_and(
      my_unaccent(i.item_default_name) ILIKE '%' || word || '%'
      OR word_similarity(word, my_unaccent(i.item_default_name)) > 0.3
    ), FALSE)
    FROM unnest(string_to_array(my_unaccent(sqlc.arg('keyword')), ' ')) AS word
    WHERE word <> ''
  )
  -- Or similarity is close enough (for fuzzy matching)
  OR my_unaccent(i.item_default_name) % my_unaccent(sqlc.arg('keyword'))
  -- Or there exists an other name containing all words from keyword
  OR EXISTS (
    SELECT 1 FROM item_other_names ion2 
    WHERE ion2.item_id = i.item_id 
    AND (
      SELECT COALESCE(bool_and(
        my_unaccent(ion2.name_string) ILIKE '%' || word || '%'
        OR word_similarity(word, my_unaccent(ion2.name_string)) > 0.3
      ), FALSE)
      FROM unnest(string_to_array(my_unaccent(sqlc.arg('keyword')), ' ')) AS word
      WHERE word <> ''
    )
  )
  -- Or type name matches all words from keyword or is highly similar
  OR (
    t.type_id IS NOT NULL AND (
      (
        SELECT COALESCE(bool_and(
          my_unaccent(t.type_name) ILIKE '%' || word || '%'
          OR word_similarity(word, my_unaccent(t.type_name)) > 0.3
        ), FALSE)
        FROM unnest(string_to_array(my_unaccent(sqlc.arg('keyword')), ' ')) AS word
        WHERE word <> ''
      )
      OR my_unaccent(t.type_name) % my_unaccent(sqlc.arg('keyword'))
    )
  )
  -- Or initials of default name matches the keyword (substring search)
  OR (length(sqlc.arg('keyword')) >= 2 AND get_initials(i.item_default_name) ILIKE '%' || my_unaccent(sqlc.arg('keyword')) || '%')
  -- Or initials of an other name matches the keyword (substring search)
  OR EXISTS (
    SELECT 1 FROM item_other_names ion3
    WHERE ion3.item_id = i.item_id
    AND length(sqlc.arg('keyword')) >= 2
    AND get_initials(ion3.name_string) ILIKE '%' || my_unaccent(sqlc.arg('keyword')) || '%'
  )
)
GROUP BY i.item_id, t.type_id, t.type_name
ORDER BY
  -- Rank by dynamic relevance score
  (
    -- Exact default-name match boost
    (CASE WHEN my_unaccent(i.item_default_name) = my_unaccent(sqlc.arg('keyword')) THEN 10.0 ELSE 0.0 END) +
    -- Prefix default-name match boost
    (CASE WHEN my_unaccent(i.item_default_name) ILIKE my_unaccent(sqlc.arg('keyword')) || '%' THEN 5.0 ELSE 0.0 END) +
    -- Exact other-name match boost
    (CASE WHEN EXISTS (
      SELECT 1 FROM item_other_names ion_score
      WHERE ion_score.item_id = i.item_id AND my_unaccent(ion_score.name_string) = my_unaccent(sqlc.arg('keyword'))
    ) THEN 8.0 ELSE 0.0 END) +
    -- Exact type-name match boost
    (CASE WHEN t.type_name IS NOT NULL AND my_unaccent(t.type_name) = my_unaccent(sqlc.arg('keyword')) THEN 6.0 ELSE 0.0 END) +
    -- Exact default-name initials match boost
    (CASE WHEN length(sqlc.arg('keyword')) >= 2 AND get_initials(i.item_default_name) = my_unaccent(sqlc.arg('keyword')) THEN 7.0 ELSE 0.0 END) +
    -- Prefix default-name initials match boost
    (CASE WHEN length(sqlc.arg('keyword')) >= 2 AND get_initials(i.item_default_name) ILIKE my_unaccent(sqlc.arg('keyword')) || '%' THEN 4.0 ELSE 0.0 END) +
    -- Substring default-name initials match boost
    (CASE WHEN length(sqlc.arg('keyword')) >= 2 AND get_initials(i.item_default_name) ILIKE '%' || my_unaccent(sqlc.arg('keyword')) || '%' THEN 2.0 ELSE 0.0 END) +
    -- Exact other-name initials match boost
    (CASE WHEN EXISTS (
      SELECT 1 FROM item_other_names ion_score3
      WHERE ion_score3.item_id = i.item_id
      AND length(sqlc.arg('keyword')) >= 2
      AND get_initials(ion_score3.name_string) = my_unaccent(sqlc.arg('keyword'))
    ) THEN 6.0 ELSE 0.0 END) +
    -- Prefix other-name initials match boost
    (CASE WHEN EXISTS (
      SELECT 1 FROM item_other_names ion_score4
      WHERE ion_score4.item_id = i.item_id
      AND length(sqlc.arg('keyword')) >= 2
      AND get_initials(ion_score4.name_string) ILIKE my_unaccent(sqlc.arg('keyword')) || '%'
    ) THEN 3.0 ELSE 0.0 END) +
    -- Substring other-name initials match boost
    (CASE WHEN EXISTS (
      SELECT 1 FROM item_other_names ion_score5
      WHERE ion_score5.item_id = i.item_id
      AND length(sqlc.arg('keyword')) >= 2
      AND get_initials(ion_score5.name_string) ILIKE '%' || my_unaccent(sqlc.arg('keyword')) || '%'
    ) THEN 1.0 ELSE 0.0 END) +
    -- Trigram similarities weights
    (similarity(my_unaccent(i.item_default_name), my_unaccent(sqlc.arg('keyword'))) * 4.0) +
    (COALESCE((
      SELECT MAX(similarity(my_unaccent(ion_score2.name_string), my_unaccent(sqlc.arg('keyword'))))
      FROM item_other_names ion_score2
      WHERE ion_score2.item_id = i.item_id
    ), 0.0) * 3.0) +
    (COALESCE(similarity(my_unaccent(t.type_name), my_unaccent(sqlc.arg('keyword'))), 0.0) * 2.0)
  ) DESC,
  i.created_at DESC
LIMIT sqlc.arg('limit_val')
OFFSET sqlc.arg('offset_val');

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
         'itemOtherNameId', ion.item_other_name_id,
         'nameString', ion.name_string
       )) FILTER (WHERE ion.item_other_name_id IS NOT NULL), '[]')::JSONB AS item_other_names,
       COALESCE(JSON_AGG(DISTINCT JSONB_BUILD_OBJECT(
         'unitId', u.unit_id,
         'unitName', u.unit_name,
         'unitPriceDefault', u.unit_price_default,
         'ratio', u.ratio,
         'isBaseUnit', u.is_base_unit
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
         'itemOtherNameId', ion.item_other_name_id,
         'nameString', ion.name_string
       )) FILTER (WHERE ion.item_other_name_id IS NOT NULL), '[]')::JSONB AS item_other_names,
       COALESCE(JSON_AGG(DISTINCT JSONB_BUILD_OBJECT(
         'unitId', u.unit_id,
         'unitName', u.unit_name,
         'unitPriceDefault', u.unit_price_default,
         'ratio', u.ratio,
         'isBaseUnit', u.is_base_unit
       )) FILTER (WHERE u.unit_id IS NOT NULL), '[]')::JSONB AS units
FROM items i
LEFT JOIN item_other_names ion ON i.item_id = ion.item_id
LEFT JOIN units u ON i.item_id = u.item_id AND u.deleted_at IS NULL
WHERE i.deleted_at IS NOT NULL
GROUP BY i.item_id
ORDER BY i.deleted_at DESC;
