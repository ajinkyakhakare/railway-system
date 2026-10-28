-- Task G4.3 | Owner: G4 (Payment, Cancellation & Refund) | Purpose: SQL proof scripts (BEFORE / ACTION / AFTER) for every G4 function, procedure, trigger and view
--
-- HOW TO RUN
--   * Open this file in MySQL Workbench, choose railway_db as the default schema (double-click it in the
--     SCHEMAS panel), then run ONE STATEMENT AT A TIME (Ctrl+Enter) so each result grid can be screenshotted.
--   * Use a single SQL tab: the tests keep ids in session variables (@run_id, @booking_id, ...).
--   * Blocks marked "EXPECT ERROR <CODE>" must fail with that code in the Output panel (that is the proof).
--   * Needs the G1-G3 objects (sp_book_ticket, sp_promote_rac_wl, seat_inventory ...) and the seeds 50-52.
--   * Every block cleans up after itself; TEST 30 proves the database is exactly as it was found.
--   * Command-line alternative (runs everything, continues after the expected errors):
--       mysql --force -u root -p railway_db < db/tests/g4_tests.sql

-- Workbench "safe update mode" blocks DELETEs on non-key columns, so switch it off (switched on again at the end).
SET SQL_SAFE_UPDATES = 0;

-- ===========================================================================
-- SETUP : test constants and a snapshot of the database (used by TEST 28-30)
-- ===========================================================================
SET @user_id         = 3;   -- Asha Patil, owner of passengers 1 (Asha), 2 (Suresh, senior), 3 (Aarav, child)
SET @other_user_id   = 4;   -- Rohan Deshmukh, used to prove NOT_OWNER
SET @from_station_id = 2;   -- Mumbai CSMT
SET @to_station_id   = 1;   -- Pune Jn (192 km from CSMT on route 1)
-- Train 1 (11001 Mumbai Pune Express), first run that is at least 3 days ahead.
-- A run that far ahead is always more than 48 hours before departure -> 10 % refund deduction.
SET @run_id = (SELECT Run_ID FROM train_run
               WHERE Train_ID = 1 AND Journey_Date >= DATE_ADD(CURDATE(), INTERVAL 3 DAY)
               ORDER BY Journey_Date LIMIT 1);

-- Pre-flight check: must show OK (otherwise run sp_generate_train_runs(1, CURDATE(), DATE_ADD(CURDATE(), INTERVAL 14 DAY)))
SELECT @run_id AS Run_ID,
       fn_departure_datetime(@run_id, @from_station_id) AS Departure_From_CSMT,
       IF(@run_id IS NULL, 'NO RUN FOUND - generate runs first', 'OK') AS Preflight;

-- Snapshot of every table the tests touch
SET @base_booking     = (SELECT COUNT(*) FROM booking);
SET @base_bp          = (SELECT COUNT(*) FROM booking_passenger);
SET @base_alloc       = (SELECT COUNT(*) FROM seat_allocation);
SET @base_history     = (SELECT COUNT(*) FROM booking_status_history);
SET @base_payment     = (SELECT COUNT(*) FROM payment);
SET @base_cancel      = (SELECT COUNT(*) FROM cancellation);
SET @base_refund      = (SELECT COUNT(*) FROM refund);
SET @base_fare_audit  = (SELECT COUNT(*) FROM fare_audit_log);
SET @base_cnf         = (SELECT Available_CNF FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = '3A');
SET @base_rac         = (SELECT RAC_Count     FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = '3A');
SET @base_wl          = (SELECT WL_Count      FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = '3A');
SET @base_fare_rules  = (SELECT GROUP_CONCAT(CONCAT(Fare_Rule_ID, ':', Base_Fare_Per_Km, ':', Min_Fare) ORDER BY Fare_Rule_ID) FROM fare_rule);

-- ===========================================================================
-- PART 1 - FUNCTIONS
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- TEST 1: fn_base_fare, SL class, 192 km -> 120.00 (the minimum fare wins: 192 x 0.55 = 105.60 < 120)
-- ---------------------------------------------------------------------------
-- BEFORE
SELECT Class_Code, Base_Fare_Per_Km, Min_Fare,
       ROUND(192 * Base_Fare_Per_Km, 2) AS Raw_Fare_192km
FROM fare_rule WHERE Class_Code = 'SL';
-- ACTION
SELECT fn_base_fare('SL', 192) AS Base_Fare_SL_192km;
-- AFTER
SELECT fn_base_fare('SL', 192) AS Actual, 120.00 AS Expected,
       IF(fn_base_fare('SL', 192) <=> 120.00, 'PASS', 'FAIL') AS Result;

-- ---------------------------------------------------------------------------
-- TEST 2: fn_base_fare, 3A class, 837 km (CSMT-Nagpur) -> 1213.65 (837 x 1.45, above the 300 minimum)
-- ---------------------------------------------------------------------------
-- BEFORE
SELECT Class_Code, Base_Fare_Per_Km, Min_Fare,
       ROUND(837 * Base_Fare_Per_Km, 2) AS Raw_Fare_837km
FROM fare_rule WHERE Class_Code = '3A';
-- ACTION
SELECT fn_base_fare('3A', 837) AS Base_Fare_3A_837km;
-- AFTER
SELECT fn_base_fare('3A', 837) AS Actual, 1213.65 AS Expected,
       IF(fn_base_fare('3A', 837) <=> 1213.65, 'PASS', 'FAIL') AS Result;

-- ---------------------------------------------------------------------------
-- TEST 3: fn_base_fare edge cases: class without a fare rule -> NULL ; 0 km -> Min_Fare of the class
-- ---------------------------------------------------------------------------
-- BEFORE
SELECT Class_Code, Min_Fare FROM fare_rule WHERE Class_Code = '1A';
SELECT COUNT(*) AS Rules_For_Class_XX FROM fare_rule WHERE Class_Code = 'XX';
-- ACTION
SELECT 'XX' AS Class_Code, 100 AS Distance_Km, fn_base_fare('XX', 100) AS Base_Fare
UNION ALL
SELECT '1A', 0, fn_base_fare('1A', 0);
-- AFTER
SELECT 'XX, 100 km (no rule)' AS Case_Name, 'NULL' AS Expected,
       IF(fn_base_fare('XX', 100) IS NULL, 'PASS', 'FAIL') AS Result
UNION ALL
SELECT '1A, 0 km (minimum fare)', '700.00',
       IF(fn_base_fare('1A', 0) <=> 700.00, 'PASS', 'FAIL');

