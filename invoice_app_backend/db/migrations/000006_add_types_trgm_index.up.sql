CREATE INDEX IF NOT EXISTS idx_types_name_unaccent_trgm 
ON types 
USING gin ((my_unaccent(type_name)) gin_trgm_ops);
