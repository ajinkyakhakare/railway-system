-- Task G1.2 | Owner: G1 Train, Station & Route | Purpose: procedures sp_add_coaches_generate_seats and sp_generate_train_runs (contract C5.2)
--
-- Both procedures own their transaction (rule R7): EXIT HANDLER -> ROLLBACK -> RESIGNAL, so the
-- original business error (code and message) reaches the caller unchanged.
-- Both are NON-helper procedures and return EXACTLY ONE result set (the final SELECT).
-- Business errors use SIGNAL SQLSTATE '45000' with a message "ERROR_CODE: readable text" (rule R8).
-- Ids are INT UNSIGNED as stated in contract C5.

DELIMITER $$

-- ---------------------------------------------------------------------------------------------
-- sp_add_coaches_generate_seats
-- Purpose : add p_coach_count coaches of one coach type to a train and generate all their seats.
--           Coach_Number = class prefix + running number per class on that train:
--             SL -> S1, S2 ...   3A -> B1 ...   2A -> A1 ...   1A -> H1 ...   CC -> C1 ...
--           The running number continues after the coaches of that class the train already has.
--           Each coach gets Seats_Per_Coach seats, Seat_No 1..n, with the Berth_Type cycle:
--             SL and 3A : LB,MB,UB,LB,MB,UB,SL,SU      2A : LB,UB,LB,UB,SL,SU
--             1A        : LB,UB                         CC : W,M,A,A,M,W
-- Params  : p_train_id      train.Train_ID
--           p_coach_type_id coach_type.Coach_Type_ID
--           p_coach_count   number of coaches to add (1..127)
-- Result  : one row with columns Coaches_Added, Seats_Added.
-- Errors  : VALIDATION_ERROR (an id is NULL, or p_coach_count is NULL or less than 1)
--           NOT_FOUND        (train or coach type does not exist)
--           (any database error is rolled back and re-raised)
-- Example : CALL sp_add_coaches_generate_seats(1, 1, 2);  -- adds S1, S2 and 2 x 72 = 144 seats
-- ---------------------------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_add_coaches_generate_seats$$
CREATE PROCEDURE sp_add_coaches_generate_seats(
    IN p_train_id      INT UNSIGNED,
    IN p_coach_type_id INT UNSIGNED,
    IN p_coach_count   TINYINT
)
BEGIN
    DECLARE v_train_id         INT UNSIGNED DEFAULT NULL;  -- stays NULL when the train does not exist
    DECLARE v_class_code       VARCHAR(3)   DEFAULT NULL;  -- stays NULL when the coach type does not exist
    DECLARE v_seats_per_coach  SMALLINT     DEFAULT NULL;
    DECLARE v_prefix           VARCHAR(1)   DEFAULT NULL;  -- S, B, A, H or C
    DECLARE v_existing_coaches INT          DEFAULT 0;     -- coaches of this class already on the train
    DECLARE v_coach_index      INT          DEFAULT 0;     -- 0-based counter of the outer loop
    DECLARE v_coach_number     VARCHAR(4);
    DECLARE v_coach_id         INT UNSIGNED;
    DECLARE v_seat_no          INT;
    DECLARE v_berth_type       VARCHAR(2);
    DECLARE v_coaches_added    INT          DEFAULT 0;
    DECLARE v_seats_added      INT          DEFAULT 0;

    -- Any database error: undo everything and pass the same error to the caller.
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    -- (1) Basic input validation (no database access yet).
    IF p_train_id IS NULL OR p_coach_type_id IS NULL OR p_coach_count IS NULL OR p_coach_count < 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'VALIDATION_ERROR: train id, coach type id and a coach count of at least 1 are required';
    END IF;

    START TRANSACTION;

    -- (2) The train must exist. FOR UPDATE locks its row, so two calls for the same train
    --     are executed one after the other and cannot produce the same Coach_Number twice.
    SELECT Train_ID
      INTO v_train_id
      FROM train
     WHERE Train_ID = p_train_id
       FOR UPDATE;

    IF v_train_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = CONCAT('NOT_FOUND: train ', p_train_id, ' does not exist');
    END IF;

    -- (3) The coach type must exist; we need its class code and seat count.
    SELECT Class_Code, Seats_Per_Coach
      INTO v_class_code, v_seats_per_coach
      FROM coach_type
     WHERE Coach_Type_ID = p_coach_type_id;

    IF v_class_code IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = CONCAT('NOT_FOUND: coach type ', p_coach_type_id, ' does not exist');
    END IF;

    -- (4) Class prefix map: SL->S, 3A->B, 2A->A, 1A->H, CC->C.
    SET v_prefix = CASE v_class_code
                       WHEN 'SL' THEN 'S'
                       WHEN '3A' THEN 'B'
                       WHEN '2A' THEN 'A'
                       WHEN '1A' THEN 'H'
                       WHEN 'CC' THEN 'C'
                   END;

    -- (5) Next coach number = (coaches of this class already on the train) + 1.
    SELECT COUNT(*)
      INTO v_existing_coaches
      FROM train_coach
     WHERE Train_ID      = p_train_id
       AND Coach_Type_ID = p_coach_type_id;

    -- (6) Outer loop: one train_coach row per new coach.
    WHILE v_coach_index < p_coach_count DO
        SET v_coach_number = CONCAT(v_prefix, v_existing_coaches + v_coach_index + 1);

        INSERT INTO train_coach (Train_ID, Coach_Type_ID, Coach_Number)
        VALUES (p_train_id, p_coach_type_id, v_coach_number);

        SET v_coach_id      = LAST_INSERT_ID();
        SET v_coaches_added = v_coaches_added + 1;

        -- Inner loop: Seat_No 1..Seats_Per_Coach, berth type taken from the class cycle.
        -- ELT(MOD(n-1, k) + 1, ...) picks element number ((n-1) mod k) + 1 of the cycle of length k.
        SET v_seat_no = 1;
        WHILE v_seat_no <= v_seats_per_coach DO
            IF v_class_code IN ('SL', '3A') THEN
                SET v_berth_type = ELT(MOD(v_seat_no - 1, 8) + 1, 'LB', 'MB', 'UB', 'LB', 'MB', 'UB', 'SL', 'SU');
            ELSEIF v_class_code = '2A' THEN
                SET v_berth_type = ELT(MOD(v_seat_no - 1, 6) + 1, 'LB', 'UB', 'LB', 'UB', 'SL', 'SU');
            ELSEIF v_class_code = '1A' THEN
                SET v_berth_type = ELT(MOD(v_seat_no - 1, 2) + 1, 'LB', 'UB');
            ELSE  -- 'CC' (the CHECK on coach_type allows no other class code)
                SET v_berth_type = ELT(MOD(v_seat_no - 1, 6) + 1, 'W', 'M', 'A', 'A', 'M', 'W');
            END IF;

            INSERT INTO seat (Coach_ID, Seat_No, Berth_Type)
            VALUES (v_coach_id, v_seat_no, v_berth_type);

            SET v_seats_added = v_seats_added + 1;
            SET v_seat_no     = v_seat_no + 1;
        END WHILE;

        SET v_coach_index = v_coach_index + 1;
    END WHILE;

    COMMIT;

    -- (7) The one and only result set.
    SELECT v_coaches_added AS Coaches_Added,
           v_seats_added   AS Seats_Added;
