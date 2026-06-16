-- Redefine get_initials to be safe when input is NULL
CREATE OR REPLACE FUNCTION get_initials(input_text text)
  RETURNS text AS
$BODY$
DECLARE
  word text;
  clean_text text;
  initials text := '';
BEGIN
  IF input_text IS NULL THEN
    RETURN NULL;
  END IF;
  clean_text := regexp_replace(my_unaccent(input_text), '[^a-zA-Z0-9\s]', ' ', 'g');
  FOREACH word IN ARRAY regexp_split_to_array(clean_text, '\s+') LOOP
    IF length(word) > 0 THEN
      initials := initials || substring(word from 1 for 1);
    END IF;
  END LOOP;
  RETURN lower(initials);
END;
$BODY$
  LANGUAGE plpgsql IMMUTABLE;

-- Create initials expression index on buyer_name
CREATE INDEX IF NOT EXISTS idx_buyers_name_initials 
ON buyers (get_initials(buyer_name));

-- Create initials expression index on address
CREATE INDEX IF NOT EXISTS idx_buyers_address_initials 
ON buyers (get_initials(address));

-- Create GIN trigram index on address
CREATE INDEX IF NOT EXISTS idx_buyers_address_unaccent_trgm 
ON buyers USING gin ((my_unaccent(address)) gin_trgm_ops);

-- B-tree indexes for numeric/code fields
CREATE INDEX IF NOT EXISTS idx_buyers_id_card_number 
ON buyers (id_card_number) 
WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_buyers_tax_id 
ON buyers (tax_id) 
WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_buyers_email 
ON buyers (email) 
WHERE deleted_at IS NULL;
