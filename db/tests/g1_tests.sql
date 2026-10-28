-- Task G1.3 | Owner group G1 (Train, Station & Route) | SQL proof tests for G1 functions, procedures, triggers and views (BEFORE / ACTION / AFTER)
--
-- HOW TO RUN
--   * Rebuild the database first (init-db script) so the seed data is in its original state.
--   * MySQL Workbench: double-click "railway_db" in the SCHEMAS panel so it is the default schema,
--     then run this file STATEMENT BY STATEMENT (Ctrl+Enter) in ONE query tab, from the top.
--     User variables (@run_date, @tt and similar) live in the session, so do not switch tabs.
--   * Blocks marked "-- EXPECT ERROR <CODE>" are SUPPOSED to fail: the red error text in the
--     Output panel (for example "Error Code: 1644. VALIDATION_ERROR: Departure time cannot be earlier than arrival time at the same stop") is the proof.
--   * Every block cleans up after itself, so the data is left exactly as found
--     (AUTO_INCREMENT counters of the touched tables are reset as well).
--   * Command line alternative: mysql --force -u root -p railway_db < db/tests/g1_tests.sql
--
-- Block layout:  -- TEST n  /  [-- EXPECT ERROR CODE]  /  [-- FIXTURE]  /  -- BEFORE  /  -- ACTION  /  -- AFTER  /  [-- CLEANUP]

-- =============================================================================
-- SETUP (run once, first)
-- =============================================================================
SET SQL_SAFE_UPDATES = 0;   -- Workbench "safe updates" would block some clean-up DELETEs; restored at the end

-- The seed creates runs for 15 consecutive dates starting on the day it was run.
-- @run_date = first seeded date, so these tests also work on a later day.
SET @run_date = (SELECT MIN(Journey_Date) FROM train_run WHERE Train_ID = 1);
SET @run_t1   = (SELECT Run_ID FROM train_run WHERE Train_ID = 1 AND Journey_Date = @run_date);
SET @run_t2   = (SELECT Run_ID FROM train_run WHERE Train_ID = 2 AND Journey_Date = @run_date);
SET @run_t3   = (SELECT Run_ID FROM train_run WHERE Train_ID = 3 AND Journey_Date = @run_date);
SET @run_t4   = (SELECT Run_ID FROM train_run WHERE Train_ID = 4 AND Journey_Date = @run_date);
SELECT @run_date AS run_date, @run_t1 AS run_train_1, @run_t2 AS run_train_2, @run_t3 AS run_train_3, @run_t4 AS run_train_4;

-- =============================================================================
-- SECTION 0: THE SEED DATA (50_seed_g1.sql)
-- =============================================================================

-- TEST 1: the seed produced the row counts of contract C6 (9 stations, 3 routes, 12 stops, 4 trains, 28 schedule rows, 5 coach types, 19 coaches, 1250 seats, 15 runs per train)
-- BEFORE
SELECT
    (SELECT COUNT(*) FROM station)        AS stations,
    (SELECT COUNT(*) FROM route)          AS routes,
    (SELECT COUNT(*) FROM route_stop)     AS route_stops,
    (SELECT COUNT(*) FROM train)          AS trains,
    (SELECT COUNT(*) FROM train_schedule) AS schedule_rows,
    (SELECT COUNT(*) FROM coach_type)     AS coach_types,
    (SELECT COUNT(*) FROM train_coach)    AS coaches,
    (SELECT COUNT(*) FROM seat)           AS seats,
    (SELECT COUNT(*) FROM train_run)      AS runs;
-- ACTION
SELECT check_name, expected, actual, IF(actual = expected, 'PASS', 'FAIL') AS result
FROM (
    SELECT 'stations'          AS check_name,    9 AS expected, (SELECT COUNT(*) FROM station)        AS actual
    UNION ALL SELECT 'routes',                   3,             (SELECT COUNT(*) FROM route)
    UNION ALL SELECT 'route stops',             12,             (SELECT COUNT(*) FROM route_stop)
    UNION ALL SELECT 'trains',                   4,             (SELECT COUNT(*) FROM train)
    UNION ALL SELECT 'schedule rows (4 x 7)',   28,             (SELECT COUNT(*) FROM train_schedule)
    UNION ALL SELECT 'coach types',              5,             (SELECT COUNT(*) FROM coach_type)
    UNION ALL SELECT 'coaches (4+2+6+7)',       19,             (SELECT COUNT(*) FROM train_coach)
    UNION ALL SELECT 'seats (all trains)',    1250,             (SELECT COUNT(*) FROM seat)
    UNION ALL SELECT 'seats train 11001',      286,             (SELECT COUNT(*) FROM seat s JOIN train_coach c ON c.Coach_ID = s.Coach_ID WHERE c.Train_ID = 1)
    UNION ALL SELECT 'seats train 12002',      156,             (SELECT COUNT(*) FROM seat s JOIN train_coach c ON c.Coach_ID = s.Coach_ID WHERE c.Train_ID = 2)
    UNION ALL SELECT 'seats train 12301',      392,             (SELECT COUNT(*) FROM seat s JOIN train_coach c ON c.Coach_ID = s.Coach_ID WHERE c.Train_ID = 3)
    UNION ALL SELECT 'seats train 12401',      416,             (SELECT COUNT(*) FROM seat s JOIN train_coach c ON c.Coach_ID = s.Coach_ID WHERE c.Train_ID = 4)
    UNION ALL SELECT 'runs train 11001',        15,             (SELECT COUNT(*) FROM train_run WHERE Train_ID = 1)
    UNION ALL SELECT 'runs train 12002',        15,             (SELECT COUNT(*) FROM train_run WHERE Train_ID = 2)
    UNION ALL SELECT 'runs train 12301',        15,             (SELECT COUNT(*) FROM train_run WHERE Train_ID = 3)
    UNION ALL SELECT 'runs train 12401',        15,             (SELECT COUNT(*) FROM train_run WHERE Train_ID = 4)
) t;
-- AFTER  (seats per train and class; 72 SL / 64 3A / 48 2A / 24 1A / 78 CC seats per coach)
SELECT c.Train_ID, ct.Class_Code, COUNT(DISTINCT c.Coach_ID) AS coaches, COUNT(s.Seat_ID) AS seats
FROM train_coach c
JOIN coach_type ct ON ct.Coach_Type_ID = c.Coach_Type_ID
JOIN seat s        ON s.Coach_ID = c.Coach_ID
GROUP BY c.Train_ID, ct.Class_Code
ORDER BY c.Train_ID, ct.Class_Code;

