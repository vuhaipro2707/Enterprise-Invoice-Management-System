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
    phone_number_snapshot
) VALUES (
    $1, $2, $3, $4, $5, $6, $7, $8, $9
) RETURNING *;

-- name: GetInvoiceByID :one
SELECT * FROM invoices
WHERE invoice_id = $1 AND deleted_at IS NULL;

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
    unit_name_snapshot
) VALUES (
    $1, $2, $3, $4, $5, $6, $7, $8
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

