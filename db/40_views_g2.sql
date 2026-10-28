-- Task G2.3 | Owner: G2 (Passenger & User) | Purpose: views v_user_account and v_passenger_booking_history (contract C5.4)
-- Re-runnable: CREATE OR REPLACE VIEW. Both views are read-only; G3 owns booking tables.

-- ---------------------------------------------------------------------------
-- v_user_account : one row per user with all role names in one column.
-- LEFT JOINs keep users that (temporarily) have no role; their Roles is NULL.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_user_account AS
SELECT
    u.User_ID,
    u.Email,
    u.Full_Name,
    u.Phone,
    u.Is_Active,
    GROUP_CONCAT(r.Role_Name ORDER BY r.Role_Name SEPARATOR ',') AS Roles,
    u.Created_At
FROM app_user u
LEFT JOIN user_role ur ON ur.User_ID = u.User_ID
LEFT JOIN role r       ON r.Role_ID  = ur.Role_ID
GROUP BY u.User_ID, u.Email, u.Full_Name, u.Phone, u.Is_Active, u.Created_At;

-- ---------------------------------------------------------------------------
-- v_passenger_booking_history : one row per passenger per booking.
-- passenger -> booking_passenger -> booking -> train_run -> train, and the
-- station table is joined twice (once for the from-code, once for the to-code).
-- Passengers that were never booked do not appear (inner joins).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_passenger_booking_history AS
SELECT
    p.User_ID,
    p.Passenger_ID,
    p.Full_Name          AS Passenger_Name,
    b.Booking_ID,
    bp.Booking_Passenger_ID,
    b.PNR,
    t.Train_No,
    t.Train_Name,
    tr.Journey_Date,
    sf.Station_Code      AS From_Station_Code,
    st.Station_Code      AS To_Station_Code,
    b.Class_Code,
    bp.Status,
    bp.Fare_Amount,
    b.Booked_At
FROM passenger p
JOIN booking_passenger bp ON bp.Passenger_ID = p.Passenger_ID
JOIN booking b            ON b.Booking_ID    = bp.Booking_ID
JOIN train_run tr         ON tr.Run_ID       = b.Run_ID
JOIN train t              ON t.Train_ID      = tr.Train_ID
JOIN station sf           ON sf.Station_ID   = b.From_Station_ID
JOIN station st           ON st.Station_ID   = b.To_Station_ID;
