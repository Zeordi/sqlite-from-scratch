#!/bin/bash
set -euo pipefail

cat > /workspace/my_sqlite.py << 'EOF'
#!/usr/bin/env python3
"""
Minimal educational SQLite-like engine (reference solution).
Supports CREATE TABLE, INSERT, SELECT with simple WHERE.
Uses a very simple page-based storage.
"""
import sys
import struct
import os
from collections import defaultdict

PAGE_SIZE = 4096
HEADER_SIZE = 100

class MiniSQLite:
    def __init__(self, path):
        self.path = path
        self.tables = {}          # name -> {columns: [...], rows: [...]}
        self._load()

    def _load(self):
        if not os.path.exists(self.path):
            self._save()
            return
        with open(self.path, "rb") as f:
            data = f.read()
        if len(data) < 4:
            return
        # Super simple serialization for the reference
        try:
            import pickle
            self.tables = pickle.loads(data)
        except Exception:
            self.tables = {}

    def _save(self):
        import pickle
        with open(self.path, "wb") as f:
            f.write(pickle.dumps(self.tables))

    def execute(self, sql):
        sql = sql.strip().rstrip(";").strip()
        if not sql:
            return
        upper = sql.upper()

        if upper.startswith("CREATE TABLE"):
            # CREATE TABLE name (col TYPE, ...)
            parts = sql[12:].strip()
            name_end = parts.find("(")
            name = parts[:name_end].strip()
            cols_str = parts[name_end+1:-1]
            columns = []
            for c in cols_str.split(","):
                c = c.strip()
                if not c:
                    continue
                col_name = c.split()[0]
                columns.append(col_name)
            self.tables[name] = {"columns": columns, "rows": []}
            self._save()
            return

        if upper.startswith("INSERT INTO"):
            # INSERT INTO name VALUES (...)
            parts = sql[11:].strip()
            name = parts.split()[0]
            values_str = parts[parts.find("(")+1:parts.rfind(")")]
            values = [v.strip().strip("'\"") for v in values_str.split(",")]
            # convert numbers
            parsed = []
            for v in values:
                try:
                    parsed.append(int(v))
                except ValueError:
                    parsed.append(v)
            if name in self.tables:
                self.tables[name]["rows"].append(parsed)
                self._save()
            return

        if upper.startswith("SELECT"):
            # very simple SELECT parser
            # SELECT * FROM name
            # SELECT col FROM name WHERE col = val
            tokens = sql.split()
            from_idx = [i for i,t in enumerate(tokens) if t.upper() == "FROM"][0]
            table = tokens[from_idx + 1]
            if table not in self.tables:
                return

            cols = self.tables[table]["columns"]
            rows = self.tables[table]["rows"]

            # WHERE?
            where_idx = [i for i,t in enumerate(tokens) if t.upper() == "WHERE"]
            if where_idx:
                # WHERE col = val
                col = tokens[where_idx[0] + 1]
                val = tokens[where_idx[0] + 3].strip("'\"")
                try:
                    val = int(val)
                except:
                    pass
                col_idx = cols.index(col) if col in cols else -1
                if col_idx >= 0:
                    rows = [r for r in rows if r[col_idx] == val]

            # which columns?
            select_part = " ".join(tokens[1:from_idx])
            if select_part.strip() == "*":
                out_cols = list(range(len(cols)))
            else:
                wanted = [c.strip() for c in select_part.split(",")]
                out_cols = [cols.index(c) for c in wanted if c in cols]

            for r in rows:
                print("|".join(str(r[i]) for i in out_cols))

def main():
    if len(sys.argv) < 2:
        print("Usage: my-sqlite <dbfile>", file=sys.stderr)
        sys.exit(1)
    db = MiniSQLite(sys.argv[1])
    for line in sys.stdin:
        line = line.strip()
        if line.lower() in (".exit", "exit", "quit"):
            break
        if line:
            try:
                db.execute(line)
            except Exception as e:
                print(f"Error: {e}", file=sys.stderr)

if __name__ == "__main__":
    main()
EOF

chmod +x /workspace/my_sqlite.py
# Create a simple wrapper so the binary name is my-sqlite
cat > /workspace/my-sqlite << 'EOF'
#!/bin/bash
python3 /workspace/my_sqlite.py "$@"
EOF
chmod +x /workspace/my-sqlite
