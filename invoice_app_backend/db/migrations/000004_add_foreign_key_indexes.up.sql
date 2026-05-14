-- Add indexes for Foreign Keys to improve JOIN performance and Cascading deletes
BEGIN;

-- 1. Table: items (type_id)
CREATE INDEX IF NOT EXISTS idx_items_type_id ON items(type_id);

-- 2. Table: item_other_names (item_id)
CREATE INDEX IF NOT EXISTS idx_item_other_names_item_id ON item_other_names(item_id);

-- 3. Table: units (item_id)
CREATE INDEX IF NOT EXISTS idx_units_item_id ON units(item_id);

-- 4. Table: invoices (account_id, buyer_id, device_holding_id)
CREATE INDEX IF NOT EXISTS idx_invoices_account_id ON invoices(account_id);
CREATE INDEX IF NOT EXISTS idx_invoices_buyer_id ON invoices(buyer_id);
CREATE INDEX IF NOT EXISTS idx_invoices_device_holding_id ON invoices(device_holding_id);

-- 5. Table: line_items (invoice_id, item_id, unit_id)
CREATE INDEX IF NOT EXISTS idx_line_items_invoice_id ON line_items(invoice_id);
CREATE INDEX IF NOT EXISTS idx_line_items_item_id ON line_items(item_id);
CREATE INDEX IF NOT EXISTS idx_line_items_unit_id ON line_items(unit_id);

-- 6. Table: print_queue (invoice_id)
CREATE INDEX IF NOT EXISTS idx_print_queue_invoice_id ON print_queue(invoice_id);

COMMIT;
