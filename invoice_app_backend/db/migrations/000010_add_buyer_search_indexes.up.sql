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
