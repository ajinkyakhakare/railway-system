-- Task G3.3 | Owner group: G3 (Reservation & Seat) | Purpose: SQL proof script (before / action / after) for the G3 functions, procedures, triggers and views
--
-- HOW TO RUN (MySQL Workbench)
--   1. Build the whole database first (scripts/init-db) so that schemas, seed data, procedures, triggers and views exist.
--   2. Open this file in a Workbench SQL tab and double-click the schema "railway_db" so it is the default schema
--      (this file does not contain USE, as required by the project rules).
--   3. Run it statement by statement (Ctrl+Enter) and take screenshots of the result grids. User variables such as
--      @run_id live in the tab's connection, so keep using the same tab. TEST 7 also needs a second tab (tab B).
--   4. Statements marked "-- EXPECT ERROR <CODE>" must fail with exactly that error. If you run the whole file at once
--      (Ctrl+Shift+Enter) switch off Query > "Stop Script Execution on Errors" first, otherwise Workbench stops at the first expected error.
--   5. Every test cleans up after itself, so the data is left as found. Some tests put the seat_inventory counters into a
--      special state with a direct UPDATE. That is allowed ONLY in this test script (normal code changes the counters
--      through triggers only, rule R9) and the cleanup restores the counters that were saved at the start of the test.
--
-- Fixed data used (contract C6): user 3 = Asha Patil owns passengers 1 (Asha, adult), 2 (Suresh, senior), 3 (Aarav, child);
-- user 4 owns passenger 4. Train 1 (11001) runs on route 1: station 2 = CSMT (stop 1), station 1 = PUNE (stop 4).
-- Class SL of train 1 has 2 coaches = 144 seats, Max_RAC = 14, Max_WL = 29.

-- =============================================================================================
-- SETUP (run these first)
-- =============================================================================================
-- Workbench "safe updates" blocks DELETE/UPDATE statements that do not filter on an indexed column; switch it off for this session.
SET SQL_SAFE_UPDATES = 0;

-- Pick the earliest run of train 1 that has NOT left yet. The first run (today) may already have departed in the
-- early morning (CSMT departure 06:00), which would give RUN_DEPARTED, so only runs after today are used.
SELECT Run_ID, Journey_Date INTO @run_id, @run_date
FROM train_run
WHERE Train_ID = 1 AND Journey_Date > CURDATE()
ORDER BY Journey_Date
LIMIT 1;

SELECT @run_id AS Run_ID_Used_By_All_Tests, @run_date AS Journey_Date;

-- =============================================================================================
-- TEST 1: fn_generate_pnr() returns a 10-digit PNR with first digit 1-9 (normal) and stays valid over 1000 calls (edge)
-- =============================================================================================
-- BEFORE
SELECT 'fn_generate_pnr reads no table, so there is no state to compare' AS Note, COUNT(*) AS Bookings_Existing FROM booking;
-- ACTION
SET @pnr = fn_generate_pnr();
-- AFTER
SELECT @pnr AS PNR,
       CHAR_LENGTH(@pnr) AS Length,
       IF(@pnr REGEXP '^[1-9][0-9]{9}$', 'PASS', 'FAIL') AS Format_Check;
-- AFTER (edge: 1000 calls, every one must match the pattern; RAND() is evaluated once per row)
WITH RECURSIVE n (i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 1000)
SELECT COUNT(*) AS Calls,
       SUM(fn_generate_pnr() REGEXP '^[1-9][0-9]{9}$') AS Valid_Format,
       IF(SUM(fn_generate_pnr() REGEXP '^[1-9][0-9]{9}$') = COUNT(*), 'PASS', 'FAIL') AS Result
FROM n;

-- =============================================================================================
-- TEST 2: fn_availability_text() gives AVL / RAC / WL / REGRET for the right inputs, including the boundaries
-- =============================================================================================
-- BEFORE (the input cases and what we expect; a temporary table disappears when the session ends)
DROP TEMPORARY TABLE IF EXISTS tmp_g3_availability_cases;
CREATE TEMPORARY TABLE tmp_g3_availability_cases (
    Case_No       INT PRIMARY KEY,
    Description   VARCHAR(60),
    Available_CNF INT,
    RAC_Count     INT,
    WL_Count      INT,
    Max_RAC       INT,
    Max_WL        INT,
    Expected      VARCHAR(20),
    Actual        VARCHAR(20) NULL
);
INSERT INTO tmp_g3_availability_cases VALUES
    (1, 'seats free -> AVL',                          5,  0,  0, 10, 20, 'AVL 5',  NULL),
    (2, 'edge: exactly one seat left',                1,  0,  0, 10, 20, 'AVL 1',  NULL),
    (3, 'no seat, RAC empty -> RAC 1',                0,  0,  0, 10, 20, 'RAC 1',  NULL),
    (4, 'RAC partly used -> next RAC number',         0,  3,  0, 10, 20, 'RAC 4',  NULL),
    (5, 'edge: last RAC place',                       0,  9,  5, 10, 20, 'RAC 10', NULL),
    (6, 'RAC full -> WL 1',                           0, 10,  0, 10, 20, 'WL 1',   NULL),
    (7, 'edge: last WL place',                        0, 10, 19, 10, 20, 'WL 20',  NULL),
    (8, 'edge: RAC and WL both full -> REGRET',       0, 10, 20, 10, 20, 'REGRET', NULL),
    (9, 'edge: class allows no RAC and no WL',        0,  0,  0,  0,  0, 'REGRET', NULL);
SELECT * FROM tmp_g3_availability_cases ORDER BY Case_No;
-- ACTION
UPDATE tmp_g3_availability_cases
   SET Actual = fn_availability_text(Available_CNF, RAC_Count, WL_Count, Max_RAC, Max_WL)
 WHERE Case_No > 0;
-- AFTER
SELECT Case_No, Description, Expected, Actual, IF(Expected = Actual, 'PASS', 'FAIL') AS Result
FROM tmp_g3_availability_cases
ORDER BY Case_No;
-- CLEANUP
DROP TEMPORARY TABLE tmp_g3_availability_cases;

-- =============================================================================================
-- TEST 3: normal booking of 2 passengers -> both CNF, seats allocated, inventory decreased by 2
--         (sp_book_ticket normal case, trg_dec_inventory CNF branch)
-- =============================================================================================
-- BEFORE
SELECT Run_ID, Class_Code, Total_Seats, Available_CNF, RAC_Count, WL_Count
FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';
-- (setup) remember the counters so that the cleanup can restore them exactly
SELECT Available_CNF, RAC_Count, WL_Count INTO @o_cnf, @o_rac, @o_wl
FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';
-- ACTION  (Asha = adult, Suresh = senior with 40 % discount; CSMT -> PUNE, class SL)
CALL sp_book_ticket(3, @run_id, 'SL', 2, 1, '[1,2]');
-- AFTER
SELECT Booking_ID INTO @bk FROM booking
WHERE User_ID = 3 AND Run_ID = @run_id ORDER BY Booking_ID DESC LIMIT 1;

SELECT Booking_ID, PNR, Booking_Status, Total_Fare   -- with the C6 seed: PENDING_PAYMENT, 192.00 (120.00 + 72.00)
FROM booking WHERE Booking_ID = @bk;

SELECT bp.Booking_Passenger_ID, p.Full_Name, bp.Status, bp.Base_Fare, bp.Concession_Type, bp.Fare_Amount,
       tc.Coach_Number, s.Seat_No, s.Berth_Type
FROM booking_passenger bp
JOIN passenger p             ON p.Passenger_ID = bp.Passenger_ID
LEFT JOIN seat_allocation sa ON sa.Booking_Passenger_ID = bp.Booking_Passenger_ID
LEFT JOIN seat s             ON s.Seat_ID = sa.Seat_ID
LEFT JOIN train_coach tc     ON tc.Coach_ID = s.Coach_ID
WHERE bp.Booking_ID = @bk
ORDER BY bp.Booking_Passenger_ID;

