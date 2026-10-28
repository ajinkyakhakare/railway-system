-- Task G1.3 | Owner group G1 (Train, Station & Route) | Views: v_train_timetable and v_train_stop_pairs
-- Run order: after all schemas, functions, procedures and triggers; before the seed files.

-- -----------------------------------------------------------------------------
-- v_train_timetable
-- One row per (train, stop): the full timetable of every train, built from the
-- train's route. The caller adds WHERE Train_ID = ? and ORDER BY Stop_Seq.
-- Day_Offset = days since the start of the journey (1 = the stop is reached
-- after midnight); Distance_From_Source_Km = km from the route's first station.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_train_timetable AS
SELECT
    t.Train_ID                  AS Train_ID,
    t.Train_No                  AS Train_No,
    t.Train_Name                AS Train_Name,
    t.Route_ID                  AS Route_ID,
    rs.Stop_Seq                 AS Stop_Seq,
    rs.Station_ID               AS Station_ID,
    s.Station_Code              AS Station_Code,
    s.Station_Name              AS Station_Name,
    rs.Arrival_Time             AS Arrival_Time,
    rs.Departure_Time           AS Departure_Time,
    rs.Day_Offset               AS Day_Offset,
    rs.Distance_From_Source_Km  AS Distance_From_Source_Km
FROM train t
JOIN route_stop rs ON rs.Route_ID   = t.Route_ID
JOIN station    s  ON s.Station_ID  = rs.Station_ID;

-- -----------------------------------------------------------------------------
-- v_train_stop_pairs
-- Every possible (from station, to station) journey of every ACTIVE train.
-- It is a self-join of route_stop on the same route where the "from" stop (a)
-- comes before the "to" stop (b): a.Stop_Seq < b.Stop_Seq.
--   Departure_Time = departure at the "from" stop (a)
--   Arrival_Time   = arrival at the "to" stop (b)
--   Distance_Km    = distance between the two stops
-- Used by the train search (/trains/search): WHERE From_Station_ID = ? AND
-- To_Station_ID = ?  (a train that visits the stations in the opposite order
-- produces no row, so the search can never return the wrong direction).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_train_stop_pairs AS
SELECT
    t.Train_ID                  AS Train_ID,
    t.Train_No                  AS Train_No,
    t.Train_Name                AS Train_Name,
    t.Train_Type                AS Train_Type,
    t.Route_ID                  AS Route_ID,
    a.Station_ID                AS From_Station_ID,
    b.Station_ID                AS To_Station_ID,
    a.Stop_Seq                  AS From_Stop_Seq,
    b.Stop_Seq                  AS To_Stop_Seq,
    a.Departure_Time            AS Departure_Time,
    b.Arrival_Time              AS Arrival_Time,
    a.Day_Offset                AS Day_Offset_From,
    b.Day_Offset                AS Day_Offset_To,
    (b.Distance_From_Source_Km - a.Distance_From_Source_Km) AS Distance_Km
FROM route_stop a
JOIN route_stop b ON a.Route_ID = b.Route_ID
                 AND a.Stop_Seq < b.Stop_Seq
JOIN train t      ON t.Route_ID = a.Route_ID
                 AND t.Is_Active = 1;
