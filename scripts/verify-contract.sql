-- F3 | owner group: F3 (database tooling) | purpose: prove that the built railway_db matches contract C4/C5 (tables, columns, functions, procedures, triggers, views)
-- Run with a default database selected, e.g.:  mysql --table --database=railway_db < scripts/verify-contract.sql
-- The script only READS information_schema; it creates and drops its own TEMPORARY tables (invisible to other sessions).
-- Note: MySQL cannot use one temporary table twice in one query, so every query below touches each temp table once.

DROP TEMPORARY TABLE IF EXISTS tmp_exp_object;
DROP TEMPORARY TABLE IF EXISTS tmp_exp_column;
DROP TEMPORARY TABLE IF EXISTS tmp_act_object;
DROP TEMPORARY TABLE IF EXISTS tmp_act_column;
DROP TEMPORARY TABLE IF EXISTS tmp_col_problem;

-- Expected objects. Kind = TABLE / FUNCTION / PROCEDURE / TRIGGER / VIEW. Expected_Cols only for tables.
CREATE TEMPORARY TABLE tmp_exp_object (
  Seq           INT         NOT NULL AUTO_INCREMENT PRIMARY KEY,
  Kind          VARCHAR(10) NOT NULL,
  Name          VARCHAR(64) NOT NULL,
  Grp           CHAR(2)     NOT NULL,
  Expected_Cols INT         NULL
) DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

-- Expected columns of every table.
CREATE TEMPORARY TABLE tmp_exp_column (
  Table_Name  VARCHAR(64) NOT NULL,
  Column_Name VARCHAR(64) NOT NULL,
  PRIMARY KEY (Table_Name, Column_Name)
) DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

-- What actually exists in railway_db (copied from information_schema; this also fixes collation clashes).
CREATE TEMPORARY TABLE tmp_act_object (
  Kind VARCHAR(10) NOT NULL,
  Name VARCHAR(64) NOT NULL,
  INDEX idx_tmp_act_object_kind_name (Kind, Name)
) DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

CREATE TEMPORARY TABLE tmp_act_column (
  Table_Name  VARCHAR(64) NOT NULL,
  Column_Name VARCHAR(64) NOT NULL,
  PRIMARY KEY (Table_Name, Column_Name)
) DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------------
-- Expected tables (contract C4) with expected column counts
-- ---------------------------------------------------------------------------
INSERT INTO tmp_exp_object (Kind, Name, Grp, Expected_Cols) VALUES
  ('TABLE', 'station',                'G1', 5),
  ('TABLE', 'route',                  'G1', 4),
  ('TABLE', 'route_stop',             'G1', 8),
  ('TABLE', 'train',                  'G1', 6),
  ('TABLE', 'train_schedule',         'G1', 3),
  ('TABLE', 'coach_type',             'G1', 4),
  ('TABLE', 'train_coach',            'G1', 4),
  ('TABLE', 'seat',                   'G1', 4),
  ('TABLE', 'train_run',              'G1', 4),
  ('TABLE', 'route_stop_audit',       'G1', 7),
  ('TABLE', 'role',                   'G2', 2),
  ('TABLE', 'app_user',               'G2', 9),
  ('TABLE', 'user_role',              'G2', 2),
  ('TABLE', 'passenger',              'G2', 6),
  ('TABLE', 'login_audit',            'G2', 6),
  ('TABLE', 'user_role_audit',        'G2', 5),
  ('TABLE', 'otp_challenge',          'G2', 7),
  ('TABLE', 'seat_inventory',         'G3', 9),
  ('TABLE', 'booking',                'G3', 10),
  ('TABLE', 'booking_passenger',      'G3', 7),
  ('TABLE', 'seat_allocation',        'G3', 4),
  ('TABLE', 'booking_status_history', 'G3', 5),
  ('TABLE', 'fare_rule',              'G4', 5),
  ('TABLE', 'concession_rule',        'G4', 4),
  ('TABLE', 'refund_rule',            'G4', 4),
  ('TABLE', 'payment',                'G4', 9),
  ('TABLE', 'cancellation',           'G4', 5),
  ('TABLE', 'refund',                 'G4', 9),
  ('TABLE', 'fare_audit_log',         'G4', 8),
  ('TABLE', 'train_run_status',       'G5', 6),
  ('TABLE', 'delay_log',              'G5', 6),
  ('TABLE', 'station_daily_revenue',  'G5', 5);

