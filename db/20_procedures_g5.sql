-- Task G5.2 | Owner group: G5 Railway Operations & Analytics | Purpose: stored procedures sp_update_train_status and sp_generate_daily_revenue

DROP PROCEDURE IF EXISTS sp_update_train_status;
DROP PROCEDURE IF EXISTS sp_generate_daily_revenue;

DELIMITER $$

-- ---------------------------------------------------------------------------
-- sp_update_train_status
-- Operator updates the live status of one train run.
--
-- Steps:
--   1. Validate input (all checks happen before any change is made):
--        RUN_NOT_FOUND    the run does not exist in train_run
--        INVALID_STATUS   status is not SCHEDULED/ON_TIME/DELAYED/CANCELLED/ARRIVED
--        VALIDATION_ERROR delay is NULL or negative
--        NOT_FOUND        p_current_station_id is given but no such station exists
--   2. START TRANSACTION and lock the train_run_status row (SELECT ... FOR UPDATE)
--      so two operators cannot overwrite each other at the same moment.
--   3. UPDATE train_run_status. Two triggers react to this UPDATE:
--        trg_status_flag (BEFORE UPDATE) may change Status
--            (delay >= 15 and SCHEDULED/ON_TIME -> DELAYED; delay = 0 and DELAYED -> ON_TIME)
--        trg_delay_log   (AFTER UPDATE)  writes delay_log when the delay changed
--   4. Read the row back AFTER the update (the BEFORE trigger may have changed
--      Status), COMMIT, and return it as the single result set.
--
-- Result set: Run_ID, Status, Delay_Minutes, Updated_At
-- ---------------------------------------------------------------------------
CREATE PROCEDURE sp_update_train_status(
    IN p_run_id             INT UNSIGNED,
    IN p_status             VARCHAR(10),
    IN p_delay_minutes      INT,
    IN p_current_station_id INT UNSIGNED,
    IN p_reason             VARCHAR(100)
)
BEGIN
    DECLARE v_count   INT DEFAULT 0;   -- generic counter for existence checks
    DECLARE v_status  VARCHAR(10);     -- values read back after the UPDATE
    DECLARE v_delay   INT;
    DECLARE v_updated DATETIME;

    -- Any SQL error (including our own SIGNAL): undo everything, pass the error on.
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    -- (1) validation ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM train_run WHERE Run_ID = p_run_id;
    IF v_count = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RUN_NOT_FOUND: train run does not exist';
    END IF;

    IF p_status IS NULL
       OR p_status NOT IN ('SCHEDULED', 'ON_TIME', 'DELAYED', 'CANCELLED', 'ARRIVED') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'INVALID_STATUS: status must be SCHEDULED, ON_TIME, DELAYED, CANCELLED or ARRIVED';
    END IF;

    IF p_delay_minutes IS NULL OR p_delay_minutes < 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'VALIDATION_ERROR: delay minutes must be 0 or more';
    END IF;

    -- The current station is optional (NULL = unknown / not reported).
    IF p_current_station_id IS NOT NULL THEN
        SELECT COUNT(*) INTO v_count FROM station WHERE Station_ID = p_current_station_id;
        IF v_count = 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'NOT_FOUND: current station does not exist';
        END IF;
    END IF;

    -- (2) transaction + row lock ---------------------------------------------
    START TRANSACTION;

    SELECT COUNT(*) INTO v_count FROM train_run_status WHERE Run_ID = p_run_id FOR UPDATE;
    IF v_count = 0 THEN
        -- Normally trg_run_init_status has already created this row when the run
        -- was inserted. This only protects against a run created without it.
        INSERT INTO train_run_status (Run_ID, Status, Delay_Minutes)
        VALUES (p_run_id, 'SCHEDULED', 0);
    END IF;

    -- (3) the update (triggers trg_status_flag and trg_delay_log fire here) --
    UPDATE train_run_status
       SET Status             = p_status,
           Delay_Minutes      = p_delay_minutes,
           Current_Station_ID = p_current_station_id,
           Last_Reason        = p_reason
     WHERE Run_ID = p_run_id;

    -- (4) read back what is really stored now, then commit ------------------
    SELECT Status, Delay_Minutes, Updated_At
      INTO v_status, v_delay, v_updated
      FROM train_run_status
     WHERE Run_ID = p_run_id;

    COMMIT;

    -- The one and only result set of this procedure.
    SELECT p_run_id   AS Run_ID,
           v_status   AS Status,
           v_delay    AS Delay_Minutes,
           v_updated  AS Updated_At;
END$$


-- ---------------------------------------------------------------------------
-- sp_generate_daily_revenue
-- Builds (or rebuilds) the daily revenue summary for ONE date.
--
-- For every origin station (booking.From_Station_ID) it adds up the successful
-- payments whose Paid_At falls on p_date:
--     Total_Revenue = SUM(payment.Amount)
--     Ticket_Count  = COUNT(DISTINCT payment.Booking_ID)
-- and stores them in station_daily_revenue with
-- INSERT ... SELECT ... ON DUPLICATE KEY UPDATE, so the procedure can be run
-- again for the same date (the UNIQUE key Station_ID + Revenue_Date turns the
-- insert into an update). One transaction.
--
-- Rows_Affected is ROW_COUNT() read straight after the statement. For
-- ON DUPLICATE KEY UPDATE MySQL counts 1 for each new row, 2 for each existing
-- row that was changed and 0 for an existing row whose values did not change.
-- Rows are never deleted: a station that has no payment on p_date is left alone.
--
-- Result set: Rows_Affected
-- ---------------------------------------------------------------------------
CREATE PROCEDURE sp_generate_daily_revenue(IN p_date DATE)
BEGIN
    DECLARE v_rows INT DEFAULT 0;

    -- Any SQL error: undo everything, pass the error on.
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_date IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'VALIDATION_ERROR: date is required';
    END IF;

    START TRANSACTION;

    INSERT INTO station_daily_revenue (Station_ID, Revenue_Date, Total_Revenue, Ticket_Count)
    SELECT b.From_Station_ID,
           p_date,
           SUM(pay.Amount),
           COUNT(DISTINCT pay.Booking_ID)
      FROM payment pay
      JOIN booking b ON b.Booking_ID = pay.Booking_ID
     WHERE pay.Payment_Status = 'SUCCESS'
       AND DATE(pay.Paid_At) = p_date
     GROUP BY b.From_Station_ID
    ON DUPLICATE KEY UPDATE
        Total_Revenue = VALUES(Total_Revenue),
        Ticket_Count  = VALUES(Ticket_Count);

    -- Must be read immediately: the next statement would overwrite ROW_COUNT().
    SET v_rows = ROW_COUNT();

    COMMIT;

    -- The one and only result set of this procedure.
    SELECT v_rows AS Rows_Affected;
END$$

DELIMITER ;