SELECT @o_cnf AS Available_CNF_Before, Available_CNF AS Available_CNF_After,
       @o_cnf - Available_CNF AS Seats_Taken,
       IF(@o_cnf - Available_CNF = 2, 'PASS', 'FAIL') AS Result
FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';
-- CLEANUP
DELETE FROM seat_allocation WHERE Booking_Passenger_ID IN (SELECT Booking_Passenger_ID FROM booking_passenger WHERE Booking_ID = @bk);
DELETE FROM booking_status_history WHERE Booking_Passenger_ID IN (SELECT Booking_Passenger_ID FROM booking_passenger WHERE Booking_ID = @bk);
DELETE FROM booking_passenger WHERE Booking_ID = @bk;
DELETE FROM booking WHERE Booking_ID = @bk;
UPDATE seat_inventory SET Available_CNF = @o_cnf, RAC_Count = @o_rac, WL_Count = @o_wl WHERE Run_ID = @run_id AND Class_Code = 'SL';
SELECT Available_CNF, RAC_Count, WL_Count FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';

-- =============================================================================================
-- TEST 4: first come, first served - only one seat left, two passengers -> one CNF and one RAC
--         (trg_dec_inventory RAC branch)
-- =============================================================================================
-- BEFORE
SELECT Run_ID, Class_Code, Total_Seats, Available_CNF, RAC_Count, WL_Count, Max_RAC
FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';
-- (setup) remember the counters
SELECT Available_CNF, RAC_Count, WL_Count INTO @o_cnf, @o_rac, @o_wl
FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';
-- ACTION step 1: TEST-ONLY shortcut - pretend a crowd already took all but one seat (direct UPDATE is allowed only in this test)
UPDATE seat_inventory SET Available_CNF = 1 WHERE Run_ID = @run_id AND Class_Code = 'SL';
-- ACTION step 2: book two passengers; the first gets the last seat, the second goes to RAC
CALL sp_book_ticket(3, @run_id, 'SL', 2, 1, '[1,2]');
-- AFTER
SELECT Booking_ID INTO @bk FROM booking
WHERE User_ID = 3 AND Run_ID = @run_id ORDER BY Booking_ID DESC LIMIT 1;

SELECT bp.Booking_Passenger_ID, p.Full_Name, bp.Status, tc.Coach_Number, s.Seat_No
FROM booking_passenger bp
JOIN passenger p             ON p.Passenger_ID = bp.Passenger_ID
LEFT JOIN seat_allocation sa ON sa.Booking_Passenger_ID = bp.Booking_Passenger_ID
LEFT JOIN seat s             ON s.Seat_ID = sa.Seat_ID
LEFT JOIN train_coach tc     ON tc.Coach_ID = s.Coach_ID
WHERE bp.Booking_ID = @bk
ORDER BY bp.Booking_Passenger_ID;                      -- EXPECT: first passenger CNF with a seat, second RAC without a seat

SELECT Available_CNF, RAC_Count, @o_rac AS RAC_Count_Before,
       IF(Available_CNF = 0 AND RAC_Count = @o_rac + 1, 'PASS', 'FAIL') AS Result
FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';
-- CLEANUP
DELETE FROM seat_allocation WHERE Booking_Passenger_ID IN (SELECT Booking_Passenger_ID FROM booking_passenger WHERE Booking_ID = @bk);
DELETE FROM booking_status_history WHERE Booking_Passenger_ID IN (SELECT Booking_Passenger_ID FROM booking_passenger WHERE Booking_ID = @bk);
DELETE FROM booking_passenger WHERE Booking_ID = @bk;
DELETE FROM booking WHERE Booking_ID = @bk;
UPDATE seat_inventory SET Available_CNF = @o_cnf, RAC_Count = @o_rac, WL_Count = @o_wl WHERE Run_ID = @run_id AND Class_Code = 'SL';
SELECT Available_CNF, RAC_Count, WL_Count FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';

-- =============================================================================================
-- TEST 5: RAC and WL fill up, then BOOKING_CLOSED_WL_FULL fires and the WHOLE booking rolls back
--         (trg_block_if_wl_full failing case, sp_book_ticket rollback)
-- =============================================================================================
-- (setup) remember the counters and the number of bookings of this run and class
SELECT Available_CNF, RAC_Count, WL_Count INTO @o_cnf, @o_rac, @o_wl
FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';
SELECT COUNT(*) INTO @o_bookings FROM booking WHERE Run_ID = @run_id AND Class_Code = 'SL';
-- (setup) TEST-ONLY shortcut: no seat left, one RAC place left, one WL place left
UPDATE seat_inventory
   SET Available_CNF = 0, RAC_Count = Max_RAC - 1, WL_Count = Max_WL - 1
 WHERE Run_ID = @run_id AND Class_Code = 'SL';
-- BEFORE
SELECT Available_CNF, RAC_Count, Max_RAC, WL_Count, Max_WL, @o_bookings AS Bookings_Of_Run_And_Class
FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';
-- ACTION: 3 passengers -> 1st takes the last RAC place, 2nd takes the last WL place, 3rd finds the waiting list full
-- EXPECT ERROR BOOKING_CLOSED_WL_FULL
CALL sp_book_ticket(3, @run_id, 'SL', 2, 1, '[1,2,3]');
-- AFTER (nothing changed: the counters are exactly as in BEFORE and no booking row was left behind)
SELECT Available_CNF, RAC_Count, Max_RAC, WL_Count, Max_WL,
       (SELECT COUNT(*) FROM booking WHERE Run_ID = @run_id AND Class_Code = 'SL') AS Bookings_Of_Run_And_Class,
       IF(RAC_Count = Max_RAC - 1 AND WL_Count = Max_WL - 1
          AND (SELECT COUNT(*) FROM booking WHERE Run_ID = @run_id AND Class_Code = 'SL') = @o_bookings,
          'PASS - whole booking rolled back', 'FAIL') AS Result
FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';
-- CLEANUP
UPDATE seat_inventory SET Available_CNF = @o_cnf, RAC_Count = @o_rac, WL_Count = @o_wl WHERE Run_ID = @run_id AND Class_Code = 'SL';
SELECT Available_CNF, RAC_Count, WL_Count FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';

