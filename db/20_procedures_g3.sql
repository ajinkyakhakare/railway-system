-- Task G3.2 | Owner: G3 (Reservation & Seat) | Procedures: sp_book_ticket, sp_promote_rac_wl (HELPER), sp_expire_unpaid_bookings
-- Runs after all schema (01..05) and function (10_*) files. Re-runnable: DROP PROCEDURE IF EXISTS before each CREATE.
--
-- Concurrency design (rules R7-R10):
--   * Lock order is always  seat_inventory -> booking -> booking_passenger -> seat_allocation / payment.
--   * The seat_inventory row of (run, class) is the "gate": every procedure that changes passenger statuses
--     of that run and class takes this row FOR UPDATE first, so two transactions can never race for the
--     same seat or the same RAC/WL position.
--   * Procedures NEVER update seat_inventory. They change booking_passenger.Status (or insert rows) and the
--     G3.3 triggers do the counter arithmetic (rule R9).
--   * NOT FOUND note: a "CONTINUE HANDLER FOR NOT FOUND" also fires when SELECT ... INTO finds no row.
--     Therefore every lookup is preceded by resetting the flag and followed by an explicit check.

DELIMITER $$

-- ===========================================================================
-- sp_book_ticket
-- Purpose : book 1..6 passengers of one user on one run/class between two stations.
--           Allocates CNF seats, or RAC / WL status when the coach class is full.
-- Params  : p_user_id         - logged-in user who pays and owns the booking
--           p_run_id          - train_run.Run_ID
--           p_class_code      - 'SL','3A','2A','1A','CC'
--           p_from_station_id / p_to_station_id - boarding and destination station ids
--           p_passenger_ids   - JSON array of passenger ids, e.g. '[3,4]' (order = booking order)
-- Result  : ONE result set -> Booking_ID, PNR, Total_Fare
-- Errors  : VALIDATION_ERROR, TOO_MANY_PASSENGERS, RUN_NOT_FOUND, INVALID_STATIONS, RUN_DEPARTED,
--           SEAT_UNAVAILABLE, PASSENGER_NOT_OWNED, BOOKING_CLOSED_WL_FULL (raised by trigger),
--           INTERNAL_ERROR (no unique PNR after 10 tries). Duplicate passenger in the list violates
--           UQ(Booking_ID, Passenger_ID) and is allowed to raise (the backend maps it to DUPLICATE).
-- Locking : seat_inventory (FOR UPDATE) -> booking (INSERT) -> booking_passenger (INSERT) -> seat_allocation (INSERT)
-- ===========================================================================
DROP PROCEDURE IF EXISTS sp_book_ticket$$
CREATE PROCEDURE sp_book_ticket(
    IN p_user_id         INT UNSIGNED,
    IN p_run_id          INT UNSIGNED,
    IN p_class_code      VARCHAR(3),
    IN p_from_station_id INT UNSIGNED,
    IN p_to_station_id   INT UNSIGNED,
    IN p_passenger_ids   JSON
)
BEGIN
    -- ---------- variables ----------
    DECLARE v_done         TINYINT DEFAULT 0;      -- set to 1 by the NOT FOUND handler
    DECLARE v_pax_count    INT DEFAULT 0;          -- number of passenger ids in the JSON array
    DECLARE v_train_id     INT UNSIGNED;
    DECLARE v_route_id     INT UNSIGNED;
    DECLARE v_from_seq     SMALLINT;               -- Stop_Seq of the boarding station
    DECLARE v_to_seq       SMALLINT;               -- Stop_Seq of the destination station
    DECLARE v_departure    DATETIME;
    DECLARE v_inventory_id INT UNSIGNED;
    DECLARE v_distance_km  INT;
    DECLARE v_base_fare    DECIMAL(10,2);
    DECLARE v_net_fare     DECIMAL(10,2);
    DECLARE v_pnr          CHAR(10);
    DECLARE v_pnr_tries    INT DEFAULT 0;
    DECLARE v_pnr_ok       TINYINT DEFAULT 0;
    DECLARE v_pnr_used     INT DEFAULT 0;
    DECLARE v_booking_id   INT UNSIGNED;
    DECLARE v_pid          INT UNSIGNED;           -- current passenger id from the cursor
    DECLARE v_dob          DATE;
    DECLARE v_declared     VARCHAR(10);            -- Concession_Type stored on the passenger
    DECLARE v_concession   VARCHAR(10);            -- effective concession (SENIOR / CHILD derived from DOB)
    DECLARE v_avail_cnf    SMALLINT;
    DECLARE v_rac_count    SMALLINT;
    DECLARE v_max_rac      SMALLINT;
    DECLARE v_status       VARCHAR(10);            -- CNF / RAC / WL for the current passenger
    DECLARE v_bp_id        INT UNSIGNED;           -- new booking_passenger id
    DECLARE v_seat_id      INT UNSIGNED;
    DECLARE v_total        DECIMAL(10,2);

    -- ---------- cursor over the JSON array, keeping the order the caller gave ----------
    DECLARE c_passengers CURSOR FOR
        SELECT jt.pid
        FROM JSON_TABLE(
                 p_passenger_ids,
                 '$[*]' COLUMNS (
                     ord FOR ORDINALITY,
                     pid INT UNSIGNED PATH '$'
                 )
             ) AS jt
        ORDER BY jt.ord;

    -- ---------- handlers ----------
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;      -- undo booking, passengers and seat allocations of this call
        RESIGNAL;      -- hand the original error (e.g. 45000 business error) to the caller
    END;

    -- =====================================================================
    -- STEP 1: cheap validation BEFORE the transaction (no locks held yet)
    -- =====================================================================
    IF p_user_id IS NULL OR p_run_id IS NULL OR p_class_code IS NULL
       OR p_from_station_id IS NULL OR p_to_station_id IS NULL OR p_passenger_ids IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'VALIDATION_ERROR: All parameters are required';
    END IF;

    IF JSON_TYPE(p_passenger_ids) <> 'ARRAY' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'VALIDATION_ERROR: Passenger list must be a JSON array';
    END IF;

    SET v_pax_count = JSON_LENGTH(p_passenger_ids);
    IF v_pax_count < 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'VALIDATION_ERROR: At least one passenger is required';
    END IF;
    IF v_pax_count > 6 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'TOO_MANY_PASSENGERS: A booking can have at most 6 passengers';
    END IF;

    -- run must exist; we also need the train to find its route
    SET v_done = 0;
    SELECT Train_ID INTO v_train_id FROM train_run WHERE Run_ID = p_run_id;
    IF v_done = 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RUN_NOT_FOUND: Train run does not exist';
    END IF;

    SELECT Route_ID INTO v_route_id FROM train WHERE Train_ID = v_train_id;

    -- both stations must be stops of that route ...
    SET v_done = 0;
    SELECT Stop_Seq INTO v_from_seq
    FROM route_stop
    WHERE Route_ID = v_route_id AND Station_ID = p_from_station_id;
    IF v_done = 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'INVALID_STATIONS: Boarding station is not on this train route';
    END IF;

    SET v_done = 0;
    SELECT Stop_Seq INTO v_to_seq
    FROM route_stop
    WHERE Route_ID = v_route_id AND Station_ID = p_to_station_id;
    IF v_done = 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'INVALID_STATIONS: Destination station is not on this train route';
    END IF;

    -- ... and the train must travel from -> to (not backwards, not the same stop)
    IF v_from_seq >= v_to_seq THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'INVALID_STATIONS: Destination must come after boarding station';
    END IF;

    -- the train must not have left the boarding station yet
    SET v_departure = fn_departure_datetime(p_run_id, p_from_station_id);
    IF v_departure IS NULL OR v_departure <= NOW() THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RUN_DEPARTED: The train has already departed from the boarding station';
    END IF;

    -- =====================================================================
    -- STEP 2: start the transaction and take the row lock on the inventory
    -- =====================================================================
    START TRANSACTION;

    SET v_done = 0;
    SELECT Inventory_ID INTO v_inventory_id
    FROM seat_inventory
    WHERE Run_ID = p_run_id AND Class_Code = p_class_code
    FOR UPDATE;                                   -- row-level lock: other bookings for this run/class wait here
    IF v_done = 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'SEAT_UNAVAILABLE: This train has no such class';
    END IF;

    -- fare of one passenger before concession (same distance for every passenger of this booking)
    SET v_distance_km = fn_distance_km(p_run_id, p_from_station_id, p_to_station_id);
    SET v_base_fare   = fn_base_fare(p_class_code, v_distance_km);
    IF v_base_fare IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'VALIDATION_ERROR: No fare rule found for this class or route';
    END IF;

    -- =====================================================================
    -- STEP 3: generate a PNR that is not used yet (max 10 attempts)
    -- =====================================================================
    SET v_pnr_tries = 0;
    SET v_pnr_ok    = 0;
    WHILE v_pnr_tries < 10 AND v_pnr_ok = 0 DO
        SET v_pnr = fn_generate_pnr();
        SELECT COUNT(*) INTO v_pnr_used FROM booking WHERE PNR = v_pnr;
        IF v_pnr_used = 0 THEN
            SET v_pnr_ok = 1;
        END IF;
        SET v_pnr_tries = v_pnr_tries + 1;
    END WHILE;

    IF v_pnr_ok = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'INTERNAL_ERROR: Could not generate a unique PNR, please retry';
    END IF;

    -- =====================================================================
    -- STEP 4: the booking header (fare is filled in at step 6)
    -- =====================================================================
    INSERT INTO booking (PNR, User_ID, Run_ID, Class_Code, From_Station_ID, To_Station_ID,
                         Booking_Status, Total_Fare)
    VALUES (v_pnr, p_user_id, p_run_id, p_class_code, p_from_station_id, p_to_station_id,
            'PENDING_PAYMENT', 0);
    SET v_booking_id = LAST_INSERT_ID();

    -- =====================================================================
    -- STEP 5: one booking_passenger row per passenger id, in the given order
    -- =====================================================================
    SET v_done = 0;
    OPEN c_passengers;

    passenger_loop: LOOP
        FETCH c_passengers INTO v_pid;
        IF v_done = 1 THEN
            LEAVE passenger_loop;                 -- cursor exhausted
        END IF;

        -- 5a) passenger must belong to the booking user
        SELECT Date_Of_Birth, Concession_Type INTO v_dob, v_declared
        FROM passenger
        WHERE Passenger_ID = v_pid AND User_ID = p_user_id;
        IF v_done = 1 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'PASSENGER_NOT_OWNED: Passenger does not belong to this user';
        END IF;

        -- 5b) concession (SENIOR/CHILD are derived from date of birth) and net fare
        SET v_concession = fn_effective_concession(v_dob, v_declared);
        SET v_net_fare   = fn_net_fare(v_base_fare, v_concession);

        -- 5c) re-read the counters: the trigger changed them after the previous passenger.
        --     We already hold the row lock, so FOR UPDATE here costs nothing and reads the latest values.
        SELECT Available_CNF, RAC_Count, Max_RAC
          INTO v_avail_cnf, v_rac_count, v_max_rac
        FROM seat_inventory
        WHERE Inventory_ID = v_inventory_id
        FOR UPDATE;

        IF v_avail_cnf > 0 THEN
            SET v_status = 'CNF';
        ELSEIF v_rac_count < v_max_rac THEN
            SET v_status = 'RAC';
        ELSE
            SET v_status = 'WL';                  -- trg_block_if_wl_full rejects this insert when WL is full
        END IF;

        -- 5d) insert the passenger; triggers adjust the inventory counters
        INSERT INTO booking_passenger (Booking_ID, Passenger_ID, Status, Base_Fare, Concession_Type, Fare_Amount)
        VALUES (v_booking_id, v_pid, v_status, v_base_fare, v_concession, v_net_fare);
        SET v_bp_id = LAST_INSERT_ID();

        -- 5e) confirmed passengers get the lowest free seat of this class on this train
        IF v_status = 'CNF' THEN
            SET v_done = 0;
            SELECT s.Seat_ID INTO v_seat_id
            FROM seat s
            JOIN train_coach c ON c.Coach_ID = s.Coach_ID
            JOIN coach_type ct ON ct.Coach_Type_ID = c.Coach_Type_ID
            JOIN train_run r   ON r.Train_ID = c.Train_ID
            WHERE r.Run_ID = p_run_id
              AND ct.Class_Code = p_class_code
              AND s.Seat_ID NOT IN (SELECT sa.Seat_ID FROM seat_allocation sa WHERE sa.Run_ID = p_run_id)
            ORDER BY c.Coach_Number, s.Seat_No
            LIMIT 1;
            IF v_done = 1 THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'SEAT_UNAVAILABLE: No free seat could be allocated';
            END IF;

            -- UQ(Run_ID, Seat_ID) is the database-level guard against double booking
            INSERT INTO seat_allocation (Run_ID, Seat_ID, Booking_Passenger_ID)
            VALUES (p_run_id, v_seat_id, v_bp_id);
        END IF;
    END LOOP passenger_loop;

    CLOSE c_passengers;

    -- =====================================================================
    -- STEP 6: total fare = sum of the passengers' net fares
    -- =====================================================================
    SELECT COALESCE(SUM(Fare_Amount), 0) INTO v_total
    FROM booking_passenger
    WHERE Booking_ID = v_booking_id;

    UPDATE booking SET Total_Fare = v_total WHERE Booking_ID = v_booking_id;

    -- =====================================================================
    -- STEP 7: commit (releases the inventory lock) and return the one result set
    -- =====================================================================
    COMMIT;

    SELECT Booking_ID, PNR, Total_Fare
    FROM booking
    WHERE Booking_ID = v_booking_id;
