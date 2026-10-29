# SQLite from Scratch

You must implement a minimal but working SQLite-compatible database engine **from scratch** in the language of your choice (C, C++, Rust, or Go preferred).

## Requirements

Your engine must support the following subset:

### Storage
- Persistent single-file database (`.db` file)
- B-tree based table storage (or equivalent page-based storage)
- At least 4 KB pages
- Support for integer primary keys and TEXT columns

### SQL subset
- `CREATE TABLE table_name (col1 TYPE, col2 TYPE, ...)`
- `INSERT INTO table_name VALUES (...);`
- `SELECT * FROM table_name;`
- `SELECT col1, col2 FROM table_name WHERE col1 = value;`
- Basic `WHERE` with `=` on integer or text columns
- Multiple tables in one database file

### Interface
Your program must be a command-line tool that:
1. Accepts a database file path as first argument
2. Reads SQL statements from stdin (one statement per line or terminated by `;`)
3. Prints query results in a simple tabular format
4. Exits cleanly on `EOF` or `.exit`

Example interaction:
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

## Constraints
- You may **not** use any existing database library (SQLite, LevelDB, RocksDB, etc.)
- You may use only the standard library of your language + basic system calls
- The database file must survive process restarts
- Your solution must be deterministic

## Scoring
The verifier will:
1. Compile / build your project
2. Run a series of SQL scripts against your binary
3. Check correctness of results and persistence
4. Give partial credit for correct CREATE + INSERT + simple SELECT

Time budget for a strong engineer: 8–14 hours.