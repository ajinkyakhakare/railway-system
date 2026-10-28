# Project Report: National Railway Reservation & Management System

> **How to use this skeleton.** Every section below contains an instruction in *italics* that says what
> to insert. Replace each instruction, and every item written as `<placeholder>`, with your real content,
> then delete this note. Items marked **Paste here** need a screenshot, a diagram or a file copied from
> the repository. Object names, tables and endpoints are already filled in from the project contract, so
> only add what is yours: screenshots, explanations and results. Keep the numbering; the faculty
> checklist follows it.

---

## Title page

| Field | Value |
|-------|-------|
| Project title | National Railway Reservation & Management System |
| Course | `<course name and code>` (Database Management Systems) |
| Institute | PICT |
| Department | Electronics & Telecommunication Engineering (E&TCE) |
| Class / Division | `<class and division>` |
| Academic year | `<yyyy-yy>` |
| Faculty guide | `<faculty name>` |
| Date of submission | `<dd Month yyyy>` |

| Group | Module | Student name | Roll no. |
|-------|--------|--------------|----------|
| G1 | Train, Station & Route | `<name>` | `<roll no>` |
| G2 | Passenger & User | `<name>` | `<roll no>` |
| G3 | Reservation & Seat | `<name>` | `<roll no>` |
| G4 | Payment, Cancellation & Refund | `<name>` | `<roll no>` |
| G5 | Railway Operations & Analytics | `<name>` | `<roll no>` |

*Insert here: your college logo, and (if your department asks for them) the certificate and
acknowledgement pages signed by the guide and head of department.*

---

## Table of contents

1. Introduction and objectives
2. System architecture
3. Module-wise design (G1 to G5)
4. Integration mapping
5. Backend and frontend summary
6. Testing
7. Results and screenshots
8. Limitations and future work
9. Conclusion
- References
- Appendix A: Contribution of each student
- Appendix B: Error codes
- Appendix C: How to run the system

---

## Abstract

*Write 150 to 250 words: the problem, the approach, the technologies, the main database features and the
result. Edit the draft below so that it reflects what your team actually delivered, then remove this
instruction.*

**Draft (edit before submitting):** Booking a railway ticket is a concurrent, rule-heavy transaction: many
users compete for the last seats of the same train on the same day, fares depend on distance, class and
concessions, and a cancellation must refund money and promote waiting passengers at the same time. This
project presents a National Railway Reservation & Management System built around a MySQL 8 database of
32 tables. Business rules live in the database as stored procedures (booking with automatic PNR,
cancellation with automatic RAC to confirmed promotion), triggers (waiting-list limit, fare-change audit,
automatic seat-inventory arithmetic), user-defined functions (net fare with concessions, refund
deduction by hours before departure) and views (station-wise daily revenue, popular routes ranked with
`RANK()`, train delay metrics). Row-level locking with `SELECT ... FOR UPDATE` and a fixed lock order give
strict ACID behaviour for PNR transactions. A Spring Boot REST API secured with JWT and role-based access
control, one-time passwords for payments, a Razorpay test-mode payment gateway and a React front end sit on
top of the database, while MongoDB stores the operations event log. The system was built by five module
groups against one shared contract and integrated through Git.

---

## 1. Introduction and objectives

### 1.1 Background and problem statement

*Insert here: 1 to 2 paragraphs on how railway reservation works (PNR, classes, CNF / RAC / WL, concessions,
refunds) and why a database-centred design suits it.*

### 1.2 Objectives

*Keep this list, and tick off in section 9 which objectives were achieved.*

1. Design a normalised relational schema of 32 tables in five modules for trains, users, reservations, payments and operations.
2. Implement booking with automatic PNR generation and CNF / RAC / WL allocation as a stored procedure.
3. Implement cancellation with a time-based refund and automatic RAC to confirmed promotion as a stored procedure.
4. Guarantee strict ACID behaviour for PNR transactions with row-level locking and a fixed lock order.
5. Enforce rules with triggers (waiting-list full, fare audit, seat-inventory counters) and compute fares and refunds with user-defined functions.
6. Provide analytical views and queries using JOIN, GROUP BY, HAVING, sub-queries and window functions.
7. Expose the system through a secured REST API (JWT, RBAC, OTP-based 2FA for payments and account security).
8. Integrate a payment gateway (Razorpay, test mode) and a mock gateway for offline demos.
9. Store the operations event log in MongoDB next to the MySQL core.
10. Deliver a React web application for passengers, operators and administrators.

### 1.3 Scope

*Insert here: what the system covers (for example: reserved tickets for the 4 seeded trains on 3 routes,
one currency, five user-facing modules) and what is deliberately out of scope (see also section 8).*

### 1.4 Technology stack

| Layer | Technology | Why it was chosen |
|-------|-----------|-------------------|
| Relational database | MySQL 8.0, InnoDB | `<one sentence>` |
| Document database | MongoDB | `<one sentence>` |
| Backend | Java 17, Spring Boot 3.3.5, Maven, JdbcTemplate | `<one sentence>` |
| Security | JWT (JJWT 0.12.6), BCrypt, Spring Security | `<one sentence>` |
| Frontend | React 18, Vite 5, Tailwind CSS 3, react-router-dom 6, axios, recharts | `<one sentence>` |
| Payments | Razorpay (test mode) and MOCK mode | `<one sentence>` |
| API testing | Postman | `<one sentence>` |

