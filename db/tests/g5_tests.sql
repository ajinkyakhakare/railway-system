-- G5.3 | owner: G5 (Railway Operations & Analytics) | SQL proof tests: fn_delay_minutes, sp_update_train_status, sp_generate_daily_revenue, 3 triggers, 4 views, 4 report queries
-- ============================================================================================================
-- HOW TO RUN
--   * Needs the finished database (init-db script: schemas, functions, procedures, triggers, views, seeds).
--   * MySQL Workbench: open this file, select the schema railway_db, then run it statement by statement
--     (Ctrl+Enter) top to bottom for screenshots. Same session = the @variables below stay alive.
--   * Command line (all at once):  mysql --force -u root -p railway_db < db/tests/g5_tests.sql
--     --force keeps going after the statements marked "EXPECT ERROR" (those are meant to fail).
--   * Every block is: -- TEST <n> / -- BEFORE / -- ACTION / -- AFTER  (+ SETUP / CLEANUP where needed).
--     AFTER queries print PASS or FAIL in a Check_Result column.
--   * Test data uses far-future dates (2099-..), the old date 2020-01-15, train numbers 999xx, route names
--     'ZZ-G5 ...' and PNRs 'ZZG5......'. Nothing from the seed/demo data is changed; all test rows are
--     deleted again.
--   * Workbench starts with "Safe Updates" ON, which rejects some of the cleanup DELETEs. STEP 0 therefore sets
--     SQL_SAFE_UPDATES = 0 for THIS SESSION only (remembering the old value) and the last statement restores it.
--     Run STEP 0 first, in the same session, or the cleanup statements may be refused.
-- ============================================================================================================


-- ============================================================================================================
-- STEP 0: session setup, then remove leftovers of an earlier interrupted run (does nothing on a clean database)
-- ============================================================================================================
SET @old_safe_updates := @@SQL_SAFE_UPDATES;
SET SQL_SAFE_UPDATES = 0;
DELETE FROM payment WHERE Booking_ID IN (SELECT Booking_ID FROM booking WHERE PNR LIKE 'ZZG5%');
DELETE FROM booking WHERE PNR LIKE 'ZZG5%';
DELETE FROM station_daily_revenue WHERE Revenue_ID > 0 AND Revenue_Date IN ('2020-01-15', '2020-01-16');
DELETE FROM delay_log WHERE Run_ID IN (SELECT Run_ID FROM train_run WHERE Journey_Date >= '2099-01-01');
DELETE FROM train_run_status WHERE Run_ID IN (SELECT Run_ID FROM train_run WHERE Journey_Date >= '2099-01-01');
DELETE FROM seat_inventory WHERE Run_ID IN (SELECT Run_ID FROM train_run WHERE Journey_Date >= '2099-01-01');
DELETE FROM train_run WHERE Journey_Date >= '2099-01-01';
DELETE FROM train WHERE Train_No LIKE '999__';
DELETE FROM route WHERE Route_Name LIKE 'ZZ-G5%';


-- ============================================================================================================
-- SECTION 1: FUNCTION fn_delay_minutes(scheduled, actual)  = GREATEST(minutes between them, 0)
-- ============================================================================================================

-- TEST 1: a train that arrives 25 minutes after schedule has a delay of 25
-- BEFORE
SELECT '2026-10-28 10:00:00' AS Scheduled, '2026-10-28 10:25:00' AS Actual;
-- ACTION
SELECT fn_delay_minutes('2026-10-28 10:00:00', '2026-10-28 10:25:00') AS Delay_Minutes;
-- AFTER
SELECT 25 AS Expected,
       fn_delay_minutes('2026-10-28 10:00:00', '2026-10-28 10:25:00') AS Actual,
       IF(fn_delay_minutes('2026-10-28 10:00:00', '2026-10-28 10:25:00') = 25, 'PASS', 'FAIL') AS Check_Result;

-- TEST 2: EDGE - a train that arrives EARLY has delay 0, never a negative number
-- BEFORE
SELECT '2026-10-28 10:00:00' AS Scheduled, '2026-10-28 09:50:00' AS Actual;
-- ACTION
SELECT fn_delay_minutes('2026-10-28 10:00:00', '2026-10-28 09:50:00') AS Delay_Minutes;
-- AFTER
SELECT 0 AS Expected,
       fn_delay_minutes('2026-10-28 10:00:00', '2026-10-28 09:50:00') AS Actual,
       IF(fn_delay_minutes('2026-10-28 10:00:00', '2026-10-28 09:50:00') = 0, 'PASS', 'FAIL') AS Check_Result;

-- TEST 3: EDGE - exactly on time gives delay 0
-- BEFORE
SELECT '2026-10-28 10:00:00' AS Scheduled, '2026-10-28 10:00:00' AS Actual;
-- ACTION
SELECT fn_delay_minutes('2026-10-28 10:00:00', '2026-10-28 10:00:00') AS Delay_Minutes;
-- AFTER
SELECT 0 AS Expected,
       fn_delay_minutes('2026-10-28 10:00:00', '2026-10-28 10:00:00') AS Actual,
       IF(fn_delay_minutes('2026-10-28 10:00:00', '2026-10-28 10:00:00') = 0, 'PASS', 'FAIL') AS Check_Result;

-- TEST 4: EDGE - delay that crosses midnight is measured on full date-times (23:50 -> 00:20 next day = 30)
-- BEFORE
SELECT '2026-10-28 23:50:00' AS Scheduled, '2026-10-29 00:20:00' AS Actual;
-- ACTION
SELECT fn_delay_minutes('2026-10-28 23:50:00', '2026-10-29 00:20:00') AS Delay_Minutes;
-- AFTER
SELECT 30 AS Expected,
       fn_delay_minutes('2026-10-28 23:50:00', '2026-10-29 00:20:00') AS Actual,
       IF(fn_delay_minutes('2026-10-28 23:50:00', '2026-10-29 00:20:00') = 30, 'PASS', 'FAIL') AS Check_Result;


