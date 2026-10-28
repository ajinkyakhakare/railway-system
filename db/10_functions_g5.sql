-- Task G5.2 | Owner group: G5 Railway Operations & Analytics | Purpose: UDF fn_delay_minutes (delay in whole minutes, never negative)

DROP FUNCTION IF EXISTS fn_delay_minutes;

DELIMITER $$

-- ---------------------------------------------------------------------------
-- fn_delay_minutes(p_scheduled, p_actual)
-- Returns how many whole minutes the actual time is LATER than the scheduled
-- time. A train that is early or exactly on time gives 0 (delay is never
-- negative). If either argument is NULL the result is NULL.
-- Example: fn_delay_minutes('2026-10-27 06:00:00','2026-10-27 06:42:30') = 42
-- Declared DETERMINISTIC (same inputs always give the same output, no table
-- access), exactly as contract C5.1 states.
-- ---------------------------------------------------------------------------
CREATE FUNCTION fn_delay_minutes(p_scheduled DATETIME, p_actual DATETIME)
RETURNS INT
DETERMINISTIC
BEGIN
    RETURN GREATEST(TIMESTAMPDIFF(MINUTE, p_scheduled, p_actual), 0);
END$$

DELIMITER ;
