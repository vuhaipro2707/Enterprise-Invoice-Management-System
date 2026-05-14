-- Use Transaction to ensure all or nothing is executed
BEGIN;

-- 1. Create ENUMs (Check if exists before creating)
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'print_status_enum') THEN
        CREATE TYPE print_status_enum AS ENUM ('Pending', 'Printing', 'Completed', 'Failed');
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'print_type_enum') THEN
        CREATE TYPE print_type_enum AS ENUM ('Original', 'Triplicate');
    END IF;
END $$;

-- 2. Create Accounts table
CREATE TABLE IF NOT EXISTS accounts (
    account_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username VARCHAR(255) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    name VARCHAR(255) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

-- 3. Create Devices table
CREATE TABLE IF NOT EXISTS devices (
    device_holding_id VARCHAR(255) PRIMARY KEY,
    device_name VARCHAR(255)
);

-- 4. Create Buyers table
CREATE TABLE IF NOT EXISTS buyers (
    buyer_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    buyer_code VARCHAR(50) UNIQUE NOT NULL,
    buyer_name VARCHAR(255) NOT NULL,
    address TEXT,
    phone_number VARCHAR(50),
    id_card_number VARCHAR(50),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

-- 5. Create Types table
CREATE TABLE IF NOT EXISTS types (
    type_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type_name VARCHAR(255) UNIQUE NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

-- 6. Create Items table
CREATE TABLE IF NOT EXISTS items (
    item_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    item_default_name VARCHAR(255) NOT NULL,
    type_id UUID REFERENCES types(type_id) ON DELETE SET NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

-- 7. Create ItemOtherNames table
CREATE TABLE IF NOT EXISTS item_other_names (
    item_other_name_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    item_id UUID REFERENCES items(item_id) ON DELETE CASCADE NOT NULL,
    name_string VARCHAR(255) NOT NULL
);

-- 8. Create Units table
CREATE TABLE IF NOT EXISTS units (
    unit_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    unit_name VARCHAR(255) NOT NULL,
    unit_price_default BIGINT NOT NULL,
    item_id UUID REFERENCES items(item_id) ON DELETE SET NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

-- 9. Create Invoices table
CREATE TABLE IF NOT EXISTS invoices (
    invoice_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID REFERENCES accounts(account_id) ON DELETE CASCADE,
    buyer_id UUID REFERENCES buyers(buyer_id) ON DELETE SET NULL,
    invoice_code VARCHAR(50) UNIQUE NOT NULL,
    total_amount BIGINT NOT NULL,
    device_holding_id VARCHAR(255) REFERENCES devices(device_holding_id) ON DELETE SET NULL,
    edit_status BOOLEAN DEFAULT FALSE,
    buyer_name_snapshot VARCHAR(255),
    address_snapshot TEXT,
    phone_number_snapshot VARCHAR(50),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

-- 10. Create LineItems table
CREATE TABLE IF NOT EXISTS line_items (
    line_item_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id UUID REFERENCES invoices(invoice_id) ON DELETE CASCADE,
    item_id UUID REFERENCES items(item_id) ON DELETE SET NULL,
    unit_id UUID REFERENCES units(unit_id) ON DELETE SET NULL,
    quantity INT NOT NULL CHECK (quantity > 0),
    unit_price_custom BIGINT,
    sub_total BIGINT NOT NULL,
    item_name_snapshot VARCHAR(255),
    unit_name_snapshot VARCHAR(255)
);

-- 11. Create PrintQueue table
CREATE TABLE IF NOT EXISTS print_queue (
    print_job_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id UUID REFERENCES invoices(invoice_id) ON DELETE CASCADE,
    print_status print_status_enum DEFAULT 'Pending',
    print_type print_type_enum NOT NULL,
    retry_count INT DEFAULT 0, -- Marks as 'Failed' if retry_count exceeds 3
    priority_num INT DEFAULT 0, -- Higher number means higher priority
    created_at TIMESTAMPTZ DEFAULT NOW(),
    printed_at TIMESTAMPTZ
);

COMMIT;