-- TEST 2: the seed coach numbers follow the class prefix + running number rule (S = SL, B = 3A, A = 2A, H = 1A, C = CC)
-- BEFORE
SELECT Train_ID, Coach_ID, Coach_Type_ID, Coach_Number FROM train_coach ORDER BY Train_ID, Coach_ID;
-- ACTION
SELECT t.Train_No, GROUP_CONCAT(c.Coach_Number ORDER BY c.Coach_ID) AS coach_numbers
FROM train t
JOIN train_coach c ON c.Train_ID = t.Train_ID
GROUP BY t.Train_ID, t.Train_No
ORDER BY t.Train_ID;
-- AFTER
SELECT Train_No, coach_numbers,
       IF(coach_numbers = CASE Train_No
                              WHEN '11001' THEN 'S1,S2,B1,C1'
                              WHEN '12002' THEN 'C1,C2'
                              WHEN '12301' THEN 'S1,S2,S3,B1,B2,A1'
                              WHEN '12401' THEN 'S1,S2,S3,B1,B2,A1,H1'
                          END, 'PASS', 'FAIL') AS result
FROM (
    SELECT t.Train_ID, t.Train_No, GROUP_CONCAT(c.Coach_Number ORDER BY c.Coach_ID) AS coach_numbers
    FROM train t
    JOIN train_coach c ON c.Train_ID = t.Train_ID
    GROUP BY t.Train_ID, t.Train_No
) x
ORDER BY Train_ID;

-- =============================================================================
-- SECTION A: FUNCTIONS (fn_distance_km, fn_departure_datetime, fn_journey_duration_min)
-- =============================================================================

-- TEST 3: fn_distance_km gives the km between two stops of the run's route (CSMT -> PUNE on train 11001 = 192 km)
-- BEFORE
SELECT rs.Stop_Seq, s.Station_Code, rs.Distance_From_Source_Km
FROM route_stop rs
JOIN station s ON s.Station_ID = rs.Station_ID
WHERE rs.Route_ID = 1
ORDER BY rs.Stop_Seq;
-- ACTION
SELECT fn_distance_km(@run_t1, 2, 1) AS distance_csmt_to_pune_km;
-- AFTER
SELECT expected, actual, IF(actual <=> expected, 'PASS', 'FAIL') AS result
FROM (SELECT 192 AS expected, fn_distance_km(@run_t1, 2, 1) AS actual) t;

-- TEST 4: fn_distance_km works for middle stops and is direction independent (absolute value): KYN <-> LNL = 124 - 54 = 70 km
-- BEFORE
SELECT rs.Stop_Seq, s.Station_Code, rs.Distance_From_Source_Km
FROM route_stop rs
JOIN station s ON s.Station_ID = rs.Station_ID
WHERE rs.Route_ID = 1 AND s.Station_Code IN ('KYN', 'LNL')
ORDER BY rs.Stop_Seq;
-- ACTION
SELECT fn_distance_km(@run_t1, 3, 4) AS kyn_to_lnl_km, fn_distance_km(@run_t1, 4, 3) AS lnl_to_kyn_km;
-- AFTER
SELECT case_name, expected, actual, IF(actual <=> expected, 'PASS', 'FAIL') AS result
FROM (
    SELECT 'KYN -> LNL'                 AS case_name, 70 AS expected, fn_distance_km(@run_t1, 3, 4) AS actual
    UNION ALL SELECT 'LNL -> KYN (reversed)', 70, fn_distance_km(@run_t1, 4, 3)
    UNION ALL SELECT 'PUNE -> CSMT (reversed)', 192, fn_distance_km(@run_t1, 1, 2)
    UNION ALL SELECT 'PUNE -> HYB on train 12301 (route 2)', 559, fn_distance_km(@run_t3, 1, 9)
) t;

-- TEST 5: fn_distance_km returns NULL when a station is not on the route of the run (edge case, not an error): HYB is not on route 1
-- BEFORE
SELECT rs.Stop_Seq, s.Station_Code FROM route_stop rs JOIN station s ON s.Station_ID = rs.Station_ID WHERE rs.Route_ID = 1 ORDER BY rs.Stop_Seq;
-- ACTION
SELECT fn_distance_km(@run_t1, 2, 9) AS csmt_to_hyb_on_route_1;
-- AFTER
SELECT case_name, actual, IF(actual IS NULL, 'PASS', 'FAIL') AS result
FROM (
    SELECT 'CSMT -> HYB (HYB not on route 1)' AS case_name, fn_distance_km(@run_t1, 2, 9) AS actual
    UNION ALL SELECT 'HYB -> PUNE (HYB not on route 1)', fn_distance_km(@run_t1, 9, 1)
) t;

-- TEST 6: fn_departure_datetime = Journey_Date + Day_Offset days + Departure_Time of the stop (KYN on train 11001 departs 06:57)
-- BEFORE
SELECT Route_Stop_ID, Stop_Seq, Station_ID, Arrival_Time, Departure_Time, Day_Offset FROM route_stop WHERE Route_ID = 1 ORDER BY Stop_Seq;
-- ACTION
SELECT fn_departure_datetime(@run_t1, 3) AS kyn_departure, fn_departure_datetime(@run_t1, 2) AS csmt_departure;
-- AFTER
SELECT case_name, expected, actual, IF(actual <=> expected, 'PASS', 'FAIL') AS result
FROM (
    SELECT 'KYN departure 06:57' AS case_name, TIMESTAMP(@run_date, '06:57:00') AS expected, fn_departure_datetime(@run_t1, 3) AS actual
    UNION ALL SELECT 'CSMT departure 06:00', TIMESTAMP(@run_date, '06:00:00'), fn_departure_datetime(@run_t1, 2)
) t;

-- TEST 7: fn_departure_datetime falls back to Arrival_Time when Departure_Time is NULL (last stop) and adds Day_Offset for after-midnight stops
-- BEFORE
SELECT Route_ID, Station_ID, Stop_Seq, Arrival_Time, Departure_Time, Day_Offset FROM route_stop WHERE Route_ID IN (1, 3) AND (Departure_Time IS NULL OR Day_Offset > 0) ORDER BY Route_ID, Stop_Seq;
-- ACTION
SELECT fn_departure_datetime(@run_t1, 1) AS pune_last_stop_route_1,
       fn_departure_datetime(@run_t4, 6) AS bsl_after_midnight,
       fn_departure_datetime(@run_t4, 7) AS ngp_last_stop_after_midnight;
-- AFTER
SELECT case_name, expected, actual, IF(actual <=> expected, 'PASS', 'FAIL') AS result
FROM (
    SELECT 'PUNE last stop: arrival 10:10 used' AS case_name, TIMESTAMP(@run_date, '10:10:00') AS expected, fn_departure_datetime(@run_t1, 1) AS actual
    UNION ALL SELECT 'BSL departure 00:55 on day +1', TIMESTAMP(DATE_ADD(@run_date, INTERVAL 1 DAY), '00:55:00'), fn_departure_datetime(@run_t4, 6)
    UNION ALL SELECT 'NGP last stop arrival 07:30 on day +1', TIMESTAMP(DATE_ADD(@run_date, INTERVAL 1 DAY), '07:30:00'), fn_departure_datetime(@run_t4, 7)
) t;

