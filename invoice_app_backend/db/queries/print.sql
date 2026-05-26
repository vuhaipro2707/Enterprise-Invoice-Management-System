-- name: CreatePrintJob :one
INSERT INTO print_queue (
    invoice_id,
    customer_price_list_id,
    print_type,
    print_part,
    priority_num,
    print_status
) VALUES (
    sqlc.narg('invoice_id')::uuid,
    sqlc.narg('customer_price_list_id')::uuid,
    sqlc.arg('print_type')::print_type_enum,
    sqlc.narg('print_part')::print_part_enum,
    COALESCE(sqlc.narg('priority_num')::integer, 0),
    'Pending'
) RETURNING *;

-- name: GetPrintJobs :many
SELECT 
    pq.print_job_id,
    pq.invoice_id,
    pq.customer_price_list_id,
    pq.print_status,
    pq.print_type,
    pq.print_part,
    pq.retry_count,
    pq.priority_num,
    pq.created_at,
    pq.printed_at,
    i.invoice_code,
    i.buyer_name_snapshot AS invoice_buyer_name,
    cpl.description AS price_list_description,
    b.buyer_name AS price_list_buyer_name
FROM print_queue pq
LEFT JOIN invoices i ON pq.invoice_id = i.invoice_id
LEFT JOIN customer_price_lists cpl ON pq.customer_price_list_id = cpl.customer_price_list_id
LEFT JOIN buyers b ON cpl.buyer_id = b.buyer_id
WHERE 
    (sqlc.narg(print_status)::text IS NULL OR sqlc.narg(print_status)::text = '' OR pq.print_status::text = sqlc.narg(print_status)::text)
    AND (
        sqlc.narg(queue_type)::text IS NULL OR sqlc.narg(queue_type)::text = 'Both' OR sqlc.narg(queue_type)::text = ''
        OR (sqlc.narg(queue_type)::text = 'Invoice' AND pq.invoice_id IS NOT NULL)
        OR (sqlc.narg(queue_type)::text = 'PriceList' AND pq.customer_price_list_id IS NOT NULL)
    )
    AND (
        (sqlc.narg(invoice_id)::uuid IS NULL AND sqlc.narg(customer_price_list_id)::uuid IS NULL)
        OR (sqlc.narg(invoice_id)::uuid IS NOT NULL AND sqlc.narg(customer_price_list_id)::uuid IS NULL AND pq.invoice_id = sqlc.narg(invoice_id)::uuid)
        OR (sqlc.narg(invoice_id)::uuid IS NULL AND sqlc.narg(customer_price_list_id)::uuid IS NOT NULL AND pq.customer_price_list_id = sqlc.narg(customer_price_list_id)::uuid)
        OR (sqlc.narg(invoice_id)::uuid IS NOT NULL AND sqlc.narg(customer_price_list_id)::uuid IS NOT NULL AND (pq.invoice_id = sqlc.narg(invoice_id)::uuid OR pq.customer_price_list_id = sqlc.narg(customer_price_list_id)::uuid))
    )
ORDER BY 
    CASE pq.print_status::text
        WHEN 'Failed' THEN 1
        WHEN 'Printing' THEN 2
        WHEN 'Pending' THEN 3
        WHEN 'Cancelled' THEN 4
        WHEN 'Completed' THEN 5
        ELSE 6
    END ASC,
    pq.priority_num DESC, 
    pq.created_at ASC
LIMIT sqlc.arg('limit_val')::integer
OFFSET sqlc.arg('offset_val')::integer;

-- name: PollPrintJob :one
SELECT * FROM print_queue
WHERE print_status = 'Pending'
ORDER BY priority_num DESC, created_at ASC
LIMIT 1;

-- name: UpdatePrintJobStatus :one
UPDATE print_queue
SET 
    print_status = COALESCE(sqlc.narg('print_status')::print_status_enum, print_status),
    retry_count = COALESCE(sqlc.narg('retry_count')::integer, retry_count),
    priority_num = COALESCE(sqlc.narg('priority_num')::integer, priority_num),
    printed_at = CASE WHEN sqlc.narg('print_status')::print_status_enum = 'Completed' THEN NOW() ELSE printed_at END
WHERE print_job_id = sqlc.arg('print_job_id')::uuid
RETURNING *;
