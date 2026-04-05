-- name: CreateBuyer :one
INSERT INTO buyers (
    buyer_code,
    buyer_name,
    address,
    phone_number,
    id_card_number
) VALUES (
    $1, $2, $3, $4, $5
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