-- ---------------------------------------------------------------------------
-- TEST 4: fn_net_fare for every concession type (base fare 1000.00)
--         NONE 1000.00 | SENIOR 600.00 | GOVT 750.00 | SOLDIER 500.00 | CHILD 500.00
-- ---------------------------------------------------------------------------
-- BEFORE
SELECT Concession_Rule_ID, Concession_Type, Discount_Percent FROM concession_rule ORDER BY Concession_Rule_ID;
-- ACTION
SELECT 'NONE' AS Concession_Type, fn_net_fare(1000.00, 'NONE') AS Net_Fare
UNION ALL SELECT 'SENIOR',  fn_net_fare(1000.00, 'SENIOR')
UNION ALL SELECT 'GOVT',    fn_net_fare(1000.00, 'GOVT')
UNION ALL SELECT 'SOLDIER', fn_net_fare(1000.00, 'SOLDIER')
UNION ALL SELECT 'CHILD',   fn_net_fare(1000.00, 'CHILD');
-- AFTER
SELECT cr.Concession_Type, cr.Discount_Percent,
       fn_net_fare(1000.00, cr.Concession_Type)           AS Actual,
       ROUND(1000.00 * (1 - cr.Discount_Percent / 100), 2) AS Expected,
       IF(fn_net_fare(1000.00, cr.Concession_Type) = ROUND(1000.00 * (1 - cr.Discount_Percent / 100), 2), 'PASS', 'FAIL') AS Result
FROM concession_rule cr ORDER BY cr.Concession_Rule_ID;

-- ---------------------------------------------------------------------------
-- TEST 5: fn_net_fare edge case: a type that is not in concession_rule gets 0 % discount
-- ---------------------------------------------------------------------------
-- BEFORE
SELECT COUNT(*) AS Rules_For_Type_XYZ FROM concession_rule WHERE Concession_Type = 'XYZ';
-- ACTION
SELECT fn_net_fare(1000.00, 'XYZ') AS Net_Fare_Unknown_Type;
-- AFTER
SELECT fn_net_fare(1000.00, 'XYZ') AS Actual, 1000.00 AS Expected,
       IF(fn_net_fare(1000.00, 'XYZ') <=> 1000.00, 'PASS', 'FAIL') AS Result;

-- ---------------------------------------------------------------------------
-- TEST 6: fn_refund_deduction_pct at 60 / 30 / 6 / 2 hours before departure -> 10 / 25 / 50 / 100 %
-- ---------------------------------------------------------------------------
-- BEFORE
SELECT Refund_Rule_ID, Min_Hours_Before, Max_Hours_Before, Deduction_Percent
FROM refund_rule ORDER BY Min_Hours_Before DESC;
-- ACTION
SELECT 60 AS Hours_Before, fn_refund_deduction_pct(60) AS Deduction_Pct
UNION ALL SELECT 30, fn_refund_deduction_pct(30)
UNION ALL SELECT 6,  fn_refund_deduction_pct(6)
UNION ALL SELECT 2,  fn_refund_deduction_pct(2);
-- AFTER
SELECT t.Hours_Before, t.Expected_Pct,
       fn_refund_deduction_pct(t.Hours_Before) AS Actual_Pct,
       IF(fn_refund_deduction_pct(t.Hours_Before) = t.Expected_Pct, 'PASS', 'FAIL') AS Result
FROM (SELECT 60.00 AS Hours_Before, 10.00 AS Expected_Pct
      UNION ALL SELECT 30.00, 25.00
      UNION ALL SELECT  6.00, 50.00
      UNION ALL SELECT  2.00, 100.00) t;

-- ---------------------------------------------------------------------------
-- TEST 7: fn_refund_deduction_pct edge cases: slab boundaries (Min inclusive, Max exclusive) and
--         a negative number of hours (no rule matches -> 100 %)
-- ---------------------------------------------------------------------------
-- BEFORE
SELECT Refund_Rule_ID, Min_Hours_Before, Max_Hours_Before, Deduction_Percent
FROM refund_rule ORDER BY Min_Hours_Before DESC;
-- ACTION
SELECT 48.00 AS Hours_Before, fn_refund_deduction_pct(48.00) AS Deduction_Pct
UNION ALL SELECT 47.99, fn_refund_deduction_pct(47.99)
UNION ALL SELECT 12.00, fn_refund_deduction_pct(12.00)
UNION ALL SELECT 11.99, fn_refund_deduction_pct(11.99)
UNION ALL SELECT  4.00, fn_refund_deduction_pct(4.00)
UNION ALL SELECT  3.99, fn_refund_deduction_pct(3.99)
UNION ALL SELECT  0.00, fn_refund_deduction_pct(0.00)
UNION ALL SELECT -5.00, fn_refund_deduction_pct(-5.00);
-- AFTER
SELECT t.Hours_Before, t.Expected_Pct,
       fn_refund_deduction_pct(t.Hours_Before) AS Actual_Pct,
       IF(fn_refund_deduction_pct(t.Hours_Before) = t.Expected_Pct, 'PASS', 'FAIL') AS Result
FROM (SELECT 48.00 AS Hours_Before, 10.00 AS Expected_Pct
      UNION ALL SELECT 47.99,  25.00
      UNION ALL SELECT 12.00,  25.00
      UNION ALL SELECT 11.99,  50.00
      UNION ALL SELECT  4.00,  50.00
      UNION ALL SELECT  3.99, 100.00
      UNION ALL SELECT  0.00, 100.00
      UNION ALL SELECT -5.00, 100.00) t;

-- ===========================================================================
-- PART 2 - TRIGGER trg_fare_audit
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- TEST 8: trg_fare_audit: changing the per-km rate of SL writes one fare_audit_log row (0.55 -> 0.60)
-- ---------------------------------------------------------------------------
-- BEFORE
SET @old_rate       = (SELECT Base_Fare_Per_Km FROM fare_rule WHERE Fare_Rule_ID = 1);
SET @old_min        = (SELECT Min_Fare         FROM fare_rule WHERE Fare_Rule_ID = 1);
SET @old_updated_at = (SELECT Updated_At       FROM fare_rule WHERE Fare_Rule_ID = 1);
SET @audit_mark     = (SELECT IFNULL(MAX(Audit_ID), 0) FROM fare_audit_log);
SELECT * FROM fare_rule WHERE Fare_Rule_ID = 1;
SELECT COUNT(*) AS New_Audit_Rows_Before FROM fare_audit_log WHERE Audit_ID > @audit_mark;
-- ACTION
UPDATE fare_rule SET Base_Fare_Per_Km = 0.60 WHERE Fare_Rule_ID = 1;
-- AFTER
SELECT * FROM fare_audit_log WHERE Audit_ID > @audit_mark;
SELECT * FROM fare_rule WHERE Fare_Rule_ID = 1;
-- CLEAN-UP (restore the rule, keep its old Updated_At, remove the audit rows of this test)
UPDATE fare_rule SET Base_Fare_Per_Km = @old_rate, Updated_At = @old_updated_at WHERE Fare_Rule_ID = 1;
DELETE FROM fare_audit_log WHERE Audit_ID > @audit_mark;
SELECT * FROM fare_rule WHERE Fare_Rule_ID = 1;