END$$

-- ---------------------------------------------------------------------------------------------
-- sp_generate_train_runs
-- Purpose : create the train_run rows (one per journey date) of a train for a date range.
--           A run is created for a date only when
--             - the train has a train_schedule row for that ISO weekday (1=Mon .. 7=Sun,
--               which is WEEKDAY(date) + 1), and
--             - no run exists yet for that train and date.
--           Therefore the procedure can be run again for the same range without creating duplicates.
--           The triggers owned by G3 (seat_inventory) and G5 (train_run_status) fire on every
--           insert; this procedure does not touch their tables.
-- Params  : p_train_id   train.Train_ID
--           p_from_date  first journey date (included)
--           p_to_date    last journey date (included); the range may cover at most 60 days
--                        after p_from_date (to - from between 0 and 60)
-- Result  : one row with the column Runs_Created (runs inserted by this call).
-- Errors  : VALIDATION_ERROR (an argument is NULL, p_to_date < p_from_date, or range > 60 days)
--           NOT_FOUND        (train does not exist)
--           (any database error is rolled back and re-raised)
-- Example : CALL sp_generate_train_runs(1, CURDATE(), DATE_ADD(CURDATE(), INTERVAL 14 DAY));
-- ---------------------------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_generate_train_runs$$
CREATE PROCEDURE sp_generate_train_runs(
    IN p_train_id  INT UNSIGNED,
    IN p_from_date DATE,
    IN p_to_date   DATE
)
BEGIN
    DECLARE v_train_id     INT UNSIGNED DEFAULT NULL;  -- stays NULL when the train does not exist
    DECLARE v_date         DATE;                       -- the date the loop is working on
    DECLARE v_runs_created INT DEFAULT 0;

    -- Any database error: undo everything and pass the same error to the caller.
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    -- (1) Input validation (no database access yet).
    IF p_train_id IS NULL OR p_from_date IS NULL OR p_to_date IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'VALIDATION_ERROR: train id, from date and to date are required';
    END IF;

    IF p_to_date < p_from_date THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'VALIDATION_ERROR: to date must not be before from date';
    END IF;

    IF DATEDIFF(p_to_date, p_from_date) > 60 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'VALIDATION_ERROR: date range must not be longer than 60 days';
    END IF;

    START TRANSACTION;

    -- (2) The train must exist. FOR UPDATE locks its row, so two simultaneous calls for the same
    --     train run one after the other; the second one then sees the runs of the first and
    --     does not hit the UNIQUE(Train_ID, Journey_Date) key.
    SELECT Train_ID
      INTO v_train_id
      FROM train
     WHERE Train_ID = p_train_id
       FOR UPDATE;

    IF v_train_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = CONCAT('NOT_FOUND: train ', p_train_id, ' does not exist');
    END IF;

    -- (3) Walk through the dates one day at a time.
    SET v_date = p_from_date;
    WHILE v_date <= p_to_date DO
        IF EXISTS (SELECT 1
                     FROM train_schedule
                    WHERE Train_ID    = p_train_id
                      AND Day_Of_Week = WEEKDAY(v_date) + 1)
           AND NOT EXISTS (SELECT 1
                             FROM train_run
                            WHERE Train_ID     = p_train_id
                              AND Journey_Date = v_date) THEN

            -- Created_At uses its default; the G3 and G5 triggers add inventory and status rows.
            INSERT INTO train_run (Train_ID, Journey_Date)
            VALUES (p_train_id, v_date);

            SET v_runs_created = v_runs_created + 1;
        END IF;

        SET v_date = DATE_ADD(v_date, INTERVAL 1 DAY);
    END WHILE;

    COMMIT;

    -- (4) The one and only result set.
    SELECT v_runs_created AS Runs_Created;
END$$

DELIMITER ;
