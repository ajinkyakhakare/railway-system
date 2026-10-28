-- G5.3 | owner: G5 (Railway Operations & Analytics) | triggers: trg_run_init_status, trg_status_flag, trg_delay_log
-- Runs after the schemas (01..05) and functions/procedures. Re-runnable: every trigger is dropped first.
-- Note: trg_run_init_status lives on G1's train_run table but only INSERTS into G5's own train_run_status (contract C11 rule 3).

DELIMITER $$

-- ---------------------------------------------------------------------------
-- trg_run_init_status
-- Every new train run automatically gets a live-status row: SCHEDULED, 0 minutes late.
-- This is why sp_update_train_status only needs to UPDATE (the row always exists).
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_run_init_status$$
CREATE TRIGGER trg_run_init_status
AFTER INSERT ON train_run
FOR EACH ROW
BEGIN
    INSERT INTO train_run_status (Run_ID, Status, Delay_Minutes)
    VALUES (NEW.Run_ID, 'SCHEDULED', 0);
END$$

-- ---------------------------------------------------------------------------
-- trg_status_flag
-- Keeps Status consistent with Delay_Minutes, so operators cannot forget to flag a late train:
--   * 15 minutes or more late while the train is SCHEDULED or ON_TIME  -> DELAYED
--   * delay cleared to 0 while the train is DELAYED                    -> ON_TIME
-- Other statuses (CANCELLED, ARRIVED) are never changed by this trigger.
-- BEFORE UPDATE: we edit the NEW row before it is written, so no extra UPDATE statement is needed.
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_status_flag$$
CREATE TRIGGER trg_status_flag
BEFORE UPDATE ON train_run_status
FOR EACH ROW
BEGIN
    IF NEW.Delay_Minutes >= 15 AND NEW.Status IN ('SCHEDULED', 'ON_TIME') THEN
        SET NEW.Status = 'DELAYED';
    END IF;

    IF NEW.Delay_Minutes = 0 AND NEW.Status = 'DELAYED' THEN
        SET NEW.Status = 'ON_TIME';
    END IF;
END$$

-- ---------------------------------------------------------------------------
-- trg_delay_log
-- History of delay changes: one delay_log row each time Delay_Minutes changes.
-- Updates that only touch the reason / station / status do NOT create a log row.
-- (<=> is MySQL's NULL-safe equality; NOT (a <=> b) means "a and b differ".)
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_delay_log$$
CREATE TRIGGER trg_delay_log
AFTER UPDATE ON train_run_status
FOR EACH ROW
BEGIN
    IF NOT (OLD.Delay_Minutes <=> NEW.Delay_Minutes) THEN
        INSERT INTO delay_log (Run_ID, Station_ID, Delay_Minutes, Reason)
        VALUES (NEW.Run_ID, NEW.Current_Station_ID, NEW.Delay_Minutes, NEW.Last_Reason);
    END IF;
END$$

DELIMITER ;