-- Expected functions (C5.1)
INSERT INTO tmp_exp_object (Kind, Name, Grp, Expected_Cols) VALUES
  ('FUNCTION', 'fn_distance_km',            'G1', NULL),
  ('FUNCTION', 'fn_departure_datetime',     'G1', NULL),
  ('FUNCTION', 'fn_journey_duration_min',   'G1', NULL),
  ('FUNCTION', 'fn_age_category',           'G2', NULL),
  ('FUNCTION', 'fn_effective_concession',   'G2', NULL),
  ('FUNCTION', 'fn_generate_pnr',           'G3', NULL),
  ('FUNCTION', 'fn_availability_text',      'G3', NULL),
  ('FUNCTION', 'fn_base_fare',              'G4', NULL),
  ('FUNCTION', 'fn_net_fare',               'G4', NULL),
  ('FUNCTION', 'fn_refund_deduction_pct',   'G4', NULL),
  ('FUNCTION', 'fn_delay_minutes',          'G5', NULL);

-- Expected procedures (C5.2)
INSERT INTO tmp_exp_object (Kind, Name, Grp, Expected_Cols) VALUES
  ('PROCEDURE', 'sp_add_coaches_generate_seats', 'G1', NULL),
  ('PROCEDURE', 'sp_generate_train_runs',        'G1', NULL),
  ('PROCEDURE', 'sp_register_user',              'G2', NULL),
  ('PROCEDURE', 'sp_record_login_attempt',       'G2', NULL),
  ('PROCEDURE', 'sp_book_ticket',                'G3', NULL),
  ('PROCEDURE', 'sp_promote_rac_wl',             'G3', NULL),
  ('PROCEDURE', 'sp_expire_unpaid_bookings',     'G3', NULL),
  ('PROCEDURE', 'sp_create_payment',             'G4', NULL),
  ('PROCEDURE', 'sp_confirm_payment',            'G4', NULL),
  ('PROCEDURE', 'sp_cancel_ticket',              'G4', NULL),
  ('PROCEDURE', 'sp_update_train_status',        'G5', NULL),
  ('PROCEDURE', 'sp_generate_daily_revenue',     'G5', NULL);

-- Expected triggers (C5.3)
INSERT INTO tmp_exp_object (Kind, Name, Grp, Expected_Cols) VALUES
  ('TRIGGER', 'trg_route_stop_audit',          'G1', NULL),
  ('TRIGGER', 'trg_route_stop_bi',             'G1', NULL),
  ('TRIGGER', 'trg_user_role_ai',              'G2', NULL),
  ('TRIGGER', 'trg_user_role_ad',              'G2', NULL),
  ('TRIGGER', 'trg_passenger_bi',              'G2', NULL),
  ('TRIGGER', 'trg_run_init_inventory',        'G3', NULL),
  ('TRIGGER', 'trg_block_if_wl_full',          'G3', NULL),
  ('TRIGGER', 'trg_dec_inventory',             'G3', NULL),
  ('TRIGGER', 'trg_adjust_inventory_on_status','G3', NULL),
  ('TRIGGER', 'trg_fare_audit',                'G4', NULL),
  ('TRIGGER', 'trg_payment_confirm',           'G4', NULL),
  ('TRIGGER', 'trg_refund_check',              'G4', NULL),
  ('TRIGGER', 'trg_run_init_status',           'G5', NULL),
  ('TRIGGER', 'trg_status_flag',               'G5', NULL),
  ('TRIGGER', 'trg_delay_log',                 'G5', NULL);