### 1.5 Team organisation and development approach

*Insert here: 1 paragraph on how five groups worked in parallel against one written contract (tables,
procedures, endpoints, error codes, routes), how files were owned by exactly one group, and how
everything was collected into one Git repository. Details belong in section 4.*

---

## 2. System architecture

*Paste here: the full content of `docs/ARCHITECTURE.md` (layer diagram, request flow, security, transaction
design). Keep its headings one level lower so that they fit under this section.*

<!-- BEGIN EMBED: docs/ARCHITECTURE.md -->

`<paste docs/ARCHITECTURE.md here>`

<!-- END EMBED: docs/ARCHITECTURE.md -->

*Also add: a one-paragraph walk-through of a booking request travelling from the React page, through the
controller and service, into `sp_book_ticket`, the triggers and back.*

---

## 3. Module-wise design

*Each module below follows the same pattern. For every item, paste the screenshot or diagram and write
2 to 4 lines of explanation under it. Screenshots of routines must come from running the matching
script in `db/tests/gN_tests.sql` (it shows the state before, the action and the state after).
Use the MySQL command line or MySQL Workbench; the screenshot must show the statement and its output.*

### 3.0 Conventions used in all modules

| Item | Convention |
|------|-----------|
| Database | `railway_db`, MySQL 8.0, InnoDB, utf8mb4 |
| Tables | snake_case, singular (`train_run`) |
| Columns | Pascal_Snake (`Train_ID`, `Fare_Amount`) |
| Primary key | `<Entity>_ID INT UNSIGNED AUTO_INCREMENT` |
| Status values | UPPER_CASE strings guarded by `CHECK` constraints |
| Routines | procedures `sp_*`, functions `fn_*`, triggers `trg_*`, views `v_*`, indexes `idx_<table>_<columns>` |
| Business errors | `SIGNAL SQLSTATE '45000'` with message `ERROR_CODE: readable text` |
| Lock order | seat_inventory, booking, booking_passenger, then seat_allocation / payment |

*Insert here (optional): one sentence of justification for each convention.*

---

### 3.1 Group G1: Train, Station & Route

*Owner(s): `<name>`. Backend package `com.railway.train`, frontend folder `modules/trains`.*

**3.1.1 Module overview**

*Insert here: what this module is responsible for (master data of stations, routes, trains, coaches,
seats and dated train runs) and which other groups depend on it. It owns 10 tables: station, route,
route_stop, train, train_schedule, coach_type, train_coach, seat, train_run, route_stop_audit.*

**3.1.2 ER diagram**

*Paste here: the rendered diagram of `docs/g1/er.mmd`. Render it by placing the file content in a
`mermaid` code block in any GitHub markdown file, or by pasting it into the Mermaid live editor, and
export the result as a PNG image. The other groups use the same method.*

**3.1.3 Relational schema**

*Paste here: one line per table in the form `Table(PK, attribute, ...; FK -> parent)`, underlining the
primary key, for all 10 tables. Model line:*

`route_stop(`**Route_Stop_ID**`, Route_ID, Station_ID, Stop_Seq, Arrival_Time, Departure_Time, Day_Offset, Distance_From_Source_Km; Route_ID -> route, Station_ID -> station; UNIQUE(Route_ID, Stop_Seq), UNIQUE(Route_ID, Station_ID))`

**3.1.4 Complete DDL**

*Paste here: the complete content of `db/01_schema_g1.sql` as a code block.*

**3.1.5 Functions**

*Paste here: one screenshot per function, taken from `db/tests/g1_tests.sql`.*

| Function | Purpose | Screenshot |
|----------|---------|------------|
| `fn_distance_km(run, from, to)` | Kilometres between two stops of the run's route | *paste here* |
| `fn_departure_datetime(run, station)` | Real departure date and time at a station (journey date + day offset + time) | *paste here* |
| `fn_journey_duration_min(run, from, to)` | Minutes from departure at one stop to arrival at another | *paste here* |

**3.1.6 Stored procedures**

| Procedure | Purpose | Screenshot (before / call / after) |
|-----------|---------|------------------------------------|
| `sp_add_coaches_generate_seats` | Adds coaches to a train and generates their seats and berth types | *paste here* |
| `sp_generate_train_runs` | Creates dated runs from the weekly schedule (re-runnable) | *paste here* |

**3.1.7 Triggers**

| Trigger | Table and event | Purpose | Screenshot |
|---------|-----------------|---------|------------|
| `trg_route_stop_bi` | route_stop, BEFORE INSERT | Rejects a halt whose departure is earlier than its arrival | *paste here* |
| `trg_route_stop_audit` | route_stop, AFTER UPDATE | Logs changed arrival / departure times in `route_stop_audit` | *paste here* |

**3.1.8 Views and queries**

| View | Purpose | Screenshot |
|------|---------|------------|
| `v_train_timetable` | Timetable of every train, stop by stop | *paste here* |
| `v_train_stop_pairs` | Self-join of route stops: every possible from-to pair on a train's route, used by train search | *paste here* |

**3.1.9 Normalisation and indexes**

*Insert here: show that `route_stop` is in 3NF (which attributes depend on the key and why the station
name is not repeated there), name the candidate keys, and list the indexes with the query each one speeds up.*

