-- Add started_printing_at column to print_queue
ALTER TABLE print_queue ADD COLUMN started_printing_at TIMESTAMPTZ;