-- =============================================================================================
-- TEST 6: cancel flow check - a CNF passenger is cancelled manually, then sp_promote_rac_wl promotes the RAC passenger to CNF
--         (sp_promote_rac_wl normal case, trg_adjust_inventory_on_status CNF->CANCELLED and RAC->CNF, booking_status_history)
-- =============================================================================================
-- (setup) remember the counters, leave one seat, book Asha (gets CNF) and Suresh (gets RAC)
SELECT Available_CNF, RAC_Count, WL_Count INTO @o_cnf, @o_rac, @o_wl
FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';
UPDATE seat_inventory SET Available_CNF = 1 WHERE Run_ID = @run_id AND Class_Code = 'SL';   -- TEST-ONLY shortcut
CALL sp_book_ticket(3, @run_id, 'SL', 2, 1, '[1,2]');
SELECT Booking_ID INTO @bk FROM booking
WHERE User_ID = 3 AND Run_ID = @run_id ORDER BY Booking_ID DESC LIMIT 1;
SELECT Booking_Passenger_ID INTO @bp_cnf FROM booking_passenger WHERE Booking_ID = @bk AND Status = 'CNF' LIMIT 1;
SELECT Booking_Passenger_ID INTO @bp_rac FROM booking_passenger WHERE Booking_ID = @bk AND Status = 'RAC' LIMIT 1;
-- BEFORE
SELECT bp.Booking_Passenger_ID, p.Full_Name, bp.Status, sa.Seat_ID
FROM booking_passenger bp
JOIN passenger p             ON p.Passenger_ID = bp.Passenger_ID
LEFT JOIN seat_allocation sa ON sa.Booking_Passenger_ID = bp.Booking_Passenger_ID
WHERE bp.Booking_ID = @bk ORDER BY bp.Booking_Passenger_ID;
SELECT Available_CNF, RAC_Count, WL_Count FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';
-- ACTION step 1: cancel the CNF passenger by changing the status; trg_adjust_inventory_on_status gives the seat back (Available_CNF + 1)
UPDATE booking_passenger SET Status = 'CANCELLED' WHERE Booking_Passenger_ID = @bp_cnf;
-- ACTION step 2: release the cancelled passenger's seat row (the cancellation procedure of G4 does the same)
DELETE FROM seat_allocation WHERE Booking_Passenger_ID = @bp_cnf;
-- ACTION step 3: promote. sp_promote_rac_wl is a helper without its own transaction, so the caller opens one.
START TRANSACTION;
CALL sp_promote_rac_wl(@run_id, 'SL', @promoted);
COMMIT;
-- AFTER
SELECT @promoted AS Promoted_Count;                    -- EXPECT 1
SELECT bp.Booking_Passenger_ID, p.Full_Name, bp.Status, sa.Seat_ID
FROM booking_passenger bp
JOIN passenger p             ON p.Passenger_ID = bp.Passenger_ID
LEFT JOIN seat_allocation sa ON sa.Booking_Passenger_ID = bp.Booking_Passenger_ID
WHERE bp.Booking_ID = @bk ORDER BY bp.Booking_Passenger_ID;   -- EXPECT: Asha CANCELLED, Suresh CNF with a seat
SELECT Available_CNF, RAC_Count, WL_Count, @o_rac AS RAC_Count_Before_Test,
       IF(Available_CNF = 0 AND RAC_Count = @o_rac, 'PASS', 'FAIL') AS Result
FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';
SELECT h.History_ID, h.Booking_Passenger_ID, h.Old_Status, h.New_Status
FROM booking_status_history h
WHERE h.Booking_Passenger_ID IN (SELECT Booking_Passenger_ID FROM booking_passenger WHERE Booking_ID = @bk)
ORDER BY h.History_ID;                                 -- EXPECT: CNF->CANCELLED, then RAC->CNF
-- CLEANUP
DELETE FROM seat_allocation WHERE Booking_Passenger_ID IN (SELECT Booking_Passenger_ID FROM booking_passenger WHERE Booking_ID = @bk);
DELETE FROM booking_status_history WHERE Booking_Passenger_ID IN (SELECT Booking_Passenger_ID FROM booking_passenger WHERE Booking_ID = @bk);
DELETE FROM booking_passenger WHERE Booking_ID = @bk;
DELETE FROM booking WHERE Booking_ID = @bk;
UPDATE seat_inventory SET Available_CNF = @o_cnf, RAC_Count = @o_rac, WL_Count = @o_wl WHERE Run_ID = @run_id AND Class_Code = 'SL';
SELECT Available_CNF, RAC_Count, WL_Count FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';

-- =============================================================================================
-- TEST 7: concurrency - two sessions fight for the same inventory row; the second one must WAIT (row-level locking, rule R10)
--         (sp_book_ticket locking)
-- This test is a script for TWO Workbench tabs. Tab A is the tab you have been using, tab B is a new SQL tab on the same schema.
-- =============================================================================================
-- BEFORE (tab A)
SELECT Available_CNF, RAC_Count, WL_Count FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';
SELECT Available_CNF, RAC_Count, WL_Count INTO @o7_cnf, @o7_rac, @o7_wl
FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';
SET @bk_t7 = NULL;
SELECT @run_id AS Run_ID_To_Use_In_Tab_B;
-- ACTION - follow these steps in order (they are comments on purpose; copy each statement into the tab named in front of it)
--   Step B0 (tab B, once): SELECT Run_ID INTO @run_id FROM train_run WHERE Train_ID = 1 AND Journey_Date > CURDATE() ORDER BY Journey_Date LIMIT 1;
--   Step A1 (tab A): START TRANSACTION;
--   Step A2 (tab A): SELECT * FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL' FOR UPDATE;
--                    -- tab A now owns the lock on the inventory row. Do NOT commit yet.
--   Step A3 (tab A): UPDATE seat_inventory SET Available_CNF = 0 WHERE Run_ID = @run_id AND Class_Code = 'SL';
--                    -- TEST-ONLY: tab A pretends it just sold the last seats.
--   Step B1 (tab B): CALL sp_book_ticket(3, @run_id, 'SL', 2, 1, '[1,2]');
--                    -- tab B shows "running" and does NOT finish: sp_book_ticket waits for A's lock on the inventory row. Take your screenshot now.
--                    -- You must finish step A4 within 50 seconds (innodb_lock_wait_timeout), otherwise tab B fails with error 1205; then repeat B1.
--   Step A4 (tab A): COMMIT;
--                    -- tab B wakes up and finishes. B read the counters AFTER A's change, so both passengers get RAC instead of CNF.
--                    -- Note the Booking_ID shown in the result grid of tab B.
--   Step A5 (tab A): SET @bk_t7 = <the Booking_ID shown in tab B>;      -- e.g. SET @bk_t7 = 57;
-- AFTER (tab A; shows nothing until step A5 has been done)
SELECT bp.Booking_Passenger_ID, p.Full_Name, bp.Status       -- EXPECT: both RAC
FROM booking_passenger bp
JOIN passenger p ON p.Passenger_ID = bp.Passenger_ID
WHERE bp.Booking_ID = @bk_t7
ORDER BY bp.Booking_Passenger_ID;
SELECT Available_CNF, RAC_Count, WL_Count FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';
-- CLEANUP (harmless when @bk_t7 is NULL; it removes the booking made in tab B and restores the counters saved above)
DELETE FROM seat_allocation WHERE Booking_Passenger_ID IN (SELECT Booking_Passenger_ID FROM booking_passenger WHERE Booking_ID = @bk_t7);
DELETE FROM booking_status_history WHERE Booking_Passenger_ID IN (SELECT Booking_Passenger_ID FROM booking_passenger WHERE Booking_ID = @bk_t7);
DELETE FROM booking_passenger WHERE Booking_ID = @bk_t7;
DELETE FROM booking WHERE Booking_ID = @bk_t7;
UPDATE seat_inventory SET Available_CNF = @o7_cnf, RAC_Count = @o7_rac, WL_Count = @o7_wl WHERE Run_ID = @run_id AND Class_Code = 'SL';
SELECT Available_CNF, RAC_Count, WL_Count FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';