-- ---------------------------------------------------------------------------
-- TEST 9: trg_fare_audit: changing only the minimum fare is logged too (120.00 -> 130.00)
-- ---------------------------------------------------------------------------
-- BEFORE
SET @old_min        = (SELECT Min_Fare   FROM fare_rule WHERE Fare_Rule_ID = 1);
SET @old_updated_at = (SELECT Updated_At FROM fare_rule WHERE Fare_Rule_ID = 1);
SET @audit_mark     = (SELECT IFNULL(MAX(Audit_ID), 0) FROM fare_audit_log);
SELECT * FROM fare_rule WHERE Fare_Rule_ID = 1;
-- ACTION
UPDATE fare_rule SET Min_Fare = 130.00 WHERE Fare_Rule_ID = 1;
-- AFTER
SELECT * FROM fare_audit_log WHERE Audit_ID > @audit_mark;
-- CLEAN-UP
UPDATE fare_rule SET Min_Fare = @old_min, Updated_At = @old_updated_at WHERE Fare_Rule_ID = 1;
DELETE FROM fare_audit_log WHERE Audit_ID > @audit_mark;
SELECT * FROM fare_rule WHERE Fare_Rule_ID = 1;

-- ---------------------------------------------------------------------------
-- TEST 10: trg_fare_audit edge case: an UPDATE that changes neither rate nor minimum (only Updated_At)
--          fires the trigger but writes NO audit row
-- ---------------------------------------------------------------------------
-- BEFORE
SET @old_updated_at = (SELECT Updated_At FROM fare_rule WHERE Fare_Rule_ID = 1);
SET @audit_mark     = (SELECT IFNULL(MAX(Audit_ID), 0) FROM fare_audit_log);
SELECT Fare_Rule_ID, Base_Fare_Per_Km, Min_Fare, Updated_At FROM fare_rule WHERE Fare_Rule_ID = 1;
-- ACTION
UPDATE fare_rule SET Updated_At = DATE_ADD(Updated_At, INTERVAL 1 SECOND) WHERE Fare_Rule_ID = 1;
-- AFTER
SELECT COUNT(*) AS New_Audit_Rows_Expected_0 FROM fare_audit_log WHERE Audit_ID > @audit_mark;
SELECT Fare_Rule_ID, Base_Fare_Per_Km, Min_Fare, Updated_At FROM fare_rule WHERE Fare_Rule_ID = 1;
-- CLEAN-UP
UPDATE fare_rule SET Updated_At = @old_updated_at WHERE Fare_Rule_ID = 1;

-- ===========================================================================
-- PART 3 - PAYMENT PROCEDURES AND trg_payment_confirm
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- TEST 11: SET-UP (G3 procedure sp_book_ticket is used as a fixture): Asha books passengers 1 and 2
--          in 3A, CSMT -> Pune. Expected fares: 300.00 (192 km x 1.45 = 278.40, minimum 300) and
--          180.00 (senior, 40 % off) -> Total_Fare 480.00, booking PENDING_PAYMENT
-- ---------------------------------------------------------------------------
-- BEFORE
SELECT Run_ID, Class_Code, Total_Seats, Available_CNF, RAC_Count, WL_Count FROM seat_inventory
WHERE Run_ID = @run_id AND Class_Code = '3A';
SELECT COUNT(*) AS Bookings_Of_User_On_Run FROM booking WHERE User_ID = @user_id AND Run_ID = @run_id;
-- ACTION
CALL sp_book_ticket(@user_id, @run_id, '3A', @from_station_id, @to_station_id, '[1,2]');
SET @booking_id = (SELECT MAX(Booking_ID) FROM booking WHERE User_ID = @user_id AND Run_ID = @run_id);
SET @pnr1       = (SELECT PNR FROM booking WHERE Booking_ID = @booking_id);
-- AFTER
SELECT Booking_ID, PNR, Booking_Status, Total_Fare FROM booking WHERE Booking_ID = @booking_id;
SELECT bp.Booking_Passenger_ID, pa.Full_Name, bp.Status, bp.Base_Fare, bp.Concession_Type, bp.Fare_Amount
FROM booking_passenger bp JOIN passenger pa ON pa.Passenger_ID = bp.Passenger_ID
WHERE bp.Booking_ID = @booking_id ORDER BY bp.Booking_Passenger_ID;
SELECT Available_CNF, RAC_Count, WL_Count FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = '3A';

-- ---------------------------------------------------------------------------
-- TEST 12: sp_create_payment (normal): a CREATED payment of 480.00 (= Total_Fare) is inserted
-- ---------------------------------------------------------------------------
-- BEFORE
SELECT Booking_ID, Booking_Status, Total_Fare FROM booking WHERE Booking_ID = @booking_id;
SELECT COUNT(*) AS Payments_For_Booking FROM payment WHERE Booking_ID = @booking_id;
-- ACTION
SET @order1 = CONCAT('MOCK_', UUID());
CALL sp_create_payment(@user_id, @booking_id, 'MOCK', @order1);
SET @payment_id = (SELECT MAX(Payment_ID) FROM payment WHERE Booking_ID = @booking_id);
-- AFTER
SELECT Payment_ID, Booking_ID, Amount, Payment_Mode, Gateway_Order_ID, Payment_Status, Paid_At
FROM payment WHERE Payment_ID = @payment_id;
SELECT b.Total_Fare, p.Amount, IF(b.Total_Fare = p.Amount, 'PASS', 'FAIL') AS Amount_Equals_Total_Fare
FROM payment p JOIN booking b ON b.Booking_ID = p.Booking_ID WHERE p.Payment_ID = @payment_id;

