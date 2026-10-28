-- Task G2.2 | Owner: G2 (Passenger & User) | Purpose: UDFs fn_age_category and fn_effective_concession (contract C5.1)

DELIMITER $$

-- ---------------------------------------------------------------------------
-- fn_age_category
-- Purpose   : classify a passenger by age (in whole years, measured today).
-- Parameter : p_dob  DATE of birth.
-- Returns   : 'CHILD'  when age < 12
--             'SENIOR' when age >= 60
--             'ADULT'  otherwise (also when p_dob is NULL)
-- Boundaries: age 11 -> CHILD, 12 -> ADULT, 59 -> ADULT, 60 -> SENIOR.
-- Note      : uses CURDATE(), so it is NOT DETERMINISTIC (the answer changes
--             from day to day). It reads no table, hence NO SQL.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_age_category$$
CREATE FUNCTION fn_age_category(p_dob DATE)
RETURNS VARCHAR(10)
NOT DETERMINISTIC
NO SQL
BEGIN
    DECLARE v_age INT;

    -- Completed years between date of birth and today.
    SET v_age = TIMESTAMPDIFF(YEAR, p_dob, CURDATE());

    IF v_age < 12 THEN
        RETURN 'CHILD';
    ELSEIF v_age >= 60 THEN
        RETURN 'SENIOR';
    END IF;

    RETURN 'ADULT';
END$$

-- ---------------------------------------------------------------------------
-- fn_effective_concession
-- Purpose   : decide which concession type applies to a passenger.
--             Age-based concessions (SENIOR, CHILD) win over the declared one.
-- Parameters: p_dob       DATE of birth
--             p_declared  concession stored on the passenger (NONE/GOVT/SOLDIER)
-- Returns   : 'SENIOR' if the passenger is a senior,
--             'CHILD'  if the passenger is a child,
--             otherwise p_declared unchanged.
-- Note      : NOT DETERMINISTIC NO SQL (depends on CURDATE through
--             fn_age_category, reads no table).
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_effective_concession$$
CREATE FUNCTION fn_effective_concession(p_dob DATE, p_declared VARCHAR(10))
RETURNS VARCHAR(10)
NOT DETERMINISTIC
NO SQL
BEGIN
    DECLARE v_category VARCHAR(10);

    SET v_category = fn_age_category(p_dob);

    IF v_category = 'SENIOR' THEN
        RETURN 'SENIOR';
    ELSEIF v_category = 'CHILD' THEN
        RETURN 'CHILD';
    END IF;

    RETURN p_declared;
END$$

DELIMITER ;
