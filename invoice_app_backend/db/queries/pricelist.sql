-- name: CreateCustomerPriceList :one
INSERT INTO customer_price_lists (
    description,
    buyer_id
) VALUES (
    $1, $2
) RETURNING *;

-- name: CreateCustomerItemPrice :one
INSERT INTO customer_item_prices (
    customer_price_list_id,
    item_id,
    unit_id,
    unit_price_custom
) VALUES (
    $1, $2, $3, $4
) RETURNING *;

-- name: GetCustomerPriceListByID :one
SELECT cpl.*,
       b.buyer_code,
       b.buyer_name,
       b.phone_number,
       b.address,
       COALESCE(JSON_AGG(JSONB_BUILD_OBJECT(
         'customer_item_price_id', cip.customer_item_price_id,
         'item_id', cip.item_id,
         'item_default_name', it.item_default_name,
         'unit_id', cip.unit_id,
         'unit_name', u.unit_name,
         'unit_price_custom', cip.unit_price_custom
       )) FILTER (WHERE cip.customer_item_price_id IS NOT NULL), '[]')::JSONB AS item_prices
FROM customer_price_lists cpl
LEFT JOIN buyers b ON cpl.buyer_id = b.buyer_id
LEFT JOIN customer_item_prices cip ON cpl.customer_price_list_id = cip.customer_price_list_id
LEFT JOIN items it ON cip.item_id = it.item_id
LEFT JOIN units u ON cip.unit_id = u.unit_id
WHERE cpl.customer_price_list_id = $1 AND cpl.deleted_at IS NULL
GROUP BY cpl.customer_price_list_id, b.buyer_id, b.buyer_code, b.buyer_name, b.phone_number, b.address;

-- name: ListCustomerPriceListsFiltered :many
SELECT cpl.*,
       b.buyer_code,
       b.buyer_name,
       b.phone_number,
       b.address
FROM customer_price_lists cpl
LEFT JOIN buyers b ON cpl.buyer_id = b.buyer_id
WHERE cpl.deleted_at IS NULL
  AND (sqlc.narg('buyer_id')::UUID IS NULL OR cpl.buyer_id = sqlc.narg('buyer_id')::UUID)
  AND (
      sqlc.narg('buyer_name')::text IS NULL 
      OR (b.buyer_id IS NOT NULL AND (my_unaccent(b.buyer_name) ILIKE my_unaccent(concat('%', sqlc.narg('buyer_name')::text, '%')) OR my_unaccent(b.buyer_code) ILIKE my_unaccent(concat('%', sqlc.narg('buyer_name')::text, '%'))))
  )
  AND (sqlc.narg('start_date')::timestamptz IS NULL OR cpl.created_at >= sqlc.narg('start_date')::timestamptz)
  AND (sqlc.narg('end_date')::timestamptz IS NULL OR cpl.created_at <= sqlc.narg('end_date')::timestamptz)
ORDER BY 
  CASE WHEN sqlc.arg('sort_by')::text = 'updated_at' AND sqlc.arg('sort_order')::text = 'desc' THEN cpl.updated_at END DESC,
  CASE WHEN sqlc.arg('sort_by')::text = 'updated_at' AND sqlc.arg('sort_order')::text = 'asc' THEN cpl.updated_at END ASC,
  CASE WHEN sqlc.arg('sort_by')::text = 'created_at' AND sqlc.arg('sort_order')::text = 'desc' THEN cpl.created_at END DESC,
  CASE WHEN sqlc.arg('sort_by')::text = 'created_at' AND sqlc.arg('sort_order')::text = 'asc' THEN cpl.created_at END ASC,
  cpl.updated_at DESC
LIMIT sqlc.arg('limit_val')
OFFSET sqlc.arg('offset_val');

-- name: UpdateCustomerPriceList :one
UPDATE customer_price_lists
SET description = $2,
    buyer_id = $3,
    updated_at = NOW()
WHERE customer_price_list_id = $1 AND deleted_at IS NULL
RETURNING *;

-- name: DeleteCustomerPriceList :exec
UPDATE customer_price_lists
SET deleted_at = NOW()
WHERE customer_price_list_id = $1;

-- name: DeleteCustomerItemPricesByPriceListID :exec
DELETE FROM customer_item_prices
WHERE customer_price_list_id = $1;
