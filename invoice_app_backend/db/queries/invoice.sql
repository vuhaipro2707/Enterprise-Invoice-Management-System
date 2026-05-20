-- name: CreateBuyer :one
INSERT INTO buyers (
    buyer_code,
    buyer_name,
    address,
    phone_number,
    id_card_number,
    lat,
    lng
) VALUES (
    $1, $2, $3, $4, $5, $6, $7
) RETURNING *;

-- name: GetBuyerByID :one
SELECT * FROM buyers
WHERE buyer_id = $1 AND deleted_at IS NULL;

-- name: GetBuyerByCode :one
SELECT * FROM buyers
WHERE buyer_code = $1 AND deleted_at IS NULL;

-- name: CreateInvoice :one
INSERT INTO invoices (
    account_id,
    buyer_id,
    invoice_code,
    total_amount,
    device_holding_id,
    edit_status,
    buyer_name_snapshot,
    address_snapshot,
    phone_number_snapshot,
    lat_snapshot,
    lng_snapshot
) VALUES (
    $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11
) RETURNING *;

-- name: GetInvoiceByID :one
SELECT i.*, b.buyer_code
FROM invoices i
LEFT JOIN buyers b ON i.buyer_id = b.buyer_id
WHERE i.invoice_id = $1 AND i.deleted_at IS NULL;

-- name: GetInvoiceWithLines :one
SELECT i.*,
       b.buyer_code,
       COALESCE(JSON_AGG(JSONB_BUILD_OBJECT(
         'line_item_id', li.line_item_id,
         'item_id', li.item_id,
         'unit_id', li.unit_id,
         'quantity', li.quantity,
         'unit_price_custom', li.unit_price_custom,
         'sub_total', li.sub_total,
         'item_name_snapshot', li.item_name_snapshot,
         'unit_name_snapshot', li.unit_name_snapshot,
         'position_key', li.position_key
       ) ORDER BY li.position_key) FILTER (WHERE li.line_item_id IS NOT NULL), '[]')::JSONB AS line_items
FROM invoices i
LEFT JOIN buyers b ON i.buyer_id = b.buyer_id
LEFT JOIN line_items li ON i.invoice_id = li.invoice_id
WHERE i.invoice_id = $1 AND i.deleted_at IS NULL
GROUP BY i.invoice_id, b.buyer_code;

-- name: UpdateInvoiceStatus :one
UPDATE invoices
SET 
    device_holding_id = $2,
    edit_status = $3,
    updated_at = NOW()
WHERE invoice_id = $1 AND deleted_at IS NULL
RETURNING *;

-- name: UpdateInvoice :one
UPDATE invoices
SET
    account_id = $2,
    buyer_id = $3,
    invoice_code = $4,
    total_amount = $5,
    device_holding_id = $6,
    edit_status = $7,
    buyer_name_snapshot = $8,
    address_snapshot = $9,
    phone_number_snapshot = $10,
    lat_snapshot = $11,
    lng_snapshot = $12,
    updated_at = NOW()
WHERE invoice_id = $1 AND deleted_at IS NULL
RETURNING *;

-- name: UpdateBuyer :one
UPDATE buyers
SET
    buyer_code = $2,
    buyer_name = $3,
    address = $4,
    phone_number = $5,
    id_card_number = $6,
    lat = $7,
    lng = $8,
    updated_at = NOW()
WHERE buyer_id = $1 AND deleted_at IS NULL
RETURNING *;

-- name: CreateLineItem :one
INSERT INTO line_items (
    invoice_id,
    item_id,
    unit_id,
    quantity,
    unit_price_custom,
    sub_total,
    item_name_snapshot,
    unit_name_snapshot,
    position_key
) VALUES (
    $1, $2, $3, $4, $5, $6, $7, $8, $9
) RETURNING *;

-- name: GetLineItemByID :one
SELECT * FROM line_items
WHERE line_item_id = $1;

-- name: UpdateLineItem :one
UPDATE line_items
SET
    item_id = $2,
    unit_id = $3,
    quantity = $4,
    unit_price_custom = $5,
    sub_total = $6,
    item_name_snapshot = $7,
    unit_name_snapshot = $8
WHERE line_item_id = $1
RETURNING *;

-- name: UpdateLineItemPos :exec
UPDATE line_items
SET position_key = $2
WHERE line_item_id = $1;

-- name: DeleteLineItem :exec
DELETE FROM line_items
WHERE line_item_id = $1;

-- name: CreateDevice :one
INSERT INTO devices (
    device_holding_id,
    device_name
) VALUES (
    $1, $2
) ON CONFLICT (device_holding_id) DO UPDATE 
SET device_name = EXCLUDED.device_name
RETURNING *;