-- ============================================================================================================
-- SECTION 2: TRIGGER trg_run_init_status  (AFTER INSERT ON train_run)
-- Fixture A (train only): a throw-away train 99991 on route 1 (removed at the end of SECTION 3).
-- ============================================================================================================
INSERT INTO train (Train_No, Train_Name, Train_Type, Route_ID)
VALUES ('99991', 'ZZ-G5 Test Train', 'EXPRESS', 1);
SET @train := LAST_INSERT_ID();
SELECT Train_ID, Train_No, Train_Name FROM train WHERE Train_ID = @train;

-- TEST 5: inserting a new train run automatically creates its status row: SCHEDULED, 0 minutes late
-- BEFORE
SELECT COUNT(*) AS Runs_Of_Test_Train,
       (SELECT COUNT(*) FROM train_run_status s JOIN train_run r ON r.Run_ID = s.Run_ID
         WHERE r.Train_ID = @train) AS Status_Rows
FROM train_run WHERE Train_ID = @train;
-- ACTION
INSERT INTO train_run (Train_ID, Journey_Date) VALUES (@train, '2099-12-29');
-- AFTER
SELECT r.Run_ID, r.Journey_Date, s.Status, s.Delay_Minutes, s.Current_Station_ID,
       IF(s.Status = 'SCHEDULED' AND s.Delay_Minutes = 0, 'PASS', 'FAIL') AS Check_Result
FROM train_run r
LEFT JOIN train_run_status s ON s.Run_ID = r.Run_ID
WHERE r.Train_ID = @train AND r.Journey_Date = '2099-12-29';
-- CLEANUP
DELETE FROM train_run_status WHERE Run_ID IN (SELECT Run_ID FROM train_run WHERE Train_ID = @train);
DELETE FROM train_run WHERE Train_ID = @train;

-- TEST 6: EDGE - a run has exactly one status row; inserting a second one by hand is rejected
-- EXPECT ERROR DUPLICATE   (MySQL error 1062 duplicate primary key; the backend maps it to DUPLICATE)
-- SETUP
INSERT INTO train_run (Train_ID, Journey_Date) VALUES (@train, '2099-12-29');
SET @run_dup := (SELECT Run_ID FROM train_run WHERE Train_ID = @train AND Journey_Date = '2099-12-29');
-- BEFORE
SELECT COUNT(*) AS Status_Rows_For_Run FROM train_run_status WHERE Run_ID = @run_dup;
-- ACTION
INSERT INTO train_run_status (Run_ID) VALUES (@run_dup);
-- AFTER
SELECT COUNT(*) AS Status_Rows_For_Run,
       IF(COUNT(*) = 1, 'PASS', 'FAIL') AS Check_Result
FROM train_run_status WHERE Run_ID = @run_dup;
-- CLEANUP
DELETE FROM train_run_status WHERE Run_ID = @run_dup;
DELETE FROM train_run WHERE Run_ID = @run_dup;


-- ============================================================================================================
-- SECTION 3: TRIGGERS trg_status_flag + trg_delay_log, PROCEDURE sp_update_train_status, VIEW v_train_live_status
-- Fixture A (run): one run of the test train on 2099-12-31. The trigger from TEST 5 creates its status row.
-- After every test the status row is reset to SCHEDULED / 0 and its delay_log rows are removed.
-- ============================================================================================================
INSERT INTO train_run (Train_ID, Journey_Date) VALUES (@train, '2099-12-31');
SET @run := (SELECT Run_ID FROM train_run WHERE Train_ID = @train AND Journey_Date = '2099-12-31');
SELECT Run_ID, Status, Delay_Minutes, Current_Station_ID FROM train_run_status WHERE Run_ID = @run;

-- TEST 7: trg_status_flag - delay 20 on an ON_TIME train flips the status to DELAYED
-- SETUP
UPDATE train_run_status SET Status = 'ON_TIME' WHERE Run_ID = @run;
-- BEFORE
SELECT Run_ID, Status, Delay_Minutes FROM train_run_status WHERE Run_ID = @run;
-- ACTION
UPDATE train_run_status SET Delay_Minutes = 20 WHERE Run_ID = @run;
-- AFTER
SELECT Run_ID, Status, Delay_Minutes,
       IF(Status = 'DELAYED' AND Delay_Minutes = 20, 'PASS', 'FAIL') AS Check_Result
FROM train_run_status WHERE Run_ID = @run;
-- CLEANUP
UPDATE train_run_status SET Status = 'SCHEDULED', Delay_Minutes = 0, Current_Station_ID = NULL, Last_Reason = NULL WHERE Run_ID = @run;
DELETE FROM delay_log WHERE Run_ID = @run;

-- TEST 8: trg_status_flag - clearing the delay (0) on a DELAYED train flips the status back to ON_TIME
-- SETUP
UPDATE train_run_status SET Status = 'DELAYED', Delay_Minutes = 45 WHERE Run_ID = @run;
-- BEFORE
SELECT Run_ID, Status, Delay_Minutes FROM train_run_status WHERE Run_ID = @run;
-- ACTION
UPDATE train_run_status SET Delay_Minutes = 0 WHERE Run_ID = @run;
-- AFTER
SELECT Run_ID, Status, Delay_Minutes,
       IF(Status = 'ON_TIME' AND Delay_Minutes = 0, 'PASS', 'FAIL') AS Check_Result
FROM train_run_status WHERE Run_ID = @run;
-- CLEANUP
UPDATE train_run_status SET Status = 'SCHEDULED', Delay_Minutes = 0, Current_Station_ID = NULL, Last_Reason = NULL WHERE Run_ID = @run;
DELETE FROM delay_log WHERE Run_ID = @run;

-- TEST 9: trg_status_flag EDGE - 14 minutes is below the 15 minute limit, status stays ON_TIME
-- SETUP
UPDATE train_run_status SET Status = 'ON_TIME' WHERE Run_ID = @run;
-- BEFORE
SELECT Run_ID, Status, Delay_Minutes FROM train_run_status WHERE Run_ID = @run;
-- ACTION
UPDATE train_run_status SET Delay_Minutes = 14 WHERE Run_ID = @run;
-- AFTER
SELECT Run_ID, Status, Delay_Minutes,
       IF(Status = 'ON_TIME' AND Delay_Minutes = 14, 'PASS', 'FAIL') AS Check_Result