-- TEST 8: fn_departure_datetime returns NULL when the station is not on the route (edge case, not an error)
-- BEFORE
SELECT rs.Stop_Seq, s.Station_Code FROM route_stop rs JOIN station s ON s.Station_ID = rs.Station_ID WHERE rs.Route_ID = 1 ORDER BY rs.Stop_Seq;
-- ACTION
SELECT fn_departure_datetime(@run_t1, 9) AS hyb_on_route_1;
-- AFTER
SELECT actual, IF(actual IS NULL, 'PASS', 'FAIL') AS result
FROM (SELECT fn_departure_datetime(@run_t1, 9) AS actual) t;

-- TEST 9: fn_journey_duration_min = minutes from departure at "from" to arrival at "to" (CSMT 06:00 -> PUNE 10:10 = 250; KYN 06:57 -> LNL 08:25 = 88)
-- BEFORE
SELECT Stop_Seq, Station_Code, Arrival_Time, Departure_Time, Day_Offset FROM v_train_timetable WHERE Train_ID = 1 ORDER BY Stop_Seq;
-- ACTION
SELECT fn_journey_duration_min(@run_t1, 2, 1) AS csmt_to_pune_min, fn_journey_duration_min(@run_t1, 3, 4) AS kyn_to_lnl_min;
-- AFTER
SELECT case_name, expected, actual, IF(actual <=> expected, 'PASS', 'FAIL') AS result
FROM (
    SELECT 'CSMT -> PUNE (06:00 to 10:10)' AS case_name, 250 AS expected, fn_journey_duration_min(@run_t1, 2, 1) AS actual
    UNION ALL SELECT 'KYN -> LNL (06:57 to 08:25)', 88, fn_journey_duration_min(@run_t1, 3, 4)
) t;

-- TEST 10: fn_journey_duration_min handles overnight journeys: CSMT -> NGP on train 12401 = 18:00 to 07:30 next day = 810 minutes
-- BEFORE
SELECT Stop_Seq, Station_Code, Arrival_Time, Departure_Time, Day_Offset FROM v_train_timetable WHERE Train_ID = 4 ORDER BY Stop_Seq;
-- ACTION
SELECT fn_journey_duration_min(@run_t4, 2, 7) AS csmt_to_ngp_min;
-- AFTER
SELECT case_name, expected, actual, IF(actual <=> expected, 'PASS', 'FAIL') AS result
FROM (
    SELECT 'CSMT -> NGP (18:00 to 07:30 next day)' AS case_name, 810 AS expected, fn_journey_duration_min(@run_t4, 2, 7) AS actual
    UNION ALL SELECT 'CSMT -> BSL (18:00 to 00:45 next day)', 405, fn_journey_duration_min(@run_t4, 2, 6)
    UNION ALL SELECT 'NK -> NGP (21:20 to 07:30 next day)', 610, fn_journey_duration_min(@run_t4, 5, 7)
    UNION ALL SELECT 'PUNE -> HYB on train 12301 (17:30 to 05:30 next day)', 720, fn_journey_duration_min(@run_t3, 1, 9)
    UNION ALL SELECT 'SUR -> HYB on train 12301 (21:50 to 05:30 next day)', 460, fn_journey_duration_min(@run_t3, 8, 9)
) t;

-- TEST 11: fn_journey_duration_min returns NULL for invalid input (edge case, not an error): reversed direction, same station, station not on the route
-- BEFORE
SELECT Stop_Seq, Station_Code FROM v_train_timetable WHERE Train_ID = 1 ORDER BY Stop_Seq;
-- ACTION
SELECT fn_journey_duration_min(@run_t1, 1, 2) AS pune_to_csmt_reversed,
       fn_journey_duration_min(@run_t1, 2, 2) AS csmt_to_csmt_same_station,
       fn_journey_duration_min(@run_t1, 2, 9) AS csmt_to_hyb_not_on_route;
-- AFTER
SELECT case_name, actual, IF(actual IS NULL, 'PASS', 'FAIL') AS result
FROM (
    SELECT 'PUNE -> CSMT (Stop_Seq from > to)' AS case_name, fn_journey_duration_min(@run_t1, 1, 2) AS actual
    UNION ALL SELECT 'CSMT -> CSMT (Stop_Seq from = to)', fn_journey_duration_min(@run_t1, 2, 2)
    UNION ALL SELECT 'CSMT -> HYB (HYB not on route 1)', fn_journey_duration_min(@run_t1, 2, 9)
) t;

-- =============================================================================
-- SECTION B: PROCEDURES (sp_add_coaches_generate_seats, sp_generate_train_runs)
-- =============================================================================

-- TEST 12: sp_add_coaches_generate_seats adds the requested coaches (S1, S2) and Seats_Per_Coach seats to each (SL: 2 coaches x 72 = 144 seats)
-- FIXTURE (a throw-away train without coaches; it is deleted in CLEANUP)
INSERT INTO train (Train_No, Train_Name, Train_Type, Route_ID, Is_Active) VALUES ('99901', 'TEST TRAIN (delete me)', 'LOCAL', 1, 1);
SET @tt = LAST_INSERT_ID();
-- BEFORE
SELECT @tt AS test_train_id,
       (SELECT COUNT(*) FROM train_coach WHERE Train_ID = @tt) AS coaches_before,
       (SELECT COUNT(*) FROM seat s JOIN train_coach c ON c.Coach_ID = s.Coach_ID WHERE c.Train_ID = @tt) AS seats_before;
-- ACTION   (coach type 1 = SL)
CALL sp_add_coaches_generate_seats(@tt, 1, 2);
-- AFTER
SELECT Coach_Number, Class_Code, Seats_Per_Coach, seats, first_seat_no, last_seat_no,
       IF(seats = Seats_Per_Coach AND first_seat_no = 1 AND last_seat_no = Seats_Per_Coach, 'PASS', 'FAIL') AS result
FROM (
    SELECT c.Coach_ID, c.Coach_Number, ct.Class_Code, ct.Seats_Per_Coach,
           COUNT(s.Seat_ID) AS seats, MIN(s.Seat_No) AS first_seat_no, MAX(s.Seat_No) AS last_seat_no
    FROM train_coach c
    JOIN coach_type ct ON ct.Coach_Type_ID = c.Coach_Type_ID
    JOIN seat s        ON s.Coach_ID = c.Coach_ID
    WHERE c.Train_ID = @tt
    GROUP BY c.Coach_ID, c.Coach_Number, ct.Class_Code, ct.Seats_Per_Coach
) x
ORDER BY Coach_ID;
-- CLEANUP
DELETE s FROM seat s JOIN train_coach c ON c.Coach_ID = s.Coach_ID WHERE c.Train_ID = @tt;
DELETE FROM train_coach WHERE Train_ID = @tt;
DELETE FROM train WHERE Train_ID = @tt;
ALTER TABLE seat AUTO_INCREMENT = 1;
ALTER TABLE train_coach AUTO_INCREMENT = 1;
ALTER TABLE train AUTO_INCREMENT = 1;