-- Expected views (C5.4)
INSERT INTO tmp_exp_object (Kind, Name, Grp, Expected_Cols) VALUES
  ('VIEW', 'v_train_timetable',          'G1', NULL),
  ('VIEW', 'v_train_stop_pairs',         'G1', NULL),
  ('VIEW', 'v_user_account',             'G2', NULL),
  ('VIEW', 'v_passenger_booking_history','G2', NULL),
  ('VIEW', 'v_seat_availability',        'G3', NULL),
  ('VIEW', 'v_run_occupancy',            'G3', NULL),
  ('VIEW', 'v_payment_history',          'G4', NULL),
  ('VIEW', 'v_refund_summary',           'G4', NULL),
  ('VIEW', 'v_train_live_status',        'G5', NULL),
  ('VIEW', 'v_station_daily_revenue',    'G5', NULL),
  ('VIEW', 'v_popular_routes',           'G5', NULL),
  ('VIEW', 'v_delay_metrics',            'G5', NULL);

-- ---------------------------------------------------------------------------
-- Expected columns of every table (contract C4)
-- ---------------------------------------------------------------------------
-- G1
INSERT INTO tmp_exp_column (Table_Name, Column_Name) VALUES
  ('station', 'Station_ID'), ('station', 'Station_Code'), ('station', 'Station_Name'),
  ('station', 'City'), ('station', 'State'),
  ('route', 'Route_ID'), ('route', 'Route_Name'), ('route', 'Source_Station_ID'),
  ('route', 'Dest_Station_ID'),
  ('route_stop', 'Route_Stop_ID'), ('route_stop', 'Route_ID'), ('route_stop', 'Station_ID'),
  ('route_stop', 'Stop_Seq'), ('route_stop', 'Arrival_Time'), ('route_stop', 'Departure_Time'),
  ('route_stop', 'Day_Offset'), ('route_stop', 'Distance_From_Source_Km'),
  ('train', 'Train_ID'), ('train', 'Train_No'), ('train', 'Train_Name'),
  ('train', 'Train_Type'), ('train', 'Route_ID'), ('train', 'Is_Active'),
  ('train_schedule', 'Schedule_ID'), ('train_schedule', 'Train_ID'), ('train_schedule', 'Day_Of_Week'),
  ('coach_type', 'Coach_Type_ID'), ('coach_type', 'Class_Code'), ('coach_type', 'Class_Name'),
  ('coach_type', 'Seats_Per_Coach'),
  ('train_coach', 'Coach_ID'), ('train_coach', 'Train_ID'), ('train_coach', 'Coach_Type_ID'),
  ('train_coach', 'Coach_Number'),
  ('seat', 'Seat_ID'), ('seat', 'Coach_ID'), ('seat', 'Seat_No'), ('seat', 'Berth_Type'),
  ('train_run', 'Run_ID'), ('train_run', 'Train_ID'), ('train_run', 'Journey_Date'),
  ('train_run', 'Created_At'),
  ('route_stop_audit', 'Audit_ID'), ('route_stop_audit', 'Route_Stop_ID'),
  ('route_stop_audit', 'Old_Arrival_Time'), ('route_stop_audit', 'New_Arrival_Time'),
  ('route_stop_audit', 'Old_Departure_Time'), ('route_stop_audit', 'New_Departure_Time'),
  ('route_stop_audit', 'Changed_At');

-- G2
INSERT INTO tmp_exp_column (Table_Name, Column_Name) VALUES
  ('role', 'Role_ID'), ('role', 'Role_Name'),
  ('app_user', 'User_ID'), ('app_user', 'Email'), ('app_user', 'Password_Hash'),
  ('app_user', 'Full_Name'), ('app_user', 'Phone'), ('app_user', 'Is_Active'),
  ('app_user', 'Failed_Login_Count'), ('app_user', 'Locked_Until'), ('app_user', 'Created_At'),
  ('user_role', 'User_ID'), ('user_role', 'Role_ID'),
  ('passenger', 'Passenger_ID'), ('passenger', 'User_ID'), ('passenger', 'Full_Name'),
  ('passenger', 'Date_Of_Birth'), ('passenger', 'Gender'), ('passenger', 'Concession_Type'),
  ('login_audit', 'Login_Audit_ID'), ('login_audit', 'User_ID'), ('login_audit', 'Email_Attempted'),
  ('login_audit', 'Success'), ('login_audit', 'IP_Address'), ('login_audit', 'Attempted_At'),
  ('user_role_audit', 'Audit_ID'), ('user_role_audit', 'User_ID'), ('user_role_audit', 'Role_ID'),
  ('user_role_audit', 'Action'), ('user_role_audit', 'Changed_At'),
  ('otp_challenge', 'Otp_ID'), ('otp_challenge', 'User_ID'), ('otp_challenge', 'Purpose'),
  ('otp_challenge', 'Otp_Hash'), ('otp_challenge', 'Expires_At'), ('otp_challenge', 'Is_Used'),
  ('otp_challenge', 'Created_At');