FROM train_run_status WHERE Run_ID = @run;
-- CLEANUP
UPDATE train_run_status SET Status = 'SCHEDULED', Delay_Minutes = 0, Current_Station_ID = NULL, Last_Reason = NULL WHERE Run_ID = @run;
DELETE FROM delay_log WHERE Run_ID = @run;

-- TEST 10: trg_status_flag EDGE - exactly 15 minutes already counts as DELAYED (SCHEDULED -> DELAYED)
-- BEFORE
SELECT Run_ID, Status, Delay_Minutes FROM train_run_status WHERE Run_ID = @run;
-- ACTION
UPDATE train_run_status SET Delay_Minutes = 15 WHERE Run_ID = @run;
-- AFTER
SELECT Run_ID, Status, Delay_Minutes,
       IF(Status = 'DELAYED' AND Delay_Minutes = 15, 'PASS', 'FAIL') AS Check_Result
FROM train_run_status WHERE Run_ID = @run;
-- CLEANUP
UPDATE train_run_status SET Status = 'SCHEDULED', Delay_Minutes = 0, Current_Station_ID = NULL, Last_Reason = NULL WHERE Run_ID = @run;
DELETE FROM delay_log WHERE Run_ID = @run;

-- TEST 11: trg_status_flag EDGE - a CANCELLED train stays CANCELLED even with a long delay value
-- BEFORE
SELECT Run_ID, Status, Delay_Minutes FROM train_run_status WHERE Run_ID = @run;
-- ACTION
UPDATE train_run_status SET Status = 'CANCELLED', Delay_Minutes = 30 WHERE Run_ID = @run;
-- AFTER
SELECT Run_ID, Status, Delay_Minutes,
       IF(Status = 'CANCELLED' AND Delay_Minutes = 30, 'PASS', 'FAIL') AS Check_Result
FROM train_run_status WHERE Run_ID = @run;
-- CLEANUP
UPDATE train_run_status SET Status = 'SCHEDULED', Delay_Minutes = 0, Current_Station_ID = NULL, Last_Reason = NULL WHERE Run_ID = @run;
DELETE FROM delay_log WHERE Run_ID = @run;

-- TEST 12: trg_delay_log - changing Delay_Minutes writes one delay_log row (run, station, new delay, reason)
-- BEFORE
SELECT COUNT(*) AS Log_Rows FROM delay_log WHERE Run_ID = @run;
-- ACTION
UPDATE train_run_status
SET Delay_Minutes = 25, Current_Station_ID = 3, Last_Reason = 'Signal failure'
WHERE Run_ID = @run;
-- AFTER
SELECT Delay_Log_ID, Run_ID, Station_ID, Delay_Minutes, Reason,
       IF(Station_ID = 3 AND Delay_Minutes = 25 AND Reason = 'Signal failure', 'PASS', 'FAIL') AS Check_Result
FROM delay_log WHERE Run_ID = @run;
-- CLEANUP
UPDATE train_run_status SET Status = 'SCHEDULED', Delay_Minutes = 0, Current_Station_ID = NULL, Last_Reason = NULL WHERE Run_ID = @run;
DELETE FROM delay_log WHERE Run_ID = @run;

-- TEST 13: trg_delay_log EDGE - an update that does NOT change Delay_Minutes (only reason/station) adds no log row
-- SETUP (creates the first and only expected log row)
UPDATE train_run_status SET Delay_Minutes = 25 WHERE Run_ID = @run;
-- BEFORE
SELECT COUNT(*) AS Log_Rows FROM delay_log WHERE Run_ID = @run;
-- ACTION
UPDATE train_run_status SET Last_Reason = 'Track work', Current_Station_ID = 4 WHERE Run_ID = @run;
-- AFTER
SELECT COUNT(*) AS Log_Rows,
       IF(COUNT(*) = 1, 'PASS', 'FAIL') AS Check_Result
FROM delay_log WHERE Run_ID = @run;
-- CLEANUP
UPDATE train_run_status SET Status = 'SCHEDULED', Delay_Minutes = 0, Current_Station_ID = NULL, Last_Reason = NULL WHERE Run_ID = @run;
DELETE FROM delay_log WHERE Run_ID = @run;

-- TEST 14: sp_update_train_status - normal call; the triggers flag the run DELAYED and write the delay log
-- BEFORE
SELECT Run_ID, Status, Delay_Minutes, Current_Station_ID FROM train_run_status WHERE Run_ID = @run;
-- ACTION  (result set: Run_ID, Status, Delay_Minutes, Updated_At)
CALL sp_update_train_status(@run, 'ON_TIME', 20, 3, 'Signal failure');
-- AFTER
SELECT Run_ID, Status, Delay_Minutes, Current_Station_ID, Last_Reason,
       IF(Status = 'DELAYED' AND Delay_Minutes = 20 AND Current_Station_ID = 3, 'PASS', 'FAIL') AS Check_Result
FROM train_run_status WHERE Run_ID = @run;
SELECT COUNT(*) AS Log_Rows, IF(COUNT(*) = 1, 'PASS', 'FAIL') AS Check_Result
FROM delay_log WHERE Run_ID = @run AND Delay_Minutes = 20;
-- CLEANUP
UPDATE train_run_status SET Status = 'SCHEDULED', Delay_Minutes = 0, Current_Station_ID = NULL, Last_Reason = NULL WHERE Run_ID = @run;
DELETE FROM delay_log WHERE Run_ID = @run;

-- TEST 15: sp_update_train_status EDGE - the current station may be NULL (position unknown)
-- BEFORE
SELECT Run_ID, Status, Delay_Minutes, Current_Station_ID FROM train_run_status WHERE Run_ID = @run;
-- ACTION
CALL sp_update_train_status(@run, 'ON_TIME', 0, NULL, NULL);
-- AFTER
SELECT Run_ID, Status, Delay_Minutes, Current_Station_ID,
       IF(Status = 'ON_TIME' AND Delay_Minutes = 0 AND Current_Station_ID IS NULL, 'PASS', 'FAIL') AS Check_Result