-- ---------------------------------------------------------------------------
-- TEST 13: sp_create_payment failing case: booking does not exist
-- EXPECT ERROR BOOKING_NOT_FOUND
-- ---------------------------------------------------------------------------
-- BEFORE
SELECT COUNT(*) AS Bookings_With_Id_99999999 FROM booking WHERE Booking_ID = 99999999;
SET @payments_now = (SELECT COUNT(*) FROM payment);
-- ACTION
CALL sp_create_payment(@user_id, 99999999, 'MOCK', 'MOCK_SHOULD_NOT_BE_CREATED');
-- AFTER (no payment row was added)
SELECT COUNT(*) AS Payments_Now, @payments_now AS Payments_Before,
       IF(COUNT(*) = @payments_now, 'PASS', 'FAIL') AS Result FROM payment;

-- ---------------------------------------------------------------------------
-- TEST 14: sp_create_payment failing case: another user tries to pay Asha's booking
-- EXPECT ERROR NOT_OWNER
-- ---------------------------------------------------------------------------
-- BEFORE
SELECT b.Booking_ID, b.User_ID AS Owner_User_ID, @other_user_id AS Caller_User_ID FROM booking b WHERE b.Booking_ID = @booking_id;
SET @payments_now = (SELECT COUNT(*) FROM payment);
-- ACTION
CALL sp_create_payment(@other_user_id, @booking_id, 'MOCK', 'MOCK_SHOULD_NOT_BE_CREATED');
-- AFTER (no payment row was added)
SELECT COUNT(*) AS Payments_Now, @payments_now AS Payments_Before,
       IF(COUNT(*) = @payments_now, 'PASS', 'FAIL') AS Result FROM payment;

-- ---------------------------------------------------------------------------
-- TEST 15: sp_confirm_payment (success) + trg_payment_confirm: the payment becomes SUCCESS and the
--          TRIGGER (not the procedure) moves the booking from PENDING_PAYMENT to CONFIRMED
-- ---------------------------------------------------------------------------
-- BEFORE
SELECT Payment_ID, Payment_Status, Gateway_Payment_ID, Paid_At FROM payment WHERE Payment_ID = @payment_id;
SELECT Booking_ID, Booking_Status FROM booking WHERE Booking_ID = @booking_id;
-- ACTION
CALL sp_confirm_payment(@payment_id, 'pay_MOCK_G43_0001', 1);
-- AFTER
SELECT Payment_ID, Payment_Status, Gateway_Payment_ID, Paid_At FROM payment WHERE Payment_ID = @payment_id;
SELECT Booking_ID, Booking_Status FROM booking WHERE Booking_ID = @booking_id;

-- ---------------------------------------------------------------------------
-- TEST 16: sp_confirm_payment failing case: confirming the same payment a second time
-- EXPECT ERROR PAYMENT_NOT_ALLOWED
-- ---------------------------------------------------------------------------
-- BEFORE
SELECT Payment_ID, Payment_Status, Gateway_Payment_ID FROM payment WHERE Payment_ID = @payment_id;
-- ACTION
CALL sp_confirm_payment(@payment_id, 'pay_MOCK_G43_DUPLICATE', 1);
-- AFTER (payment unchanged: still SUCCESS with the first gateway payment id)
SELECT Payment_ID, Payment_Status, Gateway_Payment_ID FROM payment WHERE Payment_ID = @payment_id;

-- ---------------------------------------------------------------------------
-- TEST 17: sp_create_payment failing case: the booking is already CONFIRMED (not PENDING_PAYMENT)
-- EXPECT ERROR PAYMENT_NOT_ALLOWED
-- ---------------------------------------------------------------------------
-- BEFORE
SELECT Booking_ID, Booking_Status FROM booking WHERE Booking_ID = @booking_id;
SELECT COUNT(*) AS Payments_For_Booking FROM payment WHERE Booking_ID = @booking_id;
-- ACTION
CALL sp_create_payment(@user_id, @booking_id, 'MOCK', 'MOCK_SHOULD_NOT_BE_CREATED');
-- AFTER (still exactly one payment)
SELECT COUNT(*) AS Payments_For_Booking FROM payment WHERE Booking_ID = @booking_id;

-- ---------------------------------------------------------------------------
-- TEST 18: sp_confirm_payment (failure path) + trg_payment_confirm edge case: a FAILED payment must NOT
--          confirm the booking. Booking 2 (passenger 1 only, fare 300.00) stays PENDING_PAYMENT.
--          Booking 2 is also used by TEST 19, 24-27.
-- ---------------------------------------------------------------------------
-- BEFORE
SELECT COUNT(*) AS Bookings_Of_User_On_Run FROM booking WHERE User_ID = @user_id AND Run_ID = @run_id;
-- ACTION (run the statements one by one)
CALL sp_book_ticket(@user_id, @run_id, '3A', @from_station_id, @to_station_id, '[1]');
SET @booking2_id = (SELECT MAX(Booking_ID) FROM booking WHERE User_ID = @user_id AND Run_ID = @run_id);
SET @pnr2        = (SELECT PNR FROM booking WHERE Booking_ID = @booking2_id);
SET @order2      = CONCAT('MOCK_', UUID());
CALL sp_create_payment(@user_id, @booking2_id, 'MOCK', @order2);
SET @payment2_id = (SELECT MAX(Payment_ID) FROM payment WHERE Booking_ID = @booking2_id);
CALL sp_confirm_payment(@payment2_id, 'pay_MOCK_G43_FAILED', 0);
-- AFTER
SELECT Payment_ID, Amount, Payment_Status, Paid_At FROM payment WHERE Payment_ID = @payment2_id;
SELECT Booking_ID, PNR, Booking_Status, Total_Fare FROM booking WHERE Booking_ID = @booking2_id;

-- ===========================================================================
-- PART 4 - VIEW v_payment_history
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- TEST 19: v_payment_history: normal case = both payments of Asha (SUCCESS and FAILED) with their PNRs;
--          edge case = another user sees none of them (the backend filters by User_ID)
-- ---------------------------------------------------------------------------
-- BEFORE (the underlying tables)
SELECT p.Payment_ID, p.Booking_ID, p.Amount, p.Payment_Status FROM payment p
WHERE p.Booking_ID IN (@booking_id, @booking2_id) ORDER BY p.Payment_ID;
-- ACTION
SELECT * FROM v_payment_history WHERE PNR IN (@pnr1, @pnr2) ORDER BY Payment_ID;
-- AFTER (a) the view has exactly the contract columns, in order
SELECT COLUMN_NAME, ORDINAL_POSITION FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'v_payment_history' ORDER BY ORDINAL_POSITION;
-- AFTER (b) edge: user 4 sees 0 of Asha's payments, user 3 sees both
SELECT COUNT(*) AS Rows_For_User_4_Expected_0 FROM v_payment_history WHERE PNR IN (@pnr1, @pnr2) AND User_ID = @other_user_id;
SELECT COUNT(*) AS Rows_For_User_3_Expected_2 FROM v_payment_history WHERE PNR IN (@pnr1, @pnr2) AND User_ID = @user_id;

