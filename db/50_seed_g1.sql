-- Task G1.3 | Owner group G1 (Train, Station & Route) | Master seed data of contract C6: stations, routes, stops, trains, schedules, coach types, coaches, 15 days of runs
-- Run order: AFTER all schemas (01..05), functions (10..), procedures (20..) and triggers (30..),
-- because the coaches are created by sp_add_coaches_generate_seats and the runs by
-- sp_generate_train_runs (their INSERTs fire the G3 / G5 triggers that create seat_inventory
-- and train_run_status rows). The CALL statements below print small result sets; that is expected.

-- -----------------------------------------------------------------------------
-- 1. Stations (Station_ID, Station_Code, Station_Name, City, State)
-- -----------------------------------------------------------------------------
INSERT INTO station (Station_ID, Station_Code, Station_Name, City, State) VALUES
    (1, 'PUNE', 'Pune Junction',     'Pune',      'Maharashtra'),
    (2, 'CSMT', 'Mumbai CSMT',       'Mumbai',    'Maharashtra'),
    (3, 'KYN',  'Kalyan Junction',   'Kalyan',    'Maharashtra'),
    (4, 'LNL',  'Lonavala',          'Lonavala',  'Maharashtra'),
    (5, 'NK',   'Nashik Road',       'Nashik',    'Maharashtra'),
    (6, 'BSL',  'Bhusawal Junction', 'Bhusawal',  'Maharashtra'),
    (7, 'NGP',  'Nagpur Junction',   'Nagpur',    'Maharashtra'),
    (8, 'SUR',  'Solapur Junction',  'Solapur',   'Maharashtra'),
    (9, 'HYB',  'Hyderabad Deccan',  'Hyderabad', 'Telangana');

-- -----------------------------------------------------------------------------
-- 2. Routes (Route_ID, Route_Name, Source_Station_ID, Dest_Station_ID)
-- -----------------------------------------------------------------------------
INSERT INTO route (Route_ID, Route_Name, Source_Station_ID, Dest_Station_ID) VALUES
    (1, 'Mumbai CSMT - Pune Jn',        2, 1),
    (2, 'Pune Jn - Hyderabad Deccan',   1, 9),
    (3, 'Mumbai CSMT - Nagpur',         2, 7);

-- -----------------------------------------------------------------------------
-- 3. Route stops
--    (Route_Stop_ID, Route_ID, Station_ID, Stop_Seq, Arrival_Time, Departure_Time,
--     Day_Offset, Distance_From_Source_Km)
--    First stop: no arrival time. Last stop: no departure time.
--    Day_Offset = days since the start of the journey (1 = reached after midnight).
-- -----------------------------------------------------------------------------
INSERT INTO route_stop
    (Route_Stop_ID, Route_ID, Station_ID, Stop_Seq, Arrival_Time, Departure_Time, Day_Offset, Distance_From_Source_Km)
VALUES
    -- Route 1: Mumbai CSMT - Pune Jn
    ( 1, 1, 2, 1, NULL,       '06:00:00', 0,   0),   -- CSMT
    ( 2, 1, 3, 2, '06:55:00', '06:57:00', 0,  54),   -- KYN
    ( 3, 1, 4, 3, '08:25:00', '08:27:00', 0, 124),   -- LNL
    ( 4, 1, 1, 4, '10:10:00', NULL,       0, 192),   -- PUNE
    -- Route 2: Pune Jn - Hyderabad Deccan (overnight, arrives next day)
    ( 5, 2, 1, 1, NULL,       '17:30:00', 0,   0),   -- PUNE
    ( 6, 2, 8, 2, '21:45:00', '21:50:00', 0, 249),   -- SUR
    ( 7, 2, 9, 3, '05:30:00', NULL,       1, 559),   -- HYB
    -- Route 3: Mumbai CSMT - Nagpur (overnight, arrives next day)
    ( 8, 3, 2, 1, NULL,       '18:00:00', 0,   0),   -- CSMT
    ( 9, 3, 3, 2, '18:50:00', '18:52:00', 0,  54),   -- KYN
    (10, 3, 5, 3, '21:15:00', '21:20:00', 0, 188),   -- NK
    (11, 3, 6, 4, '00:45:00', '00:55:00', 1, 423),   -- BSL
    (12, 3, 7, 5, '07:30:00', NULL,       1, 837);   -- NGP

-- -----------------------------------------------------------------------------
-- 4. Trains (Train_ID, Train_No, Train_Name, Train_Type, Route_ID, Is_Active)
-- -----------------------------------------------------------------------------
INSERT INTO train (Train_ID, Train_No, Train_Name, Train_Type, Route_ID, Is_Active) VALUES
    (1, '11001', 'Mumbai Pune Express', 'EXPRESS',   1, 1),
    (2, '12002', 'Pune Shatabdi',       'SHATABDI',  1, 1),
    (3, '12301', 'Deccan Odyssey SF',   'SUPERFAST', 2, 1),
    (4, '12401', 'Vidarbha Express',    'EXPRESS',   3, 1);