FROM train_run_status WHERE Run_ID = @run;
-- CLEANUP
UPDATE train_run_status SET Status = 'SCHEDULED', Delay_Minutes = 0, Current_Station_ID = NULL, Last_Reason = NULL WHERE Run_ID = @run;
DELETE FROM delay_log WHERE Run_ID = @run;

-- TEST 16: sp_update_train_status - an unknown status text is rejected and nothing is changed
-- EXPECT ERROR INVALID_STATUS
-- BEFORE
SELECT Run_ID, Status, Delay_Minutes FROM train_run_status WHERE Run_ID = @run;
-- ACTION
CALL sp_update_train_status(@run, 'FLYING', 10, NULL, NULL);
-- AFTER
SELECT Run_ID, Status, Delay_Minutes,
       IF(Status = 'SCHEDULED' AND Delay_Minutes = 0, 'PASS', 'FAIL') AS Check_Result
FROM train_run_status WHERE Run_ID = @run;

-- TEST 17: sp_update_train_status - a run id that does not exist is rejected
-- EXPECT ERROR RUN_NOT_FOUND
-- BEFORE
SELECT COUNT(*) AS Runs_With_This_Id FROM train_run WHERE Run_ID = 4000000000;
-- ACTION
CALL sp_update_train_status(4000000000, 'ON_TIME', 0, NULL, NULL);
-- AFTER
SELECT COUNT(*) AS Status_Rows_For_Missing_Run,
       IF(COUNT(*) = 0, 'PASS', 'FAIL') AS Check_Result
FROM train_run_status WHERE Run_ID = 4000000000;

-- TEST 18: v_train_live_status - shows train number/name, date, status, delay and the NAME of the current station
-- BEFORE
SELECT Run_ID, Train_No, Status, Delay_Minutes, Current_Station_Name FROM v_train_live_status WHERE Run_ID = @run;
-- ACTION
UPDATE train_run_status
SET Status = 'DELAYED', Delay_Minutes = 30, Current_Station_ID = 3, Last_Reason = 'Signal failure'
WHERE Run_ID = @run;
-- AFTER
SELECT Run_ID, Train_No, Train_Name, Journey_Date, Status, Delay_Minutes,
       Current_Station_ID, Current_Station_Name, Last_Reason, Updated_At,
       IF(Train_No = '99991' AND Train_Name = 'ZZ-G5 Test Train' AND Journey_Date = '2099-12-31'
          AND Status = 'DELAYED' AND Delay_Minutes = 30
          AND Current_Station_Name = 'Kalyan Junction' AND Last_Reason = 'Signal failure', 'PASS', 'FAIL') AS Check_Result
FROM v_train_live_status WHERE Run_ID = @run;
-- CLEANUP
UPDATE train_run_status SET Status = 'SCHEDULED', Delay_Minutes = 0, Current_Station_ID = NULL, Last_Reason = NULL WHERE Run_ID = @run;
DELETE FROM delay_log WHERE Run_ID = @run;

-- TEST 19: v_train_live_status EDGE - a run with no reported position is still listed (LEFT JOIN), station name NULL
-- BEFORE
SELECT Run_ID, Status, Current_Station_ID FROM train_run_status WHERE Run_ID = @run;
-- ACTION
SELECT * FROM v_train_live_status WHERE Run_ID = @run;
-- AFTER
SELECT COUNT(*) AS Rows_In_View,
       IF(COUNT(*) = 1 AND SUM(Current_Station_Name IS NULL) = 1 AND SUM(Status = 'SCHEDULED') = 1, 'PASS', 'FAIL') AS Check_Result
FROM v_train_live_status WHERE Run_ID = @run;

-- Remove fixture A (run + train)
DELETE FROM delay_log WHERE Run_ID = @run;
DELETE FROM train_run_status WHERE Run_ID = @run;
DELETE FROM train_run WHERE Run_ID = @run;
DELETE FROM train WHERE Train_ID = @train;
SELECT (SELECT COUNT(*) FROM train WHERE Train_No = '99991') AS Test_Trains_Left,
       (SELECT COUNT(*) FROM train_run WHERE Journey_Date >= '2099-01-01') AS Test_Runs_Left;


-- ============================================================================================================
-- SECTION 4: PROCEDURE sp_generate_daily_revenue, VIEWS v_station_daily_revenue / v_popular_routes /
--            v_delay_metrics, and the REPORT queries.
-- Fixture B (created once, removed at the very end; tests that change it restore it in their CLEANUP):
--   routes  ZZ-G5 Route A / B / C         (stations 1 -> 2)
--   trains  99991 on A (2 runs), 99992 on B, 99993 on C   (runs on 2099-12-31, plus 2099-12-30 for 99991)
--   delays  99991: 20 min and 40 min | 99992: 5 min | 99993: 0 min
--   bookings on 2020-01-15 (all by user 3, class SL), payments made 2020-01-15 10:00:
--     ZZG5000001 route A from PUNE(1)  1000.00 CONFIRMED          payment SUCCESS
--     ZZG5000002 route A from PUNE(1)   500.00 CONFIRMED          payment SUCCESS
--     ZZG5000003 route B from CSMT(2)   250.00 CONFIRMED          payment SUCCESS
--     ZZG5000004 route B from KYN(3)    300.00 PENDING_PAYMENT    payment FAILED
--     ZZG5000005 route C from CSMT(2)   100.00 CONFIRMED          payment SUCCESS
--     ZZG5000006 route C from CSMT(2)    80.00 EXPIRED            (no payment)
-- Expected: revenue PUNE 1500.00 (2 tickets), CSMT 350.00 (2 tickets), KYN none (payment failed);
--           booking counts A=2, B=2, C=1 (EXPIRED not counted).
-- ============================================================================================================
INSERT INTO route (Route_Name, Source_Station_ID, Dest_Station_ID)
VALUES ('ZZ-G5 Route A', 1, 2), ('ZZ-G5 Route B', 1, 2), ('ZZ-G5 Route C', 1, 2);