-- G3
INSERT INTO tmp_exp_column (Table_Name, Column_Name) VALUES
  ('seat_inventory', 'Inventory_ID'), ('seat_inventory', 'Run_ID'), ('seat_inventory', 'Class_Code'),
  ('seat_inventory', 'Total_Seats'), ('seat_inventory', 'Available_CNF'), ('seat_inventory', 'RAC_Count'),
  ('seat_inventory', 'WL_Count'), ('seat_inventory', 'Max_RAC'), ('seat_inventory', 'Max_WL'),
  ('booking', 'Booking_ID'), ('booking', 'PNR'), ('booking', 'User_ID'), ('booking', 'Run_ID'),
  ('booking', 'Class_Code'), ('booking', 'From_Station_ID'), ('booking', 'To_Station_ID'),
  ('booking', 'Booking_Status'), ('booking', 'Total_Fare'), ('booking', 'Booked_At'),
  ('booking_passenger', 'Booking_Passenger_ID'), ('booking_passenger', 'Booking_ID'),
  ('booking_passenger', 'Passenger_ID'), ('booking_passenger', 'Status'),
  ('booking_passenger', 'Base_Fare'), ('booking_passenger', 'Concession_Type'),
  ('booking_passenger', 'Fare_Amount'),
  ('seat_allocation', 'Allocation_ID'), ('seat_allocation', 'Run_ID'), ('seat_allocation', 'Seat_ID'),
  ('seat_allocation', 'Booking_Passenger_ID'),
  ('booking_status_history', 'History_ID'), ('booking_status_history', 'Booking_Passenger_ID'),
  ('booking_status_history', 'Old_Status'), ('booking_status_history', 'New_Status'),
  ('booking_status_history', 'Changed_At');

-- G4
INSERT INTO tmp_exp_column (Table_Name, Column_Name) VALUES
  ('fare_rule', 'Fare_Rule_ID'), ('fare_rule', 'Class_Code'), ('fare_rule', 'Base_Fare_Per_Km'),
  ('fare_rule', 'Min_Fare'), ('fare_rule', 'Updated_At'),
  ('concession_rule', 'Concession_Rule_ID'), ('concession_rule', 'Concession_Type'),
  ('concession_rule', 'Discount_Percent'), ('concession_rule', 'Description'),
  ('refund_rule', 'Refund_Rule_ID'), ('refund_rule', 'Min_Hours_Before'),
  ('refund_rule', 'Max_Hours_Before'), ('refund_rule', 'Deduction_Percent'),
  ('payment', 'Payment_ID'), ('payment', 'Booking_ID'), ('payment', 'Amount'),
  ('payment', 'Payment_Mode'), ('payment', 'Gateway_Order_ID'), ('payment', 'Gateway_Payment_ID'),
  ('payment', 'Payment_Status'), ('payment', 'Created_At'), ('payment', 'Paid_At'),
  ('cancellation', 'Cancellation_ID'), ('cancellation', 'Booking_Passenger_ID'),
  ('cancellation', 'Hours_Before_Departure'), ('cancellation', 'Reason'), ('cancellation', 'Cancelled_At'),
  ('refund', 'Refund_ID'), ('refund', 'Cancellation_ID'), ('refund', 'Payment_ID'),
  ('refund', 'Original_Fare'), ('refund', 'Deduction_Percent'), ('refund', 'Deduction_Amount'),
  ('refund', 'Refund_Amount'), ('refund', 'Refund_Status'), ('refund', 'Processed_At'),
  ('fare_audit_log', 'Audit_ID'), ('fare_audit_log', 'Fare_Rule_ID'),
  ('fare_audit_log', 'Old_Base_Fare_Per_Km'), ('fare_audit_log', 'New_Base_Fare_Per_Km'),
  ('fare_audit_log', 'Old_Min_Fare'), ('fare_audit_log', 'New_Min_Fare'),
  ('fare_audit_log', 'Changed_By'), ('fare_audit_log', 'Changed_At');