-- =============================================================================================
-- TEST 8: UNIQUE(Run_ID, Seat_ID) rejects a manual double allocation of the same seat
--         (database-level guard against double booking)
-- =============================================================================================
-- (setup) remember the counters, book two passengers (both CNF), find their ids and the seat of the first one
SELECT Available_CNF, RAC_Count, WL_Count INTO @o_cnf, @o_rac, @o_wl
FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';
CALL sp_book_ticket(3, @run_id, 'SL', 2, 1, '[1,2]');
SELECT Booking_ID INTO @bk FROM booking
WHERE User_ID = 3 AND Run_ID = @run_id ORDER BY Booking_ID DESC LIMIT 1;
SELECT MIN(Booking_Passenger_ID), MAX(Booking_Passenger_ID) INTO @bp1, @bp2 FROM booking_passenger WHERE Booking_ID = @bk;
SELECT Seat_ID INTO @seat1 FROM seat_allocation WHERE Booking_Passenger_ID = @bp1;
-- BEFORE (two different seats, one per passenger)
SELECT Allocation_ID, Run_ID, Seat_ID, Booking_Passenger_ID
FROM seat_allocation WHERE Booking_Passenger_ID IN (@bp1, @bp2) ORDER BY Booking_Passenger_ID;
-- ACTION step 1: free the second passenger's own seat row, so that only the (Run_ID, Seat_ID) key can reject the next INSERT
DELETE FROM seat_allocation WHERE Booking_Passenger_ID = @bp2;
-- ACTION step 2: try to give the second passenger the seat that the first passenger already holds on the same run
-- EXPECT ERROR DUPLICATE   (MySQL error 1062 "Duplicate entry"; the backend maps it to the code DUPLICATE)
INSERT INTO seat_allocation (Run_ID, Seat_ID, Booking_Passenger_ID) VALUES (@run_id, @seat1, @bp2);
-- AFTER (the seat is still held only by the first passenger)
SELECT Allocation_ID, Run_ID, Seat_ID, Booking_Passenger_ID
FROM seat_allocation WHERE Run_ID = @run_id AND Seat_ID = @seat1;
-- CLEANUP
DELETE FROM seat_allocation WHERE Booking_Passenger_ID IN (SELECT Booking_Passenger_ID FROM booking_passenger WHERE Booking_ID = @bk);
DELETE FROM booking_status_history WHERE Booking_Passenger_ID IN (SELECT Booking_Passenger_ID FROM booking_passenger WHERE Booking_ID = @bk);
DELETE FROM booking_passenger WHERE Booking_ID = @bk;
DELETE FROM booking WHERE Booking_ID = @bk;
UPDATE seat_inventory SET Available_CNF = @o_cnf, RAC_Count = @o_rac, WL_Count = @o_wl WHERE Run_ID = @run_id AND Class_Code = 'SL';
SELECT Available_CNF, RAC_Count, WL_Count FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';

-- =============================================================================================
-- TEST 9: both views (v_seat_availability and v_run_occupancy) - normal case
-- =============================================================================================
-- BEFORE (the raw counters behind the views)
SELECT Run_ID, Class_Code, Total_Seats, Available_CNF, RAC_Count, WL_Count, Max_RAC, Max_WL
FROM seat_inventory WHERE Run_ID = @run_id ORDER BY Class_Code;
-- ACTION: availability of every class of the run, with the text a passenger sees
SELECT * FROM v_seat_availability WHERE Run_ID = @run_id ORDER BY Class_Code;
-- AFTER: occupancy of every run and class on the same journey date, ranked from fullest to emptiest
SELECT * FROM v_run_occupancy WHERE Journey_Date = @run_date ORDER BY Occupancy_Rank, Run_ID, Class_Code;

-- =============================================================================================
-- TEST 10: sp_book_ticket rejects more than 6 passengers
-- =============================================================================================
-- BEFORE
SELECT COUNT(*) AS Bookings_Of_User_3 FROM booking WHERE User_ID = 3;
-- ACTION
-- EXPECT ERROR TOO_MANY_PASSENGERS
CALL sp_book_ticket(3, @run_id, 'SL', 2, 1, '[1,2,3,4,5,6,7]');
-- AFTER (no booking created)
SELECT COUNT(*) AS Bookings_Of_User_3 FROM booking WHERE User_ID = 3;

-- =============================================================================================
-- TEST 11: sp_book_ticket rejects an empty passenger list
-- =============================================================================================
-- BEFORE
SELECT COUNT(*) AS Bookings_Of_User_3 FROM booking WHERE User_ID = 3;
-- ACTION
-- EXPECT ERROR VALIDATION_ERROR
CALL sp_book_ticket(3, @run_id, 'SL', 2, 1, '[]');
-- AFTER (no booking created)
SELECT COUNT(*) AS Bookings_Of_User_3 FROM booking WHERE User_ID = 3;

-- =============================================================================================
-- TEST 12: sp_book_ticket rejects stations in the wrong order (PUNE -> CSMT runs against the direction of route 1)
-- =============================================================================================
-- BEFORE
SELECT rs.Stop_Seq, st.Station_Code FROM route_stop rs JOIN station st ON st.Station_ID = rs.Station_ID
WHERE rs.Route_ID = 1 ORDER BY rs.Stop_Seq;
-- ACTION
-- EXPECT ERROR INVALID_STATIONS
CALL sp_book_ticket(3, @run_id, 'SL', 1, 2, '[1]');
-- AFTER (no booking created)
SELECT COUNT(*) AS Bookings_Of_User_3 FROM booking WHERE User_ID = 3;

-- =============================================================================================
-- TEST 13: sp_book_ticket rejects a passenger who belongs to another user, and rolls back the part already done
--          (passenger 1 is accepted first, passenger 4 belongs to user 4)
-- =============================================================================================
-- (setup) remember the counters and the number of bookings
SELECT Available_CNF, RAC_Count, WL_Count INTO @o_cnf, @o_rac, @o_wl
FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';
SELECT COUNT(*) INTO @o_bookings FROM booking WHERE Run_ID = @run_id AND Class_Code = 'SL';
-- BEFORE
SELECT Available_CNF, RAC_Count, WL_Count, @o_bookings AS Bookings_Of_Run_And_Class
FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';
-- ACTION
-- EXPECT ERROR PASSENGER_NOT_OWNED
CALL sp_book_ticket(3, @run_id, 'SL', 2, 1, '[1,4]');
-- AFTER (counters and booking count are unchanged although passenger 1 had already been inserted before the error)
SELECT Available_CNF, RAC_Count, WL_Count,
       (SELECT COUNT(*) FROM booking WHERE Run_ID = @run_id AND Class_Code = 'SL') AS Bookings_Of_Run_And_Class,
       IF(Available_CNF = @o_cnf AND RAC_Count = @o_rac AND WL_Count = @o_wl
          AND (SELECT COUNT(*) FROM booking WHERE Run_ID = @run_id AND Class_Code = 'SL') = @o_bookings,
          'PASS - rolled back', 'FAIL') AS Result
FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';

-- =============================================================================================
-- TEST 14: sp_book_ticket rejects a class that the train does not have (train 1 has no 1A coach, so no inventory row exists)
-- =============================================================================================
-- BEFORE
SELECT Class_Code, Total_Seats FROM seat_inventory WHERE Run_ID = @run_id ORDER BY Class_Code;   -- 1A is not listed
-- ACTION
-- EXPECT ERROR SEAT_UNAVAILABLE
CALL sp_book_ticket(3, @run_id, '1A', 2, 1, '[1]');
-- AFTER (no booking created)
SELECT COUNT(*) AS Bookings_Of_User_3 FROM booking WHERE User_ID = 3;

-- =============================================================================================
-- TEST 15: sp_book_ticket rejects a run that does not exist
-- =============================================================================================
-- BEFORE
SELECT COUNT(*) AS Runs_With_Id_999999999 FROM train_run WHERE Run_ID = 999999999;
-- ACTION
-- EXPECT ERROR RUN_NOT_FOUND
CALL sp_book_ticket(3, 999999999, 'SL', 2, 1, '[1]');
-- AFTER (no booking created)
SELECT COUNT(*) AS Bookings_Of_User_3 FROM booking WHERE User_ID = 3;

-- =============================================================================================
-- TEST 16: sp_book_ticket rejects a run that has already departed
--          (a run 400 days in the past is created for this test and removed again; this also fires the run triggers)
-- =============================================================================================
-- (setup) create the past run
INSERT INTO train_run (Train_ID, Journey_Date) VALUES (1, DATE_SUB(CURDATE(), INTERVAL 400 DAY));
SET @past_run = LAST_INSERT_ID();
-- BEFORE
SELECT Run_ID, Train_ID, Journey_Date, fn_departure_datetime(Run_ID, 2) AS Departure_From_CSMT, NOW() AS Now_Is
FROM train_run WHERE Run_ID = @past_run;
-- ACTION
-- EXPECT ERROR RUN_DEPARTED
CALL sp_book_ticket(3, @past_run, 'SL', 2, 1, '[1]');
-- AFTER (no booking created for the past run)
SELECT COUNT(*) AS Bookings_For_Past_Run FROM booking WHERE Run_ID = @past_run;
-- CLEANUP (children first because of the foreign keys; train_run_status is the G5 row created by its own trigger)
DELETE FROM seat_inventory WHERE Run_ID = @past_run;
DELETE FROM train_run_status WHERE Run_ID = @past_run;
DELETE FROM train_run WHERE Run_ID = @past_run;
SELECT COUNT(*) AS Past_Run_Rows_Left FROM train_run WHERE Run_ID = @past_run;

