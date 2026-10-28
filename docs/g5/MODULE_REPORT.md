# Module Report: Railway Operations & Analytics (Group 5)

Project: National Railway Reservation & Management System, PICT (E&TCE)
Module: G5. Backend package `com.railway.ops`, frontend folder `src/modules/ops`.

## 1 Module overview and scope

Group 5 answers two questions. Operations: "Where is my train, and is it late?" Analytics: "How is the railway business doing?"

The operations side keeps one live status row for every train run. Operators change it through a REST call. Two triggers keep the row consistent and write a delay history. The analytics side turns the bookings and payments of other groups into reports: revenue per station per day, popular routes, delay metrics per train, and an admin dashboard.

In scope: 3 tables, 1 function, 2 procedures, 3 triggers, 4 views, 11 REST endpoints, 6 React pages, a MongoDB event log and a Postman collection. Out of scope: booking, payment, fares and users. These belong to G1-G4, and Group 5 only reads them.

## 2 ER diagram

The Mermaid source is `docs/g5/er.mmd`. In words:

- **train_run_status** has one row per train run. Its primary key Run_ID is also a foreign key to train_run, so train_run : train_run_status is 1:1. The trigger trg_run_init_status creates the row, so a run always has exactly one. Current_Station_ID is an optional foreign key to station: one station can be the current position of many runs (1:N), and a run may have no position yet.
- **delay_log** is the history. One train_run has many delay_log rows (1:N) and each row belongs to exactly one run. Station_ID is optional (N:1 to station).
- **station_daily_revenue** holds one summary row per station per date. One station has many rows (1:N). UNIQUE(Station_ID, Revenue_Date) prevents duplicates.

## 3 Normalization

| Table | 1NF | 2NF | 3NF |
|---|---|---|---|
| train_run_status | Atomic columns, one value per cell | Key is the single column Run_ID, so no partial dependency | Only the station id is stored, not its name, so no transitive dependency |
| delay_log | Atomic columns | Single surrogate key | Delay_Minutes, Reason and Logged_At depend only on the log row |
| station_daily_revenue | Atomic columns | Total_Revenue and Ticket_Count depend on the whole key (Station_ID, Revenue_Date) | No non-key column determines another |

Deliberate denormalization:

1. station_daily_revenue is derived data, because Total_Revenue can be recomputed from payments. It is kept as a snapshot so that a closed day does not change when data is corrected later, and so that reading one row is cheaper than summing many payments. The live view v_station_daily_revenue stays the source of truth.
2. train_run_status.Delay_Minutes repeats the newest delay_log value. The status table is the current state (fast for the board) and delay_log is the history. trg_delay_log keeps them in step.

## 4 Constraints

| Table | PK | FK | UNIQUE | CHECK | NOT NULL highlights |
|---|---|---|---|---|---|
| train_run_status | Run_ID | Run_ID to train_run; Current_Station_ID to station (nullable) | PK only | Status in 5 values; Delay_Minutes >= 0 | Status, Delay_Minutes, Updated_At |
| delay_log | Delay_Log_ID | Run_ID to train_run; Station_ID to station (nullable) | none | Delay_Minutes >= 0 | Run_ID, Delay_Minutes, Logged_At |
| station_daily_revenue | Revenue_ID | Station_ID to station | (Station_ID, Revenue_Date) | none | Station_ID, Revenue_Date, Total_Revenue, Ticket_Count |

## 5 Indexes and the query each one serves

| Index | Query it serves |
|---|---|
| PK train_run_status(Run_ID) | `WHERE Run_ID = ?` for GET /ops/status/{runId}; join column of v_train_live_status and v_delay_metrics |
| IDX delay_log(Run_ID) | "All delays of one run" and the join back to train_run |
| UQ station_daily_revenue(Station_ID, Revenue_Date) | Target of ON DUPLICATE KEY UPDATE; lookups by station and date |
| FK indexes on Current_Station_ID and Station_ID | The station join in v_train_live_status; FK checks when a station is deleted |
| Other groups' indexes (read only) | booking(Run_ID) for v_popular_routes; payment(Booking_ID) for the revenue view; train_run(Journey_Date) for the status board of one date |

