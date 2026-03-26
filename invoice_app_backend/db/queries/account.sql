-- name: GetAccountByUsername :one
SELECT * FROM accounts
WHERE username = $1 LIMIT 1;

-- name: CreateAccount :one
INSERT INTO accounts (
  username, name, password
) VALUES (
  $1, $2, $3
)
RETURNING *;