INSERT INTO train (Train_No, Train_Name, Train_Type, Route_ID)
VALUES ('99991', 'ZZ-G5 Train A', 'EXPRESS', (SELECT Route_ID FROM route WHERE Route_Name = 'ZZ-G5 Route A')),
       ('99992', 'ZZ-G5 Train B', 'EXPRESS', (SELECT Route_ID FROM route WHERE Route_Name = 'ZZ-G5 Route B')),
       ('99993', 'ZZ-G5 Train C', 'EXPRESS', (SELECT Route_ID FROM route WHERE Route_Name = 'ZZ-G5 Route C'));

INSERT INTO train_run (Train_ID, Journey_Date)
SELECT Train_ID, '2099-12-31' FROM train WHERE Train_No IN ('99991', '99992', '99993');
INSERT INTO train_run (Train_ID, Journey_Date)
SELECT Train_ID, '2099-12-30' FROM train WHERE Train_No = '99991';

SET @runA1 := (SELECT r.Run_ID FROM train_run r JOIN train t ON t.Train_ID = r.Train_ID WHERE t.Train_No = '99991' AND r.Journey_Date = '2099-12-31');
SET @runA2 := (SELECT r.Run_ID FROM train_run r JOIN train t ON t.Train_ID = r.Train_ID WHERE t.Train_No = '99991' AND r.Journey_Date = '2099-12-30');
SET @runB  := (SELECT r.Run_ID FROM train_run r JOIN train t ON t.Train_ID = r.Train_ID WHERE t.Train_No = '99992' AND r.Journey_Date = '2099-12-31');
SET @runC  := (SELECT r.Run_ID FROM train_run r JOIN train t ON t.Train_ID = r.Train_ID WHERE t.Train_No = '99993' AND r.Journey_Date = '2099-12-31');

UPDATE train_run_status SET Delay_Minutes = 20, Last_Reason = 'Fog'        WHERE Run_ID = @runA1;
UPDATE train_run_status SET Delay_Minutes = 40, Last_Reason = 'Track work' WHERE Run_ID = @runA2;
UPDATE train_run_status SET Delay_Minutes = 5,  Last_Reason = 'Late start' WHERE Run_ID = @runB;

INSERT INTO booking (PNR, User_ID, Run_ID, Class_Code, From_Station_ID, To_Station_ID, Booking_Status, Total_Fare, Booked_At)
VALUES ('ZZG5000001', 3, @runA1, 'SL', 1, 2, 'CONFIRMED',       1000.00, '2020-01-15 08:00:00'),
       ('ZZG5000002', 3, @runA1, 'SL', 1, 2, 'CONFIRMED',        500.00, '2020-01-15 08:10:00'),
       ('ZZG5000003', 3, @runB,  'SL', 2, 1, 'CONFIRMED',        250.00, '2020-01-15 08:20:00'),
       ('ZZG5000004', 3, @runB,  'SL', 3, 1, 'PENDING_PAYMENT',  300.00, '2020-01-15 08:30:00'),
       ('ZZG5000005', 3, @runC,  'SL', 2, 1, 'CONFIRMED',        100.00, '2020-01-15 08:40:00'),
       ('ZZG5000006', 3, @runC,  'SL', 2, 1, 'EXPIRED',           80.00, '2020-01-15 08:50:00');

INSERT INTO payment (Booking_ID, Amount, Payment_Mode, Payment_Status, Created_At, Paid_At)
SELECT Booking_ID, Total_Fare, 'MOCK', IF(PNR = 'ZZG5000004', 'FAILED', 'SUCCESS'),
       '2020-01-15 09:55:00', '2020-01-15 10:00:00'
FROM booking
WHERE PNR IN ('ZZG5000001', 'ZZG5000002', 'ZZG5000003', 'ZZG5000004', 'ZZG5000005');

-- fixture check (should list 6 bookings; 5 payments of which 1 FAILED)
SELECT b.PNR, b.Booking_Status, b.From_Station_ID, b.Total_Fare, p.Payment_Status, p.Amount
FROM booking b LEFT JOIN payment p ON p.Booking_ID = b.Booking_ID
WHERE b.PNR LIKE 'ZZG5%' ORDER BY b.PNR;

-- TEST 20: sp_generate_daily_revenue - one row per origin station, successful payments only
-- BEFORE
SELECT COUNT(*) AS Rows_For_2020_01_15 FROM station_daily_revenue WHERE Revenue_Date = '2020-01-15';
-- ACTION  (result set: Rows_Affected)
CALL sp_generate_daily_revenue('2020-01-15');
-- AFTER
SELECT Station_ID, Revenue_Date, Total_Revenue, Ticket_Count,
       IF((Station_ID = 1 AND Total_Revenue = 1500.00 AND Ticket_Count = 2)
       OR (Station_ID = 2 AND Total_Revenue =  350.00 AND Ticket_Count = 2), 'PASS', 'FAIL') AS Check_Result
FROM station_daily_revenue WHERE Revenue_Date = '2020-01-15' ORDER BY Station_ID;
SELECT COUNT(*) AS Rows_For_2020_01_15,
       IF(COUNT(*) = 2, 'PASS', 'FAIL') AS Check_Result_No_Row_For_Failed_Payment
FROM station_daily_revenue WHERE Revenue_Date = '2020-01-15';
-- CLEANUP
DELETE FROM station_daily_revenue WHERE Revenue_ID > 0 AND Revenue_Date = '2020-01-15';

-- TEST 21: sp_generate_daily_revenue - running it twice gives the same result (idempotent, no duplicate rows)
-- BEFORE
SELECT COUNT(*) AS Rows_For_2020_01_15 FROM station_daily_revenue WHERE Revenue_Date = '2020-01-15';
-- ACTION  (two runs in a row)
CALL sp_generate_daily_revenue('2020-01-15');
CALL sp_generate_daily_revenue('2020-01-15');
-- AFTER
SELECT COUNT(*) AS Row_Count, SUM(Total_Revenue) AS Sum_Revenue, SUM(Ticket_Count) AS Sum_Tickets,
       IF(COUNT(*) = 2 AND SUM(Total_Revenue) = 1850.00 AND SUM(Ticket_Count) = 4, 'PASS', 'FAIL') AS Check_Result
FROM station_daily_revenue WHERE Revenue_Date = '2020-01-15';
-- CLEANUP
DELETE FROM station_daily_revenue WHERE Revenue_ID > 0 AND Revenue_Date = '2020-01-15';

