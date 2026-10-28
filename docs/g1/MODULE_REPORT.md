# Module Report: Train, Station & Route Management (Group 1)

National Railway Reservation & Management System, PICT, E&TCE.

## 1 Module overview and scope

Group 1 (G1) owns the static railway data: stations, routes, route stops, trains, weekly schedules, coaches, seats and dated train runs. Every other group depends on it. G3 books seats on a run, G4 prices a ticket from the distance between two stations, and G5 tracks the live status of a run.

In scope: station and route maintenance, train maintenance, coach and seat generation, run generation, the public timetable and the public train search. Out of scope: users, bookings, payments, delays and reports.

The module contains 10 tables, 3 functions, 2 stored procedures, 2 triggers, 2 views, 20 REST endpoints and 6 React screens.

## 2 ER diagram

The Mermaid diagram is in `docs/g1/er.mmd`. In words:

- **station**: a place where trains stop (code, name, city, state).
- **route**: a named path with a source and a destination station.
- **route_stop**: one station on one route, with order (`Stop_Seq`), times, `Day_Offset` and kilometres from the source. It resolves the many-to-many link between route and station.
- **train**: a numbered service that runs on exactly one route.
- **train_schedule**: the weekdays (1 to 7) on which a train runs.
- **coach_type**: a class definition (SL, 3A, 2A, 1A, CC) with seats per coach.
- **train_coach**: a physical coach of a train. It resolves the many-to-many link between train and coach_type.
- **seat**: one seat or berth of a coach.
- **train_run**: one dated journey of a train.
- **route_stop_audit**: history of timetable changes, with no foreign key so history survives deletions.

Cardinalities: route 1:N route_stop; station 1:N route_stop; station 1:N route twice (as source and as destination); route 1:N train; train 1:N train_schedule, train_coach and train_run; coach_type 1:N train_coach; train_coach 1:N seat; route_stop 1:N route_stop_audit (logical link only).

**Why train_run exists.** The timetable (route_stop times) is a weekly template: "train 11001 leaves CSMT at 06:00". A passenger, however, books "11001 on 28 Oct". Seat counts, bookings and delays belong to that single dated journey. If we copied the timetable for every date it would be redundant, and if we stored nothing per date we could not count seats per day. So `train_run` holds one row per train per date (UNIQUE on `Train_ID, Journey_Date`) and `train_schedule` decides which weekdays get a run.

**Why Day_Offset.** Times are plain `TIME` values without a date. Train 12401 leaves Mumbai at 18:00 and reaches Bhusawal at 00:45, which is the next calendar day. `Day_Offset` stores the number of days since the start (0 to 3). The real date and time of a stop is `Journey_Date + Day_Offset days + time`, which is exactly what `fn_departure_datetime` computes.

## 3 Normalization

| Table | 1NF | 2NF | 3NF |
|---|---|---|---|
| station | Atomic columns | Single-column key | Name, city, state depend only on `Station_ID` |
| route | Atomic | Single-column key | Stations referenced by id, names not copied |
| route_stop | One value per cell | Surrogate key; whole key determines times and km | Station details stay in station |
| train | Atomic | Single-column key | Route name is read through `Route_ID` |
| train_schedule | One row per weekday, no repeating group | Only a key plus attributes | No non-key attributes |
| coach_type | Atomic | Single-column key | Seats per coach depends only on the class |
| train_coach | Atomic | Surrogate key | Class details read through `Coach_Type_ID` |
| seat | Atomic | Surrogate key | Berth type depends on the seat only |
| train_run | Atomic | Surrogate key | Train data read through `Train_ID` |
| route_stop_audit | Atomic | Surrogate key | Pure history record |

Weekdays are stored as rows in `train_schedule` instead of seven columns, which keeps the table in 1NF.

**Deliberate denormalization**
1. `Distance_From_Source_Km` is cumulative and could be derived by adding segments. We store it so that a distance is one subtraction and no recursive query is needed.
2. `route.Source_Station_ID` and `Dest_Station_ID` repeat the first and last stop. They make route lists cheap and are protected by a CHECK.
3. `seat` rows are generated from `Seats_Per_Coach`. They are derivable, but G3 needs one row per seat to allocate and to guard double booking.
4. `route_stop_audit` copies old and new times on purpose; it is a log.

