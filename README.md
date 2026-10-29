# sqlite-from-scratch

FrontierSWE / Harbor task: implement a minimal SQLite-compatible database engine from scratch.

## Task summary

The agent must build `my-sqlite`, a command-line database engine written from scratch (no database libraries) using **page-based storage with 4 KB pages**. Required SQL subset:

- `CREATE TABLE table (col TYPE, ...)` — `INTEGER`/`INT` and `TEXT` columns
- `INSERT INTO table VALUES (...);`
- `SELECT * FROM table;`
- `SELECT col1, col2 FROM table;`
- `SELECT col FROM table WHERE col = value;` (equality on INTEGER or TEXT)
- Multiple tables in one database file
- Persistence across process restarts

The program reads SQL from stdin, prints results as `|`-separated rows, and exits on `.exit` or EOF.

Binary name: `my-sqlite`.  
Target effort for a strong engineer: **8–14 hours**.

## Repository layout

```
sqlite-from-scratch/
├── instruction.md       # Full agent-facing specification
├── task.toml            # Harbor task metadata
├── README.md            # This file
├── .gitignore
├── environment/
│   ├── Dockerfile       # Build image (gcc/make by default)
│   └── workspace/
│       └── README.md    # Starter hint dropped into the agent workspace
├── tests/
│   └── test.sh          # Verifier: builds + scores, writes /logs/verifier/reward.txt
├── solution/
│   └── solve.sh         # Oracle: reference C implementation that scores exactly 1.0
```

## How the verifier works

`tests/test.sh` builds the agent's project (detects `Makefile`, `Cargo.toml`, or `go.mod`, or reuses an existing `./my-sqlite`), then runs four scored checks against `./my-sqlite`:

| Check | Weight |
|-------|--------|
| CREATE + INSERT + `SELECT *` | 0.25 |
| Persistence across restart (reopen `.db`) | 0.25 |
| Simple `WHERE col = value` | 0.25 |
| Multiple tables in one file | 0.25 |

The final score (0.0–1.0) is always written to `/logs/verifier/reward.txt`, and `Mean: <score>` is printed for Harbor.

The reference oracle in `solution/solve.sh` is a self-contained C implementation that scores exactly **1.0**.

## Running the checker locally

### Prerequisites

A C toolchain (`gcc`/`make`) is the default. The Dockerfile also provides Rust, Go, and Python.

### As the oracle (expected score 1.0)

```bash
cd sqlite-from-scratch
bash solution/solve.sh          # builds the reference my-sqlite in /workspace
bash tests/test.sh              # should report Final score: 1.00
cat /logs/verifier/reward.txt   # 1.0
```

### As an agent

Place your source and build file in the workspace, then:

```bash
cd /workspace          # your workspace containing my-sqlite source + Makefile
make
bash /path/to/tests/test.sh
cat /logs/verifier/reward.txt
```

## Expected scores

| Submission   | Expected score |
|--------------|----------------|
| Oracle (`solution/solve.sh`) | 1.00 |
| Empty / no-op agent          | 0.00 |

## Using this task (Harbor / RustLabs)

- Kind of task: **implementation / systems engineering**
- Agent goal: build a working `my-sqlite` binary satisfying `instruction.md`
- Verifier: `tests/test.sh` → writes `/logs/verifier/reward.txt`
- Oracle: `solution/solve.sh` → scores exactly 1.0

## Isolation

The agent workspace contains only `environment/workspace/README.md` (a hint). The `solution/` directory and the real scoring logic in `tests/test.sh` are not visible to the agent at runtime.
