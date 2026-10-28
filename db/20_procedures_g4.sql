-- Task G4.2 | Owner: G4 (Payment, Cancellation & Refund) | Purpose: stored procedures sp_create_payment, sp_confirm_payment, sp_cancel_ticket
-- Requires: all schemas (01..05), G1 fn_departure_datetime, G4 fn_refund_deduction_pct (10_functions_*),
--           and G3 helper sp_promote_rac_wl (20_procedures_g3.sql) at CALL time.
-- Conventions: each procedure owns its transaction, returns exactly one result set,
--              raises business errors as 'ERROR_CODE: text' (SQLSTATE 45000),
--              never touches seat_inventory directly (triggers do),
--              locks rows in the order seat_inventory -> booking -> booking_passenger -> payment.

DELIMITER $$

-- ---------------------------------------------------------------------------
-- sp_create_payment
-- Purpose : Start a payment for a booking that is waiting for payment.
-- Params  : p_user_id          - logged-in user (must own the booking)
--           p_booking_id       - booking to pay for
--           p_mode             - 'RAZORPAY' or 'MOCK'
--           p_gateway_order_id - order id from the gateway (unique, may be NULL)
-- Result  : one row: Payment_ID, Amount   (payment row is created with status CREATED)
-- Errors  : VALIDATION_ERROR (bad mode or zero fare), BOOKING_NOT_FOUND, NOT_OWNER,
--           PAYMENT_NOT_ALLOWED (booking not PENDING_PAYMENT, or already paid).
--           A duplicate Gateway_Order_ID raises the normal MySQL duplicate-key error
--           (the backend maps it to DUPLICATE).
-- ---------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_create_payment$$
CREATE PROCEDURE sp_create_payment(
    IN p_user_id          INT UNSIGNED,
    IN p_booking_id       INT UNSIGNED,
    IN p_mode             VARCHAR(10),
    IN p_gateway_order_id VARCHAR(60)
)
BEGIN
    DECLARE v_owner_id   INT UNSIGNED DEFAULT NULL;
    DECLARE v_status     VARCHAR(16)  DEFAULT NULL;
    DECLARE v_fare       DECIMAL(10,2) DEFAULT 0;
    DECLARE v_paid_count INT DEFAULT 0;
    DECLARE v_payment_id INT UNSIGNED DEFAULT NULL;

    -- Any SQL error: undo everything and pass the error on to the caller.
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    -- Input check (the CHECK constraint on payment would also reject it,
    -- but this gives a readable error code).
    IF p_mode IS NULL OR p_mode NOT IN ('RAZORPAY', 'MOCK') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'VALIDATION_ERROR: Payment mode must be RAZORPAY or MOCK';
    END IF;

    START TRANSACTION;

    -- Lock the booking row so two parallel requests cannot both pass the checks below.
    SELECT User_ID, Booking_Status, Total_Fare
      INTO v_owner_id, v_status, v_fare
      FROM booking
     WHERE Booking_ID = p_booking_id
       FOR UPDATE;

    -- User_ID is NOT NULL in booking, so NULL here means "no such booking".
    IF v_owner_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'BOOKING_NOT_FOUND: Booking does not exist';
    END IF;

    IF v_owner_id <> p_user_id THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'NOT_OWNER: This booking belongs to another user';
    END IF;

    IF v_status <> 'PENDING_PAYMENT' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'PAYMENT_NOT_ALLOWED: Booking is not waiting for payment';
    END IF;

    -- A booking that already has a successful payment must not be paid twice.
    SELECT COUNT(*)
      INTO v_paid_count
      FROM payment
     WHERE Booking_ID = p_booking_id
       AND Payment_Status = 'SUCCESS';

    IF v_paid_count > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'PAYMENT_NOT_ALLOWED: Booking is already paid';
    END IF;

    -- payment.Amount must be > 0, so a zero fare cannot be paid.
    IF v_fare IS NULL OR v_fare <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'VALIDATION_ERROR: Booking fare is zero, nothing to pay';
    END IF;

    INSERT INTO payment (Booking_ID, Amount, Payment_Mode, Gateway_Order_ID, Payment_Status)
    VALUES (p_booking_id, v_fare, p_mode, p_gateway_order_id, 'CREATED');

    SET v_payment_id = LAST_INSERT_ID();

    COMMIT;

    SELECT v_payment_id AS Payment_ID, v_fare AS Amount;