-- TEST 13: every class gets its own coach-number prefix (S, B, A, H, C), seat count and berth cycle (first 8 seats shown)
-- FIXTURE
INSERT INTO train (Train_No, Train_Name, Train_Type, Route_ID, Is_Active) VALUES ('99901', 'TEST TRAIN (delete me)', 'LOCAL', 1, 1);
SET @tt = LAST_INSERT_ID();
-- BEFORE
SELECT Coach_Type_ID, Class_Code, Class_Name, Seats_Per_Coach FROM coach_type ORDER BY Coach_Type_ID;
-- ACTION   (coach types: 1 = SL, 2 = 3A, 3 = 2A, 4 = 1A, 5 = CC; one coach of each)
CALL sp_add_coaches_generate_seats(@tt, 1, 1);
CALL sp_add_coaches_generate_seats(@tt, 2, 1);
CALL sp_add_coaches_generate_seats(@tt, 3, 1);
CALL sp_add_coaches_generate_seats(@tt, 4, 1);
CALL sp_add_coaches_generate_seats(@tt, 5, 1);
-- AFTER
SELECT Coach_Number, Class_Code, seats, first_8_berths,
       IF(Coach_Number = CASE Class_Code WHEN 'SL' THEN 'S1' WHEN '3A' THEN 'B1' WHEN '2A' THEN 'A1' WHEN '1A' THEN 'H1' WHEN 'CC' THEN 'C1' END
          AND seats = Seats_Per_Coach
          AND first_8_berths = CASE Class_Code
                                   WHEN 'SL' THEN 'LB,MB,UB,LB,MB,UB,SL,SU'
                                   WHEN '3A' THEN 'LB,MB,UB,LB,MB,UB,SL,SU'
                                   WHEN '2A' THEN 'LB,UB,LB,UB,SL,SU,LB,UB'
                                   WHEN '1A' THEN 'LB,UB,LB,UB,LB,UB,LB,UB'
                                   WHEN 'CC' THEN 'W,M,A,A,M,W,W,M'
                               END, 'PASS', 'FAIL') AS result
FROM (
    SELECT c.Coach_ID, c.Coach_Number, ct.Class_Code, ct.Seats_Per_Coach,
           COUNT(s.Seat_ID) AS seats,
           GROUP_CONCAT(CASE WHEN s.Seat_No <= 8 THEN s.Berth_Type END ORDER BY s.Seat_No) AS first_8_berths
    FROM train_coach c
    JOIN coach_type ct ON ct.Coach_Type_ID = c.Coach_Type_ID
    JOIN seat s        ON s.Coach_ID = c.Coach_ID
    WHERE c.Train_ID = @tt
    GROUP BY c.Coach_ID, c.Coach_Number, ct.Class_Code, ct.Seats_Per_Coach
) x
ORDER BY Coach_ID;
-- CLEANUP
DELETE s FROM seat s JOIN train_coach c ON c.Coach_ID = s.Coach_ID WHERE c.Train_ID = @tt;
DELETE FROM train_coach WHERE Train_ID = @tt;
DELETE FROM train WHERE Train_ID = @tt;
ALTER TABLE seat AUTO_INCREMENT = 1;
ALTER TABLE train_coach AUTO_INCREMENT = 1;
ALTER TABLE train AUTO_INCREMENT = 1;

-- TEST 14: edge case - the coach number is a running number per class, so a second call continues the numbering (S1,S2 then S3, not S1 again)
-- FIXTURE
INSERT INTO train (Train_No, Train_Name, Train_Type, Route_ID, Is_Active) VALUES ('99901', 'TEST TRAIN (delete me)', 'LOCAL', 1, 1);
SET @tt = LAST_INSERT_ID();
CALL sp_add_coaches_generate_seats(@tt, 1, 2);
-- BEFORE
SELECT GROUP_CONCAT(Coach_Number ORDER BY Coach_ID) AS coaches_before FROM train_coach WHERE Train_ID = @tt;
-- ACTION
CALL sp_add_coaches_generate_seats(@tt, 1, 1);
-- AFTER
SELECT coaches, seats, IF(coaches = 'S1,S2,S3' AND seats = 216, 'PASS', 'FAIL') AS result
FROM (
    SELECT GROUP_CONCAT(c.Coach_Number ORDER BY c.Coach_ID) AS coaches,
           (SELECT COUNT(*) FROM seat s2 JOIN train_coach c2 ON c2.Coach_ID = s2.Coach_ID WHERE c2.Train_ID = @tt) AS seats
    FROM train_coach c
    WHERE c.Train_ID = @tt
) x;
-- CLEANUP
DELETE s FROM seat s JOIN train_coach c ON c.Coach_ID = s.Coach_ID WHERE c.Train_ID = @tt;
DELETE FROM train_coach WHERE Train_ID = @tt;
DELETE FROM train WHERE Train_ID = @tt;
ALTER TABLE seat AUTO_INCREMENT = 1;
ALTER TABLE train_coach AUTO_INCREMENT = 1;
ALTER TABLE train AUTO_INCREMENT = 1;

-- TEST 15: sp_add_coaches_generate_seats rejects an unknown train
-- EXPECT ERROR NOT_FOUND
-- BEFORE
SELECT (SELECT COUNT(*) FROM train_coach) AS coaches_before, (SELECT COUNT(*) FROM seat) AS seats_before;
-- ACTION
CALL sp_add_coaches_generate_seats(99999, 1, 1);
-- AFTER   (nothing was added: the procedure rolled back / never started)
SELECT (SELECT COUNT(*) FROM train_coach) AS coaches_after, (SELECT COUNT(*) FROM seat) AS seats_after;

-- TEST 16: sp_add_coaches_generate_seats rejects an unknown coach type and leaves the real train 11001 untouched
-- EXPECT ERROR NOT_FOUND
-- BEFORE
SELECT COUNT(*) AS coaches_of_train_1_before FROM train_coach WHERE Train_ID = 1;
-- ACTION
CALL sp_add_coaches_generate_seats(1, 99999, 1);
-- AFTER
SELECT COUNT(*) AS coaches_of_train_1_after, IF(COUNT(*) = 4, 'PASS', 'FAIL') AS result FROM train_coach WHERE Train_ID = 1;