-- ===========================================================================
-- PART 5 - CANCELLATION: sp_cancel_ticket, refunds, v_refund_summary
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- TEST 20: sp_cancel_ticket (normal, paid ticket): passenger 1 (fare 300.00) of the CONFIRMED booking is
--          cancelled more than 48 h before departure -> 10 % deduction = 30.00, refund 270.00;
--          seat is freed, inventory counter goes back up, booking stays CONFIRMED (passenger 2 still travels).
--          Promoted_Count is 0 here because nobody is waiting; TEST 29 proves the promotion.
-- ---------------------------------------------------------------------------
-- BEFORE
SET @bp1   = (SELECT Booking_Passenger_ID FROM booking_passenger WHERE Booking_ID = @booking_id AND Passenger_ID = 1);
SET @bp2   = (SELECT Booking_Passenger_ID FROM booking_passenger WHERE Booking_ID = @booking_id AND Passenger_ID = 2);
SET @seat1 = (SELECT Seat_ID FROM seat_allocation WHERE Booking_Passenger_ID = @bp1);
SET @hours_before = TIMESTAMPDIFF(MINUTE, NOW(), fn_departure_datetime(@run_id, @from_station_id)) / 60;
SELECT @hours_before AS Hours_Before_Departure, fn_refund_deduction_pct(@hours_before) AS Expected_Deduction_Pct;
SELECT bp.Booking_Passenger_ID, bp.Status, bp.Fare_Amount, sa.Seat_ID AS Allocated_Seat_ID
FROM booking_passenger bp LEFT JOIN seat_allocation sa ON sa.Booking_Passenger_ID = bp.Booking_Passenger_ID
WHERE bp.Booking_ID = @booking_id ORDER BY bp.Booking_Passenger_ID;
SELECT Available_CNF, RAC_Count, WL_Count FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = '3A';
-- ACTION
CALL sp_cancel_ticket(@user_id, @bp1);
-- AFTER
SET @canc1 = (SELECT Cancellation_ID FROM cancellation WHERE Booking_Passenger_ID = @bp1);
SELECT Cancellation_ID, Booking_Passenger_ID, Hours_Before_Departure, Reason, Cancelled_At FROM cancellation WHERE Cancellation_ID = @canc1;
SELECT Refund_ID, Cancellation_ID, Payment_ID, Original_Fare, Deduction_Percent, Deduction_Amount, Refund_Amount, Refund_Status
FROM refund WHERE Cancellation_ID = @canc1;
SELECT bp.Booking_Passenger_ID, bp.Status, sa.Seat_ID AS Allocated_Seat_ID
FROM booking_passenger bp LEFT JOIN seat_allocation sa ON sa.Booking_Passenger_ID = bp.Booking_Passenger_ID
WHERE bp.Booking_ID = @booking_id ORDER BY bp.Booking_Passenger_ID;
SELECT @seat1 AS Freed_Seat_ID,
       (SELECT COUNT(*) FROM seat_allocation WHERE Run_ID = @run_id AND Seat_ID = @seat1) AS Allocations_Of_That_Seat_Expected_0;
SELECT Booking_ID, Booking_Status FROM booking WHERE Booking_ID = @booking_id;
SELECT Available_CNF, RAC_Count, WL_Count FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = '3A';

-- ---------------------------------------------------------------------------
-- TEST 21: sp_cancel_ticket failing case: cancelling the same passenger again
-- EXPECT ERROR ALREADY_CANCELLED
-- ---------------------------------------------------------------------------
-- BEFORE
SELECT Booking_Passenger_ID, Status FROM booking_passenger WHERE Booking_Passenger_ID = @bp1;
SELECT COUNT(*) AS Cancellation_Rows_For_Passenger FROM cancellation WHERE Booking_Passenger_ID = @bp1;
-- ACTION
CALL sp_cancel_ticket(@user_id, @bp1);
-- AFTER (still exactly one cancellation, still one refund)
SELECT COUNT(*) AS Cancellation_Rows_For_Passenger FROM cancellation WHERE Booking_Passenger_ID = @bp1;
SELECT COUNT(*) AS Refund_Rows_For_Cancellation FROM refund WHERE Cancellation_ID = @canc1;

-- ---------------------------------------------------------------------------
-- TEST 22: sp_cancel_ticket failing case: another user tries to cancel Asha's passenger 2
-- EXPECT ERROR NOT_OWNER
-- ---------------------------------------------------------------------------
-- BEFORE
SELECT bp.Booking_Passenger_ID, bp.Status, b.User_ID AS Owner_User_ID, @other_user_id AS Caller_User_ID
FROM booking_passenger bp JOIN booking b ON b.Booking_ID = bp.Booking_ID WHERE bp.Booking_Passenger_ID = @bp2;
-- ACTION
CALL sp_cancel_ticket(@other_user_id, @bp2);
-- AFTER (nothing changed)
SELECT Booking_Passenger_ID, Status FROM booking_passenger WHERE Booking_Passenger_ID = @bp2;
SELECT COUNT(*) AS Cancellation_Rows_For_Passenger FROM cancellation WHERE Booking_Passenger_ID = @bp2;

-- ---------------------------------------------------------------------------
-- TEST 23: sp_cancel_ticket failing case: booking passenger does not exist
-- EXPECT ERROR BOOKING_NOT_FOUND
-- ---------------------------------------------------------------------------
-- BEFORE
SELECT COUNT(*) AS Rows_With_Id_99999999 FROM booking_passenger WHERE Booking_Passenger_ID = 99999999;
SET @cancellations_now = (SELECT COUNT(*) FROM cancellation);
-- ACTION
CALL sp_cancel_ticket(@user_id, 99999999);
-- AFTER (no cancellation row was added)
SELECT COUNT(*) AS Cancellations_Now, @cancellations_now AS Cancellations_Before,
       IF(COUNT(*) = @cancellations_now, 'PASS', 'FAIL') AS Result FROM cancellation;