END$$

-- ---------------------------------------------------------------------------
-- sp_confirm_payment
-- Purpose : Record the gateway outcome (success / failure) of a payment.
--           The booking itself is NOT updated here: trigger trg_payment_confirm
--           sets Booking_Status = 'CONFIRMED' when the payment becomes SUCCESS.
-- Params  : p_payment_id         - payment to confirm (must be CREATED)
--           p_gateway_payment_id - gateway's payment id (may be NULL, e.g. failures)
--           p_success            - 1 = paid, 0 = failed
-- Result  : one row: Payment_Status, Booking_Status (read after the update)
-- Errors  : VALIDATION_ERROR (p_success not 0/1), NOT_FOUND (no such payment),
--           PAYMENT_NOT_ALLOWED (payment not CREATED, or success reported for a
--           booking that is no longer PENDING_PAYMENT, e.g. it has expired).
-- ---------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_confirm_payment$$
CREATE PROCEDURE sp_confirm_payment(
    IN p_payment_id         INT UNSIGNED,
    IN p_gateway_payment_id VARCHAR(60),
    IN p_success            TINYINT
)
BEGIN
    DECLARE v_booking_id     INT UNSIGNED DEFAULT NULL;
    DECLARE v_pay_status     VARCHAR(10)  DEFAULT NULL;
    DECLARE v_booking_status VARCHAR(16)  DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_success IS NULL OR p_success NOT IN (0, 1) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'VALIDATION_ERROR: p_success must be 0 or 1';
    END IF;

    -- Plain read (no lock) just to learn which booking the payment belongs to.
    -- We need it to lock the booking BEFORE the payment (lock order rule).
    SELECT Booking_ID
      INTO v_booking_id
      FROM payment
     WHERE Payment_ID = p_payment_id;

    IF v_booking_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'NOT_FOUND: Payment does not exist';
    END IF;

    START TRANSACTION;

    -- Lock order: booking first, then payment.
    SELECT Booking_Status
      INTO v_booking_status
      FROM booking
     WHERE Booking_ID = v_booking_id
       FOR UPDATE;

    SELECT Payment_Status
      INTO v_pay_status
      FROM payment
     WHERE Payment_ID = p_payment_id
       FOR UPDATE;

    -- Only a payment that is still CREATED can be confirmed (prevents double confirmation).
    IF v_pay_status <> 'CREATED' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'PAYMENT_NOT_ALLOWED: Payment was already confirmed or failed';
    END IF;

    -- Do not confirm money for a booking that expired or was cancelled meanwhile,
    -- otherwise the trigger would revive a booking whose seats were released.
    IF p_success = 1 AND v_booking_status <> 'PENDING_PAYMENT' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'PAYMENT_NOT_ALLOWED: Booking is no longer waiting for payment';
    END IF;

    UPDATE payment
       SET Payment_Status     = IF(p_success = 1, 'SUCCESS', 'FAILED'),
           Gateway_Payment_ID = p_gateway_payment_id,
           Paid_At            = IF(p_success = 1, NOW(), NULL)
     WHERE Payment_ID = p_payment_id;
    -- trg_payment_confirm (AFTER UPDATE) now sets the booking to CONFIRMED on success.

    COMMIT;

    SELECT p.Payment_Status, b.Booking_Status
      FROM payment p
      JOIN booking b ON b.Booking_ID = p.Booking_ID
     WHERE p.Payment_ID = p_payment_id;
END$$

