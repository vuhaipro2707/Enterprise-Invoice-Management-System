-- Trigram index for fuzzy search support (optional, requires pg_trgm extension)
-- This helps find items even with slight spelling differences
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX IF NOT EXISTS idx_items_formal_name_trgm ON items USING GIN(item_formal_name gin_trgm_ops);


CREATE EXTENSION IF NOT EXISTS unaccent;

CREATE OR REPLACE FUNCTION my_unaccent(text)
  RETURNS text AS
$BODY$
  SELECT unaccent('unaccent', $1);
$BODY$
  LANGUAGE sql IMMUTABLE
  COST 1;

CREATE INDEX IF NOT EXISTS idx_items_short_names_trgm_txt
ON items
USING gin ((my_unaccent(item_short_names::text)) gin_trgm_ops);