**3.1.10 Module documents**

*Attach or summarise: `docs/g1/data_dictionary.md` and `docs/g1/MODULE_REPORT.md`.*

---

### 3.2 Group G2: Passenger & User

*Owner(s): `<name>`. Backend package `com.railway.user`, frontend folder `modules/users`.*

**3.2.1 Module overview**

*Insert here: accounts, roles, saved passengers, login security (lock-out after repeated failures) and
OTP challenges. It owns 7 tables: role, app_user, user_role, passenger, login_audit, user_role_audit,
otp_challenge.*

**3.2.2 ER diagram**

*Paste here: the rendered diagram of `docs/g2/er.mmd`.*

**3.2.3 Relational schema**

*Paste here: one line per table (7 tables) in the form shown in section 3.1.3.*

**3.2.4 Complete DDL**

*Paste here: the complete content of `db/02_schema_g2.sql` as a code block.*

**3.2.5 Functions**

| Function | Purpose | Screenshot |
|----------|---------|------------|
| `fn_age_category(dob)` | CHILD (under 12), SENIOR (60 and over) or ADULT | *paste here* |
| `fn_effective_concession(dob, declared)` | SENIOR / CHILD derived from the date of birth, otherwise the declared concession | *paste here* |

**3.2.6 Stored procedures**

| Procedure | Purpose | Screenshot (before / call / after) |
|-----------|---------|------------------------------------|
| `sp_register_user` | Creates the account and its PASSENGER role in one transaction | *paste here* |
| `sp_record_login_attempt` | Logs the attempt, counts failures and locks the account for 15 minutes after 5 failures | *paste here* |

**3.2.7 Triggers**

| Trigger | Table and event | Purpose | Screenshot |
|---------|-----------------|---------|------------|
| `trg_user_role_ai` | user_role, AFTER INSERT | Writes a GRANT row to `user_role_audit` | *paste here* |
| `trg_user_role_ad` | user_role, AFTER DELETE | Writes a REVOKE row to `user_role_audit` | *paste here* |
| `trg_passenger_bi` | passenger, BEFORE INSERT | Rejects a date of birth in the future | *paste here* |

**3.2.8 Views and queries**

| View | Purpose | Screenshot |
|------|---------|------------|
| `v_user_account` | Users with their roles as one comma-separated column | *paste here* |
| `v_passenger_booking_history` | Every passenger's bookings with train, date, class and status | *paste here* |

**3.2.9 Security design**

*Insert here: how passwords are stored (BCrypt), how the login flow works (lock check, password check,
attempt logging, optional OTP, token issue), what the JWT contains, and how OTPs are generated, stored
(hashed) and verified (5 minutes, single use).*

**3.2.10 Module documents**

*Attach or summarise: `docs/g2/data_dictionary.md` and `docs/g2/MODULE_REPORT.md`.*

---

### 3.3 Group G3: Reservation & Seat

*Owner(s): `<name>`. Backend package `com.railway.booking`, frontend folder `modules/booking`.*

**3.3.1 Module overview**

*Insert here: seat inventory per run and class, booking with CNF / RAC / WL, seat allocation, PNR lookup,
automatic expiry of unpaid bookings. It owns 5 tables: seat_inventory, booking, booking_passenger,
seat_allocation, booking_status_history.*

**3.3.2 ER diagram**

*Paste here: the rendered diagram of `docs/g3/er.mmd`.*

**3.3.3 Relational schema**

*Paste here: one line per table (5 tables) in the form shown in section 3.1.3.*

**3.3.4 Complete DDL**

*Paste here: the complete content of `db/03_schema_g3.sql` as a code block.*

**3.3.5 Functions**

| Function | Purpose | Screenshot |
|----------|---------|------------|
| `fn_generate_pnr()` | Random 10-digit PNR, first digit 1 to 9 | *paste here* |
| `fn_availability_text(...)` | Text such as `AVL 12`, `RAC 3`, `WL 5` or `REGRET` | *paste here* |

**3.3.6 Stored procedures**

| Procedure | Purpose | Screenshot (before / call / after) |
|-----------|---------|------------------------------------|
| `sp_book_ticket` | Validates, locks the inventory row, creates the booking and passengers with CNF / RAC / WL status and seats, returns PNR and fare | *paste here* |
| `sp_promote_rac_wl` (helper) | Moves RAC to CNF and WL to RAC after a seat is freed; no own transaction | *paste here* |
| `sp_expire_unpaid_bookings` | Cancels unpaid bookings older than N minutes and releases their seats | *paste here* |

**3.3.7 Triggers**

| Trigger | Table and event | Purpose | Screenshot |
|---------|-----------------|---------|------------|
| `trg_run_init_inventory` | train_run, AFTER INSERT | Creates the seat inventory of every class of the train | *paste here* |
| `trg_block_if_wl_full` | booking_passenger, BEFORE INSERT | Blocks booking when the waiting list is full | *paste here* |
| `trg_dec_inventory` | booking_passenger, AFTER INSERT | Decrements available seats / increments RAC or WL counters | *paste here* |
| `trg_adjust_inventory_on_status` | booking_passenger, AFTER UPDATE | Moves the counters when a status changes and writes the status history | *paste here* |

**3.3.8 Views and queries**

