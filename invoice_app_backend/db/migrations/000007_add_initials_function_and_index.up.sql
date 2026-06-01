CREATE OR REPLACE FUNCTION get_initials(input_text text)
  RETURNS text AS
$BODY$
DECLARE
  word text;
  clean_text text;
  initials text := '';
BEGIN
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

-- Create expression index for fast initials lookups on default names
CREATE INDEX IF NOT EXISTS idx_items_initials 
ON items (get_initials(item_default_name));

-- Create expression index for fast initials lookups on other names
CREATE INDEX IF NOT EXISTS idx_item_other_names_initials 
ON item_other_names (get_initials(name_string));
