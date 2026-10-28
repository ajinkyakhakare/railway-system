-- Task G1.2 | Owner: G1 Train, Station & Route | Purpose: UDFs fn_distance_km, fn_departure_datetime, fn_journey_duration_min (contract C5.1)
--
-- All three functions follow the same pattern:
--   * one SELECT ... INTO with joins  train_run -> train -> route_stop
--   * the result variable starts as NULL, so "no data" simply returns NULL
--   * a local CONTINUE HANDLER FOR NOT FOUND keeps the "zero rows" condition inside the function.
--     Without it, a caller that loops over a cursor (for example G3's sp_book_ticket) could
--     mistake the "no data" condition for the end of its own cursor.
--   * "NOT DETERMINISTIC READS SQL DATA": the result depends on table contents, and the declaration
--     is required because binary logging rejects functions that declare neither.
-- Ids are INT UNSIGNED as stated in contract C5.1.

DELIMITER $$

-- ---------------------------------------------------------------------------------------------
-- fn_distance_km
-- Purpose : distance in km between two stations on the route of the train that runs on a given run.
-- Params  : p_run_id (train_run.Run_ID), p_from_station_id, p_to_station_id (station ids).
-- Returns : INT = |Distance_From_Source_Km(to) - Distance_From_Source_Km(from)|;
--           NULL when the run does not exist or either station is not on that route.
-- Errors  : none (never signals; missing data gives NULL).
-- ---------------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_distance_km$$
CREATE FUNCTION fn_distance_km(
    p_run_id          INT UNSIGNED,
    p_from_station_id INT UNSIGNED,
    p_to_station_id   INT UNSIGNED
)
RETURNS INT
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_distance INT DEFAULT NULL;

    -- If the SELECT finds no row, keep v_distance NULL.
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_distance = NULL;

    -- route_stop is joined twice: once for the "from" stop, once for the "to" stop,
    -- both restricted to the route of the train that operates this run.
    SELECT ABS(rs_to.Distance_From_Source_Km - rs_from.Distance_From_Source_Km)
      INTO v_distance
      FROM train_run  tr
      JOIN train      t       ON t.Train_ID        = tr.Train_ID
      JOIN route_stop rs_from ON rs_from.Route_ID  = t.Route_ID
                             AND rs_from.Station_ID = p_from_station_id
      JOIN route_stop rs_to   ON rs_to.Route_ID    = t.Route_ID
                             AND rs_to.Station_ID   = p_to_station_id
     WHERE tr.Run_ID = p_run_id;

    RETURN v_distance;
END$$

-- ---------------------------------------------------------------------------------------------
-- fn_departure_datetime
-- Purpose : the real date and time at which a run leaves (or, at the last stop, reaches) a station.
-- Params  : p_run_id (train_run.Run_ID), p_station_id (station id).
-- Returns : DATETIME = Journey_Date + Day_Offset days + Departure_Time of that stop
--           (Arrival_Time when Departure_Time is NULL, i.e. at the last stop);
--           NULL when the run does not exist or the station is not on the route.
-- Errors  : none (never signals; missing data gives NULL).
-- ---------------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_departure_datetime$$
CREATE FUNCTION fn_departure_datetime(
    p_run_id     INT UNSIGNED,
    p_station_id INT UNSIGNED
)
RETURNS DATETIME
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_departure DATETIME DEFAULT NULL;

    -- If the SELECT finds no row, keep v_departure NULL.
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_departure = NULL;

    -- TIMESTAMP(date, time) glues the Journey_Date and the stop's clock time together;
    -- DATE_ADD then moves it forward by Day_Offset days (overnight trains).
    -- COALESCE picks Arrival_Time when Departure_Time is NULL (last stop of the route).
    SELECT DATE_ADD(
               TIMESTAMP(tr.Journey_Date, COALESCE(rs.Departure_Time, rs.Arrival_Time)),
               INTERVAL rs.Day_Offset DAY)
      INTO v_departure
      FROM train_run  tr
      JOIN train      t  ON t.Train_ID      = tr.Train_ID
      JOIN route_stop rs ON rs.Route_ID     = t.Route_ID
                        AND rs.Station_ID   = p_station_id
     WHERE tr.Run_ID = p_run_id;

    RETURN v_departure;
END$$

-- ---------------------------------------------------------------------------------------------
-- fn_journey_duration_min
-- Purpose : travel time in minutes between two stops of a run.
-- Params  : p_run_id (train_run.Run_ID), p_from_station_id, p_to_station_id (station ids).
-- Returns : INT = minutes from departure at "from"
--                 (Journey_Date + Day_Offset days + Departure_Time of the from-stop)
--                 to arrival at "to"
--                 (Journey_Date + Day_Offset days + Arrival_Time of the to-stop);
--           NULL when the run or a station is invalid, or Stop_Seq(from) >= Stop_Seq(to).
-- Errors  : none (never signals; invalid input gives NULL).
-- ---------------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_journey_duration_min$$
CREATE FUNCTION fn_journey_duration_min(
    p_run_id          INT UNSIGNED,
    p_from_station_id INT UNSIGNED,
    p_to_station_id   INT UNSIGNED
)
RETURNS INT
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_minutes INT DEFAULT NULL;

    -- If the SELECT finds no row, keep v_minutes NULL.
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_minutes = NULL;

    -- The condition rs_from.Stop_Seq < rs_to.Stop_Seq makes the query return no row
    -- when the stations are in the wrong order (or identical), which gives NULL.
    -- The from-stop is never the last stop here, so it has a Departure_Time; COALESCE is only
    -- a safety net. The to-stop is never the first stop, so it has an Arrival_Time.
    SELECT TIMESTAMPDIFF(
               MINUTE,
               DATE_ADD(TIMESTAMP(tr.Journey_Date, COALESCE(rs_from.Departure_Time, rs_from.Arrival_Time)),
                        INTERVAL rs_from.Day_Offset DAY),
               DATE_ADD(TIMESTAMP(tr.Journey_Date, rs_to.Arrival_Time),
                        INTERVAL rs_to.Day_Offset DAY))
      INTO v_minutes
      FROM train_run  tr
      JOIN train      t       ON t.Train_ID        = tr.Train_ID
      JOIN route_stop rs_from ON rs_from.Route_ID  = t.Route_ID
                             AND rs_from.Station_ID = p_from_station_id
      JOIN route_stop rs_to   ON rs_to.Route_ID    = t.Route_ID
                             AND rs_to.Station_ID   = p_to_station_id
                             AND rs_from.Stop_Seq   < rs_to.Stop_Seq
     WHERE tr.Run_ID = p_run_id;

    RETURN v_minutes;
END$$

DELIMITER ;