| View | Purpose | Screenshot |
|------|---------|------------|
| `v_seat_availability` | Availability of every run and class with the availability text | *paste here* |
| `v_run_occupancy` | Occupancy percentage per run and class, ranked with `RANK() OVER (PARTITION BY Journey_Date ...)` | *paste here* |

**3.3.9 Concurrency and ACID proof**

*Paste here: the two-session experiment from section 6.4 (screenshots of both sessions) and a short
explanation of how `FOR UPDATE`, the `UNIQUE(Run_ID, Seat_ID)` constraint and the trigger-owned counters
together prevent double booking.*

**3.3.10 Module documents**

*Attach or summarise: `docs/g3/data_dictionary.md` and `docs/g3/MODULE_REPORT.md`.*

---

### 3.4 Group G4: Payment, Cancellation & Refund

*Owner(s): `<name>`. Backend package `com.railway.payment`, frontend folder `modules/payments`.*

**3.4.1 Module overview**

*Insert here: fare rules and concessions, payment orders and confirmation, cancellation with refund,
fare-change audit. It owns 7 tables: fare_rule, concession_rule, refund_rule, payment, cancellation,
refund, fare_audit_log.*

**3.4.2 ER diagram**

*Paste here: the rendered diagram of `docs/g4/er.mmd`.*

**3.4.3 Relational schema**

*Paste here: one line per table (7 tables) in the form shown in section 3.1.3.*

**3.4.4 Complete DDL**

*Paste here: the complete content of `db/04_schema_g4.sql` as a code block.*

**3.4.5 Functions**

| Function | Purpose | Screenshot |
|----------|---------|------------|
| `fn_base_fare(class, km)` | Distance x rate per km, but not below the minimum fare | *paste here* |
| `fn_net_fare(base, concession)` | Fare after the concession percentage | *paste here* |
| `fn_refund_deduction_pct(hours)` | Deduction percentage from the refund slab | *paste here* |

*Also paste here: the refund slab table (`refund_rule`) and 3 worked examples (fare, concession, refund) with their results.*

**3.4.6 Stored procedures**

| Procedure | Purpose | Screenshot (before / call / after) |
|-----------|---------|------------------------------------|
| `sp_create_payment` | Creates a payment for a pending booking owned by the user | *paste here* |
| `sp_confirm_payment` | Marks the payment SUCCESS or FAILED (the trigger confirms the booking) | *paste here* |
| `sp_cancel_ticket` | Cancels one passenger, calculates the refund, frees the seat and promotes RAC / WL | *paste here* |

**3.4.7 Triggers**

| Trigger | Table and event | Purpose | Screenshot |
|---------|-----------------|---------|------------|
| `trg_fare_audit` | fare_rule, AFTER UPDATE | Records old and new rate and minimum fare with the user who changed them | *paste here* |
| `trg_payment_confirm` | payment, AFTER UPDATE | Sets the booking CONFIRMED when the payment becomes SUCCESS | *paste here* |
| `trg_refund_check` | refund, BEFORE INSERT | Rejects a refund larger than the original fare | *paste here* |

**3.4.8 Views and queries**

| View | Purpose | Screenshot |
|------|---------|------------|
| `v_payment_history` | Payments of each user with PNR and status | *paste here* |
| `v_refund_summary` | Refunds with deduction details per cancelled passenger | *paste here* |

**3.4.9 Payment and cancellation flow**

*Paste here: a sequence diagram or flow chart of order creation, OTP check, gateway payment, signature
verification, confirmation, and of cancellation with refund. State what is different in MOCK and RAZORPAY mode.*

**3.4.10 Module documents**

*Attach or summarise: `docs/g4/data_dictionary.md` and `docs/g4/MODULE_REPORT.md`.*

---

### 3.5 Group G5: Railway Operations & Analytics

*Owner(s): `<name>`. Backend package `com.railway.ops`, frontend folder `modules/ops`.*

**3.5.1 Module overview**

*Insert here: live running status and delays, delay log, revenue reports, popular routes, dashboard,
MongoDB event log. It owns 3 tables: train_run_status, delay_log, station_daily_revenue.*

**3.5.2 ER diagram**

*Paste here: the rendered diagram of `docs/g5/er.mmd`.*

**3.5.3 Relational schema**

*Paste here: one line per table (3 tables) in the form shown in section 3.1.3.*

**3.5.4 Complete DDL**

*Paste here: the complete content of `db/05_schema_g5.sql` as a code block.*

**3.5.5 Functions**

| Function | Purpose | Screenshot |
|----------|---------|------------|
| `fn_delay_minutes(scheduled, actual)` | Delay in minutes, never negative | *paste here* |

**3.5.6 Stored procedures**

| Procedure | Purpose | Screenshot (before / call / after) |
|-----------|---------|------------------------------------|
| `sp_update_train_status` | Updates status, delay and current station of a run | *paste here* |
| `sp_generate_daily_revenue` | Stores the revenue of a day per origin station (insert or update) | *paste here* |

**3.5.7 Triggers**

| Trigger | Table and event | Purpose | Screenshot |
|---------|-----------------|---------|------------|
| `trg_run_init_status` | train_run, AFTER INSERT | Creates the SCHEDULED status row of a new run | *paste here* |
| `trg_status_flag` | train_run_status, BEFORE UPDATE | Sets DELAYED at 15 minutes or more, back to ON_TIME at 0 | *paste here* |
| `trg_delay_log` | train_run_status, AFTER UPDATE | Writes a `delay_log` row when the delay changes | *paste here* |