-- TEST 22: sp_generate_daily_revenue EDGE - a new payment after the first run is picked up by the next run (upsert UPDATE path)
-- SETUP
CALL sp_generate_daily_revenue('2020-01-15');
-- BEFORE
SELECT Station_ID, Total_Revenue, Ticket_Count FROM station_daily_revenue WHERE Revenue_Date = '2020-01-15' ORDER BY Station_ID;
-- ACTION  (a second successful payment of 200.00 on booking ZZG5000001, then run again)
INSERT INTO payment (Booking_ID, Amount, Payment_Mode, Payment_Status, Gateway_Payment_ID, Created_At, Paid_At)
SELECT Booking_ID, 200.00, 'MOCK', 'SUCCESS', 'ZZG5-EXTRA', '2020-01-15 14:00:00', '2020-01-15 15:00:00'
FROM booking WHERE PNR = 'ZZG5000001';
CALL sp_generate_daily_revenue('2020-01-15');
-- AFTER
SELECT Station_ID, Total_Revenue, Ticket_Count,
       IF((Station_ID = 1 AND Total_Revenue = 1700.00 AND Ticket_Count = 2)
       OR (Station_ID = 2 AND Total_Revenue =  350.00 AND Ticket_Count = 2), 'PASS', 'FAIL') AS Check_Result
FROM station_daily_revenue WHERE Revenue_Date = '2020-01-15' ORDER BY Station_ID;
-- CLEANUP
DELETE FROM payment WHERE Payment_ID > 0 AND Gateway_Payment_ID = 'ZZG5-EXTRA';
DELETE FROM station_daily_revenue WHERE Revenue_ID > 0 AND Revenue_Date = '2020-01-15';

-- TEST 23: sp_generate_daily_revenue EDGE - a date without successful payments creates no rows
-- BEFORE
SELECT COUNT(*) AS Successful_Payments_On_2020_01_16
FROM payment WHERE Payment_Status = 'SUCCESS' AND DATE(Paid_At) = '2020-01-16';
-- ACTION  (Rows_Affected should be 0)
CALL sp_generate_daily_revenue('2020-01-16');
-- AFTER
SELECT COUNT(*) AS Rows_For_2020_01_16,
       IF(COUNT(*) = 0, 'PASS', 'FAIL') AS Check_Result
FROM station_daily_revenue WHERE Revenue_Date = '2020-01-16';

-- TEST 24: v_station_daily_revenue - groups successful payments by origin station and day; FAILED payment is ignored
-- BEFORE  (raw payments of the fixture, note the FAILED one for KYN)
SELECT b.PNR, b.From_Station_ID, p.Amount, p.Payment_Status, DATE(p.Paid_At) AS Paid_Day
FROM payment p JOIN booking b ON b.Booking_ID = p.Booking_ID
WHERE b.PNR LIKE 'ZZG5%' ORDER BY b.PNR;
-- ACTION
SELECT * FROM v_station_daily_revenue WHERE Revenue_Date = '2020-01-15' ORDER BY Station_ID;
-- AFTER
SELECT COUNT(*) AS Rows_In_View,
       IF(COUNT(*) = 2
          AND SUM(Station_ID = 1 AND Total_Revenue = 1500.00 AND Ticket_Count = 2) = 1
          AND SUM(Station_ID = 2 AND Total_Revenue =  350.00 AND Ticket_Count = 2) = 1
          AND SUM(Station_ID = 3) = 0, 'PASS', 'FAIL') AS Check_Result
FROM v_station_daily_revenue WHERE Revenue_Date = '2020-01-15';

-- TEST 25: v_station_daily_revenue EDGE - two successful payments for ONE booking add up in revenue but count as one ticket
-- BEFORE
SELECT Station_ID, Station_Code, Total_Revenue, Ticket_Count
FROM v_station_daily_revenue WHERE Revenue_Date = '2020-01-15' AND Station_ID = 1;
-- ACTION
INSERT INTO payment (Booking_ID, Amount, Payment_Mode, Payment_Status, Gateway_Payment_ID, Created_At, Paid_At)
SELECT Booking_ID, 200.00, 'MOCK', 'SUCCESS', 'ZZG5-EXTRA', '2020-01-15 14:00:00', '2020-01-15 15:00:00'
FROM booking WHERE PNR = 'ZZG5000001';
-- AFTER
SELECT Station_ID, Station_Code, Total_Revenue, Ticket_Count,
       IF(Total_Revenue = 1700.00 AND Ticket_Count = 2, 'PASS', 'FAIL') AS Check_Result
FROM v_station_daily_revenue WHERE Revenue_Date = '2020-01-15' AND Station_ID = 1;
-- CLEANUP
DELETE FROM payment WHERE Payment_ID > 0 AND Gateway_Payment_ID = 'ZZG5-EXTRA';

-- TEST 26: v_popular_routes - bookings per route with RANK(); routes with equal counts share a rank and a gap follows
-- BEFORE  (bookings of the fixture per route and status)
SELECT ro.Route_Name, b.Booking_Status, COUNT(*) AS Bookings
FROM booking b
JOIN train_run r ON r.Run_ID = b.Run_ID
JOIN train t ON t.Train_ID = r.Train_ID
JOIN route ro ON ro.Route_ID = t.Route_ID
WHERE b.PNR LIKE 'ZZG5%'
GROUP BY ro.Route_Name, b.Booking_Status
ORDER BY ro.Route_Name, b.Booking_Status;
-- ACTION
SELECT * FROM v_popular_routes WHERE Route_Name LIKE 'ZZ-G5%' ORDER BY Popularity_Rank, Route_Name;
-- AFTER  (A and B both have 2 bookings -> same rank; C has 1 -> rank at least 2 places lower)
SELECT a.Booking_Count AS A_Count, b.Booking_Count AS B_Count, c.Booking_Count AS C_Count,
       a.Popularity_Rank AS A_Rank, b.Popularity_Rank AS B_Rank, c.Popularity_Rank AS C_Rank,
       IF(a.Booking_Count = 2 AND b.Booking_Count = 2 AND c.Booking_Count = 1
          AND a.Popularity_Rank = b.Popularity_Rank
          AND c.Popularity_Rank >= a.Popularity_Rank + 2, 'PASS', 'FAIL') AS Check_Result
