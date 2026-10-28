# Module Report: Reservation & Seat Management (Group 3)

PICT, E&TCE.

## 1. Module overview and scope

Group 3 is the booking core of the system. A logged-in user chooses a train run, books 1 to 6 passengers in one class and receives a 10-digit PNR. Anyone can then check availability, look up a ticket by PNR or view a seat map. The module also keeps seat counts correct after cancellation or non-payment.

**In scope:** five tables (`seat_inventory`, `booking`, `booking_passenger`, `seat_allocation`, `booking_status_history`), two functions, three procedures, four triggers, two views, eight REST endpoints and seven React screens.
**Out of scope:** trains (G1), users (G2), fares, payment and refunds (G4), live status and reports (G5).

**Inventory model.** There is one `seat_inventory` row for every pair of (train run, class). `trg_run_init_inventory` creates it when G1 inserts the `train_run`. `Total_Seats` is the number of coaches of that class multiplied by seats per coach. `Max_RAC` is 10% of `Total_Seats` and `Max_WL` is 20%, both rounded. Example: train 11001, SL, two coaches gives 144 seats, Max_RAC 14 and Max_WL 29.

**CNF / RAC / WL rules.** For each passenger the procedure reads the counters and chooses:

1. `Available_CNF > 0`: status CNF and a seat is allocated.
2. Otherwise `RAC_Count < Max_RAC`: status RAC (no seat yet).
3. Otherwise `WL_Count < Max_WL`: status WL.
4. Otherwise the booking is refused with `BOOKING_CLOSED_WL_FULL`.

When a seat is freed, the oldest RAC passenger (lowest `Booking_Passenger_ID`) becomes CNF and then the oldest WL passenger becomes RAC.

**Trigger-owned counters.** `Available_CNF`, `RAC_Count` and `WL_Count` are changed only by triggers. Procedures only change `booking_passenger.Status`; the triggers do the arithmetic. This keeps the counting rule in one place.

## 2. ER diagram

The Mermaid diagram is in `docs/g3/er.mmd`. In words:

- **seat_inventory** holds the counters of one run and one class. It has an N:1 relationship to `train_run` (a run has at most one row per class, enforced by UQ(Run_ID, Class_Code)) and an N:1 relationship to `coach_type` through `Class_Code`.
- **booking** is one purchase. A user has many bookings (1:N from `app_user`), a run has many bookings (1:N from `train_run`) and every booking points to two stations, From and To (two N:1 links to `station`).
- **booking_passenger** is one traveller on one booking. One booking has 1 to 6 of them (1:N). A `passenger` can appear in many bookings (1:N) but only once in the same booking, because of UQ(Booking_ID, Passenger_ID).
- **seat_allocation** joins a CNF passenger to a physical `seat` for one run. `booking_passenger` to `seat_allocation` is 1:0..1 (RAC and WL passengers have no row). `seat` to `seat_allocation` is 1:N over time, but only once per run.
- **booking_status_history** is an audit trail. It refers to `booking_passenger` by id only (logical N:1, no foreign key), so deletes never block history.

## 3. Normalization

| Table | 1NF | 2NF | 3NF |
|---|---|---|---|
| seat_inventory | All columns atomic. | Key is `Inventory_ID`; every column describes one (run, class) pair. | No non-key dependency, except stored `Max_RAC`/`Max_WL` (D4). |
| booking | One value per column; passengers live in a child table. | Single-column key, so no partial dependency. | User and station details come through foreign keys. `Total_Fare` is derived (D2). |
| booking_passenger | Atomic columns. | Single-column key. | Name and date of birth stay in `passenger`. Fare columns are a snapshot (D3). |
| seat_allocation | Atomic columns. | Single-column key. | Only ids stored; coach and seat details come from `seat`. |
| booking_status_history | Atomic columns. | Single-column key. | Every column depends on the history row. |

**Deliberate denormalization:**

- **D1 counters:** `Available_CNF`, `RAC_Count` and `WL_Count` could be counted from `booking_passenger`. They are stored so availability is one row read and the row can be locked.
- **D2 `booking.Total_Fare`:** equals the sum of passenger fares. It is stored so payment and "my bookings" do not need an aggregate query.
- **D3 fare snapshot:** `Base_Fare`, `Concession_Type` and `Fare_Amount` are copied at booking time. Fare rules and passenger concessions can change later, but a ticket price must not.
- **D4 `Max_RAC`, `Max_WL`:** derived from `Total_Seats` and fixed at run creation, so later coach changes do not affect sold tickets.