-- =============================================================================================
-- TEST 17: trg_run_init_inventory creates one inventory row per class with the right numbers - normal case
--          (a run 400 days in the future is created for this test and removed again)
-- =============================================================================================
-- BEFORE
SELECT ct.Class_Code, COUNT(*) AS Coaches, SUM(ct.Seats_Per_Coach) AS Seats_Of_Class
FROM train_coach tc JOIN coach_type ct ON ct.Coach_Type_ID = tc.Coach_Type_ID
WHERE tc.Train_ID = 1 GROUP BY ct.Class_Code ORDER BY ct.Class_Code;
-- ACTION
INSERT INTO train_run (Train_ID, Journey_Date) VALUES (1, DATE_ADD(CURDATE(), INTERVAL 400 DAY));
SET @new_run = LAST_INSERT_ID();
-- AFTER (every row must be fully available, with Max_RAC = 10 % and Max_WL = 20 % of the seats, rounded)
SELECT si.Class_Code, si.Total_Seats, c.Expected_Total, si.Available_CNF, si.RAC_Count, si.WL_Count, si.Max_RAC, si.Max_WL,
       IF(si.Total_Seats = c.Expected_Total AND si.Available_CNF = c.Expected_Total
          AND si.RAC_Count = 0 AND si.WL_Count = 0
          AND si.Max_RAC = ROUND(c.Expected_Total * 0.10) AND si.Max_WL = ROUND(c.Expected_Total * 0.20),
          'PASS', 'FAIL') AS Result
FROM seat_inventory si
JOIN (SELECT ct.Class_Code, SUM(ct.Seats_Per_Coach) AS Expected_Total
      FROM train_coach tc JOIN coach_type ct ON ct.Coach_Type_ID = tc.Coach_Type_ID
      WHERE tc.Train_ID = 1 GROUP BY ct.Class_Code) c ON c.Class_Code = si.Class_Code
WHERE si.Run_ID = @new_run
ORDER BY si.Class_Code;
-- CLEANUP
DELETE FROM seat_inventory WHERE Run_ID = @new_run;
DELETE FROM train_run_status WHERE Run_ID = @new_run;
DELETE FROM train_run WHERE Run_ID = @new_run;
SELECT COUNT(*) AS New_Run_Rows_Left FROM train_run WHERE Run_ID = @new_run;

-- =============================================================================================
-- TEST 18: trg_run_init_inventory edge case - a train without coaches gets a run but NO inventory rows
-- =============================================================================================
-- (setup) a temporary train on route 1 that has no coaches
INSERT INTO train (Train_No, Train_Name, Train_Type, Route_ID) VALUES ('99999', 'Test Train Without Coaches', 'LOCAL', 1);
SET @tmp_train = LAST_INSERT_ID();
-- BEFORE
SELECT COUNT(*) AS Coaches_Of_Temp_Train FROM train_coach WHERE Train_ID = @tmp_train;
-- ACTION
INSERT INTO train_run (Train_ID, Journey_Date) VALUES (@tmp_train, DATE_ADD(CURDATE(), INTERVAL 400 DAY));
SET @tmp_run = LAST_INSERT_ID();
-- AFTER
SELECT (SELECT COUNT(*) FROM train_run WHERE Run_ID = @tmp_run) AS Run_Rows,
       (SELECT COUNT(*) FROM seat_inventory WHERE Run_ID = @tmp_run) AS Inventory_Rows,
       IF((SELECT COUNT(*) FROM seat_inventory WHERE Run_ID = @tmp_run) = 0, 'PASS', 'FAIL') AS Result;
-- CLEANUP
DELETE FROM seat_inventory WHERE Run_ID = @tmp_run;
DELETE FROM train_run_status WHERE Run_ID = @tmp_run;
DELETE FROM train_run WHERE Run_ID = @tmp_run;
DELETE FROM train WHERE Train_ID = @tmp_train;
SELECT COUNT(*) AS Temp_Train_Rows_Left FROM train WHERE Train_ID = @tmp_train;

-- =============================================================================================
-- TEST 19: a passenger is accepted onto the waiting list while it is NOT full, and cancelling that waiting passenger frees the place
--          (trg_block_if_wl_full normal case, trg_dec_inventory WL branch, trg_adjust_inventory_on_status WL->CANCELLED)
-- =============================================================================================
-- (setup) remember the counters, then TEST-ONLY shortcut: no seat left and RAC full, WL empty
SELECT Available_CNF, RAC_Count, WL_Count INTO @o_cnf, @o_rac, @o_wl
FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';
UPDATE seat_inventory SET Available_CNF = 0, RAC_Count = Max_RAC, WL_Count = 0 WHERE Run_ID = @run_id AND Class_Code = 'SL';
-- BEFORE
SELECT Available_CNF, RAC_Count, Max_RAC, WL_Count, Max_WL FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';
-- ACTION step 1: book one passenger; he goes to the waiting list and the trigger lets him in
CALL sp_book_ticket(3, @run_id, 'SL', 2, 1, '[1]');
SELECT Booking_ID INTO @bk FROM booking
WHERE User_ID = 3 AND Run_ID = @run_id ORDER BY Booking_ID DESC LIMIT 1;
SELECT Booking_Passenger_ID INTO @bp FROM booking_passenger WHERE Booking_ID = @bk LIMIT 1;
-- AFTER step 1
SELECT bp.Status AS Passenger_Status,
       si.WL_Count, @o_wl AS WL_Count_Before_Test,
       IF(bp.Status = 'WL' AND si.WL_Count = 1, 'PASS', 'FAIL') AS Result
FROM booking_passenger bp
JOIN seat_inventory si ON si.Run_ID = @run_id AND si.Class_Code = 'SL'
WHERE bp.Booking_Passenger_ID = @bp;
-- ACTION step 2: the waiting passenger is cancelled (status change only; the trigger moves the counter)
UPDATE booking_passenger SET Status = 'CANCELLED' WHERE Booking_Passenger_ID = @bp;
-- AFTER step 2
SELECT WL_Count, IF(WL_Count = 0, 'PASS', 'FAIL') AS Result
FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';
SELECT Old_Status, New_Status FROM booking_status_history WHERE Booking_Passenger_ID = @bp ORDER BY History_ID;   -- EXPECT WL->CANCELLED
-- CLEANUP
DELETE FROM seat_allocation WHERE Booking_Passenger_ID IN (SELECT Booking_Passenger_ID FROM booking_passenger WHERE Booking_ID = @bk);
DELETE FROM booking_status_history WHERE Booking_Passenger_ID IN (SELECT Booking_Passenger_ID FROM booking_passenger WHERE Booking_ID = @bk);
DELETE FROM booking_passenger WHERE Booking_ID = @bk;
DELETE FROM booking WHERE Booking_ID = @bk;
UPDATE seat_inventory SET Available_CNF = @o_cnf, RAC_Count = @o_rac, WL_Count = @o_wl WHERE Run_ID = @run_id AND Class_Code = 'SL';
SELECT Available_CNF, RAC_Count, WL_Count FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';