**3.5.8 Views and queries**

| View / query | Technique | Screenshot |
|--------------|-----------|------------|
| `v_train_live_status` | JOIN of run, train, status and station | *paste here* |
| `v_station_daily_revenue` | JOIN + GROUP BY with SUM and COUNT DISTINCT | *paste here* |
| `v_popular_routes` | GROUP BY + `RANK() OVER (ORDER BY Booking_Count DESC)` | *paste here* |
| `v_delay_metrics` | GROUP BY with COUNT, AVG, MAX | *paste here* |
| Delayed trains (`/admin/reports/delayed-trains`) | GROUP BY + HAVING `AVG(Delay_Minutes) > threshold` | *paste here* |
| Top stations (`/admin/reports/top-stations`) | Sub-query: stations above the average per-station revenue | *paste here* |

**3.5.9 MongoDB event log**

*Paste here: a screenshot of the `ops_event_log` collection (MongoDB Compass or `mongosh`) after a few
status updates, and 3 to 4 lines on why this data is stored in MongoDB and not in MySQL.*

**3.5.10 Module documents**

*Attach or summarise: `docs/g5/data_dictionary.md` and `docs/g5/MODULE_REPORT.md`.*

---

## 4. Integration mapping

*Paste here: the full content of `docs/INTEGRATION_MAPPING.md`, then have the five group representatives
sign the table below. Add a short paragraph on how conflicts were found and resolved (for example with
`scripts/verify-contract.sql`, the numeric order of the `db/` files and pull-request reviews).*

<!-- BEGIN EMBED: docs/INTEGRATION_MAPPING.md -->

`<paste docs/INTEGRATION_MAPPING.md here>`

<!-- END EMBED: docs/INTEGRATION_MAPPING.md -->

**Permitted writes into another group's tables** (the only cross-group writes in the system):

| # | Writer | Target table(s) | What is written |
|---|--------|-----------------|-----------------|
| 1 | G4 `trg_payment_confirm` | `booking` (G3) | Booking_Status becomes CONFIRMED |
| 2 | G4 `sp_cancel_ticket` | `booking_passenger`, `booking`, `seat_allocation` (G3) | Status CANCELLED, booking CANCELLED, seat rows deleted; calls G3 `sp_promote_rac_wl` |
| 3 | G3 `trg_run_init_inventory` and G5 `trg_run_init_status` | G3 / G5 own tables | Insert into their own tables when G1 inserts a `train_run` |
| 4 | Backends | none | A backend never writes another group's table; it calls the owner's procedure or endpoint |

**Integration sign-off**

| Group | Representative | Roll no. | Signature | Date |
|-------|----------------|----------|-----------|------|
| G1 Train, Station & Route | `<name>` | `<roll no>` | | |
| G2 Passenger & User | `<name>` | `<roll no>` | | |
| G3 Reservation & Seat | `<name>` | `<roll no>` | | |
| G4 Payment, Cancellation & Refund | `<name>` | `<roll no>` | | |
| G5 Railway Operations & Analytics | `<name>` | `<roll no>` | | |

---

## 5. Backend and frontend summary

### 5.1 Backend

*Insert here: 1 paragraph on the SQL-first design (JdbcTemplate through the shared `SqlHelper`, no JPA),
and how a controller calls a stored procedure. Then complete the table with the number of endpoints you
implemented.*

| Module | Package | Main endpoints | Roles |
|--------|---------|----------------|-------|
| Shared | `com.railway.common` | `GET /api/v1/health`, JWT filter, error handler, `SqlHelper` | public |
| G1 | `com.railway.train` | `/stations`, `/routes`, `/trains`, `/trains/search`, `/runs/{id}`, `/admin/stations`, `/admin/routes`, `/admin/trains` | public read, ADMIN write |
| G2 | `com.railway.user` | `/auth/register`, `/auth/login`, `/auth/verify-otp`, `/auth/payment-otp`, `/users/me`, `/passengers`, `/admin/users` | public / AUTH / ADMIN |
| G3 | `com.railway.booking` | `/availability`, `/bookings`, `/bookings/my`, `/tickets/{pnr}`, `/runs/{id}/seat-map`, `/admin/occupancy` | public / AUTH / ADMIN |
| G4 | `com.railway.payment` | `/fares/quote`, `/payments/orders`, `/payments/verify`, `/payments/mock-confirm`, `/cancellations`, `/refunds/my`, `/admin/fare-rules` | AUTH / ADMIN |
| G5 | `com.railway.ops` | `/ops/status`, `/admin/reports/*`, `/admin/dashboard/summary`, `/admin/ops-events` | public / OPERATOR / ADMIN |

### 5.2 Security and error handling

*Insert here: the filter chain (JWT parsing, `ROLE_` authorities, `@PreAuthorize`), the rule that
`/api/v1/admin/**` needs ADMIN, and how a database `SIGNAL` (for example `SEAT_UNAVAILABLE`) travels through
`GlobalExceptionHandler` to a JSON response `{"success":false,"error":{"code":...,"message":...}}`.
A screenshot of one error response is welcome.*