## 4. Constraints

| Table | PK | FK | UNIQUE | CHECK | NOT NULL highlights |
|---|---|---|---|---|---|
| seat_inventory | Inventory_ID | Run_ID to train_run; Class_Code to coach_type(Class_Code) | (Run_ID, Class_Code) | Available_CNF 0..Total_Seats; RAC_Count 0..Max_RAC; WL_Count 0..Max_WL | Total_Seats, Available_CNF, Max_RAC, Max_WL |
| booking | Booking_ID | User_ID to app_user; Run_ID to train_run; From and To to station | PNR | From <> To; status in four allowed values | PNR, Class_Code, Booking_Status, Total_Fare |
| booking_passenger | Booking_Passenger_ID | Booking_ID to booking; Passenger_ID to passenger | (Booking_ID, Passenger_ID) | Status in CNF, RAC, WL, CANCELLED | Status, Base_Fare, Concession_Type, Fare_Amount |
| seat_allocation | Allocation_ID | Run_ID; Seat_ID; Booking_Passenger_ID | Booking_Passenger_ID; (Run_ID, Seat_ID) | none | all columns |
| booking_status_history | History_ID | none (deliberate) | none | none | New_Status, Changed_At |

The CHECK on `seat_inventory` is a safety net: a trigger bug cannot push a counter outside its limits.

## 5. Indexes

| Index | Query it serves |
|---|---|
| UQ(Run_ID, Class_Code) on seat_inventory | Availability for a run, and the `FOR UPDATE` row lock in `sp_book_ticket` (an exact lookup locks one row). |
| UQ(PNR) on booking | `GET /tickets/{pnr}` and the PNR uniqueness check. |
| idx on booking(User_ID) | `GET /bookings/my`. |
| UQ(Booking_ID, Passenger_ID) on booking_passenger | Loading the passengers of a booking (leftmost column is Booking_ID). |
| UQ(Run_ID, Seat_ID) on seat_allocation | Free seats of a run, the seat map, and the double-booking guard. |

## 6. Functions, procedures, triggers, views

### Functions

**fn_generate_pnr()**: returns `CHAR(10)`, NOT DETERMINISTIC NO SQL. No parameters. Logic: a random digit 1 to 9, followed by nine random digits padded with zeros. Uniqueness is checked by the caller. Example: `SELECT fn_generate_pnr();` returns for example `4829103756`.

**fn_availability_text(p_available_cnf, p_rac, p_wl, p_max_rac, p_max_wl)**: returns `VARCHAR(20)`, DETERMINISTIC. Logic: if CNF seats remain return `AVL n`; else if RAC has room return `RAC n+1`; else if WL has room return `WL n+1`; else `REGRET`. Example: `SELECT fn_availability_text(0,14,0,14,29);` returns `WL 1`. With `(5,0,0,14,29)` it returns `AVL 5`.

### Procedures

**sp_book_ticket(p_user_id, p_run_id, p_class_code, p_from_station_id, p_to_station_id, p_passenger_ids JSON)**: books the ticket.
1. Validate 1 to 6 passengers, run exists, stations are on the route in the right order, train not departed.
2. Start the transaction and lock the inventory row with `FOR UPDATE`.
3. Generate an unused PNR (up to 10 tries) and insert the booking as PENDING_PAYMENT.
4. For each passenger: check ownership, compute the net fare with the G1/G2/G4 functions, re-read counters, choose CNF, RAC or WL, insert the row (triggers update counters) and, for CNF, insert the lowest free seat into `seat_allocation`.
5. Set `Total_Fare` and commit.

Example: `CALL sp_book_ticket(3, 1, 'SL', 2, 1, '[1,2]');` returns `Booking_ID=1, PNR=4829103756, Total_Fare=192.00` (Asha pays the minimum fare of 120.00, senior Suresh pays 72.00).

**sp_promote_rac_wl(p_run_id, p_class_code, OUT p_promoted)**: HELPER, no transaction, no result set. It locks the inventory row, moves the oldest RAC passengers to CNF (with a seat) while seats are free, then moves the oldest WL passengers to RAC while RAC has room, and counts the changes. Example: `CALL sp_promote_rac_wl(1,'SL',@p); SELECT @p;` returns `1` after one CNF ticket was cancelled and one RAC passenger existed.

