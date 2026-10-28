# Viva Preparation: National Railway Reservation & Management System

This file has **12 likely questions for each of the five modules** and **8 questions about the whole
project**, each with a short, correct answer taken from the project design. Read your own module's
section first, then the whole-project section, then skim the other modules so that you can follow
questions that cross module borders.

**How to answer in a viva**

1. Answer in two or three sentences first, then add detail only if asked.
2. Give a concrete example from the project (a table, a procedure, a number from the seed data).
3. If you do not know, say what you do know and where in the code the answer is. Never invent.
4. Be ready to open the file and point at the lines: the examiner will ask "show me".

**Contents**

- [G1 Train, Station & Route](#g1-train-station--route)
- [G2 Passenger & User](#g2-passenger--user)
- [G3 Reservation & Seat](#g3-reservation--seat)
- [G4 Payment, Cancellation & Refund](#g4-payment-cancellation--refund)
- [G5 Railway Operations & Analytics](#g5-railway-operations--analytics)
- [Whole-project questions](#whole-project-questions)

**Quick facts to remember**

| Fact | Value |
|------|-------|
| Database / tables | `railway_db`, 32 tables in 5 groups (10 + 7 + 5 + 7 + 3) |
| Seed | 9 stations, 3 routes, 4 trains, 5 users, 8 passengers; runs for today + 14 days |
| Booking | 1 to 6 passengers per PNR; PNR is 10 digits |
| Inventory | RAC limit = 10 % of seats, waiting list limit = 20 % of seats (rounded) |
| Refund slab | 48 h or more: 10 % deduction; 12 to 48 h: 25 %; 4 to 12 h: 50 %; under 4 h: 100 % |
| Lock order | seat_inventory, then booking, then booking_passenger, then seat_allocation / payment |
| Security | BCrypt passwords, JWT HS256 (120 minutes), roles PASSENGER / ADMIN / OPERATOR, OTP valid 5 minutes |
| Lock-out | 5 failed logins lock the account for 15 minutes |

---

## G1 Train, Station & Route

**G1-Q1. Why is `route` a separate table from `train`, and what is `route_stop`?**
A route is a fixed path of stations; several trains can run on the same path (trains 11001 and 12002 both
use route 1), so the path is stored once and each train points to it with `Route_ID`. A station can be on
many routes and a route has many stations, which is a many-to-many relationship. `route_stop` is the
associative table that resolves it, and it carries the facts about the visit: order (`Stop_Seq`),
times, `Day_Offset` and distance from the source.

**G1-Q2. What does 3NF mean, and is `route_stop` in 3NF?**
A table is in third normal form when it is in 2NF and every non-key attribute depends on the key, the whole
key, and nothing but the key (no transitive dependency). In `route_stop` the times, `Day_Offset` and
`Distance_From_Source_Km` describe the stop itself, so they depend on the key. The station's name and city
are not stored there; they live in `station` and are reached through `Station_ID`. Storing them in
`route_stop` would create the transitive dependency `Route_Stop_ID -> Station_ID -> Station_Name`.

**G1-Q3. Why are there two unique constraints, `UNIQUE(Route_ID, Stop_Seq)` and `UNIQUE(Route_ID, Station_ID)`?**
The first guarantees that two stops cannot take the same position on a route, so the order is unambiguous.
The second guarantees that a station appears only once on a route (no loops), which keeps "from station" and
"to station" unambiguous for fares and search. Both are also candidate keys of the table.

**G1-Q4. What is `Day_Offset` and why is it needed?**
Times in `route_stop` are only times of day. A train that leaves Mumbai at 18:00 and reaches Nagpur at 07:30 the
next morning needs to say which day that arrival is on. `Day_Offset` is the number of days since the start of the
journey (0 to 3). The real date and time of a stop is `Journey_Date + Day_Offset days + time`.

**G1-Q5. What does `fn_departure_datetime` return and why is it declared `READS SQL DATA`?**
It returns the real departure `DATETIME` of a run at a station: journey date plus day offset plus departure
time (the arrival time if the stop has no departure time, i.e. the last stop). It returns NULL if the station is
not on the route. It runs a SELECT on `train_run`, `train` and `route_stop`, so it must be declared
`READS SQL DATA`. It is used by booking (is the train already gone?) and by cancellation (hours before departure).

**G1-Q6. How does `fn_distance_km` work and why is the distance stored as "from source" instead of per segment?**
Each stop stores its cumulative distance from the source. The distance between any two stops is the absolute
difference of their two values, one lookup per stop. With per-segment distances we would have to add up all
segments between the two stops for every query. The result feeds `fn_base_fare`, so it directly decides the price.

**G1-Q7. What is `v_train_stop_pairs` and how does train search use it?**
It is a view that joins `route_stop` with itself on the same route where `from.Stop_Seq < to.Stop_Seq`, and joins the
active trains of that route. Every row is one possible journey (train, from station, to station) with times and
distance. The search endpoint joins this view to `train_run` for the chosen date and calls
`fn_journey_duration_min`. The condition `from.Stop_Seq < to.Stop_Seq` is what makes searches direction-aware.

**G1-Q8. What does `sp_add_coaches_generate_seats` do and why generate seats?**
For a train and a coach type it adds N coaches, numbers them per class (S1, S2 for sleeper, B1 for 3A, A1 for 2A,
H1 for 1A, C1 for chair car) and creates `Seats_Per_Coach` seats in each, with a berth type pattern per class
(for example LB, MB, UB, LB, MB, UB, SL, SU for sleeper). It runs in one transaction, so a train never ends up
with half a coach. Real `seat` rows are needed because a confirmed passenger gets a specific seat in `seat_allocation`.

**G1-Q9. Why separate `train_schedule` and `train_run`, and how does `sp_generate_train_runs` work?**
`train_schedule` is the weekly pattern (which weekdays a train runs); `train_run` is one dated trip of a train, and
all booking, status and revenue data hang on a run. The procedure loops over a date range, computes the ISO
weekday as `WEEKDAY(date) + 1` (Monday = 1), and inserts a run only if the schedule has that day and no run exists
yet, so it can be run again safely. It rejects a range longer than 60 days or with the end before the start.

**G1-Q10. What do `trg_route_stop_bi` and `trg_route_stop_audit` do, and why is one BEFORE and one AFTER?**
`trg_route_stop_bi` (BEFORE INSERT) raises `VALIDATION_ERROR` when a stop has both times and the departure is
earlier than the arrival; a BEFORE trigger is right for validation because it stops the row before it is written.
`trg_route_stop_audit` (AFTER UPDATE) copies the old and new times into `route_stop_audit` when a time changes; an
AFTER trigger is right for logging because the update has already succeeded.

**G1-Q11. Which indexes did you create and why?**
Besides the primary and unique keys, `route_stop` has an index on `(Station_ID, Route_ID)` to find routes that pass
through a station, and `train_run` has an index on `Journey_Date` to list all runs of a day. The unique key
`(Train_ID, Journey_Date)` on `train_run` also prevents a train from having two runs on the same day. An index
speeds up reads at the price of slower writes and more storage, so only columns used in joins and filters get one.

**G1-Q12. What happens in the database when a `train_run` row is inserted, and why must coaches exist first?**
Two AFTER INSERT triggers fire on `train_run`: G3's `trg_run_init_inventory` creates one `seat_inventory` row per
class of the train, and G5's `trg_run_init_status` creates the `train_run_status` row (SCHEDULED, 0 delay). The
inventory trigger counts the train's coaches to compute `Total_Seats`, so if no coaches exist yet it would create
nothing. That is why the seed script generates coaches first and runs afterwards.

---

## G2 Passenger & User

**G2-Q1. Why are `app_user` and `passenger` two tables?**
`app_user` is the login account (email, password hash, roles); `passenger` is a person who travels. One user can
book for several people (Asha books for herself, her father and her child), and each traveller has their own date of
birth, gender and concession. Fare concessions depend on the passenger, not on the account holder, so they must be
modelled separately.

**G2-Q2. How are roles stored, and what does `v_user_account` show?**
`role` holds PASSENGER, ADMIN and OPERATOR. `user_role` is the associative table with the composite primary key
`(User_ID, Role_ID)`, so a user can have several roles but never the same role twice. `v_user_account` joins the
tables and uses `GROUP_CONCAT` with `GROUP BY` to show all roles of a user in one comma-separated column.

**G2-Q3. Why do you store a BCrypt hash and not the password?**
If the database leaks, plain passwords would be exposed. BCrypt is a one-way function: it cannot be reversed. It adds
a random salt to every hash (the same password gives different hashes) and has a configurable cost factor that makes
brute-force slow (`$2a$10$` means cost 10). At login the backend calls `matches(rawPassword, hash)`. The hash is
created in Java and passed to `sp_register_user`, so the database procedure never sees the plain password.

**G2-Q4. How is a JWT validated on every request?**
The token has three parts: header, claims (sub = user id, email, roles, expiry) and a signature made with HS256, an
HMAC-SHA256 over header and claims with the secret `app.jwt.secret`. The JWT filter reads the `Authorization: Bearer`
header, recomputes the signature with the server's secret, checks the expiry, and then puts the user and roles
(as `ROLE_<name>`) into the security context. A tampered token has a wrong signature; a token from a different
secret is rejected, which is why a changed `JWT_SECRET` causes 401 after a restart.

**G2-Q5. How does role-based access control (RBAC) work here?**
Roles are read from the token and turned into authorities such as `ROLE_ADMIN`. The security configuration says that
`/api/v1/admin/**` needs ADMIN and that a few read-only paths are public; everything else needs a login. Controllers
add `@PreAuthorize` where it is finer, for example `hasAnyRole('OPERATOR','ADMIN')` for updating train status. A
logged-in user without the right role gets 403 FORBIDDEN, a missing or bad token gets 401.

**G2-Q6. How does the account lock-out work?**
After every login attempt the backend calls `sp_record_login_attempt`. It writes a row to `login_audit`. For a
failed attempt of an existing user it increases `Failed_Login_Count`; when the count reaches 5 it sets
`Locked_Until = NOW() + 15 minutes` and resets the count to 0. A successful login resets the count and clears the
lock. While `Locked_Until` is in the future, login returns `ACCOUNT_LOCKED` (HTTP 423) even before the password is checked.

**G2-Q7. How does the OTP (2FA) work, and why is the OTP stored hashed?**
The backend generates a random OTP, stores only a hash of it (`Otp_Hash`) in `otp_challenge` with the purpose (LOGIN or
PAYMENT), the expiry (5 minutes) and `Is_Used = 0`, and gives the user a `challengeId`. To verify, the user sends the
challenge id and the OTP; the code is valid only if it matches the hash, is not expired and is not used, and it is then
marked used (single use). Hashing means a database reader cannot read live OTPs. With `app.auth.dev-mode=true` the OTP
is returned as `devOtp` so demos work without SMS or email.

**G2-Q8. What do `fn_age_category` and `fn_effective_concession` do, and why are they NOT DETERMINISTIC?**
`fn_age_category` returns CHILD (under 12), SENIOR (60 or over) or ADULT from the date of birth. `fn_effective_concession`
returns SENIOR or CHILD when the age says so, otherwise the concession the passenger declared (NONE, GOVT, SOLDIER).
Both use `CURDATE()`, so the same input gives different results on different days: that makes them NOT DETERMINISTIC
(and `NO SQL` because they read no table). Deriving the concession from the date of birth means it can never be out of date.

**G2-Q9. Why is the date-of-birth check a trigger and not a `CHECK` constraint?**
The rule is "date of birth must not be in the future", which needs `CURDATE()`. MySQL does not allow non-deterministic
functions such as `CURDATE()` or `NOW()` in `CHECK` constraints. `trg_passenger_bi` (BEFORE INSERT) compares
`Date_Of_Birth` with `CURDATE()` and raises `VALIDATION_ERROR`.

**G2-Q10. What are `login_audit` and `user_role_audit` for, and why do they have no foreign key?**
They are audit trails. `login_audit` records every login attempt with the email, success flag and IP, including
attempts for emails that do not exist, so `User_ID` can be NULL and a foreign key would not fit. `user_role_audit`
records every GRANT and REVOKE, written by the triggers `trg_user_role_ai` and `trg_user_role_ad`. An audit row must
survive even if the user or role is changed or removed later, so it is not tied by a foreign key.

**G2-Q11. What does `sp_register_user` do and why is it a transaction?**
It inserts the `app_user` row and then a `user_role` row with the PASSENGER role. If the second insert failed, we
would have an account without a role; so both inserts are in one transaction with an exit handler that rolls back.
A duplicate email is caught as `EMAIL_EXISTS` (the email column is unique). The result set is the new `User_ID`.

**G2-Q12. Why can a passenger not be deleted if used in a booking, and how is ownership enforced?**
`booking_passenger` has a foreign key to `passenger`, so deleting a passenger with bookings would orphan them; the API
reports `PASSENGER_IN_USE` (409) instead. Ownership: every passenger endpoint only touches rows whose `User_ID` is the
logged-in user (id taken from the JWT, never from the request body), otherwise `NOT_OWNER` (403), and the booking
procedure checks the same with `PASSENGER_NOT_OWNED`.

---

## G3 Reservation & Seat

**G3-Q1. Why is `seat_inventory` kept per run and per class?**
Availability is different for every dated run of a train (the 10 May train and the 11 May train have separate seats) and
for every class (sleeper and 3A have different capacities). So the unique key is `(Run_ID, Class_Code)`. The row holds
counters (`Available_CNF`, `RAC_Count`, `WL_Count`) and limits (`Max_RAC`, `Max_WL`), so availability is read from one
row instead of counting thousands of seat rows each time, and the same row is what we lock when booking.

**G3-Q2. Why are the counters changed only by triggers?**
So that the arithmetic exists in exactly one place. Procedures only change `booking_passenger.Status` (insert a
passenger as CNF, update RAC to CNF, and so on) and the triggers `trg_dec_inventory` and
`trg_adjust_inventory_on_status` adjust the counters in the same transaction. Whatever code or manual SQL changes a
status, the counters cannot drift, and nobody can forget to update them or update them twice.

**G3-Q3. What does `SELECT ... FOR UPDATE` do?**
It reads rows and locks them (exclusive row locks in InnoDB) until the transaction commits or rolls back. Another
transaction that tries to lock or modify the same row must wait. In `sp_book_ticket` the inventory row of the run and
class is locked first, so two users booking the last seat are serialised: the second one waits, then sees the counters
already changed and gets RAC or WL instead of the same seat.

**G3-Q4. Walk through `sp_book_ticket`.**
(1) Validate: 1 to 6 passengers, run exists, both stations on the route with from before to, train not yet departed.
(2) Start the transaction and lock the inventory row. (3) Generate a unique PNR with `fn_generate_pnr`. (4) Insert the
booking as PENDING_PAYMENT. (5) For each passenger: check ownership, compute the concession, base fare and net fare
with SQL functions, decide CNF if `Available_CNF > 0`, else RAC if the RAC limit is not reached, else WL; insert the
`booking_passenger` row (the triggers update the counters) and, for CNF, allocate the lowest free seat. (6) Update the
booking's total fare. (7) Commit. Any error rolls everything back.

**G3-Q5. How do you prevent two people from getting the same seat?**
Three layers. First, the inventory row lock serialises bookings of the same run and class. Second, the lowest free seat is
chosen while holding that lock, so two transactions never pick the same seat. Third, the database itself has
`UNIQUE(Run_ID, Seat_ID)` on `seat_allocation`, so even a bug in the procedure cannot insert a double allocation: the
insert would fail and the whole booking would roll back.

**G3-Q6. How does RAC to confirmed promotion work?**
When a confirmed seat is freed (cancellation or expiry) `sp_promote_rac_wl` runs. It locks the inventory row and
repeats: while `Available_CNF > 0` and an RAC passenger exists, the oldest RAC passenger (lowest
`Booking_Passenger_ID`) becomes CNF and gets the lowest free seat; then while `RAC_Count < Max_RAC` and a WL
passenger exists, the oldest WL passenger moves to RAC. It only updates statuses and inserts `seat_allocation` rows;
the trigger `trg_adjust_inventory_on_status` moves the counters. It returns the number of promotions.

**G3-Q7. What is `fn_availability_text` and how is `v_seat_availability` built?**
The function turns counters into the text a passenger knows: `AVL n` when confirmed seats are left, otherwise
`RAC k` (the position the next passenger would get) when the RAC limit is not reached, otherwise `WL k`, otherwise
`REGRET`. It is DETERMINISTIC because the result depends only on its arguments. `v_seat_availability` joins
`seat_inventory`, `train_run` and `train` and adds the function result as `Availability_Text`.

**G3-Q8. What does `trg_block_if_wl_full` do and why BEFORE INSERT?**
When a passenger is inserted with status WL and the waiting list is already at `Max_WL`, the trigger raises
`BOOKING_CLOSED_WL_FULL`. It must be BEFORE INSERT so that the row is refused before it is written and before the
AFTER trigger increments the counter. Because the error is raised inside `sp_book_ticket`, the exit handler rolls the
whole booking back, so no half-created booking remains. The table `CHECK` on `WL_Count <= Max_WL` is a second guard.

**G3-Q9. Which status changes does `trg_adjust_inventory_on_status` handle?**
CNF to CANCELLED: `Available_CNF + 1`. RAC to CANCELLED: `RAC_Count - 1`. WL to CANCELLED: `WL_Count - 1`. RAC to CNF:
`RAC_Count - 1` and `Available_CNF - 1`. WL to RAC: `WL_Count - 1` and `RAC_Count + 1`. It also inserts a row in
`booking_status_history` with old and new status, which gives a full audit of how a ticket moved.

**G3-Q10. Why does `sp_promote_rac_wl` not start its own transaction?**
It is a helper called inside another procedure's transaction (the cancellation in G4 and the expiry in G3). In MySQL,
`START TRANSACTION` inside an open transaction silently commits the outer one, which would break atomicity: the
cancellation could be committed while the promotion fails. As a helper it has no transaction control and no result
set; it reports the number of promotions through an OUT parameter, and the caller holds the lock.

**G3-Q11. What is `sp_expire_unpaid_bookings` for?**
A booking waits in PENDING_PAYMENT until it is paid. An abandoned booking would block seats for ever. The procedure
finds bookings older than N minutes that are still unpaid and, in a separate transaction for each one, cancels the
passengers, deletes their seat allocations, calls `sp_promote_rac_wl` so waiting passengers move up, and marks the
booking EXPIRED. It returns the number of expired bookings; an admin triggers it through an endpoint.

**G3-Q12. What does `v_run_occupancy` show and what is `PARTITION BY` doing?**
It shows, for each run and class, the booked seats (`Total_Seats - Available_CNF`), the occupancy percentage rounded to
one decimal, and `Occupancy_Rank = RANK() OVER (PARTITION BY Journey_Date ORDER BY Occupancy_Pct DESC)`. The window
function ranks the busiest run and class of each day separately, because `PARTITION BY` restarts the ranking for every
journey date, while every row stays in the result (unlike `GROUP BY`).

---

## G4 Payment, Cancellation & Refund

**G4-Q1. How is a fare calculated?**
`fn_base_fare(class, km)` returns the larger of `ROUND(km x Base_Fare_Per_Km, 2)` and `Min_Fare` from `fare_rule`.
`fn_net_fare(base, concession)` applies the percentage from `concession_rule`. Example: Mumbai CSMT to Pune is 192 km;
in 3A, 192 x 1.45 = 278.40, which is below the minimum of 300, so the base fare is 300. For a GOVT passenger
(25 % off) the net fare is 225.00. The same functions are used for the quote and the booking, so the two always agree.

**G4-Q2. How is the refund deduction decided?**
`fn_refund_deduction_pct(hours)` picks the `refund_rule` row where `Min_Hours_Before <= hours` and the hours are below
`Max_Hours_Before` (NULL means no upper limit): 48 h or more 10 %, 12 to 48 h 25 %, 4 to 12 h 50 %, under 4 h 100 %. If
no row matches it returns 100. Example: a 225.00 ticket cancelled 30 hours before departure: 25 % = 56.25 deducted,
168.75 refunded.

**G4-Q3. What happens at exactly 48 hours, and why is `Max_Hours_Before` nullable?**
Exactly 48 hours falls in the "48 or more" slab (10 %), because the 12-to-48 slab is `hours < 48`. The lowest slab starts
at 0; a cancellation after departure (negative hours) is refused with `CANCEL_NOT_ALLOWED`. The top slab has no upper
limit, which is expressed with NULL in `Max_Hours_Before`.

**G4-Q4. Walk through `sp_cancel_ticket`.**
(1) Check that the passenger row exists, belongs to the user and is not already cancelled, and compute the hours to
departure with `fn_departure_datetime`; negative means `CANCEL_NOT_ALLOWED`. (2) Start the transaction, lock the
inventory row, then the passenger row, and re-check the status. (3) Compute the deduction and refund; an unpaid booking
gets no refund. (4) Insert the cancellation, set the status CANCELLED, delete the seat allocation, insert the refund
for paid tickets. (5) Call `sp_promote_rac_wl`. (6) If all passengers are cancelled, mark the booking CANCELLED.
(7) Commit. It returns the refund and the number of promoted passengers.

**G4-Q5. Why does the promotion run inside the cancellation transaction?**
Cancelling frees a seat and promoting uses it. If they were separate transactions, a crash or another booking could slip
in between: the seat might be free while a waiting passenger stays waiting, or a new booking could take it. Doing
both in one transaction, under the inventory lock, makes "cancel + promote" atomic and fair (oldest first).

**G4-Q6. Describe the payment flow.**
After booking, the user asks for a payment OTP and sends it with the order request. `sp_create_payment` checks that the
booking exists, is owned by the user and is PENDING_PAYMENT, and inserts a payment with the booking's total as the
amount and status CREATED. After the gateway answers, `sp_confirm_payment` sets SUCCESS or FAILED and the paid time; the
trigger `trg_payment_confirm` then sets the booking to CONFIRMED when the payment became SUCCESS.

**G4-Q7. How do you know a Razorpay payment is genuine?**
The browser's "payment succeeded" message can be forged, so the backend verifies the signature: it computes
HMAC-SHA256 of `orderId|paymentId` with the Razorpay key secret and compares it with the signature sent by the client.
Only the real gateway (and our server) knows the secret, so a matching signature proves that the payment was made. The
secret stays on the server and in environment variables, never in the front end or in Git.

**G4-Q8. What is the difference between MOCK and RAZORPAY mode?**
`app.payment.mode=MOCK` creates an order id like `MOCK_<uuid>` and the endpoint `/payments/mock-confirm` confirms a
payment without any external call, so the system can be demonstrated offline. In RAZORPAY mode a real test-mode order is
created with the key id and secret, and the payment must be confirmed through `/payments/verify` with a valid signature.
Both modes use the same procedures and tables.

**G4-Q9. Why is an OTP needed for payments, and where is it checked?**
It is a second factor: a stolen token alone is not enough to start a payment. With `app.auth.require-payment-otp=true`,
the order endpoint verifies the OTP (purpose PAYMENT, 5 minutes, single use) through the `OtpVerifier` interface that G2
implements. The interface keeps G4 independent from G2's internals.

**G4-Q10. What does `trg_fare_audit` do, and what does `USER()` return?**
After an update of `fare_rule` that changes the rate per km or the minimum fare, the trigger inserts a row in
`fare_audit_log` with old and new values and `Changed_By = USER()`. A trigger cannot be bypassed by a forgotten line of
application code. `USER()` returns the MySQL account that ran the statement (for example `root@localhost`), not the
application user who logged in.

**G4-Q11. Why is there a trigger `trg_refund_check` as well as a `CHECK`?**
`CHECK (Refund_Amount >= 0)` stops negative refunds, and the BEFORE INSERT trigger raises `REFUND_EXCEEDS_FARE` when the
refund is larger than the original fare, which compares two columns with a clear business error code. They are two
layers of defence: even if the procedure had a bug, the database refuses to pay out more than was paid.

**G4-Q12. Why must the cancellation service method not be `@Transactional`?**
`sp_cancel_ticket` manages its own transaction (`START TRANSACTION ... COMMIT`, with a rollback handler). If Spring wrapped
the call in another transaction, the `START TRANSACTION` inside the procedure would implicitly commit the outer one, so the
two transaction scopes would not mean what the code says. So services that call such a procedure are plain methods and the
procedure is the single owner of the transaction.

---

## G5 Railway Operations & Analytics

**G5-Q1. What is `train_run_status` and why is its primary key also a foreign key?**
It holds the live state of one run: status, current station, delay and last reason. It has a one-to-one relationship with
`train_run`, so `Run_ID` is both the primary key and a foreign key. A row is created automatically by the trigger
`trg_run_init_status` when a run is inserted, so the status always exists (SCHEDULED, 0 minutes delay).

**G5-Q2. What does `trg_status_flag` do and why BEFORE UPDATE?**
Before a status row is updated, if the new delay is 15 minutes or more and the status is SCHEDULED or ON_TIME, it changes
the status to DELAYED; if the delay is 0 and the status is DELAYED, it changes it to ON_TIME. Only a BEFORE trigger can
change the values that are about to be written (`NEW.Status`), so the operator cannot leave a 40-minute delay marked
ON_TIME.

**G5-Q3. What does `trg_delay_log` do and why AFTER UPDATE?**
When `Delay_Minutes` has changed, it inserts a row in `delay_log` with the run, current station, new delay and reason.
It is AFTER UPDATE because it only records history once the update has really happened. The log feeds the delay reports,
and has an index on `Run_ID` for fast lookups.

**G5-Q4. What is `fn_delay_minutes` and why `GREATEST(..., 0)`?**
It returns the delay in minutes between the scheduled and actual time: `GREATEST(TIMESTAMPDIFF(MINUTE, scheduled, actual), 0)`.
A train that arrives early has a negative difference, but an early train is not "late by minus 5", so the result is cut
at 0. The function is DETERMINISTIC because it uses only its arguments.

**G5-Q5. Why have both the view `v_station_daily_revenue` and the table `station_daily_revenue`?**
The view calculates revenue live from payments (JOIN and GROUP BY), so it is always current but recomputed on every read.
The table is a stored snapshot that `sp_generate_daily_revenue` fills for one date with `INSERT ... ON DUPLICATE KEY UPDATE`,
using the unique key `(Station_ID, Revenue_Date)`. Running the procedure again for the same date updates the rows instead
of duplicating them. Revenue is counted per origin station from SUCCESS payments, with `Ticket_Count = COUNT(DISTINCT Booking_ID)`.

**G5-Q6. What is the difference between `RANK` and `DENSE_RANK`?**
Both give equal values the same rank, but `RANK` leaves gaps after ties and `DENSE_RANK` does not. For booking counts
10, 10, 7: `RANK` gives 1, 1, 3 and `DENSE_RANK` gives 1, 1, 2. `v_popular_routes` uses `RANK() OVER (ORDER BY Booking_Count DESC)`,
so two equally popular routes share rank 1 and the next one is rank 3, like positions in a race. (`ROW_NUMBER` would break ties
arbitrarily.)

**G5-Q7. What is a window function and how is it different from `GROUP BY`?**
`GROUP BY` collapses rows into one row per group. A window function (`OVER (...)`) calculates a value across a set of related
rows but keeps every row. In `v_popular_routes` we first group bookings per route and then rank the grouped rows with
`RANK() OVER`; in `v_run_occupancy` `PARTITION BY Journey_Date` restarts the rank for every day.

**G5-Q8. What does `v_delay_metrics` show, and what is the difference between `WHERE` and `HAVING`?**
Per train: total runs, delayed runs, average delay (rounded to one decimal) and maximum delay, using `COUNT`, `AVG` and `MAX`
with `GROUP BY` train. `WHERE` filters rows before grouping; `HAVING` filters groups after aggregation. The delayed-trains
report uses `GROUP BY` train `HAVING AVG(Delay_Minutes) > threshold`, which is impossible with `WHERE` because the average
does not exist until the rows are grouped.

**G5-Q9. How does the "top stations" report use a sub-query?**
It sums the revenue per station and keeps only the stations whose total is higher than the average per-station revenue. The
average is calculated by a sub-query (a scalar sub-query that returns one number) inside the `HAVING` or `WHERE`
comparison. This is a non-correlated sub-query: it is executed once, independent of the outer row.

**G5-Q10. Why is the operations event log in MongoDB?**
Events (who changed which run, new status, delay, reason, when) are append-only, written often, never joined or updated, and
may get new fields later. A document store fits that: no fixed schema and no migrations. It also keeps log traffic away from
the transactional MySQL tables. It is optional: with `app.mongo.enabled=false` or when MongoDB is down, the status update
still succeeds and the error is only logged; the events endpoint then returns an empty list.

**G5-Q11. Who may call which operations endpoint?**
The running-status board (`GET /ops/status`) is PUBLIC so passengers can look up delays without logging in. Updating a
train's status (`PUT /ops/status/{runId}`) needs OPERATOR or ADMIN, enforced by `@PreAuthorize("hasAnyRole('OPERATOR','ADMIN')")`.
Everything under `/admin/` (revenue, popular routes, delay reports, dashboard, event log) needs ADMIN.

**G5-Q12. Where does the dashboard get its numbers and does G5 write to other groups' tables?**
`/admin/dashboard/summary` runs read-only aggregate queries (counts and sums) over bookings, payments, runs and status
(total and confirmed bookings, total revenue, active trains, delayed runs today, cancellations today). G5 never writes to
another group's tables; the only cross-group writes in the system are the few listed in the integration mapping, and G5's
own trigger inserts only into G5 tables.

---

## Whole-project questions

**P-Q1. Explain ACID and show where each property appears in the project.**
*Atomicity*: every stored procedure that changes data runs in `START TRANSACTION ... COMMIT` with an exit handler that
rolls back, so a booking is created completely or not at all. *Consistency*: primary keys, foreign keys, unique keys and
`CHECK` constraints plus triggers keep the data valid (for example the counters never go below 0 or above the limits).
*Isolation*: row locks with `SELECT ... FOR UPDATE` make concurrent bookings of the same run and class run one after the
other. *Durability*: once `COMMIT` returns, InnoDB has written the change to its redo log, so a confirmed PNR survives a crash.

**P-Q2. What are the isolation levels, and which one does the project use?**
The SQL levels are READ UNCOMMITTED (dirty reads possible), READ COMMITTED (no dirty reads, but non-repeatable reads),
REPEATABLE READ (same rows read twice give the same data) and SERIALIZABLE (transactions behave as if one after another).
InnoDB's default is REPEATABLE READ, and the project keeps the default. For the critical part, strictness comes from
explicit locking reads: `FOR UPDATE` reads the latest committed data and locks it, so the booking procedure always
decides on the current counters, not on an old snapshot.

**P-Q3. How do you avoid deadlocks?**
A deadlock happens when two transactions each hold a lock that the other needs. We prevent it by always acquiring locks in
the same order everywhere: `seat_inventory`, then `booking`, then `booking_passenger`, then `seat_allocation` / `payment`.
Transactions are also kept short and contain no user interaction. If MySQL still detects a deadlock it rolls back one
transaction (error 1213) and the request can simply be retried.

**P-Q4. Why MySQL and MongoDB together?**
MySQL is the system of record for everything that is structured, related and must be exact: tickets, seats, money. It gives
joins, constraints, triggers and ACID transactions. MongoDB stores the operations event log: flexible documents, append-only,
high write rate, no joins. Using each database for what it is good at is called polyglot persistence. MongoDB is optional,
so the core system never depends on it.

**P-Q5. How was integration managed with Git?**
Before coding, the team fixed a written contract: table and column names, procedures with parameters and result columns,
triggers, views, endpoints, JSON fields, error codes, routes and file paths. Each file had exactly one owner and no group
edited another group's files, so merge conflicts were rare. Work was merged through branches and pull requests, the database
files run in a numeric order (schemas, functions, procedures, triggers, views, seeds), and `scripts/verify-contract.sql`
and the smoke test check that what was merged matches the contract. The integration mapping document records who writes
which table, and it is signed by the group representatives.

**P-Q6. Describe the security design end to end.**
Passwords are stored as BCrypt hashes. After login the server issues a JWT (HS256, 120 minutes) with the user id, email and
roles. Every request sends it as a Bearer token; a filter validates the signature and expiry and sets the roles. Access is
controlled by role (public paths, `/admin/**` only for ADMIN, `@PreAuthorize` for operator endpoints). Repeated failed logins
lock the account for 15 minutes. Payments need a one-time password, and the Razorpay signature is verified on the server.
Secrets such as the JWT secret and the gateway keys come from environment variables, not from the code.

**P-Q7. Trace a booking from the browser to the database.**
The React booking page calls `POST /api/v1/bookings`. The security filter checks the JWT; the controller validates the body
(a record with `jakarta.validation` annotations) and the service calls `CALL sp_book_ticket(...)` through `SqlHelper` with the
passenger ids as a JSON array. Inside the procedure the inventory row is locked, the PNR is generated, the fare is computed by
the functions, the `booking_passenger` rows are inserted and the triggers update the counters; seats are allocated and the
transaction commits. The result (booking id, PNR, total fare) goes back as JSON in the `ApiResponse` envelope; then the user
pays and the ticket shows at `/tickets/<pnr>`.

**P-Q8. Why stored procedures, and how does a database error become an API error?**
Putting the booking and cancellation rules in the database keeps them in one place, close to the data, inside one
transaction, and the same rules apply whoever calls them. It also reduces round trips. For errors, procedures and triggers
raise `SIGNAL SQLSTATE '45000'` with a message like `SEAT_UNAVAILABLE: no seats`; the Java `GlobalExceptionHandler` finds the
`SQLException` in the cause chain, reads the code before the colon, maps it to an HTTP status (for example 409) and returns
`{"success":false,"error":{"code":...,"message":...}}`. The front end shows that message to the user.
