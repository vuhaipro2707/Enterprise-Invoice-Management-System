-- 1. Tạo ENUM cho trạng thái in ấn
CREATE TYPE print_status_enum AS ENUM ('Pending', 'Printing', 'Completed', 'Failed');

-- 2. Tạo bảng Accounts
CREATE TABLE accounts (
    account_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username VARCHAR(255) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    name VARCHAR(255) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

-- 3. Tạo bảng Buyer
CREATE TABLE buyers (
    buyer_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    buyer_code VARCHAR(50) UNIQUE NOT NULL,
    buyer_name VARCHAR(255) NOT NULL,
    address TEXT, -- Google Map or Custom
    phone_number VARCHAR(50),
    id_card_number VARCHAR(50),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

-- 4. Tạo bảng Type
CREATE TABLE types (
    type_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type_name VARCHAR(255) UNIQUE NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

-- 5. Tạo bảng Units
CREATE TABLE units (
    unit_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    unit_name VARCHAR(255) NOT NULL,  -- Không unique nhưng hiện popup khi tạo mới để tránh trùng lặp
    unit_price_default BIGINT NOT NULL, -- Lưu bằng số nguyên (Int) như sơ đồ
    item_id UUID REFERENCES items(item_id) ON DELETE SET NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

-- 6. Tạo bảng Items
CREATE TABLE items (
    item_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    item_formal_name VARCHAR(255) NOT NULL, -- Sẽ được chọn từ các short name để hiển thị trên default
    item_short_names JSONB, -- Sử dụng JSONB của Postgres để truy vấn nhanh hơn JSON thường
    type_id UUID REFERENCES types(type_id) ON DELETE SET NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

-- 7. Tạo bảng Invoice
CREATE TABLE invoices (
    invoice_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID REFERENCES accounts(account_id) ON DELETE CASCADE,
    buyer_id UUID REFERENCES buyers(buyer_id) ON DELETE SET NULL,
    invoice_code VARCHAR(50) UNIQUE NOT NULL, -- Generate theo format: INV-YYYYMMDD-XXXX(từ 0001, 0002,...)
    total_amount BIGINT NOT NULL,
    device_holding_id VARCHAR(255),
    edit_status BOOLEAN DEFAULT FALSE,
    -- Snapshots tại thời điểm mua để giữ lịch sử nếu Buyer thay đổi thông tin sau này
    buyer_name_snapshot VARCHAR(255),
    address_snapshot TEXT,
    phone_number_snapshot VARCHAR(50),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

-- 8. Tạo bảng LineItems
CREATE TABLE line_items (
    line_item_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id UUID REFERENCES invoices(invoice_id) ON DELETE CASCADE,
    item_id UUID REFERENCES items(item_id) ON DELETE SET NULL,
    unit_id UUID REFERENCES units(unit_id) ON DELETE SET NULL,
    quantity INT NOT NULL CHECK (quantity > 0),
    unit_price_custom BIGINT, -- (int) như sơ đồ
    sub_total BIGINT NOT NULL,
    -- Snapshots để giữ nguyên tên item/unit lỡ sau này admin đổi tên
    item_name_snapshot VARCHAR(255),
    unit_name_snapshot VARCHAR(255)
);

-- 9. Tạo bảng PrintQueue
CREATE TABLE print_queue (
    print_job_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id UUID REFERENCES invoices(invoice_id) ON DELETE CASCADE,
    print_status print_status_enum DEFAULT 'Pending',
    retry_count INT DEFAULT 0,
    priority_num INT DEFAULT 0, -- Có thể dùng để ưu tiên in các hóa đơn quan trọng trước càng cao càng ưu tiên
    created_at TIMESTAMPTZ DEFAULT NOW(),
    printed_at TIMESTAMPTZ
);