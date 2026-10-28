-- Task I1 | Owner group: Integration (I1) | Purpose: demo bookings, payments, a cancellation, a waitlist demo, train status and daily revenue, created ONLY through stored procedures with relative dates.
--
-- Load order: this file runs AFTER all schemas, functions, procedures, triggers, views and the
-- master seeds (db/50_seed_g1.sql, 51_seed_g2.sql, 52_seed_g4.sql).
-- Rules followed here:
--   * No raw INSERT into G3/G4 tables. Every booking, payment, cancellation and refund is created
--     by calling the owner group's stored procedure, so triggers and business rules really run.
--   * Dates are relative to CURDATE(), so the script works on any day (runs exist for 14 days
--     after the seed was loaded, see C6 "Runs").
--   * Passenger / user ids follow the fixed seed data in contract section C6.

-- ---------------------------------------------------------------------------------------------
-- 0. Look up the run ids we need (runs of trains 1..4 for today + 2 days).
-- ---------------------------------------------------------------------------------------------
SET @d2 = DATE_ADD(CURDATE(), INTERVAL 2 DAY);
SET @d3 = DATE_ADD(CURDATE(), INTERVAL 3 DAY);

SELECT Run_ID INTO @r1 FROM train_run WHERE Train_ID = 1 AND Journey_Date = @d2;
SELECT Run_ID INTO @r2 FROM train_run WHERE Train_ID = 2 AND Journey_Date = @d2;
SELECT Run_ID INTO @r3 FROM train_run WHERE Train_ID = 3 AND Journey_Date = @d2;
SELECT Run_ID INTO @r4 FROM train_run WHERE Train_ID = 4 AND Journey_Date = @d2;

-- ---------------------------------------------------------------------------------------------
-- 1. Four bookings through sp_book_ticket(user, run, class, from, to, passenger-id JSON array).
--    Each CALL returns Booking_ID, PNR, Total_Fare. We then read the new Booking_ID back into a
--    variable (a plain SELECT, no write) because a procedure result set cannot be stored.
-- ---------------------------------------------------------------------------------------------

-- Booking 1: Asha (user 3) with Asha, Suresh (senior) and Aarav (child), Mumbai CSMT -> Pune, Sleeper.
CALL sp_book_ticket(3, @r1, 'SL', 2, 1, '[1,2,3]');
SELECT Booking_ID INTO @b1 FROM booking
 WHERE User_ID = 3 AND Run_ID = @r1 ORDER BY Booking_ID DESC LIMIT 1;

-- Booking 2: Rohan (user 4) with Rohan (soldier concession) and Priya, Mumbai CSMT -> Pune, Chair Car.
CALL sp_book_ticket(4, @r2, 'CC', 2, 1, '[4,5]');
SELECT Booking_ID INTO @b2 FROM booking
 WHERE User_ID = 4 AND Run_ID = @r2 ORDER BY Booking_ID DESC LIMIT 1;

-- Booking 3: Meera (user 5) with Meera (govt), Kabir and Leela (senior), Pune -> Hyderabad, AC 3 Tier.
CALL sp_book_ticket(5, @r3, '3A', 1, 9, '[6,7,8]');
SELECT Booking_ID INTO @b3 FROM booking
 WHERE User_ID = 5 AND Run_ID = @r3 ORDER BY Booking_ID DESC LIMIT 1;

-- Booking 4: Asha (user 3) alone, Mumbai CSMT -> Nagpur, Sleeper. This one stays PENDING_PAYMENT.
CALL sp_book_ticket(3, @r4, 'SL', 2, 7, '[1]');
SELECT Booking_ID INTO @b4 FROM booking
 WHERE User_ID = 3 AND Run_ID = @r4 ORDER BY Booking_ID DESC LIMIT 1;