## 4 Constraints

| Table | PK | FK | UNIQUE | CHECK | NOT NULL highlights |
|---|---|---|---|---|---|
| station | Station_ID | none | Station_Code | none | Code, name, city, state |
| route | Route_ID | Source, Dest to station | Route_Name | Source <> Dest | Route_Name |
| route_stop | Route_Stop_ID | Route_ID, Station_ID | (Route_ID, Stop_Seq), (Route_ID, Station_ID) | Stop_Seq >= 1, Day_Offset 0..3, km >= 0 | Stop_Seq, Day_Offset, km |
| train | Train_ID | Route_ID | Train_No | Train_No is 5 digits, Train_Type in list | Name, type, Is_Active |
| train_schedule | Schedule_ID | Train_ID | (Train_ID, Day_Of_Week) | Day_Of_Week 1..7 | Day_Of_Week |
| coach_type | Coach_Type_ID | none | Class_Code | Class_Code in list, seats > 0 | Class_Name, seats |
| train_coach | Coach_ID | Train_ID, Coach_Type_ID | (Train_ID, Coach_Number) | none | Coach_Number |
| seat | Seat_ID | Coach_ID | (Coach_ID, Seat_No) | Seat_No > 0, Berth_Type in list | Seat_No, Berth_Type |
| train_run | Run_ID | Train_ID | (Train_ID, Journey_Date) | none | Journey_Date, Created_At |
| route_stop_audit | Audit_ID | none (intentional) | none | none | Route_Stop_ID, Changed_At |

## 5 Indexes and the query each one serves

| Index | Query served |
|---|---|
| UNIQUE (Route_ID, Stop_Seq) | Ordered stops of a route, timetable, stop-pair join |
| UNIQUE (Route_ID, Station_ID) | Find a station on a route (distance and time functions); prevents repeated stations |
| (Station_ID, Route_ID) on route_stop | Which routes pass through a given station |
| UNIQUE (Train_ID, Journey_Date) | One run per date; "does a run exist" check in run generation |
| (Journey_Date) on train_run | Train search by date, daily reports |
| UNIQUE Train_No, Station_Code, Route_Name, Class_Code | Fast lookup and duplicate detection |
| UNIQUE (Train_ID, Day_Of_Week) | Weekday check when generating runs |
| UNIQUE (Train_ID, Coach_Number), (Coach_ID, Seat_No) | Next coach number, seat lookup and allocation |

InnoDB also creates an index for every foreign key.

## 6 Functions, procedures, triggers, views

**fn_distance_km(p_run_id, p_from_station_id, p_to_station_id)** returns INT.
Purpose: kilometres between two stations on the route of a run. Logic: find the train of the run, read `Distance_From_Source_Km` of both stops on its route, return the absolute difference, or NULL if a station is not on the route. Example: `SELECT fn_distance_km(1, 2, 1);` gives `192` (CSMT to Pune).

**fn_departure_datetime(p_run_id, p_station_id)** returns DATETIME.
Purpose: real departure moment at a station. Logic: take `Journey_Date`, add `Day_Offset` days, add `Departure_Time` (or `Arrival_Time` at the last stop). NULL if the station is not on the route. Example: `SELECT fn_departure_datetime(1, 4);` gives the run date with `08:27:00` (Lonavala).

**fn_journey_duration_min(p_run_id, p_from_station_id, p_to_station_id)** returns INT.
Purpose: travel minutes. Logic: departure at "from" as above, arrival at "to" as `Journey_Date + Day_Offset + Arrival_Time`, then `TIMESTAMPDIFF(MINUTE, ...)`. NULL when `Stop_Seq(from) >= Stop_Seq(to)`. Example: `SELECT fn_journey_duration_min(1, 2, 1);` gives `250`; reversing the stations gives `NULL`.

