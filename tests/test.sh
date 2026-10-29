#!/bin/bash
#
# FrontierSWE/Harbor verifier for sqlite-from-scratch.
# Builds the agent's submission, runs SQL checks against ./my-sqlite,
# awards partial credit, and ALWAYS writes /logs/verifier/reward.txt.
#
set -uo pipefail

REWARD_FILE=/logs/verifier/reward.txt
SCORE=0.0

# Always write the reward file, even on early failure.
write_reward() {
    mkdir -p /logs/verifier
    printf '%s\n' "$SCORE" > "$REWARD_FILE"
}
trap write_reward EXIT

cd /workspace || { echo "cannot cd /workspace"; exit 1; }

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
BINARY=./my-sqlite

build() {
    if [ -f Makefile ]; then
        make -j"$(nproc)" >/tmp/build.log 2>&1 || { cat /tmp/build.log; return 1; }
    elif [ -f Cargo.toml ]; then
        cargo build --release >/tmp/build.log 2>&1 || { cat /tmp/build.log; return 1; }
        cp target/release/my-sqlite ./my-sqlite 2>/dev/null || true
    elif [ -f go.mod ]; then
        go build -o my-sqlite . >/tmp/build.log 2>&1 || { cat /tmp/build.log; return 1; }
    elif [ -x "$BINARY" ]; then
        return 0
    else
        echo "No build system (Makefile/Cargo.toml/go.mod) and no executable my-sqlite"
        return 1
    fi
    return 0
}

if ! build; then
    echo "BUILD FAILED"
    exit 1
fi

if [ ! -x "$BINARY" ]; then
    echo "my-sqlite binary not found or not executable"
    exit 1
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
WORK="$(mktemp -d)"

run_sql() {
    # $1 = db file name, $2 = SQL (single statement or multi-line script)
    printf '%s\n.exit\n' "$2" | timeout 20s "$BINARY" "$WORK/$1" 2>/dev/null || true
}

assert_contains() {
    # $1 = output file, $2 = expected exact row line, $3 = label
    if grep -qFx -- "$2" "$1"; then
        echo "PASS: $3"
        return 0
    else
        echo "FAIL: $3 (expected to contain: $2)"
        return 1
    fi
}

add_score() {
    SCORE="$(awk -v a="$SCORE" -v b="$1" 'BEGIN{printf "%.2f", a+b}')"
}

# ---------------------------------------------------------------------------
# Test 1: CREATE TABLE + INSERT + SELECT *  (0.25)
# ---------------------------------------------------------------------------
rm -f "$WORK/t1.db"
run_sql t1.db "CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT);
INSERT INTO t VALUES (1, 'alice');
INSERT INTO t VALUES (2, 'bob');
SELECT * FROM t;" > "$WORK/out1.txt"

if assert_contains "$WORK/out1.txt" "1|alice" "test1: row 1" \
  && assert_contains "$WORK/out1.txt" "2|bob" "test1: row 2"; then
    add_score 0.25
fi

# ---------------------------------------------------------------------------
# Test 2: Persistence across process restart  (0.25)
# Reopen the same db file from test 1 in a brand-new process.
# ---------------------------------------------------------------------------
run_sql t1.db "SELECT name FROM t WHERE id = 1;" > "$WORK/out2.txt"
if assert_contains "$WORK/out2.txt" "alice" "test2: persistence"; then
    add_score 0.25
fi

# ---------------------------------------------------------------------------
# Test 3: Simple WHERE (=) + column select  (0.25)
# ---------------------------------------------------------------------------
run_sql t1.db "SELECT name FROM t WHERE id = 2;" > "$WORK/out3.txt"
if assert_contains "$WORK/out3.txt" "bob" "test3: WHERE id=2"; then
    add_score 0.25
fi

# ---------------------------------------------------------------------------
# Test 4: Multiple tables in one database file  (0.25)
# ---------------------------------------------------------------------------
rm -f "$WORK/t4.db"
run_sql t4.db "CREATE TABLE a (id INTEGER PRIMARY KEY);
CREATE TABLE b (id INTEGER PRIMARY KEY, val TEXT);
INSERT INTO a VALUES (10);
INSERT INTO b VALUES (10, 'hello');
SELECT * FROM a;
SELECT * FROM b;" > "$WORK/out4.txt"

if assert_contains "$WORK/out4.txt" "10" "test4: table a" \
   && assert_contains "$WORK/out4.txt" "10|hello" "test4: table b"; then
    add_score 0.25
fi

# ---------------------------------------------------------------------------
# Final
# ---------------------------------------------------------------------------
rm -rf "$WORK"
echo "Final score: $SCORE"
echo "Mean: $SCORE"
