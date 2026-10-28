-- G5.3 | owner: G5 (Railway Operations & Analytics) | views: v_train_live_status, v_station_daily_revenue, v_popular_routes, v_delay_metrics
-- Runs after all schemas, functions, procedures and triggers. Re-runnable: CREATE OR REPLACE VIEW.
-- Column names and order follow contract C5.4 exactly (the backend turns them into camelCase JSON keys).

-- ---------------------------------------------------------------------------
-- v_train_live_status
-- One row per train run: today's operating status of a train on a given journey date.
-- LEFT JOIN on station because Current_Station_ID is NULL until an operator reports a position.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_train_live_status AS
SELECT
    s.Run_ID,
    t.Train_No,
    t.Train_Name,
    r.Journey_Date,
    s.Status,
    s.Delay_Minutes,
    s.Current_Station_ID,
    st.Station_Name AS Current_Station_Name,
    s.Last_Reason,
    s.Updated_At
FROM train_run_status s
JOIN train_run r          ON r.Run_ID = s.Run_ID
JOIN train t              ON t.Train_ID = r.Train_ID
LEFT JOIN station st      ON st.Station_ID = s.Current_Station_ID;

-- ---------------------------------------------------------------------------
-- v_station_daily_revenue
-- Live revenue per origin station (booking.From_Station_ID) per payment day.
-- Only successful payments count. Ticket_Count uses COUNT(DISTINCT Booking_ID) so a booking that
-- has two successful payments is still counted as one ticket booking.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_station_daily_revenue AS
SELECT
    st.Station_ID,
    st.Station_Code,
    st.Station_Name,
    DATE(p.Paid_At)             AS Revenue_Date,
    SUM(p.Amount)               AS Total_Revenue,
    COUNT(DISTINCT b.Booking_ID) AS Ticket_Count
FROM payment p
JOIN booking b   ON b.Booking_ID = p.Booking_ID
JOIN station st  ON st.Station_ID = b.From_Station_ID
WHERE p.Payment_Status = 'SUCCESS'
  AND p.Paid_At IS NOT NULL
GROUP BY st.Station_ID, st.Station_Code, st.Station_Name, DATE(p.Paid_At);

-- ---------------------------------------------------------------------------
-- v_popular_routes
-- Step 1 (inner query): count bookings per route, ignoring EXPIRED bookings.
-- Step 2 (outer query): RANK() gives the same rank to routes with the same count
--                       and leaves a gap after a tie (1, 1, 3 ...).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_popular_routes AS
SELECT
    c.Route_ID,
    c.Route_Name,
    c.Booking_Count,
    RANK() OVER (ORDER BY c.Booking_Count DESC) AS Popularity_Rank
FROM (
    SELECT
        ro.Route_ID,
        ro.Route_Name,
        COUNT(b.Booking_ID) AS Booking_Count
    FROM booking b
    JOIN train_run r  ON r.Run_ID = b.Run_ID
    JOIN train t      ON t.Train_ID = r.Train_ID
    JOIN route ro     ON ro.Route_ID = t.Route_ID
    WHERE b.Booking_Status <> 'EXPIRED'
    GROUP BY ro.Route_ID, ro.Route_Name
) AS c;

-- ---------------------------------------------------------------------------
-- v_delay_metrics
-- Punctuality summary per train over all its runs that have a status row.
-- COUNT(CASE WHEN ... THEN 1 END) counts only the rows where the condition is true.
-- Trains that have no runs yet do not appear (inner joins).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_delay_metrics AS
SELECT
    t.Train_ID,
    t.Train_No,
    t.Train_Name,
    COUNT(r.Run_ID)                                      AS Total_Runs,
    COUNT(CASE WHEN s.Status = 'DELAYED' THEN 1 END)     AS Delayed_Runs,
    ROUND(AVG(s.Delay_Minutes), 1)                       AS Avg_Delay_Min,
    MAX(s.Delay_Minutes)                                 AS Max_Delay_Min
FROM train t
JOIN train_run r         ON r.Train_ID = t.Train_ID
JOIN train_run_status s  ON s.Run_ID = r.Run_ID
GROUP BY t.Train_ID, t.Train_No, t.Train_Name;
