-- Task G1.3 | Owner group G1 (Train, Station & Route) | Triggers on route_stop: timing-change audit and halt-time validation
-- Run order: after 01_schema_g1.sql (tables) and before 50_seed_g1.sql (seed).

DELIMITER $$

-- -----------------------------------------------------------------------------
-- trg_route_stop_audit  (AFTER UPDATE on route_stop)
-- Writes one row to route_stop_audit whenever the Arrival_Time or the
-- Departure_Time of a stop changes. Changes of any other column (distance,
-- day offset) are NOT audited.
-- The null-safe operator <=> is used because first stops have Arrival_Time NULL
-- and last stops have Departure_Time NULL; with plain "<>" a NULL -> time change
-- would be missed (NULL <> '06:00:00' evaluates to NULL, not TRUE).
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_route_stop_audit$$
CREATE TRIGGER trg_route_stop_audit
AFTER UPDATE ON route_stop
FOR EACH ROW
BEGIN
    IF NOT (OLD.Arrival_Time <=> NEW.Arrival_Time)
       OR NOT (OLD.Departure_Time <=> NEW.Departure_Time) THEN
        INSERT INTO route_stop_audit
            (Route_Stop_ID, Old_Arrival_Time, New_Arrival_Time,
             Old_Departure_Time, New_Departure_Time)
        VALUES
            (OLD.Route_Stop_ID, OLD.Arrival_Time, NEW.Arrival_Time,
             OLD.Departure_Time, NEW.Departure_Time);
    END IF;
END$$

-- -----------------------------------------------------------------------------
-- trg_route_stop_bi  (BEFORE INSERT on route_stop)
-- A halt never crosses midnight (Day_Offset describes the day of the stop, not
-- of the halt), so when both times are present the departure must not be
-- earlier than the arrival. Equal times (a zero-minute halt) are allowed.
-- A NULL time (first stop has no arrival, last stop has no departure) is
-- always allowed.
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_route_stop_bi$$
CREATE TRIGGER trg_route_stop_bi
BEFORE INSERT ON route_stop
FOR EACH ROW
BEGIN
    IF NEW.Arrival_Time IS NOT NULL
       AND NEW.Departure_Time IS NOT NULL
       AND NEW.Departure_Time < NEW.Arrival_Time THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'VALIDATION_ERROR: Departure time cannot be earlier than arrival time at the same stop';
    END IF;
END$$

DELIMITER ;
