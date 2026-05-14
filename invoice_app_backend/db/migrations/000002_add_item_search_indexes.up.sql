CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;

CREATE OR REPLACE FUNCTION my_unaccent(text)
  RETURNS text AS
$BODY$
  SELECT unaccent('unaccent', $1);
$BODY$
  LANGUAGE sql IMMUTABLE
  COST 1;

-- Index for searching on default name (unaccent + trigram)
CREATE INDEX IF NOT EXISTS idx_items_default_name_unaccent_trgm 
ON items 
USING gin ((my_unaccent(item_default_name)) gin_trgm_ops);

-- Index for searching on other names (unaccent + trigram)
CREATE INDEX IF NOT EXISTS idx_item_other_names_name_string_trgm
ON item_other_names
USING gin ((my_unaccent(name_string)) gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_buyers_name_unaccent_trgm 
ON buyers 
USING gin ((my_unaccent(buyer_name)) gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_buyers_phone ON buyers(phone_number) WHERE deleted_at IS NULL;

