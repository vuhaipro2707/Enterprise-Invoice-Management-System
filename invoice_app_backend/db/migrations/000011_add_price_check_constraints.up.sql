BEGIN;

ALTER TABLE units 
  ADD CONSTRAINT chk_unit_price_default CHECK (unit_price_default >= 0);

ALTER TABLE line_items 
  ADD CONSTRAINT chk_line_item_unit_price_custom CHECK (unit_price_custom >= 0);

ALTER TABLE customer_item_prices 
  ADD CONSTRAINT chk_customer_item_price_custom CHECK (unit_price_custom >= 0);

COMMIT;