**sp_expire_unpaid_bookings(p_minutes)**: frees seats of unpaid bookings. For every PENDING_PAYMENT booking older than `p_minutes`, in its own transaction: cancel its passengers, delete their seat rows, call `sp_promote_rac_wl` and mark the booking EXPIRED. Example: `CALL sp_expire_unpaid_bookings(30);` returns `Expired_Count = 0` if nothing is old enough.

### Triggers

| Trigger | Event | Behaviour and example |
|---|---|---|
| trg_run_init_inventory | AFTER INSERT on train_run | Creates one inventory row per class of the train. A new run of train 11001 gets SL 144, 3A 64, CC 78. |
| trg_block_if_wl_full | BEFORE INSERT on booking_passenger | A WL row with `WL_Count >= Max_WL` raises `BOOKING_CLOSED_WL_FULL`. |
| trg_dec_inventory | AFTER INSERT on booking_passenger | CNF subtracts 1 from `Available_CNF`; RAC adds 1 to `RAC_Count`; WL adds 1 to `WL_Count`. Inserting a CNF row changes 144 to 143. |
| trg_adjust_inventory_on_status | AFTER UPDATE on booking_passenger | Reverses the old counter and applies the new one (CNF to CANCELLED gives +1 CNF; RAC to CNF gives RAC-1 and CNF-1; WL to RAC gives WL-1 and RAC+1). Also writes `booking_status_history`. |

### Views

**v_seat_availability**: run, train, class, all counters and `Availability_Text`. Example: `SELECT Class_Code, Available_CNF, Availability_Text FROM v_seat_availability WHERE Run_ID=1;` gives `SL 144 AVL 144` on an empty run.

**v_run_occupancy**: booked seats (`Total_Seats - Available_CNF`), `Occupancy_Pct` and `RANK() OVER (PARTITION BY Journey_Date ORDER BY Occupancy_Pct DESC)`. After 2 CNF bookings on SL 144 the row shows `Booked_Seats=2, Occupancy_Pct=1.4`.

## 7. Transactions, ACID and locking

- **Atomicity:** `sp_book_ticket` runs as one transaction with `DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END`. If passenger 2 fails (for example `PASSENGER_NOT_OWNED`), the booking and passenger 1 disappear as well.
- **Consistency:** CHECKs, foreign keys, UQ(PNR) and the triggers keep the counters valid.
- **Isolation:** the first statement of the transaction locks the inventory row. A second booking for the same run and class waits. After the lock the counters are re-read, so the second session sees the first one's committed result.
- **Durability:** after `COMMIT`, InnoDB's redo log keeps the booking even after a crash.

**Lock order:** `seat_inventory`, then `booking`, then `booking_passenger`, then `seat_allocation` / `payment`. A deadlock needs a circle: session A waits for B while B waits for A. If every procedure (`sp_book_ticket`, `sp_cancel_ticket`, `sp_promote_rac_wl`, `sp_expire_unpaid_bookings`) takes locks in the same order, nobody can hold a later lock while waiting for an earlier one, so no circle can form.

**UQ(Run_ID, Seat_ID):** even if two sessions somehow chose the same seat, the second INSERT fails on this unique key, so double booking is impossible at database level.

**Two-session concurrency proof:**
1. Session 1 runs `START TRANSACTION; SELECT ... FROM seat_inventory WHERE Run_ID=? AND Class_Code=? FOR UPDATE;` and keeps the transaction open.
2. Session 2 calls `sp_book_ticket` for the same run and class and waits on the lock.
3. Session 1 runs `COMMIT`. Session 2 continues at once with fresh counters.
4. In a last-seat test (`Available_CNF = 1`), two sessions each book one passenger. Result: exactly one CNF and one RAC, and `seat_allocation` has no duplicate seat.

## 8. Backend design and endpoint summary

Code is in `com.railway.booking` (`controller`, `service`, `dto`); class names start with Booking, Availability, Ticket or Seat. The approach is SQL-first with `SqlHelper` (no JPA). Request records use `jakarta.validation` (1 to 6 passenger ids). The booking service is **not** `@Transactional` because the stored procedure owns the transaction.

| Method and path | Access | Purpose |
|---|---|---|
| GET /availability?runId | Public | Rows of `v_seat_availability` |
| POST /bookings | Logged in | Calls `sp_book_ticket`, returns PNR, fare and passengers |
| GET /bookings/my | Logged in | Own bookings, newest first |
| GET /bookings/{bookingId} | Owner or ADMIN | Full booking with seat details |
| GET /tickets/{pnr} | Public | Ticket by PNR, no names |
| GET /runs/{runId}/seat-map?classCode | Public | Seats with `occupied` flag |
| GET /admin/occupancy?date | ADMIN | Rows of `v_run_occupancy` |
| POST /admin/bookings/expire-unpaid | ADMIN | Calls `sp_expire_unpaid_bookings` |

