-- BEGIN Transaction
BEGIN;

-- Create handle_unit_changes trigger function
CREATE OR REPLACE FUNCTION handle_unit_changes()
RETURNS TRIGGER AS $$
DECLARE
    base_unit_id UUID;
    base_price BIGINT;
    other_units_count INT;
BEGIN
    -- Check if it's a DELETE or SOFT-DELETE operation
    IF TG_OP = 'DELETE' OR (TG_OP = 'UPDATE' AND NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL) THEN
        -- If it's a base unit, prevent deletion if other active units exist
        IF (TG_OP = 'DELETE' AND OLD.is_base_unit = TRUE) OR (TG_OP = 'UPDATE' AND OLD.is_base_unit = TRUE AND NEW.deleted_at IS NOT NULL) THEN
            SELECT COUNT(*) INTO other_units_count
            FROM units
            WHERE item_id = OLD.item_id
              AND unit_id != OLD.unit_id
              AND deleted_at IS NULL;
              
            IF other_units_count > 0 THEN
                RAISE EXCEPTION 'Cannot delete base unit when other units still exist. Please delete other units first';
            END IF;
        END IF;
        
        IF TG_OP = 'DELETE' THEN
            RETURN OLD;
        ELSE
            RETURN NEW;
        END IF;
    END IF;

    -- Handle INSERT operations
    IF TG_OP = 'INSERT' THEN
        -- 1. Check if the unit is a base unit
        IF NEW.is_base_unit = TRUE THEN
            -- Check if base unit already exists for the item
            SELECT unit_id INTO base_unit_id
            FROM units
            WHERE item_id = NEW.item_id
              AND is_base_unit = TRUE
              AND deleted_at IS NULL;
              
            IF base_unit_id IS NOT NULL THEN
                RAISE EXCEPTION 'Base unit already exists for this item';
            END IF;
            
            -- Base unit ratio must be 1
            NEW.ratio := 1;
        ELSE
            -- Check if base unit exists
            SELECT unit_id, unit_price_default INTO base_unit_id, base_price
            FROM units
            WHERE item_id = NEW.item_id
              AND is_base_unit = TRUE
              AND deleted_at IS NULL;
              
            IF base_unit_id IS NULL THEN
                RAISE EXCEPTION 'A base unit must be created first before adding other units';
            END IF;
            
            -- Automatically calculate the price based on base price and ratio
            NEW.unit_price_default := base_price * NEW.ratio;
        END IF;
        
        RETURN NEW;
    END IF;

    -- Handle UPDATE operations (excluding soft-deletion which is handled above)
    IF TG_OP = 'UPDATE' THEN
        -- If is_base_unit is changed to true, verify no other base unit exists
        IF NEW.is_base_unit = TRUE AND OLD.is_base_unit = FALSE THEN
            SELECT unit_id INTO base_unit_id
            FROM units
            WHERE item_id = NEW.item_id
              AND is_base_unit = TRUE
              AND unit_id != NEW.unit_id
              AND deleted_at IS NULL;
              
            IF base_unit_id IS NOT NULL THEN
                RAISE EXCEPTION 'Base unit already exists for this item';
            END IF;
            NEW.ratio := 1;
        END IF;

        IF NEW.is_base_unit = TRUE THEN
            -- Base unit ratio is locked to 1
            NEW.ratio := 1;
        END IF;

        -- If it's a base unit and the price changed, propagate to all secondary units
        IF NEW.is_base_unit = TRUE AND NEW.unit_price_default != OLD.unit_price_default THEN
            IF pg_trigger_depth() <= 1 THEN
                UPDATE units
                SET unit_price_default = NEW.unit_price_default * ratio,
                    updated_at = NOW()
                WHERE item_id = NEW.item_id
                  AND is_base_unit = FALSE
                  AND deleted_at IS NULL;
            END IF;
        END IF;

        -- If ratio changed (and it's a secondary unit), recalculate price based on base unit's price
        IF NEW.is_base_unit = FALSE AND NEW.ratio != OLD.ratio THEN
            IF pg_trigger_depth() <= 1 THEN
                SELECT unit_price_default INTO base_price
                FROM units
                WHERE item_id = NEW.item_id
                  AND is_base_unit = TRUE
                  AND deleted_at IS NULL;
                  
                NEW.unit_price_default := base_price * NEW.ratio;
            END IF;
        END IF;

        RETURN NEW;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Bind trigger function to units table for validation and propagation
DROP TRIGGER IF EXISTS trigger_handle_unit_changes ON units;
CREATE TRIGGER trigger_handle_unit_changes
BEFORE INSERT OR UPDATE OR DELETE ON units
FOR EACH ROW EXECUTE FUNCTION handle_unit_changes();

COMMIT;