-- TEST 17: sp_generate_train_runs creates a run only on weekdays that have a train_schedule row (test train runs on ONE weekday, 7-day range => exactly 1 run)
-- FIXTURE (throw-away train without coaches, scheduled only on tomorrow's weekday; deleted in CLEANUP)
INSERT INTO train (Train_No, Train_Name, Train_Type, Route_ID, Is_Active) VALUES ('99902', 'TEST TRAIN (delete me)', 'LOCAL', 1, 1);
SET @tt = LAST_INSERT_ID();
INSERT INTO train_schedule (Train_ID, Day_Of_Week) VALUES (@tt, WEEKDAY(DATE_ADD(CURDATE(), INTERVAL 1 DAY)) + 1);
-- BEFORE
SELECT ts.Train_ID, ts.Day_Of_Week AS scheduled_iso_weekday,
       (SELECT COUNT(*) FROM train_run WHERE Train_ID = @tt) AS runs_before
FROM train_schedule ts
WHERE ts.Train_ID = @tt;
-- ACTION
CALL sp_generate_train_runs(@tt, CURDATE(), DATE_ADD(CURDATE(), INTERVAL 6 DAY));
-- AFTER
SELECT Run_ID, Train_ID, Journey_Date, WEEKDAY(Journey_Date) + 1 AS iso_weekday,
       IF(Journey_Date = DATE_ADD(CURDATE(), INTERVAL 1 DAY)
          AND (SELECT COUNT(*) FROM train_run WHERE Train_ID = @tt) = 1, 'PASS', 'FAIL') AS result
FROM train_run
WHERE Train_ID = @tt;
-- CLEANUP   (trg_run_init_status of G5 created a train_run_status row: delete it first because of its foreign key)
DELETE FROM train_run_status WHERE Run_ID IN (SELECT Run_ID FROM train_run WHERE Train_ID = @tt);
DELETE FROM train_run WHERE Train_ID = @tt;
DELETE FROM train_schedule WHERE Train_ID = @tt;
DELETE FROM train WHERE Train_ID = @tt;
ALTER TABLE train_run AUTO_INCREMENT = 1;
ALTER TABLE train_schedule AUTO_INCREMENT = 1;
ALTER TABLE train AUTO_INCREMENT = 1;

-- TEST 18: sp_generate_train_runs is re-runnable (idempotent): repeating the seed range for train 11001 creates 0 runs, the count stays 15
-- BEFORE
SELECT Train_ID, COUNT(*) AS runs_before, MIN(Journey_Date) AS first_date, MAX(Journey_Date) AS last_date FROM train_run WHERE Train_ID = 1 GROUP BY Train_ID;
-- ACTION
CALL sp_generate_train_runs(1, @run_date, DATE_ADD(@run_date, INTERVAL 14 DAY));
-- AFTER
SELECT Train_ID, COUNT(*) AS runs_after, IF(COUNT(*) = 15, 'PASS', 'FAIL') AS result FROM train_run WHERE Train_ID = 1 GROUP BY Train_ID;

-- TEST 19: sp_generate_train_runs rejects an end date before the start date
-- EXPECT ERROR VALIDATION_ERROR
-- BEFORE
SELECT COUNT(*) AS runs_before FROM train_run;
-- ACTION
CALL sp_generate_train_runs(1, DATE_ADD(@run_date, INTERVAL 5 DAY), @run_date);
-- AFTER
SELECT COUNT(*) AS runs_after, IF(COUNT(*) = 60, 'PASS', 'FAIL') AS result FROM train_run;

-- TEST 20: sp_generate_train_runs rejects a range longer than 60 days (90 days requested)
-- EXPECT ERROR VALIDATION_ERROR
-- BEFORE
SELECT COUNT(*) AS runs_before FROM train_run;
-- ACTION
CALL sp_generate_train_runs(1, @run_date, DATE_ADD(@run_date, INTERVAL 90 DAY));
-- AFTER
SELECT COUNT(*) AS runs_after, IF(COUNT(*) = 60, 'PASS', 'FAIL') AS result FROM train_run;

-- TEST 21: sp_generate_train_runs rejects an unknown train
-- EXPECT ERROR NOT_FOUND
-- BEFORE
SELECT COUNT(*) AS runs_before FROM train_run;
-- ACTION
CALL sp_generate_train_runs(99999, @run_date, DATE_ADD(@run_date, INTERVAL 3 DAY));
-- AFTER
SELECT COUNT(*) AS runs_after, IF(COUNT(*) = 60, 'PASS', 'FAIL') AS result FROM train_run;

-- =============================================================================
-- SECTION C: TRIGGERS (trg_route_stop_audit, trg_route_stop_bi)
-- =============================================================================

-- TEST 22: trg_route_stop_audit writes an audit row (old and new times) when a stop's times are changed (LNL stop: 08:25/08:27 -> 08:30/08:35)
-- BEFORE
SET @audit_mark = (SELECT IFNULL(MAX(Audit_ID), 0) FROM route_stop_audit);
SELECT Route_Stop_ID, Route_ID, Station_ID, Arrival_Time, Departure_Time FROM route_stop WHERE Route_Stop_ID = 3;
SELECT COUNT(*) AS audit_rows_before FROM route_stop_audit WHERE Audit_ID > @audit_mark;
-- ACTION
UPDATE route_stop SET Arrival_Time = '08:30:00', Departure_Time = '08:35:00' WHERE Route_Stop_ID = 3;
-- AFTER
SELECT Audit_ID, Route_Stop_ID, Old_Arrival_Time, New_Arrival_Time, Old_Departure_Time, New_Departure_Time, Changed_At,
       IF(Old_Arrival_Time = '08:25:00' AND New_Arrival_Time = '08:30:00'
          AND Old_Departure_Time = '08:27:00' AND New_Departure_Time = '08:35:00', 'PASS', 'FAIL') AS result
FROM route_stop_audit
WHERE Audit_ID > @audit_mark;
-- CLEANUP   (restoring the times fires the trigger again, so the audit rows of this block are deleted afterwards)
UPDATE route_stop SET Arrival_Time = '08:25:00', Departure_Time = '08:27:00' WHERE Route_Stop_ID = 3;
DELETE FROM route_stop_audit WHERE Audit_ID > @audit_mark;
ALTER TABLE route_stop_audit AUTO_INCREMENT = 1;

-- TEST 23: edge case - changing a column other than the times (distance) does NOT create an audit row; neither does re-saving identical times
-- BEFORE
SET @audit_mark = (SELECT IFNULL(MAX(Audit_ID), 0) FROM route_stop_audit);
SELECT Route_Stop_ID, Arrival_Time, Departure_Time, Distance_From_Source_Km FROM route_stop WHERE Route_Stop_ID = 3;
-- ACTION
UPDATE route_stop SET Distance_From_Source_Km = 125, Arrival_Time = '08:25:00', Departure_Time = '08:27:00' WHERE Route_Stop_ID = 3;
-- AFTER
SELECT Route_Stop_ID, Distance_From_Source_Km,
       (SELECT COUNT(*) FROM route_stop_audit WHERE Audit_ID > @audit_mark) AS new_audit_rows,
       IF((SELECT COUNT(*) FROM route_stop_audit WHERE Audit_ID > @audit_mark) = 0, 'PASS', 'FAIL') AS result
FROM route_stop WHERE Route_Stop_ID = 3;
-- CLEANUP
UPDATE route_stop SET Distance_From_Source_Km = 124 WHERE Route_Stop_ID = 3;
DELETE FROM route_stop_audit WHERE Audit_ID > @audit_mark;
ALTER TABLE route_stop_audit AUTO_INCREMENT = 1;

-- TEST 24: edge case - the comparison is NULL-safe: giving the first stop (Arrival_Time NULL) an arrival time IS audited, with Old_Arrival_Time = NULL
-- BEFORE
SET @audit_mark = (SELECT IFNULL(MAX(Audit_ID), 0) FROM route_stop_audit);
SELECT Route_Stop_ID, Station_ID, Stop_Seq, Arrival_Time, Departure_Time FROM route_stop WHERE Route_Stop_ID = 1;
-- ACTION
UPDATE route_stop SET Arrival_Time = '05:55:00' WHERE Route_Stop_ID = 1;
-- AFTER
SELECT Audit_ID, Route_Stop_ID, Old_Arrival_Time, New_Arrival_Time, Old_Departure_Time, New_Departure_Time,
       IF(Old_Arrival_Time IS NULL AND New_Arrival_Time = '05:55:00'
          AND Old_Departure_Time = '06:00:00' AND New_Departure_Time = '06:00:00', 'PASS', 'FAIL') AS result
FROM route_stop_audit
WHERE Audit_ID > @audit_mark;
-- CLEANUP
UPDATE route_stop SET Arrival_Time = NULL WHERE Route_Stop_ID = 1;
DELETE FROM route_stop_audit WHERE Audit_ID > @audit_mark;
ALTER TABLE route_stop_audit AUTO_INCREMENT = 1;

-- TEST 25: trg_route_stop_bi accepts valid stops: first stop (no arrival), zero-minute halt (departure = arrival), normal halt, last stop (no departure)
-- FIXTURE (throw-away route; deleted in CLEANUP)
INSERT INTO route (Route_Name, Source_Station_ID, Dest_Station_ID) VALUES ('TEST ROUTE (delete me)', 1, 2);
SET @tr = LAST_INSERT_ID();
-- BEFORE
SELECT @tr AS test_route_id, (SELECT COUNT(*) FROM route_stop WHERE Route_ID = @tr) AS stops_before;
-- ACTION
INSERT INTO route_stop (Route_ID, Station_ID, Stop_Seq, Arrival_Time, Departure_Time, Day_Offset, Distance_From_Source_Km) VALUES
    (@tr, 1, 1, NULL,       '06:00:00', 0,   0),
    (@tr, 3, 2, '07:00:00', '07:00:00', 0,  50),
    (@tr, 4, 3, '08:00:00', '08:10:00', 0, 100),
    (@tr, 2, 4, '09:00:00', NULL,       0, 150);
-- AFTER
SELECT Stop_Seq, Station_ID, Arrival_Time, Departure_Time,
       IF((SELECT COUNT(*) FROM route_stop WHERE Route_ID = @tr) = 4, 'PASS', 'FAIL') AS result
FROM route_stop WHERE Route_ID = @tr ORDER BY Stop_Seq;
-- CLEANUP
DELETE FROM route_stop WHERE Route_ID = @tr;
DELETE FROM route WHERE Route_ID = @tr;
ALTER TABLE route_stop AUTO_INCREMENT = 1;
ALTER TABLE route AUTO_INCREMENT = 1;

-- TEST 26: trg_route_stop_bi rejects a stop whose departure is earlier than its arrival (arrival 10:00, departure 09:59)
-- EXPECT ERROR VALIDATION_ERROR
-- FIXTURE
INSERT INTO route (Route_Name, Source_Station_ID, Dest_Station_ID) VALUES ('TEST ROUTE (delete me)', 1, 2);
SET @tr = LAST_INSERT_ID();
-- BEFORE
SELECT @tr AS test_route_id, (SELECT COUNT(*) FROM route_stop WHERE Route_ID = @tr) AS stops_before;
-- ACTION
INSERT INTO route_stop (Route_ID, Station_ID, Stop_Seq, Arrival_Time, Departure_Time, Day_Offset, Distance_From_Source_Km)
VALUES (@tr, 3, 1, '10:00:00', '09:59:00', 0, 0);
-- AFTER   (the bad row was not stored)
SELECT COUNT(*) AS stops_after, IF(COUNT(*) = 0, 'PASS', 'FAIL') AS result FROM route_stop WHERE Route_ID = @tr;
-- CLEANUP
DELETE FROM route_stop WHERE Route_ID = @tr;
DELETE FROM route WHERE Route_ID = @tr;
ALTER TABLE route_stop AUTO_INCREMENT = 1;
ALTER TABLE route AUTO_INCREMENT = 1;

-- TEST 27: edge case - trg_route_stop_bi also rejects a halt that would cross midnight (arrival 23:50, departure 00:10)
-- EXPECT ERROR VALIDATION_ERROR
-- FIXTURE
INSERT INTO route (Route_Name, Source_Station_ID, Dest_Station_ID) VALUES ('TEST ROUTE (delete me)', 1, 2);
SET @tr = LAST_INSERT_ID();
-- BEFORE
SELECT @tr AS test_route_id, (SELECT COUNT(*) FROM route_stop WHERE Route_ID = @tr) AS stops_before;
-- ACTION
INSERT INTO route_stop (Route_ID, Station_ID, Stop_Seq, Arrival_Time, Departure_Time, Day_Offset, Distance_From_Source_Km)
VALUES (@tr, 3, 1, '23:50:00', '00:10:00', 0, 0);
-- AFTER
SELECT COUNT(*) AS stops_after, IF(COUNT(*) = 0, 'PASS', 'FAIL') AS result FROM route_stop WHERE Route_ID = @tr;
-- CLEANUP
DELETE FROM route_stop WHERE Route_ID = @tr;
DELETE FROM route WHERE Route_ID = @tr;
ALTER TABLE route_stop AUTO_INCREMENT = 1;
ALTER TABLE route AUTO_INCREMENT = 1;

-- =============================================================================
-- SECTION D: VIEWS (v_train_timetable, v_train_stop_pairs) AND THE "TRAINS FROM STATION 2 TO STATION 1" QUERY
-- =============================================================================

-- TEST 28: v_train_timetable has exactly the contract columns (in order) and lists the 5 stops of train 12401 in route order
-- BEFORE
SELECT Route_Stop_ID, Route_ID, Station_ID, Stop_Seq, Arrival_Time, Departure_Time, Day_Offset, Distance_From_Source_Km FROM route_stop WHERE Route_ID = 3 ORDER BY Stop_Seq;
-- ACTION
SELECT * FROM v_train_timetable WHERE Train_No = '12401' ORDER BY Stop_Seq;
-- AFTER
SELECT view_name, actual_columns,
       IF(actual_columns = 'Train_ID,Train_No,Train_Name,Route_ID,Stop_Seq,Station_ID,Station_Code,Station_Name,Arrival_Time,Departure_Time,Day_Offset,Distance_From_Source_Km'
          AND stops_of_12401 = 5, 'PASS', 'FAIL') AS result
FROM (
    SELECT 'v_train_timetable' AS view_name,
           (SELECT GROUP_CONCAT(COLUMN_NAME ORDER BY ORDINAL_POSITION)
              FROM information_schema.COLUMNS
             WHERE TABLE_SCHEMA = 'railway_db' AND TABLE_NAME = 'v_train_timetable') AS actual_columns,
           (SELECT COUNT(*) FROM v_train_timetable WHERE Train_No = '12401') AS stops_of_12401
) x;

-- TEST 29: edge case - v_train_timetable keeps NULL arrival at the first stop, NULL departure at the last stop and the after-midnight Day_Offset (stops / null arrivals / null departures / max Day_Offset per train)
-- BEFORE
SELECT Train_ID, Train_No, COUNT(*) AS stops FROM v_train_timetable GROUP BY Train_ID, Train_No ORDER BY Train_ID;
-- ACTION
SELECT Train_No, Stop_Seq, Station_Code, Arrival_Time, Departure_Time, Day_Offset
FROM v_train_timetable
WHERE (Arrival_Time IS NULL OR Departure_Time IS NULL OR Day_Offset > 0)
ORDER BY Train_ID, Stop_Seq;
-- AFTER
SELECT Train_No, summary,
       IF(summary = CASE Train_No
                        WHEN '11001' THEN '4/1/1/0'
                        WHEN '12002' THEN '4/1/1/0'
                        WHEN '12301' THEN '3/1/1/1'
                        WHEN '12401' THEN '5/1/1/1'
                    END, 'PASS', 'FAIL') AS result
FROM (
    SELECT Train_ID, Train_No,
           CONCAT(COUNT(*), '/', SUM(Arrival_Time IS NULL), '/', SUM(Departure_Time IS NULL), '/', MAX(Day_Offset)) AS summary
    FROM v_train_timetable
    GROUP BY Train_ID, Train_No
) x
ORDER BY Train_ID;

-- TEST 30: v_train_stop_pairs has exactly the contract columns and one row per ordered stop pair of each active train (route with n stops => n*(n-1)/2 pairs: 6 / 6 / 3 / 10)
-- BEFORE
SELECT Route_ID, COUNT(*) AS stops FROM route_stop GROUP BY Route_ID ORDER BY Route_ID;
-- ACTION
SELECT * FROM v_train_stop_pairs WHERE Train_No = '11001' ORDER BY From_Stop_Seq, To_Stop_Seq;
-- AFTER
SELECT view_name, actual_columns,
       IF(actual_columns = 'Train_ID,Train_No,Train_Name,Train_Type,Route_ID,From_Station_ID,To_Station_ID,From_Stop_Seq,To_Stop_Seq,Departure_Time,Arrival_Time,Day_Offset_From,Day_Offset_To,Distance_Km',
          'PASS', 'FAIL') AS columns_result
FROM (
    SELECT 'v_train_stop_pairs' AS view_name,
           (SELECT GROUP_CONCAT(COLUMN_NAME ORDER BY ORDINAL_POSITION)
              FROM information_schema.COLUMNS
             WHERE TABLE_SCHEMA = 'railway_db' AND TABLE_NAME = 'v_train_stop_pairs') AS actual_columns
) x;
SELECT Train_No, pairs, IF(pairs = CASE Train_No WHEN '11001' THEN 6 WHEN '12002' THEN 6 WHEN '12301' THEN 3 WHEN '12401' THEN 10 END, 'PASS', 'FAIL') AS pairs_result
FROM (SELECT Train_ID, Train_No, COUNT(*) AS pairs FROM v_train_stop_pairs GROUP BY Train_ID, Train_No) x
ORDER BY Train_ID;
SELECT Train_No, From_Station_ID, To_Station_ID, Departure_Time, Arrival_Time, Day_Offset_From, Day_Offset_To, Distance_Km,
       IF(Departure_Time = '06:00:00' AND Arrival_Time = '10:10:00' AND Day_Offset_From = 0 AND Day_Offset_To = 0 AND Distance_Km = 192, 'PASS', 'FAIL') AS csmt_pune_result
FROM v_train_stop_pairs
WHERE Train_No = '11001' AND From_Station_ID = 2 AND To_Station_ID = 1;

-- TEST 31: edge case - v_train_stop_pairs only contains ACTIVE trains: deactivating train 12002 removes its 6 pairs, re-activating brings them back
-- BEFORE
SELECT Train_No, COUNT(*) AS pairs_before FROM v_train_stop_pairs WHERE Train_ID = 2 GROUP BY Train_No;
-- ACTION
UPDATE train SET Is_Active = 0 WHERE Train_ID = 2;
-- AFTER
SELECT (SELECT COUNT(*) FROM v_train_stop_pairs WHERE Train_ID = 2) AS pairs_of_12002,
       (SELECT COUNT(*) FROM v_train_stop_pairs) AS pairs_total,
       IF((SELECT COUNT(*) FROM v_train_stop_pairs WHERE Train_ID = 2) = 0
          AND (SELECT COUNT(*) FROM v_train_stop_pairs) = 19, 'PASS', 'FAIL') AS result;
-- CLEANUP
UPDATE train SET Is_Active = 1 WHERE Train_ID = 2;

-- TEST 32: "trains from station 2 (CSMT) to station 1 (PUNE)" - the train-search query (v_train_stop_pairs joined to train_run on the date, duration by fn_journey_duration_min): trains 11001 and 12002, 250 min, 192 km
-- BEFORE
SELECT Train_No, Train_Name, From_Station_ID, To_Station_ID, Departure_Time, Arrival_Time, Distance_Km
FROM v_train_stop_pairs
WHERE From_Station_ID = 2 AND To_Station_ID = 1
ORDER BY Train_No;
-- ACTION
SELECT r.Run_ID, p.Train_ID, p.Train_No, p.Train_Name, p.Train_Type, p.From_Station_ID, p.To_Station_ID,
       r.Journey_Date, p.Departure_Time, p.Arrival_Time,
       fn_journey_duration_min(r.Run_ID, p.From_Station_ID, p.To_Station_ID) AS Duration_Min,
       p.Distance_Km
FROM v_train_stop_pairs p
JOIN train_run r ON r.Train_ID = p.Train_ID AND r.Journey_Date = @run_date
WHERE p.From_Station_ID = 2 AND p.To_Station_ID = 1
ORDER BY p.Departure_Time, p.Train_No;
-- AFTER
SELECT COUNT(*) AS trains_found, GROUP_CONCAT(Train_No ORDER BY Train_No) AS train_numbers,
       MIN(Duration_Min) AS min_duration, MAX(Duration_Min) AS max_duration, MIN(Distance_Km) AS min_km, MAX(Distance_Km) AS max_km,
       IF(COUNT(*) = 2 AND GROUP_CONCAT(Train_No ORDER BY Train_No) = '11001,12002'
          AND MIN(Duration_Min) = 250 AND MAX(Duration_Min) = 250
          AND MIN(Distance_Km) = 192 AND MAX(Distance_Km) = 192, 'PASS', 'FAIL') AS result
FROM (
    SELECT p.Train_No, p.Distance_Km, fn_journey_duration_min(r.Run_ID, p.From_Station_ID, p.To_Station_ID) AS Duration_Min
    FROM v_train_stop_pairs p
    JOIN train_run r ON r.Train_ID = p.Train_ID AND r.Journey_Date = @run_date
    WHERE p.From_Station_ID = 2 AND p.To_Station_ID = 1
) q;

-- TEST 33: edge case - the search never returns a wrong direction or an unconnected pair: PUNE -> CSMT and CSMT -> HYB give 0 trains
-- BEFORE
SELECT Route_ID, Station_ID, Stop_Seq FROM route_stop WHERE Station_ID IN (1, 2, 9) ORDER BY Route_ID, Stop_Seq;
-- ACTION
SELECT r.Run_ID, p.Train_No, p.From_Station_ID, p.To_Station_ID
FROM v_train_stop_pairs p
JOIN train_run r ON r.Train_ID = p.Train_ID AND r.Journey_Date = @run_date
WHERE (p.From_Station_ID = 1 AND p.To_Station_ID = 2)
   OR (p.From_Station_ID = 2 AND p.To_Station_ID = 9);
-- AFTER
SELECT case_name, trains_found, IF(trains_found = 0, 'PASS', 'FAIL') AS result
FROM (
    SELECT 'PUNE -> CSMT (opposite direction)' AS case_name,
           (SELECT COUNT(*) FROM v_train_stop_pairs WHERE From_Station_ID = 1 AND To_Station_ID = 2) AS trains_found
    UNION ALL
    SELECT 'CSMT -> HYB (no train connects them)',
           (SELECT COUNT(*) FROM v_train_stop_pairs WHERE From_Station_ID = 2 AND To_Station_ID = 9)
) t;

-- TEST 34: overnight search - CSMT (2) to NGP (7) finds train 12401 only, 810 minutes (18:00 to 07:30 next day), 837 km, Day_Offset_To = 1
-- BEFORE
SELECT Train_No, Stop_Seq, Station_Code, Arrival_Time, Departure_Time, Day_Offset FROM v_train_timetable WHERE Train_ID = 4 AND Station_ID IN (2, 7) ORDER BY Stop_Seq;
-- ACTION
SELECT r.Run_ID, p.Train_No, p.Train_Name, r.Journey_Date, p.Departure_Time, p.Arrival_Time, p.Day_Offset_From, p.Day_Offset_To,
       fn_journey_duration_min(r.Run_ID, p.From_Station_ID, p.To_Station_ID) AS Duration_Min, p.Distance_Km
FROM v_train_stop_pairs p
JOIN train_run r ON r.Train_ID = p.Train_ID AND r.Journey_Date = @run_date
WHERE p.From_Station_ID = 2 AND p.To_Station_ID = 7;
-- AFTER
SELECT Train_No, Duration_Min, Distance_Km, Day_Offset_To,
       IF(Train_No = '12401' AND Duration_Min = 810 AND Distance_Km = 837 AND Day_Offset_To = 1
          AND (SELECT COUNT(*) FROM v_train_stop_pairs WHERE From_Station_ID = 2 AND To_Station_ID = 7) = 1, 'PASS', 'FAIL') AS result
FROM (
    SELECT p.Train_No, p.Distance_Km, p.Day_Offset_To,
           fn_journey_duration_min(r.Run_ID, p.From_Station_ID, p.To_Station_ID) AS Duration_Min
    FROM v_train_stop_pairs p
    JOIN train_run r ON r.Train_ID = p.Train_ID AND r.Journey_Date = @run_date
    WHERE p.From_Station_ID = 2 AND p.To_Station_ID = 7
) q;

-- =============================================================================
-- END: restore the Workbench safe-update setting changed in SETUP
-- =============================================================================
SET SQL_SAFE_UPDATES = 1;

-- SUMMARY (what each test proves)
--   TEST  1  Seed: row counts of contract C6 (9 stations, 3 routes, 12 stops, 4 trains, 28 schedule rows, 5 coach types, 19 coaches, 1250 seats, 15 runs per train) and seats per class.
--   TEST  2  Seed: coach numbers follow the class prefix + running number rule for every train.
--   TEST  3  fn_distance_km: CSMT -> PUNE = 192 km.
--   TEST  4  fn_distance_km: middle stops (KYN/LNL = 70 km), direction independent, route 2 (PUNE -> HYB = 559 km).
--   TEST  5  fn_distance_km: NULL when a station is not on the run's route.
--   TEST  6  fn_departure_datetime: Journey_Date + Departure_Time of the stop.
--   TEST  7  fn_departure_datetime: Arrival_Time fallback at the last stop and Day_Offset for after-midnight stops.
--   TEST  8  fn_departure_datetime: NULL when the station is not on the route.
--   TEST  9  fn_journey_duration_min: same-day journeys (CSMT -> PUNE = 250 min, KYN -> LNL = 88 min).
--   TEST 10  fn_journey_duration_min: overnight journeys (CSMT -> NGP = 810 min and four more cases).
--   TEST 11  fn_journey_duration_min: NULL for reversed direction, same station, station not on the route.
--   TEST 12  sp_add_coaches_generate_seats: coaches S1,S2 and 72 seats each (Seat_No 1..72).
--   TEST 13  sp_add_coaches_generate_seats: prefixes S/B/A/H/C, seat counts and berth cycles of all five classes.
--   TEST 14  sp_add_coaches_generate_seats: running coach numbers continue across calls (S1,S2,S3).
--   TEST 15  sp_add_coaches_generate_seats: NOT_FOUND for an unknown train, nothing added.
--   TEST 16  sp_add_coaches_generate_seats: NOT_FOUND for an unknown coach type, real train untouched.
--   TEST 17  sp_generate_train_runs: only weekdays with a train_schedule row get a run (1 run in a 7-day range).
--   TEST 18  sp_generate_train_runs: idempotent re-run creates 0 runs (15 stay 15).
--   TEST 19  sp_generate_train_runs: VALIDATION_ERROR when the end date is before the start date.
--   TEST 20  sp_generate_train_runs: VALIDATION_ERROR when the range is longer than 60 days.
--   TEST 21  sp_generate_train_runs: NOT_FOUND for an unknown train.
--   TEST 22  trg_route_stop_audit: audit row with old/new arrival and departure after a time change.
--   TEST 23  trg_route_stop_audit: no audit row when only the distance changes or identical times are saved.
--   TEST 24  trg_route_stop_audit: NULL-safe (NULL arrival -> time is audited).
--   TEST 25  trg_route_stop_bi: valid stops accepted (first stop, zero-minute halt, normal halt, last stop).
--   TEST 26  trg_route_stop_bi: VALIDATION_ERROR when departure < arrival.
--   TEST 27  trg_route_stop_bi: VALIDATION_ERROR for a halt that crosses midnight.
--   TEST 28  v_train_timetable: exact contract columns and the 5 ordered stops of train 12401.
--   TEST 29  v_train_timetable: NULL first arrival / last departure and after-midnight Day_Offset for every train.
--   TEST 30  v_train_stop_pairs: exact contract columns, pair counts 6/6/3/10 and the exact CSMT -> PUNE row.
--   TEST 31  v_train_stop_pairs: inactive trains are excluded.
--   TEST 32  Trains from station 2 to station 1: 11001 and 12002, 250 min, 192 km.
--   TEST 33  Train search: no result for the opposite direction or an unconnected pair.
--   TEST 34  Train search: overnight CSMT -> NGP finds only train 12401, 810 min, 837 km.