-- =============================================================================================
-- TEST 20: sp_promote_rac_wl moves the oldest WL passenger to RAC when a RAC place becomes free
--          (sp_promote_rac_wl second rule, trg_adjust_inventory_on_status WL->RAC)
-- =============================================================================================
-- (setup) remember the counters; TEST-ONLY shortcut: no seat left and RAC full; then one passenger lands on the waiting list
SELECT Available_CNF, RAC_Count, WL_Count INTO @o_cnf, @o_rac, @o_wl
FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';
UPDATE seat_inventory SET Available_CNF = 0, RAC_Count = Max_RAC, WL_Count = 0 WHERE Run_ID = @run_id AND Class_Code = 'SL';
CALL sp_book_ticket(3, @run_id, 'SL', 2, 1, '[1]');
SELECT Booking_ID INTO @bk FROM booking
WHERE User_ID = 3 AND Run_ID = @run_id ORDER BY Booking_ID DESC LIMIT 1;
SELECT Booking_Passenger_ID INTO @bp FROM booking_passenger WHERE Booking_ID = @bk LIMIT 1;
-- BEFORE
SELECT bp.Status AS Passenger_Status, si.Available_CNF, si.RAC_Count, si.Max_RAC, si.WL_Count
FROM booking_passenger bp
JOIN seat_inventory si ON si.Run_ID = @run_id AND si.Class_Code = 'SL'
WHERE bp.Booking_Passenger_ID = @bp;                   -- EXPECT: WL, RAC full, WL_Count 1
-- ACTION step 1: TEST-ONLY shortcut - one RAC place becomes free (as if a RAC passenger had cancelled)
UPDATE seat_inventory SET RAC_Count = RAC_Count - 1 WHERE Run_ID = @run_id AND Class_Code = 'SL';
-- ACTION step 2: promote (the caller owns the transaction)
START TRANSACTION;
CALL sp_promote_rac_wl(@run_id, 'SL', @promoted);
COMMIT;
-- AFTER
SELECT @promoted AS Promoted_Count;                    -- EXPECT 1
SELECT bp.Status AS Passenger_Status, si.RAC_Count, si.Max_RAC, si.WL_Count,
       IF(bp.Status = 'RAC' AND si.RAC_Count = si.Max_RAC AND si.WL_Count = 0, 'PASS', 'FAIL') AS Result
FROM booking_passenger bp
JOIN seat_inventory si ON si.Run_ID = @run_id AND si.Class_Code = 'SL'
WHERE bp.Booking_Passenger_ID = @bp;
SELECT Old_Status, New_Status FROM booking_status_history WHERE Booking_Passenger_ID = @bp ORDER BY History_ID;   -- EXPECT WL->RAC
-- CLEANUP
DELETE FROM seat_allocation WHERE Booking_Passenger_ID IN (SELECT Booking_Passenger_ID FROM booking_passenger WHERE Booking_ID = @bk);
DELETE FROM booking_status_history WHERE Booking_Passenger_ID IN (SELECT Booking_Passenger_ID FROM booking_passenger WHERE Booking_ID = @bk);
DELETE FROM booking_passenger WHERE Booking_ID = @bk;
DELETE FROM booking WHERE Booking_ID = @bk;
UPDATE seat_inventory SET Available_CNF = @o_cnf, RAC_Count = @o_rac, WL_Count = @o_wl WHERE Run_ID = @run_id AND Class_Code = 'SL';
SELECT Available_CNF, RAC_Count, WL_Count FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';

-- =============================================================================================
-- TEST 21: sp_promote_rac_wl edge case - nobody is waiting, so nothing is promoted (result 0, counters untouched)
--          (a run 400 days in the future with no bookings is created for this test and removed again)
-- =============================================================================================
-- (setup)
INSERT INTO train_run (Train_ID, Journey_Date) VALUES (1, DATE_ADD(CURDATE(), INTERVAL 400 DAY));
SET @new_run = LAST_INSERT_ID();
-- BEFORE
SELECT Class_Code, Total_Seats, Available_CNF, RAC_Count, WL_Count FROM seat_inventory WHERE Run_ID = @new_run AND Class_Code = 'SL';
-- ACTION
START TRANSACTION;
CALL sp_promote_rac_wl(@new_run, 'SL', @promoted);
COMMIT;
-- AFTER
SELECT @promoted AS Promoted_Count,                    -- EXPECT 0
       Available_CNF, RAC_Count, WL_Count,
       IF(@promoted = 0 AND Available_CNF = Total_Seats AND RAC_Count = 0 AND WL_Count = 0, 'PASS', 'FAIL') AS Result
FROM seat_inventory WHERE Run_ID = @new_run AND Class_Code = 'SL';
-- CLEANUP
DELETE FROM seat_inventory WHERE Run_ID = @new_run;
DELETE FROM train_run_status WHERE Run_ID = @new_run;
DELETE FROM train_run WHERE Run_ID = @new_run;
SELECT COUNT(*) AS New_Run_Rows_Left FROM train_run WHERE Run_ID = @new_run;

-- =============================================================================================
-- TEST 22: trg_dec_inventory edge case - a booking_passenger row inserted as CANCELLED changes no counter
-- =============================================================================================
-- (setup) remember the counters; insert a bare booking row (no passengers yet)
SELECT Available_CNF, RAC_Count, WL_Count INTO @o_cnf, @o_rac, @o_wl
FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';
INSERT INTO booking (PNR, User_ID, Run_ID, Class_Code, From_Station_ID, To_Station_ID)
VALUES (fn_generate_pnr(), 3, @run_id, 'SL', 2, 1);
SET @bk = LAST_INSERT_ID();
-- BEFORE
SELECT Available_CNF, RAC_Count, WL_Count FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';
-- ACTION
INSERT INTO booking_passenger (Booking_ID, Passenger_ID, Status, Base_Fare, Concession_Type, Fare_Amount)
VALUES (@bk, 1, 'CANCELLED', 120.00, 'NONE', 120.00);
-- AFTER
SELECT Available_CNF, RAC_Count, WL_Count,
       IF(Available_CNF = @o_cnf AND RAC_Count = @o_rac AND WL_Count = @o_wl, 'PASS - no counter changed', 'FAIL') AS Result
FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';
-- CLEANUP
DELETE FROM booking_status_history WHERE Booking_Passenger_ID IN (SELECT Booking_Passenger_ID FROM booking_passenger WHERE Booking_ID = @bk);
DELETE FROM booking_passenger WHERE Booking_ID = @bk;
DELETE FROM booking WHERE Booking_ID = @bk;
SELECT Available_CNF, RAC_Count, WL_Count FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';

-- =============================================================================================
-- TEST 23: trg_adjust_inventory_on_status - cancelling a RAC passenger gives the RAC place back (RAC->CANCELLED)
-- =============================================================================================
-- (setup) remember the counters, leave one seat, book Asha (CNF) and Suresh (RAC)
SELECT Available_CNF, RAC_Count, WL_Count INTO @o_cnf, @o_rac, @o_wl
FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';
UPDATE seat_inventory SET Available_CNF = 1 WHERE Run_ID = @run_id AND Class_Code = 'SL';   -- TEST-ONLY shortcut
CALL sp_book_ticket(3, @run_id, 'SL', 2, 1, '[1,2]');
SELECT Booking_ID INTO @bk FROM booking
WHERE User_ID = 3 AND Run_ID = @run_id ORDER BY Booking_ID DESC LIMIT 1;
SELECT Booking_Passenger_ID INTO @bp_rac FROM booking_passenger WHERE Booking_ID = @bk AND Status = 'RAC' LIMIT 1;
-- BEFORE
SELECT Available_CNF, RAC_Count, @o_rac AS RAC_Count_Before_Test FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';   -- RAC_Count is one higher
-- ACTION
UPDATE booking_passenger SET Status = 'CANCELLED' WHERE Booking_Passenger_ID = @bp_rac;
-- AFTER
SELECT RAC_Count, @o_rac AS RAC_Count_Before_Test, IF(RAC_Count = @o_rac, 'PASS', 'FAIL') AS Result
FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';
SELECT Old_Status, New_Status FROM booking_status_history WHERE Booking_Passenger_ID = @bp_rac ORDER BY History_ID;   -- EXPECT RAC->CANCELLED
-- CLEANUP
DELETE FROM seat_allocation WHERE Booking_Passenger_ID IN (SELECT Booking_Passenger_ID FROM booking_passenger WHERE Booking_ID = @bk);
DELETE FROM booking_status_history WHERE Booking_Passenger_ID IN (SELECT Booking_Passenger_ID FROM booking_passenger WHERE Booking_ID = @bk);
DELETE FROM booking_passenger WHERE Booking_ID = @bk;
DELETE FROM booking WHERE Booking_ID = @bk;
UPDATE seat_inventory SET Available_CNF = @o_cnf, RAC_Count = @o_rac, WL_Count = @o_wl WHERE Run_ID = @run_id AND Class_Code = 'SL';
SELECT Available_CNF, RAC_Count, WL_Count FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';