FROM v_popular_routes a
JOIN v_popular_routes b ON b.Route_Name = 'ZZ-G5 Route B'
JOIN v_popular_routes c ON c.Route_Name = 'ZZ-G5 Route C'
WHERE a.Route_Name = 'ZZ-G5 Route A';

-- TEST 27: v_popular_routes EDGE - an EXPIRED booking is not counted
-- BEFORE
SELECT Route_Name, Booking_Count, Popularity_Rank FROM v_popular_routes WHERE Route_Name = 'ZZ-G5 Route C';
-- ACTION  (one more EXPIRED booking on route C)
INSERT INTO booking (PNR, User_ID, Run_ID, Class_Code, From_Station_ID, To_Station_ID, Booking_Status, Total_Fare, Booked_At)
VALUES ('ZZG5000007', 3, @runC, 'SL', 2, 1, 'EXPIRED', 90.00, '2020-01-15 09:00:00');
-- AFTER
SELECT Route_Name, Booking_Count, Popularity_Rank,
       IF(Booking_Count = 1, 'PASS', 'FAIL') AS Check_Result
FROM v_popular_routes WHERE Route_Name = 'ZZ-G5 Route C';
-- CLEANUP
DELETE FROM booking WHERE PNR = 'ZZG5000007';

-- TEST 28: v_delay_metrics - total runs, delayed runs, average (1 decimal) and maximum delay per train
-- BEFORE  (the status rows behind the numbers)
SELECT t.Train_No, r.Journey_Date, s.Status, s.Delay_Minutes
FROM train t JOIN train_run r ON r.Train_ID = t.Train_ID JOIN train_run_status s ON s.Run_ID = r.Run_ID
WHERE t.Train_No IN ('99991', '99992') ORDER BY t.Train_No, r.Journey_Date;
-- ACTION
SELECT * FROM v_delay_metrics WHERE Train_No IN ('99991', '99992') ORDER BY Train_No;
-- AFTER
SELECT Train_No, Total_Runs, Delayed_Runs, Avg_Delay_Min, Max_Delay_Min,
       IF((Train_No = '99991' AND Total_Runs = 2 AND Delayed_Runs = 2 AND Avg_Delay_Min = 30.0 AND Max_Delay_Min = 40)
       OR (Train_No = '99992' AND Total_Runs = 1 AND Delayed_Runs = 0 AND Avg_Delay_Min =  5.0 AND Max_Delay_Min =  5), 'PASS', 'FAIL') AS Check_Result
FROM v_delay_metrics WHERE Train_No IN ('99991', '99992') ORDER BY Train_No;

-- TEST 29: v_delay_metrics EDGE - a never-delayed train shows 0 / 0.0 / 0; a train without any run is not listed
-- SETUP  (train 99994 has no runs)
INSERT INTO train (Train_No, Train_Name, Train_Type, Route_ID)
VALUES ('99994', 'ZZ-G5 Train D', 'EXPRESS', (SELECT Route_ID FROM route WHERE Route_Name = 'ZZ-G5 Route A'));
-- BEFORE
SELECT t.Train_No, (SELECT COUNT(*) FROM train_run r WHERE r.Train_ID = t.Train_ID) AS Runs
FROM train t WHERE t.Train_No IN ('99993', '99994') ORDER BY t.Train_No;
-- ACTION
SELECT * FROM v_delay_metrics WHERE Train_No IN ('99993', '99994');
-- AFTER
SELECT COUNT(*) AS Rows_In_View,
       IF(COUNT(*) = 1
          AND SUM(Train_No = '99994') = 0
          AND SUM(Train_No = '99993' AND Total_Runs = 1 AND Delayed_Runs = 0 AND Avg_Delay_Min = 0.0 AND Max_Delay_Min = 0) = 1,
          'PASS', 'FAIL') AS Check_Result
FROM v_delay_metrics WHERE Train_No IN ('99993', '99994');
-- CLEANUP
DELETE FROM train WHERE Train_No = '99994';


-- ============================================================================================================
-- SECTION 5: REPORT QUERIES (the same SQL the backend uses for the G5 reports).
-- They run on ALL data in the database, so rows of the real seed/demo data appear next to the ZZ-G5 fixture rows.
-- ============================================================================================================

-- REPORT: delayed trains  (GROUP BY train, HAVING AVG(Delay_Minutes) > 15)
-- Fixture expectation: train 99991 appears (average 30.0, 2 delayed runs); 99992 (5.0) and 99993 (0.0) do not.
SELECT t.Train_ID, t.Train_No, t.Train_Name,
       ROUND(AVG(s.Delay_Minutes), 1)                   AS Avg_Delay_Min,
       COUNT(CASE WHEN s.Status = 'DELAYED' THEN 1 END) AS Delayed_Runs
FROM train t
JOIN train_run r        ON r.Train_ID = t.Train_ID
JOIN train_run_status s ON s.Run_ID = r.Run_ID
GROUP BY t.Train_ID, t.Train_No, t.Train_Name
HAVING AVG(s.Delay_Minutes) > 15
ORDER BY Avg_Delay_Min DESC;

-- REPORT: top stations above average revenue  (subquery computes the average of the per-station totals)
-- Fixture expectation: PUNE (1500.00) is above the average of PUNE and CSMT (925.00); CSMT (350.00) is not.
SELECT Station_ID, Station_Name, SUM(Total_Revenue) AS Station_Total_Revenue
FROM v_station_daily_revenue
GROUP BY Station_ID, Station_Name
HAVING SUM(Total_Revenue) > (
        SELECT AVG(per_station.Station_Total)
        FROM (SELECT SUM(Total_Revenue) AS Station_Total
              FROM v_station_daily_revenue
              GROUP BY Station_ID) AS per_station
      )
ORDER BY Station_Total_Revenue DESC;