-- ---------------------------------------------------------------------------
-- sp_cancel_ticket
-- Purpose : Cancel ONE passenger of a booking, work out the refund, release the
--           seat and promote waiting passengers (RAC -> CNF, WL -> RAC).
-- Params  : p_user_id              - logged-in user (must own the booking)
--           p_booking_passenger_id - passenger row to cancel
-- Steps   : 1 validate and compute hours before departure (no transaction yet)
--           2 START TRANSACTION, lock inventory -> booking -> booking_passenger, re-check
--           3 compute deduction and refund (unpaid booking: refund 0, no refund row)
--           4 insert cancellation, set passenger CANCELLED, free the seat, insert refund
--           5 CALL sp_promote_rac_wl   6 close the booking if everybody cancelled   7 COMMIT
-- Result  : one row: Cancellation_ID, Original_Fare, Deduction_Percent,
--           Refund_Amount, Promoted_Count
-- Errors  : BOOKING_NOT_FOUND, NOT_OWNER, ALREADY_CANCELLED,
--           CANCEL_NOT_ALLOWED (train already departed), NOT_FOUND (seat inventory missing).
-- Note    : seat_inventory counters change ONLY through triggers
--           (trg_adjust_inventory_on_status fires on the status UPDATE).
--           The procedure has no reason parameter, so cancellation.Reason stays NULL
--           (the backend may UPDATE it afterwards).
-- ---------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_cancel_ticket$$
CREATE PROCEDURE sp_cancel_ticket(
    IN p_user_id              INT UNSIGNED,
    IN p_booking_passenger_id INT UNSIGNED
)
BEGIN
    -- Data about the passenger row and its booking
    DECLARE v_booking_id     INT UNSIGNED  DEFAULT NULL;
    DECLARE v_owner_id       INT UNSIGNED  DEFAULT NULL;
    DECLARE v_run_id         INT UNSIGNED  DEFAULT NULL;
    DECLARE v_class_code     VARCHAR(3)    DEFAULT NULL;
    DECLARE v_from_station   INT UNSIGNED  DEFAULT NULL;
    DECLARE v_pass_status    VARCHAR(10)   DEFAULT NULL;
    DECLARE v_booking_status VARCHAR(16)   DEFAULT NULL;

    -- Time calculation
    DECLARE v_departure      DATETIME      DEFAULT NULL;
    DECLARE v_minutes        INT           DEFAULT NULL;
    DECLARE v_hours          DECIMAL(8,2)  DEFAULT NULL;

    -- Locks and money
    DECLARE v_inventory_id   INT UNSIGNED  DEFAULT NULL;
    DECLARE v_original       DECIMAL(10,2) DEFAULT 0;
    DECLARE v_pct            DECIMAL(5,2)  DEFAULT 0;
    DECLARE v_deduction      DECIMAL(10,2) DEFAULT 0;
    DECLARE v_refund         DECIMAL(10,2) DEFAULT 0;
    DECLARE v_payment_id     INT UNSIGNED  DEFAULT NULL;

    -- Outputs
    DECLARE v_cancellation_id INT UNSIGNED DEFAULT NULL;
    DECLARE v_promoted        INT          DEFAULT 0;
    DECLARE v_active_left     INT          DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    -- ===== Step 1: validations (before the transaction) =====
    SELECT bp.Booking_ID, bp.Status, b.User_ID, b.Run_ID, b.Class_Code, b.From_Station_ID
      INTO v_booking_id, v_pass_status, v_owner_id, v_run_id, v_class_code, v_from_station
      FROM booking_passenger bp
      JOIN booking b ON b.Booking_ID = bp.Booking_ID
     WHERE bp.Booking_Passenger_ID = p_booking_passenger_id;

    IF v_booking_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'BOOKING_NOT_FOUND: Booking passenger does not exist';
    END IF;

    IF v_owner_id <> p_user_id THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'NOT_OWNER: This ticket belongs to another user';
    END IF;

    IF v_pass_status = 'CANCELLED' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ALREADY_CANCELLED: This passenger is already cancelled';
    END IF;

    -- Hours left before the train leaves the passenger's boarding station.
    -- Whole minutes are checked first so the sign is never lost by rounding.
    SET v_departure = fn_departure_datetime(v_run_id, v_from_station);
    SET v_minutes   = TIMESTAMPDIFF(MINUTE, NOW(), v_departure);

    IF v_minutes IS NULL OR v_minutes < 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'CANCEL_NOT_ALLOWED: The train has already departed';
    END IF;

    SET v_hours = v_minutes / 60.0;

    -- ===== Step 2: transaction and locks (order: inventory -> booking -> booking_passenger) =====
    START TRANSACTION;

    SELECT Inventory_ID
      INTO v_inventory_id
      FROM seat_inventory
     WHERE Run_ID = v_run_id
       AND Class_Code = v_class_code
       FOR UPDATE;

    IF v_inventory_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'NOT_FOUND: Seat inventory for this run and class does not exist';
    END IF;

    SELECT Booking_Status
      INTO v_booking_status
      FROM booking
     WHERE Booking_ID = v_booking_id
       FOR UPDATE;

    -- Re-read the passenger under the lock: someone else may have cancelled it meanwhile.
    SELECT Status, Fare_Amount
      INTO v_pass_status, v_original
      FROM booking_passenger
     WHERE Booking_Passenger_ID = p_booking_passenger_id
       FOR UPDATE;

    IF v_pass_status = 'CANCELLED' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ALREADY_CANCELLED: This passenger is already cancelled';
    END IF;

    -- ===== Step 3: deduction and refund =====
    SET v_pct       = fn_refund_deduction_pct(v_hours);
    SET v_deduction = ROUND(v_original * v_pct / 100, 2);
    SET v_refund    = v_original - v_deduction;

    -- Refunds exist only for paid bookings: find the latest successful payment.
    -- Unpaid bookings (anything but CONFIRMED) get refund 0 and no refund row.
    IF v_booking_status = 'CONFIRMED' THEN
        SELECT Payment_ID
          INTO v_payment_id
          FROM payment
         WHERE Booking_ID = v_booking_id
           AND Payment_Status = 'SUCCESS'
         ORDER BY Paid_At DESC, Payment_ID DESC
         LIMIT 1;
    END IF;

    IF v_payment_id IS NULL THEN
        SET v_refund = 0;
    END IF;

    -- ===== Step 4: record the cancellation, release the seat, store the refund =====
    INSERT INTO cancellation (Booking_Passenger_ID, Hours_Before_Departure)
    VALUES (p_booking_passenger_id, v_hours);

    SET v_cancellation_id = LAST_INSERT_ID();

    -- Triggers adjust seat_inventory and write booking_status_history.
    UPDATE booking_passenger
       SET Status = 'CANCELLED'
     WHERE Booking_Passenger_ID = p_booking_passenger_id;

    -- Free the physical seat (no rows are deleted for RAC / WL passengers).
    DELETE FROM seat_allocation
     WHERE Booking_Passenger_ID = p_booking_passenger_id;

    IF v_payment_id IS NOT NULL THEN
        INSERT INTO refund (Cancellation_ID, Payment_ID, Original_Fare,
                            Deduction_Percent, Deduction_Amount, Refund_Amount)
        VALUES (v_cancellation_id, v_payment_id, v_original,
                v_pct, v_deduction, v_refund);
    END IF;

    -- ===== Step 5: promote waiting passengers (G3 helper; the inventory lock is already held) =====
    CALL sp_promote_rac_wl(v_run_id, v_class_code, v_promoted);

    -- ===== Step 6: close the booking when every passenger is cancelled =====
    SELECT COUNT(*)
      INTO v_active_left
      FROM booking_passenger
     WHERE Booking_ID = v_booking_id
       AND Status <> 'CANCELLED';

    IF v_active_left = 0 THEN
        UPDATE booking
           SET Booking_Status = 'CANCELLED'
         WHERE Booking_ID = v_booking_id;
    END IF;

    -- ===== Step 7 =====
    COMMIT;

    SELECT v_cancellation_id AS Cancellation_ID,
           v_original        AS Original_Fare,
           v_pct             AS Deduction_Percent,
           v_refund          AS Refund_Amount,
           v_promoted        AS Promoted_Count;
END$$

DELIMITER ;
