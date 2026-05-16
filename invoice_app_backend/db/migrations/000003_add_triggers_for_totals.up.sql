-- BEGIN Transaction
BEGIN;

-- 1. Trigger for line_items: sub_total = quantity * unit_price_custom (or unit_price_default if custom is null)
CREATE OR REPLACE FUNCTION calculate_line_item_subtotal()
RETURNS TRIGGER AS $$
DECLARE
    price BIGINT;
BEGIN
    -- If unit_price_custom is provided, use it. Otherwise, fetch unit_price_default from units table.
    IF NEW.unit_price_custom IS NOT NULL THEN
        price := NEW.unit_price_custom;
    ELSE
        SELECT unit_price_default INTO price FROM units WHERE unit_id = NEW.unit_id;
    END IF;

    -- Calculate sub_total
    NEW.sub_total := NEW.quantity * price;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_calculate_line_item_subtotal ON line_items;
CREATE TRIGGER trigger_calculate_line_item_subtotal
BEFORE INSERT OR UPDATE OF quantity, unit_price_custom, unit_id ON line_items
FOR EACH ROW EXECUTE FUNCTION calculate_line_item_subtotal();


-- 2. Trigger for invoices: total_amount = sum of sub_total of all its line_items
CREATE OR REPLACE FUNCTION update_invoice_total_amount()
RETURNS TRIGGER AS $$
DECLARE
    target_invoice_id UUID;
BEGIN
    -- Determine which invoice needs updating
    IF (TG_OP = 'DELETE') THEN
        target_invoice_id := OLD.invoice_id;
    ELSE
        target_invoice_id := NEW.invoice_id;
    END IF;

    -- Update total_amount in invoices table
    UPDATE invoices
    SET total_amount = COALESCE((SELECT SUM(sub_total) FROM line_items WHERE invoice_id = target_invoice_id), 0),
        updated_at = NOW()
    WHERE invoice_id = target_invoice_id;

    RETURN NULL; -- result is ignored since this is an AFTER trigger
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_invoice_total_amount ON line_items;
CREATE TRIGGER trigger_update_invoice_total_amount
AFTER INSERT OR UPDATE OF sub_total OR DELETE ON line_items
FOR EACH ROW EXECUTE FUNCTION update_invoice_total_amount();

COMMIT;