## 6 Functions, procedures, triggers, views

### 6.1 fn_delay_minutes(p_scheduled DATETIME, p_actual DATETIME) RETURNS INT, DETERMINISTIC
Purpose: delay in whole minutes. Logic: `GREATEST(TIMESTAMPDIFF(MINUTE, p_scheduled, p_actual), 0)`. The same input always gives the same output, so it is DETERMINISTIC. Early arrival gives 0, never a negative number.
Example: `SELECT fn_delay_minutes('2026-10-28 06:00:00', '2026-10-28 06:25:00');` returns 25. With the two arguments swapped it returns 0.

### 6.2 sp_update_train_status(p_run_id, p_status, p_delay_minutes, p_current_station_id, p_reason)
Purpose: change the live status of one run. The station may be NULL. Logic: (1) check that the run exists, else RUN_NOT_FOUND; (2) check that the status is one of SCHEDULED, ON_TIME, DELAYED, CANCELLED, ARRIVED, else INVALID_STATUS; (3) START TRANSACTION, UPDATE train_run_status, COMMIT (the two triggers fire inside this transaction); (4) final SELECT. An EXIT HANDLER rolls back and re-raises on any SQL error.
Example: `CALL sp_update_train_status(1, 'DELAYED', 25, 3, 'Signal failure near Kalyan');`
Expected: one row, Run_ID 1, Status DELAYED, Delay_Minutes 25, Updated_At (current time).

### 6.3 sp_generate_daily_revenue(p_date DATE)
Purpose: store one day's revenue per origin station. Logic: join payment to booking; keep Payment_Status = 'SUCCESS' and DATE(Paid_At) = p_date; GROUP BY booking.From_Station_ID; Total_Revenue = SUM(Amount); Ticket_Count = COUNT(DISTINCT Booking_ID); write with INSERT ... ON DUPLICATE KEY UPDATE, so running it twice is safe.
Example: `CALL sp_generate_daily_revenue('2026-10-28');`
Expected: one row, Rows_Affected. It is 1 for each new station row; MySQL counts an updated existing row as 2.

### 6.4 trg_run_init_status (AFTER INSERT on train_run)
Inserts (NEW.Run_ID, 'SCHEDULED', 0) into train_run_status. This guarantees the 1:1 link, so the board never misses a run and the update procedure only needs UPDATE.
Example: after `CALL sp_generate_train_runs(1, '2026-11-01', '2026-11-01');` the query `SELECT Status, Delay_Minutes FROM train_run_status WHERE Run_ID = <new id>;` returns SCHEDULED, 0.

### 6.5 trg_status_flag (BEFORE UPDATE on train_run_status)
Rule 1: if NEW.Delay_Minutes >= 15 and NEW.Status is SCHEDULED or ON_TIME, set NEW.Status = 'DELAYED'. Rule 2: if NEW.Delay_Minutes = 0 and NEW.Status = 'DELAYED', set 'ON_TIME'. CANCELLED and ARRIVED are never touched. Because it is a BEFORE trigger it edits the row being saved, so no second UPDATE is needed.
Example: updating run 1 to ('ON_TIME', 20) stores DELAYED; updating it to ('DELAYED', 0) stores ON_TIME.

### 6.6 trg_delay_log (AFTER UPDATE on train_run_status)
When Delay_Minutes changed, inserts into delay_log (Run_ID, Current_Station_ID, new Delay_Minutes, Last_Reason). Example: changing run 1 from 0 to 25 minutes adds one row (1, 3, 25, 'Signal failure near Kalyan'); saving 25 again adds nothing.

### 6.7 Views