### 5.3 Frontend

*Insert here: 1 paragraph on the structure (shared components, `AuthContext`, `useAsync`, one folder per module
with `routes.jsx`, `api.js` and `pages/`). Then add one screenshot per page you built.*

| Module | Routes | Access |
|--------|--------|--------|
| trains | `/trains/search`, `/trains`, `/trains/:trainId` | public |
| trains | `/admin/trains`, `/admin/stations`, `/admin/routes` | ADMIN |
| users | `/login`, `/register` | public |
| users | `/profile`, `/passengers` | logged in |
| users | `/admin/users` | ADMIN |
| booking | `/availability/:runId`, `/tickets`, `/tickets/:pnr`, `/seat-map/:runId/:classCode` | public |
| booking | `/book/:runId/:classCode`, `/my-bookings` | logged in |
| booking | `/admin/occupancy` | ADMIN |
| payments | `/payment/:bookingId`, `/cancel/:bookingPassengerId`, `/payments/history` | logged in |
| payments | `/admin/fares` | ADMIN |
| ops | `/ops/board` | public |
| ops | `/ops/update` | OPERATOR, ADMIN |
| ops | `/admin/dashboard`, `/admin/reports/revenue`, `/admin/reports/routes`, `/admin/reports/delays` | ADMIN |

*Also paste here: the user journey diagram: search, availability, booking, payment, ticket, cancellation.*

---

## 6. Testing

### 6.1 SQL proof scripts

*Run each script and paste its output (screenshot or text). Each script shows the data before, the action
and the data after.*

| Script | Group | What it should demonstrate | Output |
|--------|-------|----------------|--------|
| `db/tests/g1_tests.sql` | G1 | Distance, departure and duration functions, coach / seat generation, run generation, route stop triggers | *paste here* |
| `db/tests/g2_tests.sql` | G2 | Registration, lock-out after failed logins, concession functions, role audit, date-of-birth check | *paste here* |
| `db/tests/g3_tests.sql` | G3 | Booking with CNF / RAC / WL, counters moved only by triggers, waiting-list-full block, RAC promotion, expiry of unpaid bookings | *paste here* |
| `db/tests/g4_tests.sql` | G4 | Fare and refund functions, payment confirmation, cancellation with refund, fare audit, refund check | *paste here* |
| `db/tests/g5_tests.sql` | G5 | Status flag and delay log triggers, daily revenue upsert, ranking and aggregate views | *paste here* |

### 6.2 API tests with Postman

*Import `postman/environment.json` and the five collections, run each collection with the Collection Runner
and paste the result summary (passed / failed requests).*

| Collection | Requests | Passed | Failed | Screenshot |
|------------|----------|--------|--------|------------|
| `postman/g1.postman_collection.json` | `<n>` | `<n>` | `<n>` | *paste here* |
| `postman/g2.postman_collection.json` | `<n>` | `<n>` | `<n>` | *paste here* |
| `postman/g3.postman_collection.json` | `<n>` | `<n>` | `<n>` | *paste here* |
| `postman/g4.postman_collection.json` | `<n>` | `<n>` | `<n>` | *paste here* |
| `postman/g5.postman_collection.json` | `<n>` | `<n>` | `<n>` | *paste here* |

### 6.3 Smoke test

*Run the end-to-end smoke test script of the project on a freshly created database (it needs `jq`) and
paste its console output. Explain in 2 to 3 lines which steps it covers (health check, login, search,
booking, payment, ticket, cancellation).*

### 6.4 Concurrency and ACID test

*Repeat this two-session experiment and paste a screenshot of both sessions. It shows that a second booking
waits for the first one (isolation), and that no seat is sold twice.*

Session A (keep the window open):

```sql
SET @run = (SELECT Run_ID FROM train_run
            WHERE Train_ID = 1 AND Journey_Date = DATE_ADD(CURDATE(), INTERVAL 1 DAY));
START TRANSACTION;
SELECT * FROM seat_inventory WHERE Run_ID = @run AND Class_Code = 'SL' FOR UPDATE;
-- do not commit yet
```

Session B (second window):

```sql
SET @run = (SELECT Run_ID FROM train_run
            WHERE Train_ID = 1 AND Journey_Date = DATE_ADD(CURDATE(), INTERVAL 1 DAY));
CALL sp_book_ticket(3, @run, 'SL', 2, 1, '[1]');   -- waits for session A
```

Session A: `COMMIT;` Session B now finishes. Then check:

```sql
SELECT Total_Seats, Available_CNF, RAC_Count, WL_Count FROM seat_inventory
WHERE Run_ID = @run AND Class_Code = 'SL';
SELECT COUNT(*) AS allocated_seats, COUNT(DISTINCT Seat_ID) AS distinct_seats
FROM seat_allocation WHERE Run_ID = @run;
```

*Explain the result: the counters changed by exactly one passenger and `allocated_seats` equals
`distinct_seats`. Mention what `innodb_lock_wait_timeout` does when session A never commits.*

### 6.5 Test case table

*Add at least 15 test cases covering all modules. Keep the format below. Include negative cases
(wrong owner, too many passengers, departed train, full waiting list, wrong OTP).*