-- -----------------------------------------------------------------------------
-- 5. Train schedule: all four trains run every day (Day_Of_Week 1=Mon .. 7=Sun)
--    (Schedule_ID, Train_ID, Day_Of_Week)
-- -----------------------------------------------------------------------------
INSERT INTO train_schedule (Schedule_ID, Train_ID, Day_Of_Week) VALUES
    ( 1, 1, 1),
    ( 2, 1, 2),
    ( 3, 1, 3),
    ( 4, 1, 4),
    ( 5, 1, 5),
    ( 6, 1, 6),
    ( 7, 1, 7),
    ( 8, 2, 1),
    ( 9, 2, 2),
    (10, 2, 3),
    (11, 2, 4),
    (12, 2, 5),
    (13, 2, 6),
    (14, 2, 7),
    (15, 3, 1),
    (16, 3, 2),
    (17, 3, 3),
    (18, 3, 4),
    (19, 3, 5),
    (20, 3, 6),
    (21, 3, 7),
    (22, 4, 1),
    (23, 4, 2),
    (24, 4, 3),
    (25, 4, 4),
    (26, 4, 5),
    (27, 4, 6),
    (28, 4, 7);

-- -----------------------------------------------------------------------------
-- 6. Coach types (Coach_Type_ID, Class_Code, Class_Name, Seats_Per_Coach)
-- -----------------------------------------------------------------------------
INSERT INTO coach_type (Coach_Type_ID, Class_Code, Class_Name, Seats_Per_Coach) VALUES
    (1, 'SL', 'Sleeper Class',  72),
    (2, '3A', 'AC 3 Tier',      64),
    (3, '2A', 'AC 2 Tier',      48),
    (4, '1A', 'AC First Class', 24),
    (5, 'CC', 'AC Chair Car',   78);

-- -----------------------------------------------------------------------------
-- 7. Coaches and seats, generated by the procedure
--    CALL sp_add_coaches_generate_seats(train_id, coach_type_id, coach_count)
--    Coach types: 1 = SL, 2 = 3A, 3 = 2A, 4 = 1A, 5 = CC
--    The coaches MUST exist before the runs are generated (step 8), because the
--    trigger that creates seat_inventory counts the coaches of the train.
-- -----------------------------------------------------------------------------
-- Train 1 (11001): SL x2, 3A x1, CC x1
CALL sp_add_coaches_generate_seats(1, 1, 2);
CALL sp_add_coaches_generate_seats(1, 2, 1);
CALL sp_add_coaches_generate_seats(1, 5, 1);

-- Train 2 (12002): CC x2
CALL sp_add_coaches_generate_seats(2, 5, 2);

-- Train 3 (12301): SL x3, 3A x2, 2A x1
CALL sp_add_coaches_generate_seats(3, 1, 3);
CALL sp_add_coaches_generate_seats(3, 2, 2);
CALL sp_add_coaches_generate_seats(3, 3, 1);

-- Train 4 (12401): SL x3, 3A x2, 2A x1, 1A x1
CALL sp_add_coaches_generate_seats(4, 1, 3);
CALL sp_add_coaches_generate_seats(4, 2, 2);
CALL sp_add_coaches_generate_seats(4, 3, 1);
CALL sp_add_coaches_generate_seats(4, 4, 1);

-- -----------------------------------------------------------------------------
-- 8. Runs: today and the next 14 days (15 dates) for every train
--    CALL sp_generate_train_runs(train_id, from_date, to_date)
--    Each new run fires the triggers that create its seat_inventory rows (G3)
--    and its train_run_status row (G5).
-- -----------------------------------------------------------------------------
CALL sp_generate_train_runs(1, CURDATE(), DATE_ADD(CURDATE(), INTERVAL 14 DAY));
CALL sp_generate_train_runs(2, CURDATE(), DATE_ADD(CURDATE(), INTERVAL 14 DAY));
CALL sp_generate_train_runs(3, CURDATE(), DATE_ADD(CURDATE(), INTERVAL 14 DAY));
CALL sp_generate_train_runs(4, CURDATE(), DATE_ADD(CURDATE(), INTERVAL 14 DAY));

-- -----------------------------------------------------------------------------
-- 9. Quick check of the seeded G1 data (expected: 9 / 3 / 12 / 4 / 28 / 5 / 19 / 1250 / 60)
-- -----------------------------------------------------------------------------
SELECT
    (SELECT COUNT(*) FROM station)        AS Stations,
    (SELECT COUNT(*) FROM route)          AS Routes,
    (SELECT COUNT(*) FROM route_stop)     AS Route_Stops,
    (SELECT COUNT(*) FROM train)          AS Trains,
    (SELECT COUNT(*) FROM train_schedule) AS Schedule_Rows,
    (SELECT COUNT(*) FROM coach_type)     AS Coach_Types,
    (SELECT COUNT(*) FROM train_coach)    AS Coaches,
    (SELECT COUNT(*) FROM seat)           AS Seats,
    (SELECT COUNT(*) FROM train_run)      AS Runs;
