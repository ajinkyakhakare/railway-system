-- Task G4.2 | Owner: G4 (Payment, Cancellation & Refund) | Purpose: UDFs fn_base_fare, fn_net_fare, fn_refund_deduction_pct (fare, concession and refund-deduction calculation)
-- Requires: schema files 01..04 (tables fare_rule, concession_rule, refund_rule).
-- Seed file 52_seed_g4.sql provides the rule rows; the functions work (with defaults) even if the tables are empty.

DELIMITER $$

-- ---------------------------------------------------------------------------
-- fn_base_fare
-- Purpose : Fare for ONE passenger before concession, from distance and class.
-- Params  : p_class_code   - 'SL','3A','2A','1A','CC'
--           p_distance_km  - travel distance in km (see G1 fn_distance_km)
-- Returns : GREATEST(ROUND(distance * Base_Fare_Per_Km, 2), Min_Fare)
--           NULL when there is no fare_rule row for the class
--           (or when the distance itself is NULL).
-- Errors  : none (never raises; NULL means "cannot price this").
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_base_fare$$
CREATE FUNCTION fn_base_fare(p_class_code VARCHAR(3), p_distance_km INT)
RETURNS DECIMAL(10,2)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    -- Stays NULL if no fare_rule row exists for the class
    -- (SELECT ... INTO leaves the variable untouched when no row is found).
    DECLARE v_fare DECIMAL(10,2) DEFAULT NULL;

    SELECT GREATEST(ROUND(p_distance_km * Base_Fare_Per_Km, 2), Min_Fare)
      INTO v_fare
      FROM fare_rule
     WHERE Class_Code = p_class_code;

    RETURN v_fare;
END$$

-- ---------------------------------------------------------------------------
-- fn_net_fare
-- Purpose : Apply a concession discount to a base fare.
-- Params  : p_base_fare        - fare before concession
--           p_concession_type  - 'NONE','SENIOR','GOVT','SOLDIER','CHILD'
-- Returns : ROUND(p_base_fare * (1 - Discount_Percent / 100), 2)
--           Discount is 0% when the concession type is not found in
--           concession_rule. NULL base fare gives NULL.
-- Errors  : none.
-- Example : fn_net_fare(1000, 'SENIOR') = 600.00  (SENIOR = 40%)
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_net_fare$$
CREATE FUNCTION fn_net_fare(p_base_fare DECIMAL(10,2), p_concession_type VARCHAR(10))
RETURNS DECIMAL(10,2)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    -- Default 0% discount, kept when the type is unknown.
    DECLARE v_discount DECIMAL(5,2) DEFAULT 0;

    SELECT Discount_Percent
      INTO v_discount
      FROM concession_rule
     WHERE Concession_Type = p_concession_type;

    RETURN ROUND(p_base_fare * (1 - v_discount / 100), 2);
END$$

-- ---------------------------------------------------------------------------
-- fn_refund_deduction_pct
-- Purpose : Percentage of the fare that is deducted when a ticket is cancelled,
--           depending on how many hours remain before departure.
-- Params  : p_hours_before - hours between cancellation and departure
-- Returns : Deduction_Percent of the refund_rule row where
--             Min_Hours_Before <= p_hours_before
--             AND (Max_Hours_Before IS NULL OR p_hours_before < Max_Hours_Before)
--           100.00 when no row matches (e.g. negative or NULL hours).
-- Errors  : none.
-- Examples (with seed 52): 60 -> 10.00, 30 -> 25.00, 6 -> 50.00, 2 -> 100.00
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_refund_deduction_pct$$
CREATE FUNCTION fn_refund_deduction_pct(p_hours_before DECIMAL(8,2))
RETURNS DECIMAL(5,2)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    -- Default 100% (no refund) when no rule matches.
    DECLARE v_pct DECIMAL(5,2) DEFAULT 100;

    -- Rule bands should not overlap; ORDER BY ... LIMIT 1 guarantees a single
    -- row (the band with the highest lower bound) even if they do.
    SELECT Deduction_Percent
      INTO v_pct
      FROM refund_rule
     WHERE Min_Hours_Before <= p_hours_before
       AND (Max_Hours_Before IS NULL OR p_hours_before < Max_Hours_Before)
     ORDER BY Min_Hours_Before DESC
     LIMIT 1;

    RETURN v_pct;
END$$

DELIMITER ;
