#!/usr/bin/env bash
# Menguji migration Nekadaja pada database uji sementara:
#   1) up -> 2) down -> 3) up ulang -> 4) uji constraint.
# Kredensial memakai variabel standar PostgreSQL (PGHOST, PGPORT, PGUSER, PGPASSWORD).
# Jangan arahkan ke database yang berisi data penting: database uji dibuat ulang setiap kali.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIGRATIONS="${MIGRATIONS_DIR:-$HERE/../../migrations}"
TEST_DB="${TEST_DB:-nekadaja_migration_test}"
PSQL=(psql -v ON_ERROR_STOP=1 -q)

"${PSQL[@]}" -d postgres -c "DROP DATABASE IF EXISTS \"$TEST_DB\"" -c "CREATE DATABASE \"$TEST_DB\"" >/dev/null

apply() { # $1 = up|down
  local files
  if [ "$1" = up ]; then files=$(ls "$MIGRATIONS"/*.up.sql | sort); else files=$(ls "$MIGRATIONS"/*.down.sql | sort -r); fi
  for f in $files; do
    "${PSQL[@]}" -d "$TEST_DB" -1 -f "$f" >/dev/null
    echo "  $1  OK  $(basename "$f")"
  done
}
count_tables() { "${PSQL[@]}" -d "$TEST_DB" -Atc "select count(*) from information_schema.tables where table_schema='public'"; }

echo "== 1. up";   apply up;   echo "   tabel: $(count_tables)"
echo "== 2. down"; apply down; echo "   tabel: $(count_tables)"
[ "$(count_tables)" = "0" ] || { echo "GAGAL: masih ada tabel setelah down"; exit 1; }
echo "== 3. up ulang"; apply up; echo "   tabel: $(count_tables)"

echo "== 4. uji constraint"
RESULT="$(psql -d "$TEST_DB" -q -f "$HERE/constraints_test.sql" 2>&1 | sed -n '/=== HASIL ===/,$p')"
echo "$RESULT"
echo "$RESULT" | grep -Eq '^ +[0-9]+ \| +0 \| ' || { echo "GAGAL: ada uji constraint yang tidak lulus"; exit 1; }
echo "Semua pengujian migration lulus."
