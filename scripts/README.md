# Database scripts (task F3)

These scripts rebuild the whole `railway_db` database from the SQL files in `db/` and then check
it against the contract.

| File | Purpose |
|------|---------|
| `db/00_database.sql` | Drops and recreates the empty database `railway_db` (utf8mb4). |
| `scripts/init-db.sh` | Rebuild script for Linux / macOS (bash). |
| `scripts/init-db.ps1` | Rebuild script for Windows (PowerShell). |
| `scripts/verify-contract.sql` | Compares the built database with the contract and prints OK / MISSING. |

## Requirements

* MySQL 8.0 server running, and the `mysql` command line client on your `PATH`
  (test with `mysql --version`).
* A MySQL user that may create databases and run `SET GLOBAL` (normally `root`).

## What the scripts do

1. Run `SET GLOBAL log_bin_trust_function_creators = 1;` (needed for stored functions when binary
   logging is on). If this fails you only get a warning.
2. Run `db/00_database.sql`, which **deletes** and recreates `railway_db`.
3. Run every file in `db/` named `NN_something.sql` (two digits first), sorted by name, so the
   numbers give the order: schemas (01-05), functions (10), procedures (20), triggers (30),
   views (40), seeds (50-52). The folder `db/tests/` is never run.
   `db/60_demo_data.sql` is run **only** with the demo option.
4. The name of each file is printed before it runs. The script **stops at the first error** and
   shows the failing file and the MySQL error text.
5. At the end it prints `DB READY` and runs `scripts/verify-contract.sql`.

Files that do not exist yet are simply not run. You can generate the tasks in any order and run the
script after each one; the verifier tells you what is still missing.

## Settings and password

All settings come from environment variables. Defaults are shown in brackets.

| Variable | Meaning |
|----------|---------|
| `MYSQL_USER` | MySQL user [`root`] |
| `MYSQL_PWD` | MySQL password. If not set, the script asks for it (typing is hidden). |
| `MYSQL_HOST` | Server host [`127.0.0.1`] |
| `MYSQL_PORT` | Server port [`3306`] |

### Linux / macOS

```bash
chmod +x scripts/init-db.sh                # first time only
export MYSQL_PWD='your-password'           # optional, otherwise you are asked
./scripts/init-db.sh                       # master data only
./scripts/init-db.sh --demo                # also loads db/60_demo_data.sql
```

### Windows (PowerShell)

```powershell
$env:MYSQL_PWD = 'your-password'           # optional, otherwise you are asked
.\scripts\init-db.ps1                      # master data only
.\scripts\init-db.ps1 -Demo                # also loads db\60_demo_data.sql

# If scripts are blocked by the execution policy:
powershell -ExecutionPolicy Bypass -File .\scripts\init-db.ps1 -Demo
```

Run both scripts from anywhere; they find the repository folder from their own location.

## Running only the verifier

```bash
mysql -u root -p --table --database=railway_db < scripts/verify-contract.sql
```

`railway_db` must exist because the verifier needs a default database for its temporary tables.
It only reads `information_schema`; it changes nothing in your data.

## How to read the verifier output

The output has these blocks, one after another:

* **(a) TABLES** - one row for each of the 32 contract tables. `Table_Status` is `OK` or `MISSING`.
  `Actual_Columns` is compared with `Expected_Columns`; `Column_Count_Check` is `OK`, `DIFF`
  (a column too many or too few) or `n/a` (table missing).
* **(b) COLUMNS** - if every one of the 182 expected columns exists you see one line,
  `ALL COLUMNS OK`. Otherwise only the problems are listed, with the reason `COLUMN MISSING`
  (table exists, column does not) or `TABLE MISSING`.
* **(c) FUNCTIONS, PROCEDURES, TRIGGERS, VIEWS** - one row for each expected object with
  `OK` or `MISSING`.
* **TOTALS PER TYPE** - for each type: the contract total (32 / 11 / 12 / 15 / 12), how many the
  verifier lists, how many were found and how many are missing.
* **(d) SUMMARY** - one row with the number of missing tables, columns (in existing tables),
  functions, procedures, triggers and views, then `Total_Missing` and the `Verdict`:
  `CONTRACT OK` when nothing is missing, otherwise `CONTRACT INCOMPLETE`.

If only some task files have been loaded, a long list of `MISSING` rows is normal. It tells you
which files still have to be added. The goal is `Total_Missing = 0` and `CONTRACT OK`.

## Common problems

| Message | Likely cause |
|---------|--------------|
| `the 'mysql' command line client was not found` | MySQL client folder is not on `PATH`. |
| `Access denied for user` | Wrong `MYSQL_USER` / `MYSQL_PWD`. |
| `FAILED FILE: db/xx_....sql` | The SQL in that file has an error; read the MySQL error text below it. |
| `This function has none of DETERMINISTIC, NO SQL ...` | `SET GLOBAL` was not allowed; run it as a user with SUPER, or run `SET GLOBAL log_bin_trust_function_creators = 1;` once as root. |