-- ---------------------------------------------------------------------------
-- TEST 24: v_refund_summary: normal case = the refund of TEST 20 with passenger name and PNR;
--          edge case = another user sees nothing
-- ---------------------------------------------------------------------------
-- BEFORE (the underlying tables)
SELECT Refund_ID, Cancellation_ID, Payment_ID, Original_Fare, Deduction_Percent, Deduction_Amount, Refund_Amount, Refund_Status
FROM refund WHERE Cancellation_ID = @canc1;
-- ACTION
SELECT * FROM v_refund_summary WHERE PNR = @pnr1 AND User_ID = @user_id;
-- AFTER (a) the view has exactly the contract columns, in order
SELECT COLUMN_NAME, ORDINAL_POSITION FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'v_refund_summary' ORDER BY ORDINAL_POSITION;
-- AFTER (b) edge: user 4 sees none of Asha's refunds
SELECT COUNT(*) AS Rows_For_User_4_Expected_0 FROM v_refund_summary WHERE PNR = @pnr1 AND User_ID = @other_user_id;

-- ---------------------------------------------------------------------------
-- TEST 25: sp_cancel_ticket edge case: cancelling an UNPAID ticket (booking 2, payment FAILED, booking still
--          PENDING_PAYMENT) -> refund 0.00, NO refund row, booking becomes CANCELLED (its only passenger left),
--          and v_refund_summary shows nothing for it
-- ---------------------------------------------------------------------------
-- BEFORE
SET @bp3 = (SELECT Booking_Passenger_ID FROM booking_passenger WHERE Booking_ID = @booking2_id LIMIT 1);
SELECT bp.Booking_Passenger_ID, bp.Status, bp.Fare_Amount, b.Booking_Status
FROM booking_passenger bp JOIN booking b ON b.Booking_ID = bp.Booking_ID WHERE bp.Booking_Passenger_ID = @bp3;
-- ACTION
CALL sp_cancel_ticket(@user_id, @bp3);
-- AFTER
SET @canc3 = (SELECT Cancellation_ID FROM cancellation WHERE Booking_Passenger_ID = @bp3);
SELECT Cancellation_ID, Booking_Passenger_ID, Hours_Before_Departure, Cancelled_At FROM cancellation WHERE Cancellation_ID = @canc3;
SELECT COUNT(*) AS Refund_Rows_Expected_0 FROM refund WHERE Cancellation_ID = @canc3;
SELECT Booking_ID, Booking_Status FROM booking WHERE Booking_ID = @booking2_id;
SELECT COUNT(*) AS Rows_In_v_refund_summary_Expected_0 FROM v_refund_summary WHERE PNR = @pnr2;

-- ===========================================================================
-- PART 6 - TRIGGER trg_refund_check
-- (uses the cancellation of TEST 25, which has no refund row yet; original fare = 300.00)
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- TEST 26: trg_refund_check (normal / boundary): refund equal to the original fare is accepted
-- ---------------------------------------------------------------------------
-- BEFORE
SELECT COUNT(*) AS Refund_Rows_Expected_0 FROM refund WHERE Cancellation_ID = @canc3;
-- ACTION
INSERT INTO refund (Cancellation_ID, Payment_ID, Original_Fare, Deduction_Percent, Deduction_Amount, Refund_Amount)
VALUES (@canc3, @payment2_id, 300.00, 0.00, 0.00, 300.00);
-- AFTER
SELECT Refund_ID, Cancellation_ID, Original_Fare, Refund_Amount, Refund_Status FROM refund WHERE Cancellation_ID = @canc3;
-- CLEAN-UP
DELETE FROM refund WHERE Cancellation_ID = @canc3;
SELECT COUNT(*) AS Refund_Rows_Expected_0 FROM refund WHERE Cancellation_ID = @canc3;

-- ---------------------------------------------------------------------------
-- TEST 27: trg_refund_check failing case: manual refund of 350.00 for an original fare of 300.00
-- EXPECT ERROR REFUND_EXCEEDS_FARE
-- ---------------------------------------------------------------------------
-- BEFORE
SELECT COUNT(*) AS Refund_Rows_Expected_0 FROM refund WHERE Cancellation_ID = @canc3;
-- ACTION
INSERT INTO refund (Cancellation_ID, Payment_ID, Original_Fare, Deduction_Percent, Deduction_Amount, Refund_Amount)
VALUES (@canc3, @payment2_id, 300.00, 0.00, 0.00, 350.00);
-- AFTER (the oversized refund was rejected, nothing inserted)
SELECT COUNT(*) AS Refund_Rows_Expected_0 FROM refund WHERE Cancellation_ID = @canc3;

-- ---------------------------------------------------------------------------
-- TEST 28: sp_cancel_ticket: cancelling the LAST active passenger of a booking sets the booking CANCELLED
--          (passenger 2 is a senior: fare 180.00, 10 % deduction = 18.00, refund 162.00).
--          Then the whole main flow (TEST 11-27) is deleted so the data is left as found.
-- ---------------------------------------------------------------------------
-- BEFORE
SELECT bp.Booking_Passenger_ID, bp.Status, bp.Fare_Amount, b.Booking_Status
FROM booking_passenger bp JOIN booking b ON b.Booking_ID = bp.Booking_ID WHERE bp.Booking_Passenger_ID = @bp2;
-- ACTION
CALL sp_cancel_ticket(@user_id, @bp2);
-- AFTER
SELECT Booking_ID, Booking_Status FROM booking WHERE Booking_ID IN (@booking_id, @booking2_id);
SELECT Booking_Passenger_ID, Status FROM booking_passenger WHERE Booking_ID IN (@booking_id, @booking2_id) ORDER BY Booking_Passenger_ID;
SELECT * FROM v_refund_summary WHERE PNR = @pnr1 ORDER BY Cancellation_ID;
-- CLEAN-UP (child tables first; all test passengers are CANCELLED, so the inventory counters are already back)
DELETE FROM refund WHERE Cancellation_ID IN
    (SELECT Cancellation_ID FROM cancellation WHERE Booking_Passenger_ID IN
        (SELECT Booking_Passenger_ID FROM booking_passenger WHERE Booking_ID IN (@booking_id, @booking2_id)));
DELETE FROM cancellation WHERE Booking_Passenger_ID IN
    (SELECT Booking_Passenger_ID FROM booking_passenger WHERE Booking_ID IN (@booking_id, @booking2_id));
DELETE FROM payment WHERE Booking_ID IN (@booking_id, @booking2_id);
DELETE FROM seat_allocation WHERE Booking_Passenger_ID IN
    (SELECT Booking_Passenger_ID FROM booking_passenger WHERE Booking_ID IN (@booking_id, @booking2_id));
DELETE FROM booking_status_history WHERE Booking_Passenger_ID IN
    (SELECT Booking_Passenger_ID FROM booking_passenger WHERE Booking_ID IN (@booking_id, @booking2_id));