-- ---------------------------------------------------------------------------------------------
-- 2. Pay the first three bookings (MOCK gateway). Booking 4 is deliberately left unpaid.
--    sp_create_payment -> inserts a CREATED payment for the booking total.
--    sp_confirm_payment(..., 1) -> marks it SUCCESS; trg_payment_confirm then sets the booking
--    to CONFIRMED.
-- ---------------------------------------------------------------------------------------------
CALL sp_create_payment(3, @b1, 'MOCK', 'MOCK_DEMO_1');
SELECT Payment_ID INTO @p1 FROM payment WHERE Booking_ID = @b1 ORDER BY Payment_ID DESC LIMIT 1;
CALL sp_confirm_payment(@p1, 'MOCKPAY_DEMO_1', 1);

CALL sp_create_payment(4, @b2, 'MOCK', 'MOCK_DEMO_2');
SELECT Payment_ID INTO @p2 FROM payment WHERE Booking_ID = @b2 ORDER BY Payment_ID DESC LIMIT 1;
CALL sp_confirm_payment(@p2, 'MOCKPAY_DEMO_2', 1);

CALL sp_create_payment(5, @b3, 'MOCK', 'MOCK_DEMO_3');
SELECT Payment_ID INTO @p3 FROM payment WHERE Booking_ID = @b3 ORDER BY Payment_ID DESC LIMIT 1;
CALL sp_confirm_payment(@p3, 'MOCKPAY_DEMO_3', 1);

-- ---------------------------------------------------------------------------------------------
-- 3. Cancel ONE passenger (Suresh, passenger 2) of the first, paid booking.
--    sp_cancel_ticket calculates the deduction with fn_refund_deduction_pct, writes the
--    cancellation and refund rows, frees the seat and promotes any RAC/WL passenger.
-- ---------------------------------------------------------------------------------------------
SELECT Booking_Passenger_ID INTO @bp_cancel FROM booking_passenger
 WHERE Booking_ID = @b1 AND Passenger_ID = 2;
CALL sp_cancel_ticket(3, @bp_cancel);

-- ---------------------------------------------------------------------------------------------
-- 4. Waiting-list demonstration: train 4, run of today + 3 days, class SL.
--    We shrink this ONE inventory row to 2 seats / 1 RAC / 1 WL so that three bookings fill
--    confirmed, RAC and waiting list. This direct UPDATE is legal only because the run has NO
--    bookings yet (the counters still equal the freshly created values, so the CHECK
--    constraint and the "counters are changed only by triggers" rule are not violated).
-- ---------------------------------------------------------------------------------------------
SELECT Run_ID INTO @r4w FROM train_run WHERE Train_ID = 4 AND Journey_Date = @d3;

UPDATE seat_inventory
   SET Total_Seats = 2, Available_CNF = 2, Max_RAC = 1, Max_WL = 1
 WHERE Run_ID = @r4w AND Class_Code = 'SL';

-- Asha books passengers 1 and 2: both get CNF (2 seats available -> 0 left).
CALL sp_book_ticket(3, @r4w, 'SL', 2, 7, '[1,2]');
-- Rohan books passenger 4: no seat is left, so the passenger becomes RAC (1 of 1).
CALL sp_book_ticket(4, @r4w, 'SL', 2, 7, '[4]');
-- Meera books passenger 6: RAC is full, so the passenger goes on the waiting list (1 of 1).
CALL sp_book_ticket(5, @r4w, 'SL', 2, 7, '[6]');

/* ===========================  RUN MANUALLY IN WORKBENCH  ===================================
   The waiting list is now full (WL_Count = Max_WL = 1). The next booking MUST FAIL with
   BOOKING_CLOSED_WL_FULL raised by trigger trg_block_if_wl_full. It is left in this comment so
   that this script never aborts. To demonstrate it, run these two lines in ONE session:

       SELECT Run_ID INTO @r4w FROM train_run
        WHERE Train_ID = 4 AND Journey_Date = DATE_ADD(CURDATE(), INTERVAL 3 DAY);
       CALL sp_book_ticket(5, @r4w, 'SL', 2, 7, '[7]');

   Expected: ERROR 1644 (45000): BOOKING_CLOSED_WL_FULL: ...  and the whole booking is rolled back.
   =========================================================================================== */

