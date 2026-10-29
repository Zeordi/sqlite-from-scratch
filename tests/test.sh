#!/bin/bash
set -euo pipefail

SCORE=0.0
MAX=1.0

cd /workspace

# --- Build ---
if [ -f Makefile ]; then
  make -j$(nproc) || exit 1
elif [ -f Cargo.toml ]; then
  cargo build --release || exit 1
  cp target/release/my-sqlite ./my-sqlite || true
elif [ -f go.mod ]; then
  go build -o my-sqlite . || exit 1
else
  echo "No build system found"
  exit 1
fi

BINARY=./my-sqlite
if [ ! -x "$BINARY" ]; then
  echo "Binary not found or not executable"
  exit 1
fi

# Helper
run_sql() {
  local db=$1
  local sql=$2
  echo -e "$sql\n.exit" | timeout 10s $BINARY "$db" 2>/dev/null || true
}

# Test 1: CREATE + INSERT + SELECT *  (0.4)
rm -f test1.db
run_sql test1.db "CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT);
INSERT INTO t VALUES (1, 'alice');
INSERT INTO t VALUES (2, 'bob');
SELECT * FROM t;" > out1.txt

if grep -q "1|alice" out1.txt && grep -q "2|bob" out1.txt; then
  SCORE=$(echo "$SCORE + 0.4" | bc)
  echo "PASS: basic CREATE/INSERT/SELECT"
else
  echo "FAIL: basic CREATE/INSERT/SELECT"
fi

# Test 2: Persistence (0.2)
run_sql test1.db "SELECT name FROM t WHERE id = 1;" > out2.txt
if grep -q "alice" out2.txt; then
  SCORE=$(echo "$SCORE + 0.2" | bc)
  echo "PASS: persistence"
else
  echo "FAIL: persistence"
fi

# Test 3: WHERE clause (0.2)
run_sql test1.db "SELECT name FROM t WHERE id = 2;" > out3.txt
if grep -q "bob" out3.txt; then
  SCORE=$(echo "$SCORE + 0.2" | bc)
  echo "PASS: WHERE"
else
  echo "FAIL: WHERE"
fi

# Test 4: Multiple tables (0.2)
rm -f test4.db
run_sql test4.db "CREATE TABLE a (id INTEGER PRIMARY KEY);
CREATE TABLE b (id INTEGER PRIMARY KEY, val TEXT);
INSERT INTO a VALUES (10);
INSERT INTO b VALUES (10, 'hello');
SELECT * FROM a;
SELECT * FROM b;" > out4.txt

if grep -q "10" out4.txt && grep -q "hello" out4.txt; then
  SCORE=$(echo "$SCORE + 0.2" | bc)
  echo "PASS: multiple tables"
else
  echo "FAIL: multiple tables"
fi

# Final score
echo "Final score: $SCORE"
mkdir -p /logs/verifier
echo "$SCORE" > /logs/verifier/reward.txt

# Harbor expects Mean printed
echo "Mean: $SCORE"
