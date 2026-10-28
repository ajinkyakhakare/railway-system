-- Task G3.3 | Owner group: G3 (Reservation & Seat) | Purpose: the four G3 triggers that create and maintain seat_inventory counters (contract C5.3)
-- Runs after all schemas (01..05) and all functions/procedures (10_*, 20_*). Re-runnable: every trigger is dropped before it is created.
-- Design rule R9: seat_inventory counters (Available_CNF, RAC_Count, WL_Count) are changed ONLY by the triggers in this file.
-- Procedures only change booking_passenger.Status (or insert booking_passenger rows) and these triggers do the arithmetic.

DELIMITER $$

-- ---------------------------------------------------------------------------------------------
-- trg_run_init_inventory
-- When a train_run is created, create one seat_inventory row for every coach class of that train.
--   Total_Seats   = number of coaches of the class * Seats_Per_Coach
--   Available_CNF = Total_Seats (nothing booked yet), RAC_Count = 0, WL_Count = 0
--   Max_RAC       = 10 % of Total_Seats (rounded), Max_WL = 20 % of Total_Seats (rounded)
-- Coaches must exist before runs are generated, otherwise the train has no classes and no row is created.
-- One INSERT-SELECT statement with GROUP BY handles all classes at once (one row per distinct Class_Code).
-- Only the G3 table seat_inventory is written (contract C11 rule 3).
-- ---------------------------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_run_init_inventory$$
CREATE TRIGGER trg_run_init_inventory
AFTER INSERT ON train_run
FOR EACH ROW
BEGIN
    INSERT INTO seat_inventory
        (Run_ID, Class_Code, Total_Seats, Available_CNF, RAC_Count, WL_Count, Max_RAC, Max_WL)
    SELECT NEW.Run_ID,
           ct.Class_Code,
           SUM(ct.Seats_Per_Coach),                 -- one row per coach, so the SUM = coaches * seats per coach
           SUM(ct.Seats_Per_Coach),                 -- all seats are free at the start
           0,
           0,
           ROUND(SUM(ct.Seats_Per_Coach) * 0.10),   -- RAC limit
           ROUND(SUM(ct.Seats_Per_Coach) * 0.20)    -- waiting-list limit
    FROM train_coach tc
    JOIN coach_type ct ON ct.Coach_Type_ID = tc.Coach_Type_ID
    WHERE tc.Train_ID = NEW.Train_ID
    GROUP BY ct.Class_Code;
END$$

-- ---------------------------------------------------------------------------------------------
-- trg_block_if_wl_full
-- Runs BEFORE a booking_passenger row is inserted. If the new passenger is going to the waiting list
-- but the waiting list of that run and class is already full, stop with BOOKING_CLOSED_WL_FULL.
-- The error aborts the INSERT, so sp_book_ticket rolls the whole booking back.
-- The inventory row is found through the booking (Run_ID, Class_Code) of NEW.Booking_ID.
-- ---------------------------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_block_if_wl_full$$
CREATE TRIGGER trg_block_if_wl_full
BEFORE INSERT ON booking_passenger
FOR EACH ROW
BEGIN
    DECLARE v_wl_count SMALLINT DEFAULT NULL;
    DECLARE v_max_wl   SMALLINT DEFAULT NULL;

    IF NEW.Status = 'WL' THEN
        SELECT si.WL_Count, si.Max_WL
          INTO v_wl_count, v_max_wl
          FROM booking b
          JOIN seat_inventory si ON si.Run_ID = b.Run_ID
                                AND si.Class_Code = b.Class_Code
         WHERE b.Booking_ID = NEW.Booking_ID;

        -- Both variables stay NULL when no inventory row is found; then nothing is blocked here.
        IF v_wl_count IS NOT NULL AND v_wl_count >= v_max_wl THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'BOOKING_CLOSED_WL_FULL: Waiting list is full for this train and class';
        END IF;
    END IF;
END$$