-- REPORT: routes ranked - RANK() versus DENSE_RANK() side by side
-- RANK() leaves a gap after a tie (1, 1, 3); DENSE_RANK() does not (1, 1, 2).
-- Fixture expectation: Route A and Route B tie (2 bookings), Route C (1 booking) shows the difference.
SELECT Route_ID, Route_Name, Booking_Count,
       Popularity_Rank                                    AS Rank_With_Gaps,
       DENSE_RANK() OVER (ORDER BY Booking_Count DESC)    AS Dense_Rank_No_Gaps
FROM v_popular_routes
ORDER BY Popularity_Rank, Route_Name;

-- REPORT: dashboard summary counters  (six scalar subqueries in one row)
SELECT
    (SELECT COUNT(*) FROM booking)                                            AS Total_Bookings,
    (SELECT COUNT(*) FROM booking WHERE Booking_Status = 'CONFIRMED')         AS Confirmed_Bookings,
    (SELECT COALESCE(SUM(Amount), 0) FROM payment WHERE Payment_Status = 'SUCCESS') AS Total_Revenue,
    (SELECT COUNT(*) FROM train WHERE Is_Active = 1)                          AS Active_Trains,
    (SELECT COUNT(*) FROM train_run_status s JOIN train_run r ON r.Run_ID = s.Run_ID
      WHERE r.Journey_Date = CURDATE() AND s.Status = 'DELAYED')              AS Delayed_Runs_Today,
    (SELECT COUNT(*) FROM cancellation WHERE DATE(Cancelled_At) = CURDATE())  AS Cancellations_Today;


-- ============================================================================================================
-- FINAL CLEANUP: remove fixture B and any other test row (same statements as STEP 0)
-- ============================================================================================================
DELETE FROM payment WHERE Booking_ID IN (SELECT Booking_ID FROM booking WHERE PNR LIKE 'ZZG5%');
DELETE FROM booking WHERE PNR LIKE 'ZZG5%';
DELETE FROM station_daily_revenue WHERE Revenue_ID > 0 AND Revenue_Date IN ('2020-01-15', '2020-01-16');
DELETE FROM delay_log WHERE Run_ID IN (SELECT Run_ID FROM train_run WHERE Journey_Date >= '2099-01-01');
DELETE FROM train_run_status WHERE Run_ID IN (SELECT Run_ID FROM train_run WHERE Journey_Date >= '2099-01-01');
DELETE FROM seat_inventory WHERE Run_ID IN (SELECT Run_ID FROM train_run WHERE Journey_Date >= '2099-01-01');
DELETE FROM train_run WHERE Journey_Date >= '2099-01-01';
DELETE FROM train WHERE Train_No LIKE '999__';
DELETE FROM route WHERE Route_Name LIKE 'ZZ-G5%';

-- all counters below must be 0
SELECT (SELECT COUNT(*) FROM booking WHERE PNR LIKE 'ZZG5%')               AS Test_Bookings_Left,
       (SELECT COUNT(*) FROM train WHERE Train_No LIKE '999__')            AS Test_Trains_Left,
       (SELECT COUNT(*) FROM route WHERE Route_Name LIKE 'ZZ-G5%')         AS Test_Routes_Left,
       (SELECT COUNT(*) FROM train_run WHERE Journey_Date >= '2099-01-01') AS Test_Runs_Left,
       (SELECT COUNT(*) FROM station_daily_revenue WHERE Revenue_Date IN ('2020-01-15', '2020-01-16')) AS Test_Revenue_Rows_Left;

-- give the session its original Safe Updates setting back
SET SQL_SAFE_UPDATES = @old_safe_updates;


-- SUMMARY (what each test proves)
--   TEST  1  fn_delay_minutes: late arrival gives the number of minutes late
--   TEST  2  fn_delay_minutes: early arrival gives 0, never negative
--   TEST  3  fn_delay_minutes: exactly on time gives 0
--   TEST  4  fn_delay_minutes: works across midnight (full date-times)
--   TEST  5  trg_run_init_status: a new run gets a SCHEDULED / 0 status row automatically
--   TEST  6  trg_run_init_status: only one status row per run (duplicate insert fails, EXPECT ERROR DUPLICATE)
--   TEST  7  trg_status_flag: delay 20 on ON_TIME becomes DELAYED
--   TEST  8  trg_status_flag: delay 0 on DELAYED becomes ON_TIME
--   TEST  9  trg_status_flag: 14 minutes is below the limit, status stays ON_TIME
--   TEST 10  trg_status_flag: 15 minutes is the limit, SCHEDULED becomes DELAYED
--   TEST 11  trg_status_flag: CANCELLED is never changed by the trigger
--   TEST 12  trg_delay_log: a delay change writes a log row with station and reason
--   TEST 13  trg_delay_log: an update without a delay change writes no log row
--   TEST 14  sp_update_train_status: normal update; triggers flag the run DELAYED and log the delay
--   TEST 15  sp_update_train_status: current station may be NULL
--   TEST 16  sp_update_train_status: INVALID_STATUS for an unknown status, data unchanged
--   TEST 17  sp_update_train_status: RUN_NOT_FOUND for a missing run
--   TEST 18  v_train_live_status: shows train, date, status, delay and current station name
--   TEST 19  v_train_live_status: run without a position is still listed (station name NULL)
--   TEST 20  sp_generate_daily_revenue: one row per origin station, failed payments ignored
--   TEST 21  sp_generate_daily_revenue: running twice gives the same result (idempotent)
--   TEST 22  sp_generate_daily_revenue: a later payment is added by the next run (upsert update)
--   TEST 23  sp_generate_daily_revenue: date without payments creates no rows
--   TEST 24  v_station_daily_revenue: grouping by station and day, only SUCCESS payments
--   TEST 25  v_station_daily_revenue: two payments of one booking add revenue but count as one ticket
--   TEST 26  v_popular_routes: booking counts, tie gives equal RANK() and a gap after it
--   TEST 27  v_popular_routes: EXPIRED bookings are not counted
--   TEST 28  v_delay_metrics: total / delayed runs, average (1 decimal) and maximum delay per train
--   TEST 29  v_delay_metrics: never-delayed train shows zeros; train without runs is absent
--   REPORT   delayed trains (HAVING AVG > 15), top stations (subquery), RANK vs DENSE_RANK, dashboard counters