## 9. Frontend screens

| Route | Screen |
|---|---|
| /availability/:runId | Class table with availability text; rows link to booking. |
| /book/:runId/:classCode | Pick up to 6 passengers, then go to payment. |
| /my-bookings | Bookings; passengers link to cancellation. |
| /tickets and /tickets/:pnr | PNR search box and the ticket page. |
| /seat-map/:runId/:classCode | Coach-wise grid, occupied seats highlighted. |
| /admin/occupancy | Date filter, occupancy percentage and rank. |

## 10. Test cases

| ID | Objective | Input | Expected | Actual | Screenshot |
|---|---|---|---|---|---|
| TC-01 | Find a run | GET /trains/search CSMT to Pune, tomorrow | 200, runId stored | | |
| TC-02 | Availability, valid and missing run | runId, then 999999 | 200 with `AVL n`; 404 RUN_NOT_FOUND | | |
| TC-03 | Book two passengers | Asha, passengers 1 and 2, SL | 200, 10-digit PNR, total 192.00 | | |
| TC-04 | Counters after booking | GET /availability after TC-03 | Available_CNF reduced by CNF count | | |
| TC-05 | Passenger of another user | passengerIds [4] | 403 PASSENGER_NOT_OWNED | | |
| TC-06 | Seven passengers | 7 ids | 400 VALIDATION_ERROR or TOO_MANY_PASSENGERS | | |
| TC-07 | Wrong station order, missing run | Pune to CSMT; runId 999999 | 400 INVALID_STATIONS; 404 RUN_NOT_FOUND | | |
| TC-08 | No login | POST /bookings without token | 401 UNAUTHORIZED | | |
| TC-09 | My bookings and details | /bookings/my; /bookings/{id} as owner, admin, operator | PNR listed; 200, 200, 403 | | |
| TC-10 | Ticket lookup, known and unknown PNR | /tickets/{pnr}; 0000000000 | 200, no names; 404 NOT_FOUND | | |
| TC-11 | Seat map | GET seat-map, SL | 200, booked seats occupied | | |
| TC-12 | Admin occupancy and expiry | Admin, then passenger; minutes 30 | 200 and expiredCount; 403 FORBIDDEN | | |
| TC-13 | Two-session lock | Section 7 steps | Session 2 waits, then continues | | |
| TC-14 | Last-seat race | Two sessions, one seat | One CNF, one RAC, no duplicate seat | | |
| TC-15 | WL full | Fill WL to Max_WL, book again | BOOKING_CLOSED_WL_FULL | | |

## 11. Integration points with other groups

- **G1:** `train_run`, `seat`, `coach_type`, `station` and `route_stop` are read. `fn_distance_km` and `fn_departure_datetime` are used by the booking procedure. `trg_run_init_inventory` sits on G1's `train_run` but writes only to G3's table. The search screen sends users to `/availability/:runId`.
- **G2:** `app_user` and `passenger` are read. `fn_effective_concession` decides SENIOR, CHILD, GOVT or SOLDIER. The JWT user id is used for ownership checks.
- **G4:** `fn_base_fare` and `fn_net_fare` calculate fares. After booking, the user goes to `/payment/:bookingId`. `trg_payment_confirm` sets the booking CONFIRMED. `sp_cancel_ticket` updates G3 rows and calls `sp_promote_rac_wl`.
- **G5:** `v_popular_routes` counts non-EXPIRED bookings; revenue reports use `booking.From_Station_ID`.

## 12. Assumptions and limitations

- A seat is held for the whole run, not only the booked part of the journey, so it is not re-sold after a passenger leaves early.
- The lowest free seat is chosen automatically; users cannot pick a berth. RAC and WL passengers have no seat until promoted.
- Unpaid bookings expire only when an admin calls the expire endpoint. No scheduler is included.
- The Postman collection uses tomorrow's date, so runs must exist for it (seed runs cover 15 days).
- Postman assumes a missing run returns 404 `RUN_NOT_FOUND` for availability and seat map, and accepts HTTP 200 or 201 for POST requests. Adjust if the final code differs.
- This report follows the contract; update it if the final code differs.