-- ---------------------------------------------------------------------------------------------
-- trg_dec_inventory
-- Runs AFTER a booking_passenger row is inserted and moves the matching counter:
--   CNF -> Available_CNF - 1,  RAC -> RAC_Count + 1,  WL -> WL_Count + 1.
-- A row inserted with any other status (for example CANCELLED) does not change any counter.
-- ---------------------------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_dec_inventory$$
CREATE TRIGGER trg_dec_inventory
AFTER INSERT ON booking_passenger
FOR EACH ROW
BEGIN
    DECLARE v_run_id     INT UNSIGNED DEFAULT NULL;
    DECLARE v_class_code VARCHAR(3)   DEFAULT NULL;

    -- Which inventory row does this passenger belong to? Ask the booking.
    SELECT b.Run_ID, b.Class_Code
      INTO v_run_id, v_class_code
      FROM booking b
     WHERE b.Booking_ID = NEW.Booking_ID;

    IF NEW.Status = 'CNF' THEN
        UPDATE seat_inventory
           SET Available_CNF = Available_CNF - 1
         WHERE Run_ID = v_run_id AND Class_Code = v_class_code;
    ELSEIF NEW.Status = 'RAC' THEN
        UPDATE seat_inventory
           SET RAC_Count = RAC_Count + 1
         WHERE Run_ID = v_run_id AND Class_Code = v_class_code;
    ELSEIF NEW.Status = 'WL' THEN
        UPDATE seat_inventory
           SET WL_Count = WL_Count + 1
         WHERE Run_ID = v_run_id AND Class_Code = v_class_code;
    END IF;
END$$

-- ---------------------------------------------------------------------------------------------
-- trg_adjust_inventory_on_status
-- Runs AFTER booking_passenger is updated. Only a change of Status matters; every other column
-- change is ignored. The counter moves for exactly these transitions:
--   CNF -> CANCELLED : Available_CNF + 1        (a confirmed seat becomes free)
--   RAC -> CANCELLED : RAC_Count - 1
--   WL  -> CANCELLED : WL_Count - 1
--   RAC -> CNF       : RAC_Count - 1 and Available_CNF - 1   (promotion, a seat is taken)
--   WL  -> RAC       : WL_Count - 1 and RAC_Count + 1        (promotion)
-- Any other transition changes no counter. Every status change (listed or not) is written to
-- booking_status_history.
-- ---------------------------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_adjust_inventory_on_status$$
CREATE TRIGGER trg_adjust_inventory_on_status
AFTER UPDATE ON booking_passenger
FOR EACH ROW
BEGIN
    DECLARE v_run_id     INT UNSIGNED DEFAULT NULL;
    DECLARE v_class_code VARCHAR(3)   DEFAULT NULL;

    -- <=> is the NULL-safe "not equal" test: only continue when Status really changed.
    IF NOT (OLD.Status <=> NEW.Status) THEN

        SELECT b.Run_ID, b.Class_Code
          INTO v_run_id, v_class_code
          FROM booking b
         WHERE b.Booking_ID = NEW.Booking_ID;

        IF OLD.Status = 'CNF' AND NEW.Status = 'CANCELLED' THEN
            UPDATE seat_inventory
               SET Available_CNF = Available_CNF + 1
             WHERE Run_ID = v_run_id AND Class_Code = v_class_code;

        ELSEIF OLD.Status = 'RAC' AND NEW.Status = 'CANCELLED' THEN
            UPDATE seat_inventory
               SET RAC_Count = RAC_Count - 1
             WHERE Run_ID = v_run_id AND Class_Code = v_class_code;

        ELSEIF OLD.Status = 'WL' AND NEW.Status = 'CANCELLED' THEN
            UPDATE seat_inventory
               SET WL_Count = WL_Count - 1
             WHERE Run_ID = v_run_id AND Class_Code = v_class_code;

        ELSEIF OLD.Status = 'RAC' AND NEW.Status = 'CNF' THEN
            UPDATE seat_inventory
               SET RAC_Count     = RAC_Count - 1,
                   Available_CNF = Available_CNF - 1
             WHERE Run_ID = v_run_id AND Class_Code = v_class_code;

        ELSEIF OLD.Status = 'WL' AND NEW.Status = 'RAC' THEN
            UPDATE seat_inventory
               SET WL_Count  = WL_Count - 1,
                   RAC_Count = RAC_Count + 1
             WHERE Run_ID = v_run_id AND Class_Code = v_class_code;
        END IF;

        -- Audit trail: one history row for EVERY status change.
        INSERT INTO booking_status_history (Booking_Passenger_ID, Old_Status, New_Status)
        VALUES (NEW.Booking_Passenger_ID, OLD.Status, NEW.Status);
    END IF;
END$$

DELIMITER ;