| ID | Module | Test case | Input | Expected result | Actual result | Pass / Fail |
|----|--------|-----------|-------|-----------------|---------------|-------------|
| T01 | G2 | Register with an existing email | `asha@railway.test` | `EMAIL_EXISTS` (409) | `<result>` | `<P/F>` |
| T02 | G3 | Book 7 passengers in one booking | 7 passenger ids | `TOO_MANY_PASSENGERS` (400) | `<result>` | `<P/F>` |
| T03 | G4 | Cancel a ticket twice | same passenger id | `ALREADY_CANCELLED` (409) | `<result>` | `<P/F>` |
| T04 | `<module>` | `<case>` | `<input>` | `<expected>` | `<result>` | `<P/F>` |

### 6.6 Defects found and fixed (optional)

*List the bugs found during integration and testing, who fixed them, and what was changed.*

---

## 7. Results and screenshots

*Paste here one screenshot for every item of the checklist and write one caption line per screenshot.
Use the seeded accounts (password `Test@1234`).*

| No. | Screen / result | Route or source | Screenshot |
|-----|-----------------|-----------------|------------|
| 1 | Home page | `/` | *paste here* |
| 2 | Train search result | `/trains/search` | *paste here* |
| 3 | Timetable of a train | `/trains/:trainId` | *paste here* |
| 4 | Availability by class (AVL / RAC / WL) | `/availability/:runId` | *paste here* |
| 5 | Registration and login | `/register`, `/login` | *paste here* |
| 6 | Saved passengers | `/passengers` | *paste here* |
| 7 | Booking form with fare quote | `/book/:runId/:classCode` | *paste here* |
| 8 | Payment with OTP | `/payment/:bookingId` | *paste here* |
| 9 | Razorpay test checkout (if used) | `/payment/:bookingId` | *paste here* |
| 10 | Ticket by PNR with seats | `/tickets/:pnr` | *paste here* |
| 11 | My bookings | `/my-bookings` | *paste here* |
| 12 | Cancellation with refund preview | `/cancel/:bookingPassengerId` | *paste here* |
| 13 | RAC / WL passenger promoted after a cancellation (before and after) | `/my-bookings`, `/tickets/:pnr` | *paste here* |
| 14 | Seat map | `/seat-map/:runId/:classCode` | *paste here* |
| 15 | Live running board | `/ops/board` | *paste here* |
| 16 | Operator status update | `/ops/update` | *paste here* |
| 17 | Admin dashboard | `/admin/dashboard` | *paste here* |
| 18 | Revenue, popular routes and delay reports (charts) | `/admin/reports/*` | *paste here* |
| 19 | Fare rule change and the audit log | `/admin/fares` | *paste here* |
| 20 | MongoDB event log | `ops_event_log` | *paste here* |

*Add 1 to 2 paragraphs of discussion: what the results show about correctness (no double booking, correct
refunds, correct promotion) and performance.*

---

## 8. Limitations and future work

*List the real limitations of your build, and the improvements you would make. Starting points (delete
what does not apply, add your own):*

**Limitations**

- OTPs are returned in the API response when `app.auth.dev-mode=true`; there is no real email or SMS delivery.
- Payments run in mock or Razorpay test mode only; there is no real money flow, settlement or gateway refund call.
- Seat allocation takes the lowest free seat of the class; passengers cannot choose berth preference or coach.
- A booking covers one origin-destination pair; there are no connecting journeys or quotas.
- Reserved tickets only: no tatkal, no platform tickets, no unreserved coaches.
- A JWT cannot be revoked before it expires (stateless design).
- Seed data covers 9 stations, 3 routes and 4 trains; runs exist only for a 15-day window.

**Future work**

- Real email / SMS gateway for OTPs and notifications.
- Gateway refunds through the Razorpay API, webhooks for payment status.
- Berth preference, coach choice and seat-map selection while booking.
- Connecting journeys and dynamic pricing.
- Refresh tokens and token revocation.
- Read replicas or caching for the search and availability queries.
- Automated tests in CI (JUnit, Testcontainers, front-end tests).

---

## 9. Conclusion

*Write 1 to 2 paragraphs: what was built, which objectives of section 1.2 were met (tick them one by one),
what the team learned about database design, concurrency and integration, and a closing sentence about
the value of the project.*

---

## References

*Add every source you used, in a consistent format. Starting points:*

1. MySQL 8.0 Reference Manual: https://dev.mysql.com/doc/refman/8.0/en/
2. Spring Boot reference documentation: https://spring.io/projects/spring-boot
3. JSON Web Token (JWT), RFC 7519: https://datatracker.ietf.org/doc/html/rfc7519
4. JJWT library: https://github.com/jwtk/jjwt
5. Razorpay API and test-mode documentation: https://razorpay.com/docs/
6. MongoDB manual: https://www.mongodb.com/docs/
7. React documentation: https://react.dev/
8. Vite documentation: https://vitejs.dev/
9. Tailwind CSS documentation: https://tailwindcss.com/docs
10. `<textbook: author, title, edition, publisher, year>` (database systems textbook prescribed in the course)
11. `<any other paper, website or lecture notes used>`

---

## Appendix A: Contribution of each student

*Fill in one row per student. Count commits or files if your guide asks for evidence. The total of each
column must make sense with section 3.*

