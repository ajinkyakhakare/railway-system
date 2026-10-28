#!/usr/bin/env bash
# F3 | owner group: F3 (database tooling) | purpose: rebuild railway_db from every db/*.sql file, then run the contract verifier
#
# Usage:   ./scripts/init-db.sh            (schema, functions, procedures, triggers, views, seeds)
#          ./scripts/init-db.sh --demo     (same, plus db/60_demo_data.sql)
#
# Environment variables (all optional):
#   MYSQL_USER  (default root)       MYSQL_HOST (default 127.0.0.1)
#   MYSQL_PORT  (default 3306)       MYSQL_PWD  (if not set, the script asks for it)

export LC_ALL=C   # makes the file-name glob sort in plain byte order (01_, 10_, 20_ ...)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
DB_DIR="$REPO_ROOT/db"
VERIFIER="$SCRIPT_DIR/verify-contract.sql"

usage() {
  echo "Usage: $0 [--demo]"
  echo "  --demo   also run db/60_demo_data.sql (sample bookings)"
}

# ---- 1. read arguments -------------------------------------------------------
INCLUDE_DEMO=0
for arg in "$@"; do
  case "$arg" in
    --demo)    INCLUDE_DEMO=1 ;;
    -h|--help) usage; exit 0 ;;
    *)         echo "Unknown argument: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

# ---- 2. connection settings --------------------------------------------------
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_HOST="${MYSQL_HOST:-127.0.0.1}"
MYSQL_PORT="${MYSQL_PORT:-3306}"

if ! command -v mysql >/dev/null 2>&1; then
  echo "ERROR: the 'mysql' command line client was not found on PATH." >&2
  exit 1
fi

if [ -z "${MYSQL_PWD:-}" ]; then
  read -r -s -p "MySQL password for user '$MYSQL_USER' (press Enter for none): " MYSQL_PWD
  echo
fi
export MYSQL_PWD   # the mysql client reads the password from this variable

MYSQL_BASE=(mysql --host="$MYSQL_HOST" --port="$MYSQL_PORT" --user="$MYSQL_USER" --default-character-set=utf8mb4)

# ---- helpers -----------------------------------------------------------------

# Prints a file, skipping a UTF-8 byte-order mark if there is one (mysql rejects a BOM).
emit_file() {
  if [ "$(head -c 3 "$1" | od -An -tx1 | tr -d ' \n')" = "efbbbf" ]; then
    tail -c +4 "$1"
  else
    cat "$1"
  fi
}

# Runs one SQL file through the mysql client. Extra arguments are passed to mysql.
# Returns 1 and prints the mysql error text when the file fails.
run_sql_file() {
  local file="$1"; shift
  local output
  if ! output="$(emit_file "$file" | "${MYSQL_BASE[@]}" "$@" 2>&1)"; then
    echo "" >&2
    echo "FAILED FILE: $file" >&2
    echo "MYSQL ERROR: $output" >&2
    return 1
  fi
  if [ -n "$output" ]; then
    echo "$output"
  fi
  return 0
}

# ---- 3. allow stored functions with binary logging on ------------------------
if ! out="$("${MYSQL_BASE[@]}" -e "SET GLOBAL log_bin_trust_function_creators = 1;" 2>&1)"; then
  echo "WARNING: could not run SET GLOBAL log_bin_trust_function_creators = 1 (needs SUPER privilege)."
  echo "         Details: $out"
  echo "         Continuing; creating functions may fail if binary logging is enabled."
fi

# ---- 4. create the empty database (db/00_database.sql, no --database option) -
if [ ! -f "$DB_DIR/00_database.sql" ]; then
  echo "ERROR: $DB_DIR/00_database.sql not found." >&2
  exit 1
fi
echo ">>> Running 00_database.sql"
run_sql_file "$DB_DIR/00_database.sql" || exit 1

# ---- 5. collect all numbered files (sorted by name), skip 00 and maybe 60 ----
files=()
for f in "$DB_DIR"/[0-9][0-9]_*.sql; do
  [ -e "$f" ] || continue                      # glob matched nothing
  name="$(basename "$f")"
  if [ "$name" = "00_database.sql" ]; then
    continue                                   # already executed above
  fi
  if [ "$name" = "60_demo_data.sql" ] && [ "$INCLUDE_DEMO" -eq 0 ]; then
    echo "--- Skipping 60_demo_data.sql (use --demo to include it)"
    continue
  fi
  files+=("$f")
done

# ---- 6. run them in order, stop at the first error ---------------------------
for f in "${files[@]}"; do
  echo ">>> Running $(basename "$f")"
  run_sql_file "$f" --database=railway_db || exit 1
done

echo ""
echo "DB READY"
echo ""

# ---- 7. contract verifier ----------------------------------------------------
if [ ! -f "$VERIFIER" ]; then
  echo "ERROR: $VERIFIER not found." >&2
  exit 1
fi
echo ">>> Running verify-contract.sql"
run_sql_file "$VERIFIER" --database=railway_db --table || exit 1
exit 0