**sp_add_coaches_generate_seats(p_train_id, p_coach_type_id, p_coach_count)**
Purpose: add coaches and their seats. Logic: check train and coach type (NOT_FOUND), start a transaction, find the highest existing number of that class, insert coaches (S1, S2 for SL, B for 3A, A for 2A, H for 1A, C for CC), insert seats 1..n with the berth pattern of the class, commit. Example: `CALL sp_add_coaches_generate_seats(1, 2, 1);` returns `Coaches_Added = 1, Seats_Added = 64` (coach B2).

**sp_generate_train_runs(p_train_id, p_from_date, p_to_date)**
Purpose: create dated runs. Logic: validate train (NOT_FOUND) and range (VALIDATION_ERROR if to < from or more than 60 days); loop over dates; insert a run when the weekday exists in `train_schedule` and no run exists yet. Example: `CALL sp_generate_train_runs(1, CURDATE(), DATE_ADD(CURDATE(), INTERVAL 20 DAY));` returns `Runs_Created = 6` after the seed created 15 runs; calling it again returns `0`.

**trg_route_stop_audit** (AFTER UPDATE on route_stop). Purpose: keep timetable history. Logic: if arrival or departure changed, insert old and new values into `route_stop_audit`. Example: `UPDATE route_stop SET Departure_Time='06:58:00' WHERE Route_ID=1 AND Station_ID=3;` adds a row with `Old_Departure_Time 06:57:00`, `New_Departure_Time 06:58:00`.

**trg_route_stop_bi** (BEFORE INSERT on route_stop). Purpose: stop impossible halts. Logic: when both times are set and departure is earlier than arrival, raise an error. Example: inserting arrival `10:00:00` and departure `09:00:00` fails with `VALIDATION_ERROR: ...`.

**v_train_timetable**: one row per train per stop (train joined to route_stop and station). Example: `SELECT Stop_Seq, Station_Code, Departure_Time FROM v_train_timetable WHERE Train_ID=1 ORDER BY Stop_Seq;` returns 4 rows, CSMT 06:00 to PUNE (no departure).

**v_train_stop_pairs**: self-join of `route_stop` on the same route with `from.Stop_Seq < to.Stop_Seq`, joined to active trains; `Distance_Km` is the difference of the two kilometre values. Example: `SELECT Departure_Time, Arrival_Time, Distance_Km FROM v_train_stop_pairs WHERE Train_ID=1 AND From_Station_ID=2 AND To_Station_ID=1;` returns one row: `06:00:00`, `10:10:00`, `192`.

## 7 Transactions, ACID and locking

Both procedures own their transaction (exit handler with ROLLBACK and RESIGNAL, then START TRANSACTION and COMMIT), so a failure leaves nothing half-written: atomicity. For run generation this includes the rows that G3 and G5 triggers insert for each new run (seat inventory and status), so a run never exists without its inventory. CHECK, UNIQUE and foreign keys keep the data consistent. InnoDB row locks and the default REPEATABLE READ isolation protect concurrent edits, and committed data is durable. G1 never locks seat inventory, so it cannot break the global lock order (inventory, booking, passenger, allocation). The Spring service methods that call these procedures are not `@Transactional`. Creating a route with its stops is plain SQL, so that service method is transactional and the route and all stops are saved together or not at all.

## 8 Backend design and endpoint summary

Package `com.railway.train` has `controller`, `service` and `dto` sub-packages, with class names starting `Station`, `Route`, `Train` or `Coach`. The services use `SqlHelper` (no JPA). Request DTOs are records with validation annotations. Controllers return `ApiResponse<T>` and protect admin methods with `@PreAuthorize("hasRole('ADMIN')")`.

