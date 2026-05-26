-- name: GetGlobalSettings :one
SELECT id, global_settings_file
FROM global_settings
WHERE is_singleton = TRUE
LIMIT 1;

-- name: UpdateGlobalSettings :one
UPDATE global_settings
SET global_settings_file = $1
WHERE is_singleton = TRUE
RETURNING id, global_settings_file;

-- name: InsertGlobalSettings :one
INSERT INTO global_settings (global_settings_file)
VALUES ($1)
ON CONFLICT (is_singleton) DO NOTHING
RETURNING id, global_settings_file;