DELETE FROM booking_passenger WHERE Booking_ID IN (@booking_id, @booking2_id);
DELETE FROM booking WHERE Booking_ID IN (@booking_id, @booking2_id);
SELECT Available_CNF, RAC_Count, WL_Count,
       IF(Available_CNF = @base_cnf AND RAC_Count = @base_rac AND WL_Count = @base_wl, 'PASS', 'FAIL') AS Inventory_Back_To_Start
FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = '3A';

-- ===========================================================================
-- PART 7 - AUTOMATIC PROMOTION INSIDE sp_cancel_ticket
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- TEST 29: sp_cancel_ticket promotes the oldest RAC passenger to CNF (Promoted_Count = 1) and gives
--          him the seat that the cancelled passenger released.
--          TEST FIXTURE: a real train needs hundreds of bookings to be full, so to simulate "3A is full" this
--          test sets seat_inventory.Available_CNF = 0 by hand (the ONLY place where a counter is written
--          outside a trigger) and restores the original counters in the clean-up.
--          Rohan (user 4): passenger 4 (SOLDIER, 50 %) gets CNF; then the class is made full; passenger 5 gets RAC.
-- ---------------------------------------------------------------------------
-- BEFORE
SET @cnf0 = (SELECT Available_CNF FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = '3A');
SET @rac0 = (SELECT RAC_Count     FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = '3A');
SET @wl0  = (SELECT WL_Count      FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = '3A');
SELECT Run_ID, Class_Code, Total_Seats, Available_CNF, RAC_Count, WL_Count, Max_RAC, Max_WL FROM seat_inventory
WHERE Run_ID = @run_id AND Class_Code = '3A';
-- SET-UP 1: passenger 4 books and gets a confirmed seat
CALL sp_book_ticket(@other_user_id, @run_id, '3A', @from_station_id, @to_station_id, '[4]');
SET @bookingA_id = (SELECT MAX(Booking_ID) FROM booking WHERE User_ID = @other_user_id AND Run_ID = @run_id);
SET @bpA         = (SELECT Booking_Passenger_ID FROM booking_passenger WHERE Booking_ID = @bookingA_id);
-- SET-UP 2 (FIXTURE): pretend that no confirmed seat is left in 3A on this run
UPDATE seat_inventory SET Available_CNF = 0 WHERE Run_ID = @run_id AND Class_Code = '3A';
-- SET-UP 3: passenger 5 books -> no confirmed seat is free, so the status is RAC
CALL sp_book_ticket(@other_user_id, @run_id, '3A', @from_station_id, @to_station_id, '[5]');
SET @bookingB_id = (SELECT MAX(Booking_ID) FROM booking WHERE User_ID = @other_user_id AND Run_ID = @run_id);
SET @bpB         = (SELECT Booking_Passenger_ID FROM booking_passenger WHERE Booking_ID = @bookingB_id);
-- State just before the action: A = CNF with a seat, B = RAC without a seat, Available_CNF = 0
SELECT bp.Booking_Passenger_ID, pa.Full_Name, bp.Status, sa.Seat_ID AS Allocated_Seat_ID
FROM booking_passenger bp
JOIN passenger pa ON pa.Passenger_ID = bp.Passenger_ID
LEFT JOIN seat_allocation sa ON sa.Booking_Passenger_ID = bp.Booking_Passenger_ID
WHERE bp.Booking_Passenger_ID IN (@bpA, @bpB) ORDER BY bp.Booking_Passenger_ID;
SELECT Available_CNF, RAC_Count, WL_Count FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = '3A';
-- ACTION: passenger 4 cancels (unpaid ticket, so the refund is 0.00); Promoted_Count must be 1
CALL sp_cancel_ticket(@other_user_id, @bpA);
-- AFTER: A = CANCELLED, B = CNF with the seat A released, RAC counter back to its start value, Available_CNF = 0 again
SELECT bp.Booking_Passenger_ID, pa.Full_Name, bp.Status, sa.Seat_ID AS Allocated_Seat_ID
FROM booking_passenger bp
JOIN passenger pa ON pa.Passenger_ID = bp.Passenger_ID
LEFT JOIN seat_allocation sa ON sa.Booking_Passenger_ID = bp.Booking_Passenger_ID
WHERE bp.Booking_Passenger_ID IN (@bpA, @bpB) ORDER BY bp.Booking_Passenger_ID;
SELECT Available_CNF, RAC_Count, WL_Count,
       IF(RAC_Count = @rac0, 'PASS', 'FAIL') AS Rac_Counter_Back_To_Start
FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = '3A';
SELECT History_ID, Booking_Passenger_ID, Old_Status, New_Status, Changed_At
FROM booking_status_history WHERE Booking_Passenger_ID IN (@bpA, @bpB) ORDER BY History_ID;
-- CLEAN-UP: cancel passenger 5 as well, restore the counters of the fixture, delete the test rows
CALL sp_cancel_ticket(@other_user_id, @bpB);
UPDATE seat_inventory SET Available_CNF = @cnf0, RAC_Count = @rac0, WL_Count = @wl0
WHERE Run_ID = @run_id AND Class_Code = '3A';
DELETE FROM refund WHERE Cancellation_ID IN
    (SELECT Cancellation_ID FROM cancellation WHERE Booking_Passenger_ID IN (@bpA, @bpB));
DELETE FROM cancellation WHERE Booking_Passenger_ID IN (@bpA, @bpB);
DELETE FROM payment WHERE Booking_ID IN (@bookingA_id, @bookingB_id);
DELETE FROM seat_allocation WHERE Booking_Passenger_ID IN (@bpA, @bpB);
DELETE FROM booking_status_history WHERE Booking_Passenger_ID IN (@bpA, @bpB);
DELETE FROM booking_passenger WHERE Booking_ID IN (@bookingA_id, @bookingB_id);
DELETE FROM booking WHERE Booking_ID IN (@bookingA_id, @bookingB_id);
SELECT Available_CNF, RAC_Count, WL_Count FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = '3A';

