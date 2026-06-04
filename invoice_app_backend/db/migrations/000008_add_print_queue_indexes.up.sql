BEGIN;

-- Index for active print jobs polling
CREATE INDEX IF NOT EXISTS idx_print_queue_active_poll 
ON print_queue (priority_num DESC, created_at ASC) 
WHERE print_status IN ('Pending', 'Printing');

-- Index for printing history jobs listing
CREATE INDEX IF NOT EXISTS idx_print_queue_history 
ON print_queue (created_at DESC) 
WHERE print_status IN ('Completed', 'Failed', 'Cancelled');

COMMIT;