-- G5
INSERT INTO tmp_exp_column (Table_Name, Column_Name) VALUES
  ('train_run_status', 'Run_ID'), ('train_run_status', 'Status'),
  ('train_run_status', 'Current_Station_ID'), ('train_run_status', 'Delay_Minutes'),
  ('train_run_status', 'Last_Reason'), ('train_run_status', 'Updated_At'),
  ('delay_log', 'Delay_Log_ID'), ('delay_log', 'Run_ID'), ('delay_log', 'Station_ID'),
  ('delay_log', 'Delay_Minutes'), ('delay_log', 'Reason'), ('delay_log', 'Logged_At'),
  ('station_daily_revenue', 'Revenue_ID'), ('station_daily_revenue', 'Station_ID'),
  ('station_daily_revenue', 'Revenue_Date'), ('station_daily_revenue', 'Total_Revenue'),
  ('station_daily_revenue', 'Ticket_Count');

-- ---------------------------------------------------------------------------
-- Read what actually exists in railway_db (one INSERT per source, no UNION: avoids collation clashes)
-- ---------------------------------------------------------------------------
INSERT INTO tmp_act_object (Kind, Name)
  SELECT 'TABLE', TABLE_NAME FROM information_schema.TABLES
  WHERE TABLE_SCHEMA = 'railway_db' AND TABLE_TYPE = 'BASE TABLE';
INSERT INTO tmp_act_object (Kind, Name)
  SELECT 'VIEW', TABLE_NAME FROM information_schema.VIEWS
  WHERE TABLE_SCHEMA = 'railway_db';
INSERT INTO tmp_act_object (Kind, Name)
  SELECT ROUTINE_TYPE, ROUTINE_NAME FROM information_schema.ROUTINES
  WHERE ROUTINE_SCHEMA = 'railway_db';
INSERT INTO tmp_act_object (Kind, Name)
  SELECT 'TRIGGER', TRIGGER_NAME FROM information_schema.TRIGGERS
  WHERE TRIGGER_SCHEMA = 'railway_db';
INSERT INTO tmp_act_column (Table_Name, Column_Name)
  SELECT TABLE_NAME, COLUMN_NAME FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = 'railway_db';

-- Expected columns that do not exist (reason says whether the whole table is missing or just the column)
CREATE TEMPORARY TABLE tmp_col_problem AS
  SELECT e.Table_Name,
         e.Column_Name,
         IF(o.Name IS NULL, 'TABLE MISSING', 'COLUMN MISSING') AS Reason
  FROM tmp_exp_column e
  LEFT JOIN tmp_act_column a ON a.Table_Name = e.Table_Name AND a.Column_Name = e.Column_Name
  LEFT JOIN tmp_act_object o ON o.Kind = 'TABLE' AND o.Name = e.Table_Name
  WHERE a.Column_Name IS NULL;

SELECT COUNT(*) INTO @missing_cols FROM tmp_col_problem;
SELECT COUNT(*) INTO @cols_missing_existing FROM tmp_col_problem WHERE Reason = 'COLUMN MISSING';

-- ---------------------------------------------------------------------------
-- (a) Tables: OK / MISSING and actual versus expected column count
-- ---------------------------------------------------------------------------
SELECT '=== (a) TABLES (expected 32) ===' AS Section;
SELECT e.Name AS Table_Name,
       e.Grp  AS Owner_Group,
       IF(a.Name IS NULL, 'MISSING', 'OK') AS Table_Status,
       IFNULL(c.Actual_Cols, 0) AS Actual_Columns,
       e.Expected_Cols          AS Expected_Columns,
       CASE WHEN a.Name IS NULL THEN 'n/a'
            WHEN c.Actual_Cols = e.Expected_Cols THEN 'OK'
            ELSE 'DIFF' END AS Column_Count_Check
