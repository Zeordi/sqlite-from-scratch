#!/bin/bash
#
# Oracle reference solution for sqlite-from-scratch.
# Writes a deterministic, page-based C implementation of my-sqlite into
# /workspace and builds it. Scoring against tests/test.sh must yield exactly 1.0.
#
set -euo pipefail

cd /workspace

# ---------------------------------------------------------------------------
# Reference implementation: my-sqlite.c
# Page-based storage (4 KB pages), CREATE TABLE, INSERT, SELECT *, SELECT
# columns, simple WHERE (=), multiple tables, persistence across restarts.
# No database libraries used; C standard library only.
# ---------------------------------------------------------------------------
cat > /workspace/my-sqlite.c << 'CEOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <ctype.h>

#define PAGE_SIZE 4096
#define MAGIC "MSQLITE1"
#define MAGIC_LEN 8
#define MAX_TABLES 40
#define MAX_COLS 16
#define MAX_NAME 64

static uint8_t *g_buf = NULL;
static long g_cap = 0;
static long g_size = 0;
static const char *g_path = NULL;

static void u32w(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)(v & 0xff);
    p[1] = (uint8_t)((v >> 8) & 0xff);
    p[2] = (uint8_t)((v >> 16) & 0xff);
    p[3] = (uint8_t)((v >> 24) & 0xff);
}
static uint32_t u32r(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static int ensure_cap(long need) {
    long cap = g_cap;
    while (cap < g_size + need) {
        if (cap == 0) cap = PAGE_SIZE;
        else cap *= 2;
    }
    if (cap != g_cap) {
        uint8_t *nb = realloc(g_buf, cap);
        if (!nb) return -1;
        g_buf = nb;
        g_cap = cap;
    }
    return 0;
}

static int file_read_all(void) {
    FILE *f = fopen(g_path, "rb");
    if (!f) return 0;
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (sz <= 0) { fclose(f); return 0; }
    if (ensure_cap(sz) != 0) { fclose(f); return -1; }
    size_t rd = fread(g_buf, 1, sz, f);
    g_size = sz;
    fclose(f);
    return (rd == (size_t)sz) ? 0 : -1;
}

static void grow_to(long bytes) {
    if (ensure_cap(bytes) != 0) return;
    if (bytes > g_size) g_size = bytes;
}

static int file_write_all(void) {
    FILE *f = fopen(g_path, "wb");
    if (!f) return -1;
    size_t wr = fwrite(g_buf, 1, g_size, f);
    fclose(f);
    return (wr == (size_t)g_size) ? 0 : -1;
}

static int table_index(const char *name) {
    uint32_t nt = u32r(g_buf + 12);
    for (uint32_t i = 0; i < nt; i++) {
        uint8_t *e = g_buf + 16 + i * 96;
        if (strcmp((char *)e, name) == 0) return (int)i;
    }
    return -1;
}

static int parse_cols(const char *cols_str, char names[MAX_COLS][MAX_NAME], uint32_t types[MAX_COLS]) {
    int n = 0;
    char tmp[1024];
    strncpy(tmp, cols_str, sizeof(tmp) - 1);
    tmp[sizeof(tmp) - 1] = 0;
    char *tok = strtok(tmp, ",");
    while (tok && n < MAX_COLS) {
        while (*tok == ' ') tok++;
        char *end = tok + strlen(tok) - 1;
        while (end > tok && *end == ' ') { *end = 0; end--; }
        char *colname = tok;
        char *typestr = strchr(tok, ' ');
        if (!typestr) return -1;
        *typestr = 0;
        typestr++;
        while (*typestr == ' ') typestr++;
        strncpy(names[n], colname, MAX_NAME - 1);
        names[n][MAX_NAME - 1] = 0;
        char type_tok[32];
        int tk = 0;
        while (*typestr && *typestr != ' ' && tk < 31) {
            type_tok[tk++] = (char)toupper((unsigned char)*typestr);
            typestr++;
        }
        type_tok[tk] = 0;
        if (strcmp(type_tok, "INTEGER") == 0 || strcmp(type_tok, "INT") == 0) types[n] = 0;
        else if (strcmp(type_tok, "TEXT") == 0) types[n] = 1;
        else return -1;
        n++;
        tok = strtok(NULL, ",");
    }
    return n;
}

static void write_schema_page(uint32_t pageno, int num_cols, char names[MAX_COLS][MAX_NAME], uint32_t types[MAX_COLS]) {
    uint8_t *p = g_buf + pageno * PAGE_SIZE;
    memset(p, 0, PAGE_SIZE);
    u32w(p, (uint32_t)num_cols);
    for (int i = 0; i < num_cols; i++) {
        uint8_t *c = p + 4 + (uint32_t)i * 40;
        strncpy((char *)c, names[i], MAX_NAME - 1);
        u32w(c + 32, types[i]);
    }
}

static int create_table(const char *name, int num_cols, char names[MAX_COLS][MAX_NAME], uint32_t types[MAX_COLS]) {
    if (table_index(name) >= 0) return 0;
    uint32_t nt = u32r(g_buf + 12);
    if (nt >= MAX_TABLES) return -1;
    uint32_t schema_page = u32r(g_buf + 8);
    u32w(g_buf + 8, schema_page + 1);
    uint32_t data_page = schema_page + 1;
    u32w(g_buf + 8, data_page + 1);
    grow_to((long)(data_page + 1) * PAGE_SIZE);
    uint8_t *e = g_buf + 16 + (uint32_t)nt * 96;
    memset(e, 0, 96);
    strncpy((char *)e, name, 31);
    u32w(e + 32, schema_page);
    u32w(e + 36, data_page);
    u32w(e + 40, (uint32_t)num_cols);
    u32w(e + 44, 0);
    u32w(g_buf + 12, nt + 1);
    write_schema_page(schema_page, num_cols, names, types);
    uint8_t *dp = g_buf + data_page * PAGE_SIZE;
    memset(dp, 0, PAGE_SIZE);
    u32w(dp, 0);
    u32w(dp + 4, 0);
    u32w(dp + 8, 12);
    return 0;
}

static int table_schema(int ti, int *num_cols, char names[MAX_COLS][MAX_NAME], uint32_t types[MAX_COLS]) {
    uint8_t *e = g_buf + 16 + (uint32_t)ti * 96;
    uint32_t sp = u32r(e + 32);
    uint8_t *p = g_buf + sp * PAGE_SIZE;
    *num_cols = (int)u32r(p);
    for (int i = 0; i < *num_cols; i++) {
        uint8_t *c = p + 4 + (uint32_t)i * 40;
        strncpy(names[i], (char *)c, MAX_NAME - 1);
        names[i][MAX_NAME - 1] = 0;
        types[i] = u32r(c + 32);
    }
    return 0;
}

static int data_first_page(int ti) {
    uint8_t *e = g_buf + 16 + (uint32_t)ti * 96;
    return (int)u32r(e + 36);
}
static int num_rows_get(int ti) {
    uint8_t *e = g_buf + 16 + (uint32_t)ti * 96;
    return (int)u32r(e + 44);
}
static void set_num_rows(int ti, int n) {
    uint8_t *e = g_buf + 16 + (uint32_t)ti * 96;
    u32w(e + 44, (uint32_t)n);
}

static int col_index(int ti, const char *col) {
    int nc;
    char names[MAX_COLS][MAX_NAME];
    uint32_t types[MAX_COLS];
    table_schema(ti, &nc, names, types);
    for (int i = 0; i < nc; i++)
        if (strcmp(names[i], col) == 0) return i;
    return -1;
}

static int row_size(int num_cols, uint32_t types[MAX_COLS], int64_t *values, char **texts) {
    (void)values;
    int sz = 4;
    for (int i = 0; i < num_cols; i++) {
        if (types[i] == 0) sz += 4;
        else sz += 2 + (int)strlen(texts[i]);
    }
    return sz;
}

static int insert_row(int ti, int num_cols, char names[MAX_COLS][MAX_NAME], uint32_t types[MAX_COLS],
                      int64_t *values, char **texts) {
    (void)names;
    int first = data_first_page(ti);
    int last = first;
    int cur = first;
    while (cur != 0) {
        uint8_t *p = g_buf + (uint32_t)cur * PAGE_SIZE;
        uint32_t nxt = u32r(p);
        last = cur;
        if (nxt == 0) break;
        cur = (int)nxt;
    }
    uint8_t *p = g_buf + (uint32_t)last * PAGE_SIZE;
    int nrows = (int)u32r(p + 4);
    int used = (int)u32r(p + 8);
    int rsz = row_size(num_cols, types, values, texts);
    if (used + rsz + 2 > PAGE_SIZE - 16) {
        uint32_t np = u32r(g_buf + 8);
        u32w(g_buf + 8, np + 1);
        grow_to((long)(np + 1) * PAGE_SIZE);
        uint8_t *oldp = g_buf + (uint32_t)last * PAGE_SIZE;
        uint8_t *np_ = g_buf + (uint32_t)np * PAGE_SIZE;
        memset(np_, 0, PAGE_SIZE);
        u32w(np_, 0);
        u32w(np_ + 4, 0);
        u32w(np_ + 8, 12);
        u32w(oldp, np);
        p = np_;
        used = 12;
        nrows = 0;
    }
    uint8_t *w = p + used;
    u32w(w, (uint32_t)(num_rows_get(ti) + 1));
    w += 4;
    for (int i = 0; i < num_cols; i++) {
        if (types[i] == 0) { u32w(w, (uint32_t)values[i]); w += 4; }
        else {
            uint16_t len = (uint16_t)strlen(texts[i]);
            w[0] = (uint8_t)(len & 0xff);
            w[1] = (uint8_t)((len >> 8) & 0xff);
            w += 2;
            memcpy(w, texts[i], len);
            w += len;
        }
    }
    u32w(p + 8, used + rsz);
    u32w(p + 4, nrows + 1);
    set_num_rows(ti, num_rows_get(ti) + 1);
    return 0;
}

static void print_value(uint8_t **r, uint32_t type) {
    if (type == 0) {
        uint32_t v = u32r(*r);
        *r += 4;
        printf("%u", v);
    } else {
        uint16_t len = (uint16_t)((*r)[0] | ((uint16_t)(*r)[1] << 8));
        *r += 2;
        fwrite(*r, 1, len, stdout);
        *r += len;
    }
}

static void advance_col(uint8_t **r, uint32_t type) {
    if (type == 0) *r += 4;
    else {
        uint16_t l = (*r)[0] | ((uint16_t)(*r)[1] << 8);
        *r += 2 + l;
    }
}

static void scan_table(int ti, int num_cols, char names[MAX_COLS][MAX_NAME], uint32_t types[MAX_COLS],
                       int want_all, int *out_cols, int out_n,
                       const char *where_col, int64_t where_int, const char *where_text) {
    (void)names;
    int wc = where_col ? col_index(ti, where_col) : -1;
    int cur = data_first_page(ti);
    while (cur != 0) {
        uint8_t *p = g_buf + (uint32_t)cur * PAGE_SIZE;
        uint32_t nxt = u32r(p);
        int nrows = (int)u32r(p + 4);
        int used = (int)u32r(p + 8);
        int off = 12;
        int counted = 0;
        while (counted < nrows && off + 4 <= used) {
            uint8_t *row = p + off;
            int match = 1;
            if (wc >= 0) {
                uint8_t *wr = row + 4;
                for (int i = 0; i < num_cols; i++) {
                    if (i == wc) break;
                    advance_col(&wr, types[i]);
                }
                if (types[wc] == 0) {
                    int64_t v = (int64_t)(int32_t)u32r(wr);
                    match = (v == where_int);
                } else {
                    uint16_t l = wr[0] | ((uint16_t)wr[1] << 8);
                    wr += 2;
                    match = (l == (uint16_t)strlen(where_text) && memcmp(wr, where_text, l) == 0);
                }
            }
            if (match) {
                uint8_t *rr = row + 4;
                int firstcol = 1;
                if (want_all) {
                    for (int i = 0; i < num_cols; i++) {
                        if (!firstcol) putchar('|');
                        firstcol = 0;
                        print_value(&rr, types[i]);
                    }
                } else {
                    for (int k = 0; k < out_n; k++) {
                        int ci = out_cols[k];
                        uint8_t *tr = row + 4;
                        for (int i = 0; i < num_cols; i++) {
                            if (i == ci) break;
                            advance_col(&tr, types[i]);
                        }
                        if (!firstcol) putchar('|');
                        firstcol = 0;
                        print_value(&tr, types[ci]);
                    }
                }
                putchar('\n');
            }
            off += 4;
            for (int i = 0; i < num_cols; i++) {
                if (types[i] == 0) off += 4;
                else {
                    off += 2;
                    off += (uint16_t)(p[off - 2] | (p[off - 1] << 8));
                }
            }
            counted++;
        }
        cur = (int)nxt;
    }
}

static char *trim(char *s) {
    while (*s == ' ') s++;
    char *e = s + strlen(s) - 1;
    while (e > s && *e == ' ') { *e = 0; e--; }
    return s;
}

static int exec_sql(char *sql) {
    size_t len = strlen(sql);
    while (len > 0 && (sql[len - 1] == ';' || sql[len - 1] == ' ' || sql[len - 1] == '\t'))
        sql[--len] = 0;
    len = strlen(sql);
    char *s = sql;
    while (*s == ' ') s++;
    if (len == 0 || *s == 0) return 0;
    char upper[4096];
    strncpy(upper, s, sizeof(upper) - 1);
    upper[sizeof(upper) - 1] = 0;
    for (char *p = upper; *p; p++) *p = (char)toupper((unsigned char)*p);

    if (strncmp(upper, "CREATE TABLE", 12) == 0) {
        char *rest = s + 12;
        while (*rest == ' ') rest++;
        char *paren = strchr(rest, '(');
        if (!paren) return -1;
        *paren = 0;
        char *tname = trim(rest);
        char *cols_str = paren + 1;
        char *endp = strrchr(cols_str, ')');
        if (endp) *endp = 0;
        char names[MAX_COLS][MAX_NAME];
        uint32_t types[MAX_COLS];
        int nc = parse_cols(cols_str, names, types);
        if (nc <= 0) return -1;
        return create_table(tname, nc, names, types);
    }
    if (strncmp(upper, "INSERT INTO", 11) == 0) {
        char *rest = s + 11;
        while (*rest == ' ') rest++;
        char *sp = strchr(rest, ' ');
        if (!sp) return -1;
        *sp = 0;
        char *tname = trim(rest);
        char *vals = strchr(sp + 1, '(');
        if (!vals) return -1;
        vals++;
        char *endv = strrchr(vals, ')');
        if (endv) *endv = 0;
        int ti = table_index(tname);
        if (ti < 0) return -1;
        int nc;
        char names[MAX_COLS][MAX_NAME];
        uint32_t types[MAX_COLS];
        table_schema(ti, &nc, names, types);
        char tmp[4096];
        strncpy(tmp, vals, sizeof(tmp) - 1);
        tmp[sizeof(tmp) - 1] = 0;
        int64_t values[MAX_COLS];
        char *texts[MAX_COLS];
        char *ct = strtok(tmp, ",");
        int i = 0;
        while (ct && i < nc) {
            char *v = trim(ct);
            if (*v == '\'') { v++; char *e = strrchr(v, '\''); if (e) *e = 0; texts[i] = v; values[i] = 0; }
            else if (*v == '"') { v++; char *e = strrchr(v, '"'); if (e) *e = 0; texts[i] = v; values[i] = 0; }
            else { values[i] = atoll(v); texts[i] = ""; }
            i++;
            ct = strtok(NULL, ",");
        }
        if (i != nc) return -1;
        return insert_row(ti, nc, names, types, values, texts);
    }
    if (strncmp(upper, "SELECT", 6) == 0) {
        char *from = strcasestr(s, " FROM ");
        if (!from) return -1;
        char *select_part = s + 6;
        while (*select_part == ' ') select_part++;
        *from = 0;
        while (select_part[0] && select_part[strlen(select_part) - 1] == ' ')
            select_part[strlen(select_part) - 1] = 0;
        int want_all = (strcmp(select_part, "*") == 0);
        char *tname_and_where = from + 6;
        char *where = strcasestr(tname_and_where, " WHERE ");
        const char *wcol = NULL;
        int64_t wint = 0;
        char wtext_buf[256];
        char *wtext = NULL;
        if (where) {
            *where = 0;
            where += 7;
            where = trim(where);
            char *eq = strchr(where, '=');
            if (!eq) return -1;
            *eq = 0;
            wcol = trim(where);
            char *val = trim(eq + 1);
            char vtmp[256];
            strncpy(vtmp, val, sizeof(vtmp) - 1);
            vtmp[sizeof(vtmp) - 1] = 0;
            char *vt = vtmp;
            if (*vt == '\'') {
                vt++;
                char *e = strrchr(vt, '\'');
                if (e) *e = 0;
                strncpy(wtext_buf, vt, sizeof(wtext_buf) - 1);
                wtext_buf[sizeof(wtext_buf) - 1] = 0;
                wtext = wtext_buf;
                wint = 0;
            } else if (*vt == '"') {
                vt++;
                char *e = strrchr(vt, '"');
                if (e) *e = 0;
                strncpy(wtext_buf, vt, sizeof(wtext_buf) - 1);
                wtext_buf[sizeof(wtext_buf) - 1] = 0;
                wtext = wtext_buf;
                wint = 0;
            } else {
                wtext = NULL;
                wint = atoll(vt);
            }
        }
        char *tname = trim(tname_and_where);
        int ti = table_index(tname);
        if (ti < 0) return -1;
        int nc;
        char names[MAX_COLS][MAX_NAME];
        uint32_t types[MAX_COLS];
        table_schema(ti, &nc, names, types);
        int out_cols[MAX_COLS];
        int out_n = 0;
        if (!want_all) {
            char tmp[1024];
            strncpy(tmp, select_part, sizeof(tmp) - 1);
            tmp[sizeof(tmp) - 1] = 0;
            char *ct = strtok(tmp, ",");
            while (ct) {
                char *c = trim(ct);
                int ci = col_index(ti, c);
                if (ci < 0) return -1;
                out_cols[out_n++] = ci;
                ct = strtok(NULL, ",");
            }
        }
        scan_table(ti, nc, names, types, want_all, out_cols, out_n, wcol, wint, wtext);
        return 0;
    }
    return -1;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "Usage: my-sqlite <dbfile>\n");
        return 1;
    }
    g_path = argv[1];
    g_buf = NULL;
    g_cap = 0;
    g_size = 0;
    if (file_read_all() != 0) {
        fprintf(stderr, "read error\n");
        return 1;
    }
    if (g_size == 0) {
        g_buf = NULL;
        g_cap = 0;
        g_size = 0;
        if (ensure_cap(PAGE_SIZE) != 0) return 1;
        g_size = PAGE_SIZE;
        memcpy(g_buf, MAGIC, MAGIC_LEN);
        u32w(g_buf + 8, 1);
        u32w(g_buf + 12, 0);
    } else {
        if (g_size < 16 || memcmp(g_buf, MAGIC, MAGIC_LEN) != 0) {
            fprintf(stderr, "not a database\n");
            return 1;
        }
    }
    char line[4096];
    while (fgets(line, sizeof(line), stdin)) {
        size_t l = strlen(line);
        while (l > 0 && (line[l - 1] == '\n' || line[l - 1] == '\r')) line[--l] = 0;
        char *s = line;
        while (*s == ' ') s++;
        if (s[0] == 0) continue;
        char low[256];
        strncpy(low, s, sizeof(low) - 1);
        low[sizeof(low) - 1] = 0;
        for (char *p = low; *p; p++) *p = (char)tolower((unsigned char)*p);
        if (strcmp(low, ".exit") == 0 || strcmp(low, "exit") == 0 || strcmp(low, "quit") == 0) break;
        exec_sql(s);
    }
    if (file_write_all() != 0) {
        fprintf(stderr, "write error\n");
        return 1;
    }
    return 0;
}
CEOF

cat > /workspace/Makefile << 'MEOF'
CC      = gcc
CFLAGS  = -O2 -Wall -Wextra

my-sqlite: my-sqlite.c
	$(CC) $(CFLAGS) -o my-sqlite my-sqlite.c

clean:
	rm -f my-sqlite

.PHONY: clean
MEOF

# Build the reference binary.
make -j"$(nproc)" >/tmp/oracle-build.log 2>&1 || { cat /tmp/oracle-build.log; exit 1; }

# Sanity check: the binary must exist and be executable.
if [ ! -x /workspace/my-sqlite ]; then
    echo "Oracle build failed to produce /workspace/my-sqlite"
    exit 1
fi

echo "Oracle my-sqlite built successfully."
