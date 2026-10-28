-- Task G3.3 | Owner group: G3 (Reservation & Seat) | Purpose: views v_seat_availability and v_run_occupancy (contract C5.4)
-- Runs after all tables, functions, procedures and triggers. Re-runnable: CREATE OR REPLACE VIEW.
-- Both views are read-only reports built on seat_inventory; the REST API reads them for /availability and /admin/occupancy.

-- ---------------------------------------------------------------------------------------------
-- v_seat_availability : one row per (run, class) with the live counters and the text shown on the
-- booking screen (AVL n / RAC n / WL n / REGRET) produced by the G3 function fn_availability_text.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_seat_availability AS
SELECT si.Run_ID,
       tr.Train_ID,
       t.Train_No,
       t.Train_Name,
       tr.Journey_Date,
       si.Class_Code,
       si.Total_Seats,
       si.Available_CNF,
       si.RAC_Count,
       si.WL_Count,
       si.Max_RAC,
       si.Max_WL,
       fn_availability_text(si.Available_CNF, si.RAC_Count, si.WL_Count, si.Max_RAC, si.Max_WL) AS Availability_Text
FROM seat_inventory si
JOIN train_run tr ON tr.Run_ID   = si.Run_ID
JOIN train     t  ON t.Train_ID  = tr.Train_ID;

-- ---------------------------------------------------------------------------------------------
-- v_run_occupancy : how full each (run, class) is, and its rank among all rows of the same journey date.
--   Booked_Seats  = Total_Seats - Available_CNF            (confirmed seats only; RAC/WL are not seats)
--   Occupancy_Pct = Booked_Seats * 100 / Total_Seats, one decimal
--   Occupancy_Rank = RANK() within the journey date, fullest first (ties share a rank)
-- The percentage is computed in an inner query because a window function cannot use a column
-- alias that is defined in the same SELECT.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_run_occupancy AS
SELECT x.Run_ID,
       x.Train_No,
       x.Journey_Date,
       x.Class_Code,
       x.Total_Seats,
       x.Booked_Seats,
       x.Occupancy_Pct,
       RANK() OVER (PARTITION BY x.Journey_Date ORDER BY x.Occupancy_Pct DESC) AS Occupancy_Rank
FROM (
    SELECT si.Run_ID,
           t.Train_No,
           tr.Journey_Date,
           si.Class_Code,
           si.Total_Seats,
           (si.Total_Seats - si.Available_CNF) AS Booked_Seats,
           IF(si.Total_Seats = 0,
              0,
              ROUND((si.Total_Seats - si.Available_CNF) * 100 / si.Total_Seats, 1)) AS Occupancy_Pct
    FROM seat_inventory si
    JOIN train_run tr ON tr.Run_ID  = si.Run_ID
    JOIN train     t  ON t.Train_ID = tr.Train_ID
) x;
