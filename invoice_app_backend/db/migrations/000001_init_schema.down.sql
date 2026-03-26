-- Chạy ngược từ dưới lên so với file up.sql
DROP TABLE IF EXISTS print_queue;
DROP TABLE IF EXISTS line_items;
DROP TABLE IF EXISTS invoices;
DROP TABLE IF EXISTS items;
DROP TABLE IF EXISTS units;
DROP TABLE IF EXISTS types;
DROP TABLE IF EXISTS buyers;
DROP TABLE IF EXISTS accounts;

-- Xóa ENUM type cuối cùng
DROP TYPE IF EXISTS print_status_enum;