# G5 Data Dictionary - Railway Operations & Analytics

Database: `railway_db` (MySQL 8.0, InnoDB, utf8mb4). Schema file: `db/05_schema_g5.sql`
(runs after `01_schema_g1.sql` .. `04_schema_g4.sql` because it references `train_run` and `station`).

Key legend: **PK** primary key, **FK** foreign key, **UQ** unique, **IDX** secondary index.

---

## 1. `train_run_status`

Current live state of each train run (one row per run). `Run_ID` is both the primary key and a
foreign key to `train_run`, so the relationship is strictly 1-to-1. The row is created by trigger
`trg_run_init_status` when a run is inserted and is updated through `sp_update_train_status`.

| Field | Type | Null | Key | Default | Description |
|---|---|---|---|---|---|
| Run_ID | INT UNSIGNED | NO | PK, FK -> train_run(Run_ID) | - | The train run this status belongs to. |
| Status | VARCHAR(10) | NO | IDX | 'SCHEDULED' | One of SCHEDULED, ON_TIME, DELAYED, CANCELLED, ARRIVED (CHECK). Trigger `trg_status_flag` switches it to DELAYED when the delay is 15 minutes or more, and back to ON_TIME when the delay returns to 0. |
| Current_Station_ID | INT UNSIGNED | YES | FK -> station(Station_ID), IDX | NULL | Station where the train currently is or was last reported. NULL when unknown. |
| Delay_Minutes | INT | NO | - | 0 | Current delay in minutes (CHECK >= 0). |
| Last_Reason | VARCHAR(100) | YES | - | NULL | Reason given with the most recent status update (for example "Signal failure"). |
| Updated_At | DATETIME | NO | - | CURRENT_TIMESTAMP, ON UPDATE CURRENT_TIMESTAMP | Time of the last change; MySQL refreshes it automatically on every UPDATE. |

Constraints and indexes: `fk_train_run_status_train_run`, `fk_train_run_status_station`,
`chk_train_run_status_status`, `chk_train_run_status_delay`, `idx_train_run_status_status`,
`idx_train_run_status_current_station_id`.

---

## 2. `delay_log`

Append-only history of delay changes. A row is inserted by trigger `trg_delay_log` whenever the
`Delay_Minutes` of a `train_run_status` row changes. It feeds the delay analytics
(`v_delay_metrics` and the delayed-trains report).

| Field | Type | Null | Key | Default | Description |
|---|---|---|---|---|---|
| Delay_Log_ID | INT UNSIGNED | NO | PK (AUTO_INCREMENT) | auto | Surrogate identifier of the log entry. |
| Run_ID | INT UNSIGNED | NO | FK -> train_run(Run_ID), IDX | - | The train run the delay belongs to. |
| Station_ID | INT UNSIGNED | YES | FK -> station(Station_ID), IDX | NULL | Station at which the delay was reported. NULL when unknown. |
| Delay_Minutes | INT | NO | - | - | Delay in minutes at the time of logging (CHECK >= 0). |
| Reason | VARCHAR(100) | YES | - | NULL | Reason recorded with the update. |
| Logged_At | DATETIME | NO | - | CURRENT_TIMESTAMP | When the entry was written. |

Constraints and indexes: `fk_delay_log_train_run`, `fk_delay_log_station`, `chk_delay_log_delay`,
`idx_delay_log_run_id`, `idx_delay_log_station_id`.

---

## 3. `station_daily_revenue`

Pre-aggregated revenue per origin station per day, filled by `sp_generate_daily_revenue` with
`INSERT ... ON DUPLICATE KEY UPDATE` (so the report can be regenerated safely). Revenue comes from
payments with status SUCCESS, grouped by the booking's `From_Station_ID` and `DATE(Paid_At)`. It
stores totals only, so it has no foreign key to `payment` or `booking`.

| Field | Type | Null | Key | Default | Description |
|---|---|---|---|---|---|
| Revenue_ID | INT UNSIGNED | NO | PK (AUTO_INCREMENT) | auto | Surrogate identifier of the revenue row. |
| Station_ID | INT UNSIGNED | NO | FK -> station(Station_ID), UQ (with Revenue_Date) | - | Origin station of the bookings counted. |
| Revenue_Date | DATE | NO | UQ (with Station_ID), IDX | - | Calendar day the payments were made. |
| Total_Revenue | DECIMAL(12,2) | NO | - | - | Sum of successful payment amounts for that station and day. |
| Ticket_Count | INT | NO | - | - | Number of distinct bookings paid for that station and day. |

Constraints and indexes: `fk_station_daily_revenue_station`,
`uq_station_daily_revenue_station_date` (Station_ID, Revenue_Date),
`idx_station_daily_revenue_revenue_date`.

---

## Relationships

| Parent | Child | Cardinality | Notes |
|---|---|---|---|
| train_run | train_run_status | 1 : 1 | Child PK is the FK. Row created by `trg_run_init_status`. |
| train_run | delay_log | 1 : N | One run can have many delay entries. |
| station | train_run_status | 1 : N (optional) | `Current_Station_ID`, nullable. |
| station | delay_log | 1 : N (optional) | `Station_ID`, nullable. |
| station | station_daily_revenue | 1 : N | One row per station per day. |

---

## MongoDB: `ops_event_log`

Database `railway_ops` (URI configured in `application.yml` as `spring.data.mongodb.uri`).
Used only when `app.mongo.enabled=true`. One document is written after every successful
`PUT /api/v1/ops/status/{runId}` and the documents are read by `GET /api/v1/admin/ops-events`.
A failure in MongoDB never fails the status update; the MySQL tables above remain the source of truth.

| Field | Type | Description |
|---|---|---|
| runId | number (long) | Id of the train run (`train_run.Run_ID`). |
| status | string | New status: SCHEDULED, ON_TIME, DELAYED, CANCELLED or ARRIVED. |
| delayMinutes | number (int) | Delay in minutes reported with the update. |
| reason | string | Free-text reason; may be null. |
| changedBy | string | Identity of the operator or admin who made the change. |
| at | date (ISO-8601 datetime) | When the event happened. |

(MongoDB also adds its own `_id` ObjectId to each document.)

**Why a schema-less store suits an append-only event log:**

- Events are only inserted, never updated or joined, so no foreign keys, transactions or
  normalisation are needed.
- The shape of an event can grow later (for example GPS position, weather, or the operator's
  device) without an `ALTER TABLE`; old and new documents can live in the same collection.
- Writes are cheap and fast, which matters because status updates can arrive in bursts when many
  trains are delayed at once.
- It separates high-volume operational history from the transactional MySQL data, so the booking
  tables are not slowed down or bloated by log traffic.