END$$


-- ===========================================================================
-- sp_promote_rac_wl                                  *** HELPER PROCEDURE ***
-- Purpose : after a seat becomes free, move the oldest RAC passengers to CNF (with a seat) and then the
--           oldest WL passengers to RAC. Repeats until nothing changes.
-- Params  : p_run_id, p_class_code - the (run, class) whose waiting list is processed
--           p_promoted (OUT)       - number of promotions done (RAC->CNF plus WL->RAC)
-- Result  : NO result set. NO START TRANSACTION / COMMIT / ROLLBACK - the caller owns the transaction
--           and must already hold (or be willing to take) the seat_inventory lock.
-- Errors  : SEAT_UNAVAILABLE (no inventory row, or counters say a seat is free but none can be found).
-- Locking : seat_inventory (FOR UPDATE, re-taken harmlessly if the caller holds it) -> booking_passenger
--           (UPDATE) -> seat_allocation (INSERT). "Oldest" = lowest Booking_Passenger_ID on bookings of this
--           run/class that are not CANCELLED or EXPIRED.
-- Note    : the caller must not have executed a plain (non-locking) read of this run/class's passengers
--           before taking the inventory lock, so that the reads below see the latest committed data.
-- ===========================================================================
DROP PROCEDURE IF EXISTS sp_promote_rac_wl$$
CREATE PROCEDURE sp_promote_rac_wl(
    IN  p_run_id     INT UNSIGNED,
    IN  p_class_code VARCHAR(3),
    OUT p_promoted   INT
)
BEGIN
    -- ---------- variables ----------
    DECLARE v_found        TINYINT DEFAULT 1;      -- set to 0 by the NOT FOUND handler
    DECLARE v_changed      TINYINT DEFAULT 0;      -- did the last pass promote anybody?
    DECLARE v_inventory_id INT UNSIGNED;
    DECLARE v_avail_cnf    SMALLINT;
    DECLARE v_rac_count    SMALLINT;
    DECLARE v_max_rac      SMALLINT;
    DECLARE v_bp_id        INT UNSIGNED;
    DECLARE v_seat_id      INT UNSIGNED;

    -- ---------- handler (no rollback here: this is a helper) ----------
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_found = 0;

    SET p_promoted = 0;

    -- lock the gate row first (lock order rule R10)
    SET v_found = 1;
    SELECT Inventory_ID INTO v_inventory_id
    FROM seat_inventory
    WHERE Run_ID = p_run_id AND Class_Code = p_class_code
    FOR UPDATE;
    IF v_found = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'SEAT_UNAVAILABLE: No seat inventory for this run and class';
    END IF;

    REPEAT
        SET v_changed = 0;

        -- -----------------------------------------------------------------
        -- (a) RAC -> CNF while a confirmed seat is free and somebody is on RAC
        -- -----------------------------------------------------------------
        rac_to_cnf: LOOP
            SELECT Available_CNF INTO v_avail_cnf
            FROM seat_inventory
            WHERE Inventory_ID = v_inventory_id
            FOR UPDATE;                            -- latest counters (triggers changed them)
            IF v_avail_cnf <= 0 THEN
                LEAVE rac_to_cnf;
            END IF;

            -- oldest RAC passenger of this run/class
            SET v_found = 1;
            SELECT bp.Booking_Passenger_ID INTO v_bp_id
            FROM booking_passenger bp
            JOIN booking b ON b.Booking_ID = bp.Booking_ID
            WHERE b.Run_ID = p_run_id
              AND b.Class_Code = p_class_code
              AND b.Booking_Status NOT IN ('CANCELLED', 'EXPIRED')
              AND bp.Status = 'RAC'
            ORDER BY bp.Booking_Passenger_ID
            LIMIT 1;
            IF v_found = 0 THEN
                LEAVE rac_to_cnf;                  -- nobody on RAC
            END IF;

            -- lowest free seat, found exactly like sp_book_ticket does
            SET v_found = 1;
            SELECT s.Seat_ID INTO v_seat_id
            FROM seat s
            JOIN train_coach c ON c.Coach_ID = s.Coach_ID
            JOIN coach_type ct ON ct.Coach_Type_ID = c.Coach_Type_ID
            JOIN train_run r   ON r.Train_ID = c.Train_ID
            WHERE r.Run_ID = p_run_id
              AND ct.Class_Code = p_class_code
              AND s.Seat_ID NOT IN (SELECT sa.Seat_ID FROM seat_allocation sa WHERE sa.Run_ID = p_run_id)
            ORDER BY c.Coach_Number, s.Seat_No
            LIMIT 1;
            IF v_found = 0 THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'SEAT_UNAVAILABLE: Counters show a free seat but none was found';
            END IF;

            -- status change first (trigger moves the counters), then the seat
            UPDATE booking_passenger SET Status = 'CNF' WHERE Booking_Passenger_ID = v_bp_id;
            INSERT INTO seat_allocation (Run_ID, Seat_ID, Booking_Passenger_ID)
            VALUES (p_run_id, v_seat_id, v_bp_id);

            SET p_promoted = p_promoted + 1;
            SET v_changed  = 1;
        END LOOP rac_to_cnf;

        -- -----------------------------------------------------------------
        -- (b) WL -> RAC while RAC has room and somebody is on the waiting list
        -- -----------------------------------------------------------------
        wl_to_rac: LOOP
            SELECT RAC_Count, Max_RAC INTO v_rac_count, v_max_rac
            FROM seat_inventory
            WHERE Inventory_ID = v_inventory_id
            FOR UPDATE;
            IF v_rac_count >= v_max_rac THEN
                LEAVE wl_to_rac;                   -- RAC is full
            END IF;

            -- oldest WL passenger of this run/class
            SET v_found = 1;
            SELECT bp.Booking_Passenger_ID INTO v_bp_id
            FROM booking_passenger bp
            JOIN booking b ON b.Booking_ID = bp.Booking_ID
            WHERE b.Run_ID = p_run_id
              AND b.Class_Code = p_class_code
              AND b.Booking_Status NOT IN ('CANCELLED', 'EXPIRED')
              AND bp.Status = 'WL'
            ORDER BY bp.Booking_Passenger_ID
            LIMIT 1;
            IF v_found = 0 THEN
                LEAVE wl_to_rac;                   -- nobody on the waiting list
            END IF;

            UPDATE booking_passenger SET Status = 'RAC' WHERE Booking_Passenger_ID = v_bp_id;

            SET p_promoted = p_promoted + 1;
            SET v_changed  = 1;
        END LOOP wl_to_rac;
    UNTIL v_changed = 0
    END REPEAT;