-- ---------------------------------------------------------------------------------------------
-- 5. Live train status for TODAY's runs of trains 1..4 through sp_update_train_status
--    (run, status, delay minutes, current station, reason).
--    Note: trg_status_flag may adjust the status by itself (for example delay >= 15 minutes).
-- ---------------------------------------------------------------------------------------------
SELECT Run_ID INTO @t1 FROM train_run WHERE Train_ID = 1 AND Journey_Date = CURDATE();
SELECT Run_ID INTO @t2 FROM train_run WHERE Train_ID = 2 AND Journey_Date = CURDATE();
SELECT Run_ID INTO @t3 FROM train_run WHERE Train_ID = 3 AND Journey_Date = CURDATE();
SELECT Run_ID INTO @t4 FROM train_run WHERE Train_ID = 4 AND Journey_Date = CURDATE();

-- Train 1: running on time, currently at Kalyan (station 3).
CALL sp_update_train_status(@t1, 'ON_TIME', 0, 3, 'Running on time');
-- Train 2: 25 minutes late, currently at Lonavala (station 4).
CALL sp_update_train_status(@t2, 'DELAYED', 25, 4, 'Signal failure near Lonavala');
-- Train 3: 70 minutes late, currently at Solapur (station 8).
CALL sp_update_train_status(@t3, 'DELAYED', 70, 8, 'Track maintenance work');
-- Train 4: not started yet, no current station.
CALL sp_update_train_status(@t4, 'SCHEDULED', 0, NULL, 'Waiting for departure');

-- ARRIVED example: train 1 on YESTERDAY's run.
-- The seed only creates runs from today onwards, so yesterday's run normally does not exist.
-- To "skip safely" the CALL is built as text and executed only when @y1 is not NULL;
-- otherwise the harmless statement DO 0 runs instead.
SELECT Run_ID INTO @y1 FROM train_run
 WHERE Train_ID = 1 AND Journey_Date = DATE_SUB(CURDATE(), INTERVAL 1 DAY);

SET @arrived_sql = IF(@y1 IS NULL,
    'DO 0',
    'CALL sp_update_train_status(@y1, ''ARRIVED'', 0, 1, ''Arrived at Pune Junction'')');
PREPARE arrived_stmt FROM @arrived_sql;
EXECUTE arrived_stmt;
DEALLOCATE PREPARE arrived_stmt;

-- ---------------------------------------------------------------------------------------------
-- 6. Daily revenue report for today (payments were made today, so Paid_At = today).
-- ---------------------------------------------------------------------------------------------
CALL sp_generate_daily_revenue(CURDATE());

-- ---------------------------------------------------------------------------------------------
-- Summary: what the demo data created. Expected after a clean load:
--   bookings CONFIRMED 3, PENDING_PAYMENT 4 (booking 4 and the three waitlist-demo bookings),
--   payments SUCCESS 3, cancellations 1, refunds 1.
-- ---------------------------------------------------------------------------------------------
SELECT CONCAT('bookings ', Booking_Status) AS Metric, COUNT(*) AS Metric_Count
  FROM booking
 GROUP BY Booking_Status
UNION ALL
SELECT CONCAT('booking passengers ', Status), COUNT(*)
  FROM booking_passenger
 GROUP BY Status
UNION ALL
SELECT CONCAT('payments ', Payment_Status), COUNT(*)
  FROM payment
 GROUP BY Payment_Status
UNION ALL
SELECT 'cancellations', COUNT(*) FROM cancellation
UNION ALL
SELECT 'refunds', COUNT(*) FROM refund
ORDER BY Metric;