FROM tmp_exp_object e
LEFT JOIN tmp_act_object a ON a.Kind = e.Kind AND a.Name = e.Name
LEFT JOIN (SELECT Table_Name, COUNT(*) AS Actual_Cols
           FROM tmp_act_column
           GROUP BY Table_Name) c ON c.Table_Name = e.Name
WHERE e.Kind = 'TABLE'
ORDER BY e.Seq;

-- ---------------------------------------------------------------------------
-- (b) Columns: only problems are listed; otherwise one line "ALL COLUMNS OK"
-- ---------------------------------------------------------------------------
SELECT '=== (b) COLUMNS (182 expected) ===' AS Section;
SELECT 'ALL COLUMNS OK' AS Column_Check FROM DUAL WHERE @missing_cols = 0;
SELECT Table_Name, Column_Name, Reason FROM tmp_col_problem ORDER BY Table_Name, Column_Name;

-- ---------------------------------------------------------------------------
-- (c) Functions, procedures, triggers, views: OK / MISSING
-- ---------------------------------------------------------------------------
SELECT '=== (c) FUNCTIONS (11), PROCEDURES (12), TRIGGERS (15), VIEWS (12) ===' AS Section;
SELECT e.Kind AS Object_Type,
       e.Name AS Object_Name,
       e.Grp  AS Owner_Group,
       IF(a.Name IS NULL, 'MISSING', 'OK') AS Status
FROM tmp_exp_object e
LEFT JOIN tmp_act_object a ON a.Kind = e.Kind AND a.Name = e.Name
WHERE e.Kind <> 'TABLE'
ORDER BY e.Seq;

-- ---------------------------------------------------------------------------
-- Totals per object type (Expected_Total is the number fixed by the contract;
-- Listed is how many this verifier checks; they must be equal)
-- ---------------------------------------------------------------------------
SELECT '=== TOTALS PER TYPE ===' AS Section;
SELECT e.Kind AS Object_Type,
       CASE e.Kind WHEN 'TABLE' THEN 32
                   WHEN 'FUNCTION' THEN 11
                   WHEN 'PROCEDURE' THEN 12
                   WHEN 'TRIGGER' THEN 15
                   ELSE 12 END AS Expected_Total,
       COUNT(*) AS Listed_In_Verifier,
       SUM(a.Name IS NOT NULL) AS Found,
       SUM(a.Name IS NULL)     AS Missing
FROM tmp_exp_object e
LEFT JOIN tmp_act_object a ON a.Kind = e.Kind AND a.Name = e.Name
GROUP BY e.Kind
ORDER BY MIN(e.Seq);

-- ---------------------------------------------------------------------------
-- (d) Summary row: number of missing items
-- Columns_Missing counts only columns missing from tables that exist
-- (columns of missing tables are already covered by Tables_Missing).
-- ---------------------------------------------------------------------------
SELECT '=== (d) SUMMARY ===' AS Section;
SELECT SUM(e.Kind = 'TABLE'     AND a.Name IS NULL) AS Tables_Missing,
       @cols_missing_existing                       AS Columns_Missing,
       SUM(e.Kind = 'FUNCTION'  AND a.Name IS NULL) AS Functions_Missing,
       SUM(e.Kind = 'PROCEDURE' AND a.Name IS NULL) AS Procedures_Missing,
       SUM(e.Kind = 'TRIGGER'   AND a.Name IS NULL) AS Triggers_Missing,
       SUM(e.Kind = 'VIEW'      AND a.Name IS NULL) AS Views_Missing,
       SUM(a.Name IS NULL) + @cols_missing_existing AS Total_Missing,
       IF(SUM(a.Name IS NULL) + @cols_missing_existing = 0,
          'CONTRACT OK', 'CONTRACT INCOMPLETE')     AS Verdict
FROM tmp_exp_object e
LEFT JOIN tmp_act_object a ON a.Kind = e.Kind AND a.Name = e.Name;

DROP TEMPORARY TABLE IF EXISTS tmp_col_problem;
DROP TEMPORARY TABLE IF EXISTS tmp_act_column;
DROP TEMPORARY TABLE IF EXISTS tmp_act_object;
DROP TEMPORARY TABLE IF EXISTS tmp_exp_column;
DROP TEMPORARY TABLE IF EXISTS tmp_exp_object;