END$$


-- ===========================================================================
-- sp_expire_unpaid_bookings
-- Purpose : release the seats of bookings that stayed PENDING_PAYMENT longer than p_minutes.
-- Params  : p_minutes - age limit in minutes (>= 0)
-- Result  : ONE result set -> Expired_Count
-- Errors  : VALIDATION_ERROR (p_minutes NULL or negative); any error aborts the CURRENT booking only,
--           bookings already expired stay expired (each booking has its own transaction).
-- Locking : per booking: seat_inventory (FOR UPDATE) -> booking (FOR UPDATE) -> booking_passenger (UPDATE)
--           -> seat_allocation (DELETE) -> sp_promote_rac_wl
-- ===========================================================================
DROP PROCEDURE IF EXISTS sp_expire_unpaid_bookings$$
CREATE PROCEDURE sp_expire_unpaid_bookings(
    IN p_minutes INT
)
BEGIN
    -- ---------- variables ----------
    DECLARE v_done         TINYINT DEFAULT 0;
    DECLARE v_count        INT DEFAULT 0;          -- how many bookings were expired
    DECLARE v_booking_id   INT UNSIGNED;
    DECLARE v_run_id       INT UNSIGNED;
    DECLARE v_class_code   VARCHAR(3);
    DECLARE v_inventory_id INT UNSIGNED;
    DECLARE v_status       VARCHAR(16);
    DECLARE v_promoted     INT DEFAULT 0;

    -- ---------- cursor over a private snapshot of the target bookings ----------
    -- (a temporary table, so that expiring one booking cannot disturb the list we are walking)
    DECLARE c_targets CURSOR FOR
        SELECT Booking_ID, Run_ID, Class_Code
        FROM tmp_expire_targets
        ORDER BY Booking_ID;

    -- ---------- handlers ----------
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;      -- undo the booking that was being processed
        RESIGNAL;
    END;

    IF p_minutes IS NULL OR p_minutes < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'VALIDATION_ERROR: Minutes must be zero or more';
    END IF;

    -- collect the targets (plain read, no transaction needed: each one is re-checked under lock below)
    DROP TEMPORARY TABLE IF EXISTS tmp_expire_targets;
    CREATE TEMPORARY TABLE tmp_expire_targets AS
        SELECT Booking_ID, Run_ID, Class_Code
        FROM booking
        WHERE Booking_Status = 'PENDING_PAYMENT'
          AND Booked_At < DATE_SUB(NOW(), INTERVAL p_minutes MINUTE);

    SET v_done = 0;
    OPEN c_targets;

    booking_loop: LOOP
        FETCH c_targets INTO v_booking_id, v_run_id, v_class_code;
        IF v_done = 1 THEN
            LEAVE booking_loop;                    -- all targets processed
        END IF;

        -- ----- one transaction per booking -----
        START TRANSACTION;

        -- 1) gate row first (lock order)
        SELECT Inventory_ID INTO v_inventory_id
        FROM seat_inventory
        WHERE Run_ID = v_run_id AND Class_Code = v_class_code
        FOR UPDATE;
        IF v_done = 1 THEN
            SET v_done = 0;                        -- inventory row missing: nothing to release, skip
            ROLLBACK;
            ITERATE booking_loop;
        END IF;

        -- 2) booking row; re-check the status because a payment may have confirmed it meanwhile
        SELECT Booking_Status INTO v_status
        FROM booking
        WHERE Booking_ID = v_booking_id
        FOR UPDATE;
        IF v_done = 1 THEN
            SET v_done = 0;                        -- booking vanished: skip
            ROLLBACK;
            ITERATE booking_loop;
        END IF;

        IF v_status = 'PENDING_PAYMENT' THEN
            -- 3) cancel every non-cancelled passenger (trigger gives the counters back)
            UPDATE booking_passenger
               SET Status = 'CANCELLED'
             WHERE Booking_ID = v_booking_id
               AND Status <> 'CANCELLED';

            -- 4) free their seats
            DELETE sa
            FROM seat_allocation sa
            JOIN booking_passenger bp ON bp.Booking_Passenger_ID = sa.Booking_Passenger_ID
            WHERE bp.Booking_ID = v_booking_id;

            -- 5) let RAC / waiting-list passengers move up into the freed places
            CALL sp_promote_rac_wl(v_run_id, v_class_code, v_promoted);

            -- 6) finally mark the booking itself
            UPDATE booking SET Booking_Status = 'EXPIRED' WHERE Booking_ID = v_booking_id;

            SET v_count = v_count + 1;
        END IF;

        COMMIT;
    END LOOP booking_loop;

    CLOSE c_targets;
    DROP TEMPORARY TABLE IF EXISTS tmp_expire_targets;

    SELECT v_count AS Expired_Count;
END$$

DELIMITER ;