-- =============================================================================================
-- TEST 24: trg_adjust_inventory_on_status edge cases - (a) an UPDATE that does not change Status does nothing,
--          (b) a transition that is not in the contract list (CNF->RAC) changes no counter but IS written to the history
-- =============================================================================================
-- (setup) remember the counters, book one passenger (CNF)
SELECT Available_CNF, RAC_Count, WL_Count INTO @o_cnf, @o_rac, @o_wl
FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';
CALL sp_book_ticket(3, @run_id, 'SL', 2, 1, '[1]');
SELECT Booking_ID INTO @bk FROM booking
WHERE User_ID = 3 AND Run_ID = @run_id ORDER BY Booking_ID DESC LIMIT 1;
SELECT Booking_Passenger_ID INTO @bp FROM booking_passenger WHERE Booking_ID = @bk LIMIT 1;
-- BEFORE
SELECT Available_CNF, RAC_Count, WL_Count FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';
SELECT COUNT(*) AS History_Rows FROM booking_status_history WHERE Booking_Passenger_ID = @bp;   -- 0
-- ACTION (a): change a column other than Status
UPDATE booking_passenger SET Base_Fare = Base_Fare + 1 WHERE Booking_Passenger_ID = @bp;
-- AFTER (a): still no history row, counters unchanged
SELECT (SELECT COUNT(*) FROM booking_status_history WHERE Booking_Passenger_ID = @bp) AS History_Rows,
       Available_CNF, RAC_Count, WL_Count,
       IF((SELECT COUNT(*) FROM booking_status_history WHERE Booking_Passenger_ID = @bp) = 0, 'PASS', 'FAIL') AS Result
FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';
-- ACTION (b): unlisted transition CNF -> RAC
UPDATE booking_passenger SET Status = 'RAC' WHERE Booking_Passenger_ID = @bp;
-- AFTER (b): counters did not move, but one history row CNF->RAC exists
SELECT Available_CNF, RAC_Count, WL_Count FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';   -- same as after the booking
SELECT Old_Status, New_Status FROM booking_status_history WHERE Booking_Passenger_ID = @bp ORDER BY History_ID;   -- EXPECT CNF->RAC
-- CLEANUP (direct deletes, then the saved counters are restored; the status trick above left the counters inconsistent on purpose)
DELETE FROM seat_allocation WHERE Booking_Passenger_ID IN (SELECT Booking_Passenger_ID FROM booking_passenger WHERE Booking_ID = @bk);
DELETE FROM booking_status_history WHERE Booking_Passenger_ID IN (SELECT Booking_Passenger_ID FROM booking_passenger WHERE Booking_ID = @bk);
DELETE FROM booking_passenger WHERE Booking_ID = @bk;
DELETE FROM booking WHERE Booking_ID = @bk;
UPDATE seat_inventory SET Available_CNF = @o_cnf, RAC_Count = @o_rac, WL_Count = @o_wl WHERE Run_ID = @run_id AND Class_Code = 'SL';
SELECT Available_CNF, RAC_Count, WL_Count FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';

-- =============================================================================================
-- TEST 25: sp_expire_unpaid_bookings expires an old unpaid booking, frees its seats and cancels its passengers
-- =============================================================================================
-- (setup) remember the counters, book two passengers, then make the booking look 10 years old (TEST-ONLY UPDATE of Booked_At).
-- Ten years is used together with a 1,000,000 minute limit (about 1.9 years) so that ONLY this test booking qualifies
-- and any other unpaid booking in the database (for example demo data) is left alone.
SELECT Available_CNF, RAC_Count, WL_Count INTO @o_cnf, @o_rac, @o_wl
FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';
CALL sp_book_ticket(3, @run_id, 'SL', 2, 1, '[1,2]');
SELECT Booking_ID INTO @bk FROM booking
WHERE User_ID = 3 AND Run_ID = @run_id ORDER BY Booking_ID DESC LIMIT 1;
UPDATE booking SET Booked_At = DATE_SUB(NOW(), INTERVAL 10 YEAR) WHERE Booking_ID = @bk;
-- BEFORE
SELECT Booking_ID, Booking_Status, Booked_At FROM booking WHERE Booking_ID = @bk;
SELECT Status, COUNT(*) AS Passengers FROM booking_passenger WHERE Booking_ID = @bk GROUP BY Status;
SELECT COUNT(*) AS Seat_Allocations FROM seat_allocation WHERE Booking_Passenger_ID IN (SELECT Booking_Passenger_ID FROM booking_passenger WHERE Booking_ID = @bk);
SELECT Available_CNF, @o_cnf AS Available_CNF_Before_Test FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';   -- 2 lower
-- ACTION
CALL sp_expire_unpaid_bookings(1000000);              -- EXPECT Expired_Count 1
-- AFTER
SELECT Booking_ID, Booking_Status FROM booking WHERE Booking_ID = @bk;   -- EXPECT EXPIRED
SELECT Status, COUNT(*) AS Passengers FROM booking_passenger WHERE Booking_ID = @bk GROUP BY Status;   -- EXPECT CANCELLED x2
SELECT COUNT(*) AS Seat_Allocations FROM seat_allocation WHERE Booking_Passenger_ID IN (SELECT Booking_Passenger_ID FROM booking_passenger WHERE Booking_ID = @bk);   -- EXPECT 0
SELECT Available_CNF, @o_cnf AS Available_CNF_Before_Test, IF(Available_CNF = @o_cnf, 'PASS', 'FAIL') AS Result
FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';
-- CLEANUP
DELETE FROM seat_allocation WHERE Booking_Passenger_ID IN (SELECT Booking_Passenger_ID FROM booking_passenger WHERE Booking_ID = @bk);
DELETE FROM booking_status_history WHERE Booking_Passenger_ID IN (SELECT Booking_Passenger_ID FROM booking_passenger WHERE Booking_ID = @bk);
DELETE FROM booking_passenger WHERE Booking_ID = @bk;
DELETE FROM booking WHERE Booking_ID = @bk;
UPDATE seat_inventory SET Available_CNF = @o_cnf, RAC_Count = @o_rac, WL_Count = @o_wl WHERE Run_ID = @run_id AND Class_Code = 'SL';
SELECT Available_CNF, RAC_Count, WL_Count FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';

