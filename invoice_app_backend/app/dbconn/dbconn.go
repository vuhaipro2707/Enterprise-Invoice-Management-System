package dbconn

import "database/sql"

// DB is the global database connection pool used to start transactions
var DB *sql.DB