| Endpoint | Access | Purpose |
|---|---|---|
| GET /stations, /routes, /coach-types | Public | Master lists |
| POST, PUT, DELETE /admin/stations | Admin | Maintain stations |
| GET /routes/{id}/stops | Public | Ordered stops |
| POST /admin/routes, PUT /admin/route-stops/{id} | Admin | Create route, edit stop times |
| GET /trains, /trains/{id}, /trains/{id}/timetable, /trains/{id}/coaches | Public | Train data |
| GET /trains/{id}/runs, /runs/{runId} | Public | Dated runs |
| GET /trains/search | Public | Search by stations and date |
| POST, PUT /admin/trains | Admin | Create or update a train and its weekdays |
| POST /admin/trains/{id}/coaches | Admin | Call sp_add_coaches_generate_seats |
| POST /admin/trains/{id}/runs/generate | Admin | Call sp_generate_train_runs |

Errors use the shared envelope, for example `DUPLICATE` (409), `NOT_FOUND` (404) and `FORBIDDEN` (403). The Postman collection `postman/g1.postman_collection.json` calls every endpoint.

## 9 Frontend screens

| Route | Access | Screen |
|---|---|---|
| /trains/search | Public | Search form (from, to, date) and result table |
| /trains | Public | Train list with a name or number filter |
| /trains/:trainId | Public | Timetable with Day_Offset shown as "+1 day" |
| /admin/trains | Admin | Create, edit, add coaches, generate runs |
| /admin/stations | Admin | Station table with add, edit and delete |
| /admin/routes | Admin | Create a route with stops, edit stop times |

## 10 Test cases

| ID | Objective | Input | Expected | Actual | Screenshot |
|---|---|---|---|---|---|
| G1-T01 | Distance function | `fn_distance_km(1,2,1)` | 192 | | |
| G1-T02 | Station not on route | `fn_distance_km(1,2,9)` | NULL | | |
| G1-T03 | Overnight duration | `fn_journey_duration_min` for CSMT to NGP, train 12401 | 810 | | |
| G1-T04 | Seat generation | `CALL sp_add_coaches_generate_seats(1,2,1)` | 1 coach, 64 seats | | |
| G1-T05 | Re-runnable run generation | Call `sp_generate_train_runs` twice | Second call returns 0 | | |
| G1-T06 | Date range limit | Range of 90 days | VALIDATION_ERROR | | |
| G1-T07 | Halt validation trigger | Departure before arrival | VALIDATION_ERROR | | |
| G1-T08 | Audit trigger | Update a departure time | One audit row | | |
| G1-T09 | Search | CSMT to Pune, today | Train 11001, 250 min, 192 km | | |
| G1-T10 | Same station search | from = to | 400 error | | |
| G1-T11 | Duplicate train number | POST 11001 | 409 DUPLICATE | | |
| G1-T12 | Role check | Passenger creates station | 403 FORBIDDEN | | |

## 11 Integration points with other groups

- **G3:** `trg_run_init_inventory` fires on every new `train_run` and builds seat inventory from the coaches, so coaches must exist before runs. `sp_book_ticket` uses `fn_distance_km` and `fn_departure_datetime`, validates stations through `route_stop`, and allocates seats from `seat`.
- **G4:** `fn_distance_km` feeds the fare. Booking calls `fn_base_fare(class, km)`, which returns the larger of `km x Base_Fare_Per_Km` and `Min_Fare`, then `fn_net_fare` applies the concession. Example: CSMT to Pune is 192 km; sleeper is 192 x 0.55 = 105.60, below the minimum, so the base fare is 120.00, and a soldier pays 60.00. `fare_rule` and `seat_inventory` also reference `coach_type.Class_Code`. `sp_cancel_ticket` uses `fn_departure_datetime`.
- **G5:** `trg_run_init_status` also fires on `train_run`, and the live status view joins runs and stations.
- **G2:** the login tokens and the ADMIN role protect all `/admin` endpoints.

## 12 Assumptions and limitations

- Seed run ids start at 1 for train 1; examples assume that.
- Trains, routes and runs cannot be deleted through the API. A train is switched off with `Is_Active`.
- Editing a stop changes times only, not the stop order or the kilometres.
- There are no holidays or special trains; only weekly patterns.
- Distance ignores direction and uses the stored cumulative kilometres.
- Berth patterns are fixed per class.
- Run generation is limited to 60 days per call.
- Expected outputs come from the contract; the student will adjust wording if the final code differs.