- **v_train_live_status**: INNER JOIN train_run_status, train_run and train; LEFT JOIN station for Current_Station_Name (LEFT, because a run may have no position). Example: `SELECT * FROM v_train_live_status WHERE Run_ID = 1;` gives 1, 11001, Mumbai Pune Express, the journey date, DELAYED, 25, 3, Kalyan Junction, the reason and the timestamp.
- **v_station_daily_revenue**: JOIN payment, booking and station; WHERE Payment_Status = 'SUCCESS'; GROUP BY station and DATE(Paid_At) (shown as Revenue_Date); SUM(Amount) and COUNT(DISTINCT Booking_ID). It is live, never stale. Example: one paid booking of two Sleeper passengers CSMT to Pune (2 x 120) gives Station 2, CSMT, Mumbai CSMT, the date, 240.00, 1.
- **v_popular_routes**: JOIN booking, train_run, train and route; WHERE Booking_Status <> 'EXPIRED'; GROUP BY route; Booking_Count = COUNT(*); Popularity_Rank = `RANK() OVER (ORDER BY Booking_Count DESC)`. Example: route 1 with 4 bookings gets rank 1, route 3 with 1 booking gets rank 2.
- **v_delay_metrics**: JOIN train_run_status, train_run and train; GROUP BY train; Total_Runs = COUNT(*); Delayed_Runs = runs with Status 'DELAYED'; Avg_Delay_Min = ROUND(AVG(Delay_Minutes), 1); Max_Delay_Min = MAX(Delay_Minutes). Example: train 11001 with 15 runs, one delayed by 25 minutes, gives 15, 1, 1.7, 25.

**RANK() vs DENSE_RANK().** With booking counts 10, 10, 7: RANK gives 1, 1, 3 (a gap after a tie); DENSE_RANK gives 1, 1, 2. The contract uses RANK, so two routes with equal counts share a rank and the next rank is skipped.

### 6.8 Queries behind the report endpoints

- **Delayed trains (GROUP BY + HAVING).** Group the runs by train and keep trains with `HAVING AVG(Delay_Minutes) > ?`. WHERE cannot do this, because it filters rows before grouping and the average does not exist yet; HAVING filters after grouping.
- **Top stations (subquery).** Total revenue per station is compared with the average of those totals: `HAVING SUM(Total_Revenue) > (SELECT AVG(t) FROM (SELECT SUM(Total_Revenue) AS t FROM v_station_daily_revenue GROUP BY Station_ID) x)`. With totals 100, 200 and 600 the average is 300, so only the 600 station is returned.

### 6.9 Why MongoDB for the event log

Every status update appends one document to the collection `ops_event_log`: runId, status, delayMinutes, reason, changedBy, at. An event log is append-only and write-heavy. It needs no joins or multi-row transactions, and its fields may grow later, which suits a schema-flexible document store. MySQL keeps the authoritative current state with full ACID guarantees, while MongoDB keeps the audit trail without crowding the relational tables. This also meets the faculty requirement of using both databases. Mongo is switched off by default (`app.mongo.enabled=false`), and a Mongo failure never fails the request.

## 7 Transactions, ACID and locking

- **Atomicity:** sp_update_train_status owns its transaction. The status change and the delay_log row written by trg_delay_log are in the same transaction, so both succeed or both roll back.
- **Consistency:** CHECK constraints (status list, Delay_Minutes >= 0), foreign keys and trg_status_flag keep every stored state valid.
- **Isolation:** the UPDATE takes an exclusive row lock, so two operators changing the same run are serialized. Under InnoDB's default REPEATABLE READ, sp_generate_daily_revenue reads a stable snapshot of payments.
- **Durability:** InnoDB writes committed changes to its redo log.
- **Lock order:** G5 never touches seat_inventory, booking_passenger or seat_allocation, so it cannot create a deadlock with the G3/G4 order. Its reads of booking and payment are plain consistent reads without locks.
- **Spring:** services that CALL these procedures are not @Transactional, because the procedures manage their own transactions.

## 8 Backend design and endpoint summary