-- =============================================================================================
-- TEST 26: sp_expire_unpaid_bookings edge cases - an old CONFIRMED (paid) booking is never expired, and a second call finds nothing (0)
-- =============================================================================================
-- (setup) remember the counters, book one passenger, mark the booking CONFIRMED and old (TEST-ONLY; the real flow confirms through G4 payment)
SELECT Available_CNF, RAC_Count, WL_Count INTO @o_cnf, @o_rac, @o_wl
FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';
CALL sp_book_ticket(3, @run_id, 'SL', 2, 1, '[3]');
SELECT Booking_ID INTO @bk FROM booking
WHERE User_ID = 3 AND Run_ID = @run_id ORDER BY Booking_ID DESC LIMIT 1;
UPDATE booking SET Booking_Status = 'CONFIRMED', Booked_At = DATE_SUB(NOW(), INTERVAL 10 YEAR) WHERE Booking_ID = @bk;
-- BEFORE
SELECT Booking_ID, Booking_Status, Booked_At FROM booking WHERE Booking_ID = @bk;
SELECT Status, COUNT(*) AS Passengers FROM booking_passenger WHERE Booking_ID = @bk GROUP BY Status;
-- ACTION
CALL sp_expire_unpaid_bookings(1000000);              -- EXPECT Expired_Count 0
-- AFTER
SELECT Booking_ID, Booking_Status, IF(Booking_Status = 'CONFIRMED', 'PASS - not expired', 'FAIL') AS Result FROM booking WHERE Booking_ID = @bk;
SELECT Status, COUNT(*) AS Passengers FROM booking_passenger WHERE Booking_ID = @bk GROUP BY Status;   -- EXPECT still CNF
-- CLEANUP
DELETE FROM seat_allocation WHERE Booking_Passenger_ID IN (SELECT Booking_Passenger_ID FROM booking_passenger WHERE Booking_ID = @bk);
DELETE FROM booking_status_history WHERE Booking_Passenger_ID IN (SELECT Booking_Passenger_ID FROM booking_passenger WHERE Booking_ID = @bk);
DELETE FROM booking_passenger WHERE Booking_ID = @bk;
DELETE FROM booking WHERE Booking_ID = @bk;
UPDATE seat_inventory SET Available_CNF = @o_cnf, RAC_Count = @o_rac, WL_Count = @o_wl WHERE Run_ID = @run_id AND Class_Code = 'SL';
SELECT Available_CNF, RAC_Count, WL_Count FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';

-- =============================================================================================
-- TEST 27: both views - edge case: a completely full class shows REGRET, 100.0 % occupancy and rank 1
-- =============================================================================================
-- (setup) remember the counters
SELECT Available_CNF, RAC_Count, WL_Count INTO @o_cnf, @o_rac, @o_wl
FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';
-- BEFORE
SELECT Class_Code, Available_CNF, RAC_Count, WL_Count, Availability_Text FROM v_seat_availability WHERE Run_ID = @run_id AND Class_Code = 'SL';
SELECT Class_Code, Booked_Seats, Occupancy_Pct, Occupancy_Rank FROM v_run_occupancy WHERE Run_ID = @run_id AND Class_Code = 'SL';
-- ACTION: TEST-ONLY shortcut - sold out, RAC full, waiting list full
UPDATE seat_inventory SET Available_CNF = 0, RAC_Count = Max_RAC, WL_Count = Max_WL WHERE Run_ID = @run_id AND Class_Code = 'SL';
-- AFTER
SELECT Class_Code, Available_CNF, RAC_Count, WL_Count, Availability_Text,     -- EXPECT REGRET
       IF(Availability_Text = 'REGRET', 'PASS', 'FAIL') AS Result
FROM v_seat_availability WHERE Run_ID = @run_id AND Class_Code = 'SL';
SELECT Class_Code, Total_Seats, Booked_Seats, Occupancy_Pct, Occupancy_Rank,   -- EXPECT 144 booked, 100.0, rank 1
       IF(Occupancy_Pct = 100.0 AND Occupancy_Rank = 1, 'PASS', 'FAIL') AS Result
FROM v_run_occupancy WHERE Run_ID = @run_id AND Class_Code = 'SL';
-- CLEANUP
UPDATE seat_inventory SET Available_CNF = @o_cnf, RAC_Count = @o_rac, WL_Count = @o_wl WHERE Run_ID = @run_id AND Class_Code = 'SL';
SELECT Available_CNF, RAC_Count, WL_Count FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = 'SL';

-- =============================================================================================
-- TEARDOWN
-- =============================================================================================
SET SQL_SAFE_UPDATES = 1;

-- SUMMARY - what each test proves
--   TEST  1  fn_generate_pnr: 10 digits, first digit 1-9, valid over 1000 calls.
--   TEST  2  fn_availability_text: AVL / RAC / WL / REGRET and every boundary (last seat, last RAC place, last WL place, no RAC/WL allowed).
--   TEST  3  sp_book_ticket normal booking: both passengers CNF, seats allocated, fares with senior concession, Available_CNF down by 2 (trg_dec_inventory CNF).
--   TEST  4  First come, first served: one seat left, two passengers -> CNF + RAC (trg_dec_inventory RAC).
--   TEST  5  trg_block_if_wl_full fires BOOKING_CLOSED_WL_FULL; the whole booking rolls back, counters and booking count unchanged.
--   TEST  6  Manual cancel + sp_promote_rac_wl: RAC becomes CNF with a seat; trg_adjust_inventory_on_status CNF->CANCELLED and RAC->CNF; history rows written.
--   TEST  7  Two-session concurrency: the second booking waits for the first session's lock on seat_inventory, then gets RAC (row-level locking).
--   TEST  8  UNIQUE(Run_ID, Seat_ID) rejects a manual double allocation of one seat (DUPLICATE).
--   TEST  9  v_seat_availability and v_run_occupancy return correct rows for a normal state.
--   TEST 10  sp_book_ticket: TOO_MANY_PASSENGERS for 7 passengers.
--   TEST 11  sp_book_ticket: VALIDATION_ERROR for an empty passenger list.
--   TEST 12  sp_book_ticket: INVALID_STATIONS when "from" is after "to" on the route.
--   TEST 13  sp_book_ticket: PASSENGER_NOT_OWNED, and the part already inserted is rolled back.
--   TEST 14  sp_book_ticket: SEAT_UNAVAILABLE for a class the train does not have.
--   TEST 15  sp_book_ticket: RUN_NOT_FOUND.
--   TEST 16  sp_book_ticket: RUN_DEPARTED for a run in the past.
--   TEST 17  trg_run_init_inventory: one inventory row per class, Total_Seats / Available_CNF / Max_RAC (10 %) / Max_WL (20 %) correct.
--   TEST 18  trg_run_init_inventory edge: a train without coaches gets no inventory rows.
--   TEST 19  trg_block_if_wl_full normal (WL accepted while not full), trg_dec_inventory WL branch, trg_adjust_inventory_on_status WL->CANCELLED.
--   TEST 20  sp_promote_rac_wl moves a WL passenger to RAC when a RAC place is free (trg_adjust_inventory_on_status WL->RAC).
--   TEST 21  sp_promote_rac_wl edge: nobody waiting -> 0 promotions, counters untouched.
--   TEST 22  trg_dec_inventory edge: a row inserted as CANCELLED changes no counter.
--   TEST 23  trg_adjust_inventory_on_status RAC->CANCELLED gives the RAC place back.
--   TEST 24  trg_adjust_inventory_on_status edges: no Status change = no history; unlisted transition = no counter change but history row.
--   TEST 25  sp_expire_unpaid_bookings: old unpaid booking becomes EXPIRED, passengers CANCELLED, seats freed, counters restored.
--   TEST 26  sp_expire_unpaid_bookings edges: an old CONFIRMED booking is not expired; nothing to expire = 0.
--   TEST 27  Views edge: a full class shows REGRET, 100.0 % occupancy and rank 1.
--   Coverage: functions (TEST 1-2), sp_book_ticket (3-5, 7-8, 10-16), sp_promote_rac_wl (6, 20, 21), sp_expire_unpaid_bookings (25-26),
--   trg_run_init_inventory (17-18), trg_block_if_wl_full (5, 19), trg_dec_inventory (3, 4, 19, 22),
--   trg_adjust_inventory_on_status (6, 19, 20, 23, 24), views (9, 27).