-- ===========================================================================
-- PART 8 - PROOF THAT THE DATA WAS LEFT AS FOUND
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- TEST 30: every table touched by TESTS 1-29 has the same row count as in the SETUP snapshot,
--          the 3A counters of the run are unchanged and the fare rules are unchanged
-- ---------------------------------------------------------------------------
-- BEFORE
SELECT @run_id AS Run_ID, @base_cnf AS Snapshot_Available_CNF, @base_rac AS Snapshot_RAC, @base_wl AS Snapshot_WL;
-- ACTION
SELECT 'booking' AS Item, @base_booking AS Snapshot, (SELECT COUNT(*) FROM booking) AS Now_Value
UNION ALL SELECT 'booking_passenger',      @base_bp,         (SELECT COUNT(*) FROM booking_passenger)
UNION ALL SELECT 'seat_allocation',        @base_alloc,      (SELECT COUNT(*) FROM seat_allocation)
UNION ALL SELECT 'booking_status_history', @base_history,    (SELECT COUNT(*) FROM booking_status_history)
UNION ALL SELECT 'payment',                @base_payment,    (SELECT COUNT(*) FROM payment)
UNION ALL SELECT 'cancellation',           @base_cancel,     (SELECT COUNT(*) FROM cancellation)
UNION ALL SELECT 'refund',                 @base_refund,     (SELECT COUNT(*) FROM refund)
UNION ALL SELECT 'fare_audit_log',         @base_fare_audit, (SELECT COUNT(*) FROM fare_audit_log)
UNION ALL SELECT 'seat_inventory.Available_CNF', @base_cnf,  (SELECT Available_CNF FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = '3A')
UNION ALL SELECT 'seat_inventory.RAC_Count',     @base_rac,  (SELECT RAC_Count     FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = '3A')
UNION ALL SELECT 'seat_inventory.WL_Count',      @base_wl,   (SELECT WL_Count      FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = '3A');
-- AFTER
SELECT IF(@base_fare_rules = (SELECT GROUP_CONCAT(CONCAT(Fare_Rule_ID, ':', Base_Fare_Per_Km, ':', Min_Fare) ORDER BY Fare_Rule_ID) FROM fare_rule),
          'PASS - fare rules unchanged', 'FAIL - fare rules differ') AS Fare_Rules_Check;
SELECT IF(@base_booking = (SELECT COUNT(*) FROM booking)
      AND @base_bp = (SELECT COUNT(*) FROM booking_passenger)
      AND @base_alloc = (SELECT COUNT(*) FROM seat_allocation)
      AND @base_history = (SELECT COUNT(*) FROM booking_status_history)
      AND @base_payment = (SELECT COUNT(*) FROM payment)
      AND @base_cancel = (SELECT COUNT(*) FROM cancellation)
      AND @base_refund = (SELECT COUNT(*) FROM refund)
      AND @base_fare_audit = (SELECT COUNT(*) FROM fare_audit_log)
      AND @base_cnf = (SELECT Available_CNF FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = '3A')
      AND @base_rac = (SELECT RAC_Count     FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = '3A')
      AND @base_wl  = (SELECT WL_Count      FROM seat_inventory WHERE Run_ID = @run_id AND Class_Code = '3A'),
      'PASS - database left exactly as found', 'FAIL - some test data is left behind') AS Overall_Result;

-- Switch Workbench safe-update mode on again
SET SQL_SAFE_UPDATES = 1;

-- SUMMARY (what each test proves)
--  TEST  1  fn_base_fare: minimum fare applies (SL, 192 km -> 120.00 instead of 105.60)
--  TEST  2  fn_base_fare: distance x rate when above the minimum (3A, 837 km -> 1213.65)
--  TEST  3  fn_base_fare: unknown class -> NULL; 0 km -> Min_Fare
--  TEST  4  fn_net_fare: NONE 0 %, SENIOR 40 %, GOVT 25 %, SOLDIER 50 %, CHILD 50 % of a 1000.00 fare
--  TEST  5  fn_net_fare: unknown concession type -> 0 % discount
--  TEST  6  fn_refund_deduction_pct: 60 h -> 10 %, 30 h -> 25 %, 6 h -> 50 %, 2 h -> 100 %
--  TEST  7  fn_refund_deduction_pct: slab boundaries (48, 47.99, 12, 11.99, 4, 3.99, 0) and negative hours -> 100 %
--  TEST  8  trg_fare_audit: a changed per-km rate is logged (old, new, user) and the rule is restored
--  TEST  9  trg_fare_audit: a changed minimum fare is logged too
--  TEST 10  trg_fare_audit: an update that changes neither rate nor minimum writes no audit row
--  TEST 11  sp_book_ticket (G3 fixture): fares 300.00 + 180.00 = 480.00, booking PENDING_PAYMENT, seats allocated
--  TEST 12  sp_create_payment: CREATED payment whose Amount equals booking.Total_Fare
--  TEST 13  sp_create_payment: BOOKING_NOT_FOUND for an unknown booking
--  TEST 14  sp_create_payment: NOT_OWNER when another user pays the booking
--  TEST 15  sp_confirm_payment + trg_payment_confirm: payment SUCCESS and the trigger sets booking CONFIRMED
--  TEST 16  sp_confirm_payment: PAYMENT_NOT_ALLOWED when the payment is confirmed a second time
--  TEST 17  sp_create_payment: PAYMENT_NOT_ALLOWED when the booking is already CONFIRMED
--  TEST 18  sp_confirm_payment failure path + trg_payment_confirm edge: FAILED payment leaves booking PENDING_PAYMENT
--  TEST 19  v_payment_history: exact columns, rows of the owner (SUCCESS + FAILED), nothing for another user
--  TEST 20  sp_cancel_ticket: paid ticket > 48 h before departure -> 10 % deduction, refund 270.00, seat freed,
--           inventory counter restored, booking stays CONFIRMED, Promoted_Count 0 (nobody waiting)
--  TEST 21  sp_cancel_ticket: ALREADY_CANCELLED on a second cancellation of the same passenger
--  TEST 22  sp_cancel_ticket: NOT_OWNER when another user cancels
--  TEST 23  sp_cancel_ticket: BOOKING_NOT_FOUND for an unknown booking passenger
--  TEST 24  v_refund_summary: exact columns, refund row with passenger name and PNR, nothing for another user
--  TEST 25  sp_cancel_ticket: unpaid ticket -> refund 0.00, no refund row, booking CANCELLED, absent from v_refund_summary
--  TEST 26  trg_refund_check: a refund equal to the original fare is accepted (boundary)
--  TEST 27  trg_refund_check: REFUND_EXCEEDS_FARE when the refund is larger than the original fare
--  TEST 28  sp_cancel_ticket: last passenger cancelled -> booking CANCELLED (refund 162.00); main-flow test rows deleted
--  TEST 29  sp_cancel_ticket: RAC passenger is promoted to CNF with the freed seat (Promoted_Count 1), history rows written
--  TEST 30  all test data removed: row counts, seat counters and fare rules equal the SETUP snapshot