| Student | Roll no. | Group | Database files | Backend files | Frontend files | Documents / tests | Share of work |
|---------|----------|-------|----------------|---------------|----------------|-------------------|---------------|
| `<name>` | `<roll no>` | G1 | `db/01_schema_g1.sql`, `db/10_functions_g1.sql`, `db/20_procedures_g1.sql`, `db/30_triggers_g1.sql`, `db/40_views_g1.sql`, `db/50_seed_g1.sql` | `com.railway.train` | `modules/trains` | `db/tests/g1_tests.sql`, `postman/g1...`, `docs/g1/*` | `<%>` |
| `<name>` | `<roll no>` | G2 | `db/02_schema_g2.sql`, `db/10_functions_g2.sql`, `db/20_procedures_g2.sql`, `db/30_triggers_g2.sql`, `db/40_views_g2.sql`, `db/51_seed_g2.sql` | `com.railway.user` | `modules/users` | `db/tests/g2_tests.sql`, `postman/g2...`, `docs/g2/*` | `<%>` |
| `<name>` | `<roll no>` | G3 | `db/03_schema_g3.sql`, `db/10_functions_g3.sql`, `db/20_procedures_g3.sql`, `db/30_triggers_g3.sql`, `db/40_views_g3.sql` | `com.railway.booking` | `modules/booking` | `db/tests/g3_tests.sql`, `postman/g3...`, `docs/g3/*` | `<%>` |
| `<name>` | `<roll no>` | G4 | `db/04_schema_g4.sql`, `db/10_functions_g4.sql`, `db/20_procedures_g4.sql`, `db/30_triggers_g4.sql`, `db/40_views_g4.sql`, `db/52_seed_g4.sql` | `com.railway.payment` | `modules/payments` | `db/tests/g4_tests.sql`, `postman/g4...`, `docs/g4/*` | `<%>` |
| `<name>` | `<roll no>` | G5 | `db/05_schema_g5.sql`, `db/10_functions_g5.sql`, `db/20_procedures_g5.sql`, `db/30_triggers_g5.sql`, `db/40_views_g5.sql` | `com.railway.ops` | `modules/ops` | `db/tests/g5_tests.sql`, `postman/g5...`, `docs/g5/*` | `<%>` |
| `<name>` | `<roll no>` | Shared (F1, F2, F3, I1) | `db/00_database.sql`, `db/60_demo_data.sql`, `scripts/*` | `com.railway.common`, `pom.xml`, `application.yml` | Vite project, shared components | `README.md`, `docs/*` | `<%>` |

---

## Appendix B: Error codes

*Keep this table; it is the list of business error codes returned by the database and the API.*

| Code | HTTP | Meaning |
|------|------|---------|
| `VALIDATION_ERROR` | 400 | Invalid input |
| `INVALID_STATIONS` | 400 | Stations not on the route, or wrong order |
| `TOO_MANY_PASSENGERS` | 400 | More than 6 passengers in one booking |
| `INVALID_STATUS` | 400 | Unknown train status |
| `INVALID_CREDENTIALS` | 401 | Wrong email or password |
| `UNAUTHORIZED` | 401 | Missing or invalid token |
| `OTP_INVALID` | 401 | Wrong, expired or used OTP |
| `FORBIDDEN` | 403 | Role not allowed |
| `NOT_OWNER` | 403 | Record belongs to another user |
| `PASSENGER_NOT_OWNED` | 403 | Passenger belongs to another user |
| `NOT_FOUND` | 404 | Record not found |
| `RUN_NOT_FOUND` | 404 | Train run not found |
| `BOOKING_NOT_FOUND` | 404 | Booking or booking passenger not found |
| `EMAIL_EXISTS` | 409 | Email already registered |
| `DUPLICATE` | 409 | Duplicate key |
| `CONSTRAINT_VIOLATION` | 409 | Database constraint violated |
| `PASSENGER_IN_USE` | 409 | Passenger is referenced by bookings |
| `SEAT_UNAVAILABLE` | 409 | No inventory for the run and class |
| `BOOKING_CLOSED_WL_FULL` | 409 | Waiting list is full |
| `RUN_DEPARTED` | 409 | The train has already departed |
| `ALREADY_CANCELLED` | 409 | Passenger already cancelled |
| `CANCEL_NOT_ALLOWED` | 409 | Departure time has passed |
| `PAYMENT_NOT_ALLOWED` | 409 | Booking or payment is in the wrong state |
| `REFUND_EXCEEDS_FARE` | 409 | Refund larger than the original fare |
| `ACCOUNT_LOCKED` | 423 | Account locked after repeated failed logins |
| `INTERNAL_ERROR` | 500 | Unexpected server error |

---

## Appendix C: How to run the system

*Keep this short appendix, or replace it with a screenshot of a successful start. Full details and
troubleshooting are in `README.md`.*

1. Install JDK 17, Maven 3.9, Node 20 and MySQL 8 (MongoDB and `jq` are optional).
2. Set `DB_USER` and `DB_PASSWORD`.
3. Run `scripts/init-db.sh` (or `scripts/init-db.ps1` on Windows); optionally load `db/60_demo_data.sql`.
4. `cd backend && mvn spring-boot:run`
5. `cd frontend && npm install && npm run dev`
6. Open http://localhost:5173 and log in as `admin@railway.test`, `operator@railway.test` or
   `asha@railway.test` with the password `Test@1234`.