-- name: GetDeviceByID :one
SELECT * FROM devices
WHERE device_holding_id = $1;

-- name: GetInvoiceWithDeviceName :one
SELECT i.*, d.device_name
FROM invoices i
LEFT JOIN devices d ON i.device_holding_id = d.device_holding_id
WHERE i.invoice_id = $1 AND i.deleted_at IS NULL;

-- name: ListBuyers :many
SELECT * FROM buyers
WHERE deleted_at IS NULL
ORDER BY created_at DESC
LIMIT $1 OFFSET $2;

-- name: SearchBuyers :many
SELECT * FROM buyers
WHERE deleted_at IS NULL
AND (
    my_unaccent(buyer_name) ILIKE '%' || my_unaccent(sqlc.arg('keyword')) || '%'
    OR my_unaccent(buyer_code) ILIKE '%' || my_unaccent(sqlc.arg('keyword')) || '%'
    OR phone_number ILIKE '%' || sqlc.arg('keyword') || '%'
    OR id_card_number ILIKE '%' || sqlc.arg('keyword') || '%'
    OR my_unaccent(address) ILIKE '%' || my_unaccent(sqlc.arg('keyword')) || '%'
)
ORDER BY
    CASE WHEN buyer_code = sqlc.arg('keyword') THEN 0 ELSE 1 END,
    CASE WHEN phone_number = sqlc.arg('keyword') THEN 0 ELSE 1 END,
    CASE WHEN id_card_number = sqlc.arg('keyword') THEN 0 ELSE 1 END,
    similarity(my_unaccent(buyer_name), my_unaccent(sqlc.arg('keyword'))) DESC
LIMIT $1;

-- name: GetLastBuyerCode :one
SELECT buyer_code FROM buyers
WHERE buyer_code LIKE 'KH-%'
ORDER BY buyer_code DESC
LIMIT 1;

-- name: GetLastInvoiceCode :one
SELECT invoice_code FROM invoices
WHERE invoice_code LIKE $1
ORDER BY invoice_code DESC
LIMIT 1;

-- name: ListEditingInvoices :many
SELECT i.*, d.device_name, b.buyer_code
FROM invoices i
LEFT JOIN devices d ON i.device_holding_id = d.device_holding_id
LEFT JOIN buyers b ON i.buyer_id = b.buyer_id
WHERE i.edit_status = TRUE AND i.deleted_at IS NULL
ORDER BY i.updated_at DESC;

-- name: ListInvoicesFiltered :many
SELECT i.*, d.device_name, b.buyer_code
FROM invoices i
LEFT JOIN devices d ON i.device_holding_id = d.device_holding_id
LEFT JOIN buyers b ON i.buyer_id = b.buyer_id
WHERE i.deleted_at IS NULL
  AND (sqlc.arg('show_editing')::boolean = TRUE OR i.edit_status = FALSE)
  AND (sqlc.narg('buyer_id')::UUID IS NULL OR i.buyer_id = sqlc.narg('buyer_id')::UUID)
  AND (sqlc.narg('invoice_code')::text IS NULL OR my_unaccent(i.invoice_code) ILIKE my_unaccent(concat('%', sqlc.narg('invoice_code')::text, '%')))
  AND (sqlc.narg('item_id')::UUID IS NULL OR EXISTS (
      SELECT 1 FROM line_items li 
      WHERE li.invoice_id = i.invoice_id AND li.item_id = sqlc.narg('item_id')::UUID
  ))
  AND (sqlc.narg('start_date')::timestamptz IS NULL OR i.created_at >= sqlc.narg('start_date')::timestamptz)
  AND (sqlc.narg('end_date')::timestamptz IS NULL OR i.created_at <= sqlc.narg('end_date')::timestamptz)
ORDER BY 
  CASE WHEN sqlc.arg('sort_by')::text = 'updated_at' AND sqlc.arg('sort_order')::text = 'desc' THEN i.updated_at END DESC,
  CASE WHEN sqlc.arg('sort_by')::text = 'updated_at' AND sqlc.arg('sort_order')::text = 'asc' THEN i.updated_at END ASC,
  CASE WHEN sqlc.arg('sort_by')::text = 'created_at' AND sqlc.arg('sort_order')::text = 'desc' THEN i.created_at END DESC,
  CASE WHEN sqlc.arg('sort_by')::text = 'created_at' AND sqlc.arg('sort_order')::text = 'asc' THEN i.created_at END ASC,
  i.updated_at DESC
LIMIT sqlc.arg('limit_val')
OFFSET sqlc.arg('offset_val');

