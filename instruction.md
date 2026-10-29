# SQLite from Scratch

## Mission

Implement a **minimal but real SQLite-compatible database engine from scratch**. You are building `my-sqlite`, a command-line database program that stores data in a single portable file using **page-based storage (4 KB pages)** and supports a core subset of SQL. No existing database libraries may be used.

This is a long-horizon, systems-heavy task. Target effort for a strong engineer: **8–14 hours**.

## Required features

Your engine must implement all of the following:

### Storage layer
- A persistent single-file database (`.db`).
- **Page-based storage with 4 KB pages.** Page 0 is a superblock/schema page; table data lives in linked data pages.
- Integer primary keys and TEXT columns.
- The database file must survive process restarts (reopen the same `.db` and read previously written data).

### SQL subset
- `CREATE TABLE table_name (col1 TYPE, col2 TYPE, ...)`
  - Supported types: `INTEGER` / `INT`, `TEXT`. `PRIMARY KEY` may appear on the id column.
- `INSERT INTO table_name VALUES (v1, v2, ...);`
- `SELECT * FROM table_name;`
- `SELECT col1, col2 FROM table_name;`
- `SELECT col FROM table_name WHERE col = value;` (simple equality on INTEGER or TEXT)
- Multiple tables in a single database file.

### Interface
1. The program is invoked as `./my-sqlite <database-file>`.
2. It reads SQL statements from **stdin** (one statement per line, optionally terminated by `;`).
3. It prints query results in a simple tabular format: column values separated by `|`, one row per line.
4. It exits cleanly on `EOF` or `.exit`.

Example interaction:
```
$ ./my-sqlite test.db
sqlite> CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);
sqlite> INSERT INTO users VALUES (1, 'Alice');
sqlite> INSERT INTO users VALUES (2, 'Bob');
sqlite> SELECT * FROM users;
1|Alice
2|Bob
sqlite> SELECT name FROM users WHERE id = 2;
Bob
sqlite> .exit
$
```

### Constraints
- You may **not** use any existing database library (SQLite, LevelDB, RocksDB, Berkeley DB, etc.) or any ORM/query-builder that provides storage.
- You may use only your language's standard library plus basic system calls.
- The solution must be **deterministic**.
- The binary must be named `my-sqlite`.

## How you are scored

The verifier (`tests/test.sh`) builds your project and runs a fixed set of SQL scripts against `my-sqlite`. Each script awards partial credit:

| Check | Weight | What is verified |
|-------|--------|------------------|
| CREATE + INSERT + SELECT * | 0.25 | Table created, rows inserted, all rows printed |
| Persistence across restart | 0.25 | Reopen the same `.db`, rows still present |
| Simple WHERE (=) | 0.25 | `SELECT ... WHERE col = value` filters correctly |
| Multiple tables | 0.25 | Two tables coexist in one file, each queryable |

Final score is the sum, in `[0.0, 1.0]`, written to `/logs/verifier/reward.txt`. The reference (oracle) solution scores exactly **1.0**.

## Suggested approach

1. Pick a language (C, C++, Rust, or Go recommended). Provide a `Makefile`, `Cargo.toml`, or `go.mod` so `make`/`cargo build`/`go build` produces `my-sqlite`.
2. Design the on-disk format: a 4 KB page 0 (magic + schema directory), one schema page per table, and linked data pages holding rows.
3. Implement `CREATE TABLE`, then `INSERT`, then `SELECT *`, then `SELECT` columns, then `WHERE`, then multi-table.
4. Test persistence by closing and reopening the database file.

Time budget for a strong engineer: **8–14 hours**.
