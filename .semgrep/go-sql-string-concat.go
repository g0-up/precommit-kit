package rules

import (
	"context"
	"database/sql"
	"fmt"
)

func cases(ctx context.Context, db *sql.DB, name string, id int) {
	// ruleid: go-sql-query-string-concat
	db.Query("SELECT * FROM users WHERE name = '" + name + "'")
	// ruleid: go-sql-query-string-concat
	db.QueryContext(ctx, fmt.Sprintf("SELECT * FROM users WHERE id = %d", id))
	// ruleid: go-sql-query-string-concat
	db.ExecContext(ctx, "DELETE FROM users WHERE id = "+fmt.Sprint(id))
	// ok: go-sql-query-string-concat
	db.Query("SELECT * FROM users WHERE name = $1", name)
	// ok: go-sql-query-string-concat
	db.QueryContext(ctx, "SELECT * FROM users "+"WHERE id = $1", id)
}