Layers: controller (HTTP and @PreAuthorize), service (calls SqlHelper), dto (Java records with jakarta.validation). All responses use ApiResponse. Errors from SIGNAL SQLSTATE '45000' are mapped to JSON codes by the GlobalExceptionHandler. /admin/** requires ADMIN in SecurityConfig. After a successful status update the service writes the Mongo event inside a try/catch.

| Method and path | Access | Result |
|---|---|---|
| GET /ops/status?date | Public | Rows of v_train_live_status for the date (default today) |
| GET /ops/status/{runId} | Public | One row of that view |
| PUT /ops/status/{runId} | OPERATOR or ADMIN | {runId, status, delayMinutes, updatedAt} |
| GET /admin/reports/revenue?from&to | ADMIN | Rows of v_station_daily_revenue in the range |
| POST /admin/reports/revenue/generate | ADMIN | {rowsAffected} |
| GET /admin/reports/popular-routes | ADMIN | Rows of v_popular_routes |
| GET /admin/reports/delay-metrics | ADMIN | Rows of v_delay_metrics |
| GET /admin/reports/delayed-trains?thresholdMinutes=15 | ADMIN | Trains with average delay above the threshold |
| GET /admin/reports/top-stations | ADMIN | Stations above average revenue |
| GET /admin/dashboard/summary | ADMIN | Six counters |
| GET /admin/ops-events?limit=50 | ADMIN | Events from MongoDB, empty if disabled |

## 9 Frontend screens

| Route | Who | Content |
|---|---|---|
| /ops/board | Public | Live status board with a date picker and status badges |
| /ops/update | OPERATOR, ADMIN | Form to set status, delay, current station and reason for a run |
| /admin/dashboard | ADMIN | Six summary cards |
| /admin/reports/revenue | ADMIN | Date-range filter, revenue table, generate button, bar chart |
| /admin/reports/routes | ADMIN | Popular routes with rank, bar chart |
| /admin/reports/delays | ADMIN | Delay metrics, delayed trains with a threshold input |

## 10 Test cases

| ID | Objective | Input | Expected | Actual | Screenshot |
|---|---|---|---|---|---|
| T01 | Public board | GET /ops/status, no token | 200, list of runs | | |
| T02 | Operator update | PUT run 1, DELAYED, 25 | 200, DELAYED, 25 | | |
| T03 | Auto-flag | PUT ON_TIME with 20 min | Stored status DELAYED | | |
| T04 | Auto-clear | PUT DELAYED with 0 min | Stored status ON_TIME | | |
| T05 | Delay history | Two changes of delay | One delay_log row per change | | |
| T06 | Invalid status | status FLYING | 400 INVALID_STATUS | | |
| T07 | Unknown run | PUT run 999999 | 404 RUN_NOT_FOUND | | |
| T08 | Negative delay | delayMinutes -5 | 400 VALIDATION_ERROR | | |
| T09 | Role check | Passenger token on PUT or on /admin/reports/* | 403 FORBIDDEN | | |
| T10 | Revenue range | from and to dates | Only rows inside the range | | |
| T11 | Upsert | Generate revenue twice for one date | No duplicate rows | | |
| T12 | Popular routes | Equal booking counts | Equal ranks, next rank skipped | | |
| T13 | Dashboard | GET summary as admin | Six numbers | | |
| T14 | Mongo off | GET ops-events, mongo disabled | 200, empty list | | |

## 11 Integration points with other groups

Group 5 writes only to its own three tables and never calls other groups' procedures (contract C11). It reads other groups' data only through views and joins.

| Group | What G5 uses | How |
|---|---|---|
| G1 | train_run, train, route, station | trg_run_init_status fires when sp_generate_train_runs inserts a run; views join these tables |
| G2 | Roles ADMIN and OPERATOR, JWT | SecurityConfig and @PreAuthorize decide access |
| G3 | booking | v_popular_routes and the dashboard counters read it |
| G4 | payment, cancellation | The revenue views and procedure, and cancellationsToday, read them |
| F1/F2 | ApiResponse, SqlHelper, shared React components | Used as they are |

The backend itself queries G5 views and G5 tables. The dashboard counters are read-only COUNT and SUM queries on other groups' tables.

## 12 Assumptions and limitations

- Revenue belongs to the origin station (booking.From_Station_ID) and to the date of payment (Paid_At).
- Delayed_Runs counts runs whose Status is DELAYED.
- The revenue endpoint reads the live view; station_daily_revenue is a stored snapshot.
- Negative delay is rejected by request validation (VALIDATION_ERROR); the CHECK constraint is the second barrier.
- Run 1 in the examples is train 11001 on the first seeded day; run ids depend on when the seed was loaded.
- The unique key starts with Station_ID, so a query by date alone cannot use it efficiently. Acceptable at this data size.
- The status board is public by design. MongoDB is optional and off by default.
- This report follows the contract. Adjust the wording if the final code differs.
