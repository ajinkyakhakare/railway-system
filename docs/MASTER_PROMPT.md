MASTER PROMPT (part 1 of 2: rules)

You are a senior software engineer on a college DBMS project: "National Railway Reservation &
Management System" (PICT, E&TCE). The project is built by MANY SEPARATE AI CHATS. Each chat
produces different files. A human collects every file into ONE Git repository and runs it on a
laptop. Your files must fit together with files you cannot see. The CONTRACT (Part 2) is law.

The system has 5 modules (groups):
  G1 Train, Station & Route    G2 Passenger & User     G3 Reservation & Seat
  G4 Payment, Cancellation & Refund                    G5 Railway Operations & Analytics
Faculty requirements you must honour: MySQL + MongoDB; Spring Boot; React; JWT/RBAC + 2FA for
payments and account security; REST APIs; payment gateway (Razorpay, test mode); row-level
locking and strict ACID for PNR transactions; stored procedures (booking with auto-PNR,
cancellation with auto RAC->Confirmed promotion); triggers (block booking when waitlist full,
fare-change audit log, auto-decrement seat inventory); UDFs (net fare with concessions,
refund deduction % by hours before departure); views/queries (station-wise daily revenue,
popular routes with RANK(), train delay metrics, JOIN/GROUP BY/HAVING/subqueries).

HARD RULES
R1  Never rename, add or remove anything the contract defines: tables, columns, types,
    procedures, functions, triggers, views, parameters, result-set columns, endpoints, JSON
    fields, routes, packages, class names, file paths. You MAY add indexes, comments and
    private helpers INSIDE your own files.
R2  Create ONLY the files listed in your task. Never recreate or edit another task's files.
    If you find a contract bug or contradiction, do not work around it silently: finish what
    you can and end your answer with a line "CONTRACT ISSUE: <description>".
R3  OUTPUT FORMAT. For every file write one line "=== FILE: <repo-relative path> ===" and then
    ONE fenced code block holding the COMPLETE file. No placeholders ("...", "rest unchanged",
    "TODO"). If the answer is too long, finish the current file, write
    "CONTINUE-WITH: <next file path>" and stop; I will reply "continue".
R4  After the files print "SELF-CHECK" (max 12 lines): confirm each required item of the task
    is implemented and list any ASSUMPTIONS (should be none). No other prose, no questions.
R5  SQL: MySQL 8.0, InnoDB, utf8mb4, runs through the mysql CLI. Use DELIMITER $$ for routines
    and triggers and end with DELIMITER ; . Files must be re-runnable: DROP ... IF EXISTS before
    CREATE for routines/triggers, CREATE OR REPLACE VIEW; tables use plain CREATE TABLE (the
    database is rebuilt from scratch). First line of every file: a comment with task id, owner
    group and purpose. Do not put USE or CREATE DATABASE in files (the init script does it).
R6  Every function declares DETERMINISTIC, or NOT DETERMINISTIC plus NO SQL / READS SQL DATA as
    stated in the contract (binary logging rejects functions without a declaration).
R7  Procedures own their transactions: DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK;
    RESIGNAL; END; START TRANSACTION ... COMMIT. EXCEPTION: procedures marked HELPER never
    start or commit a transaction and return NO result set (use OUT parameters).
    Every non-helper procedure returns EXACTLY ONE result set (final SELECT) as the contract says.
R8  Business errors: SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR_CODE: readable text'.
    ERROR_CODE must come from contract section C7. Nothing else in the text before the colon.
R9  seat_inventory counters (Available_CNF, RAC_Count, WL_Count) are changed ONLY by triggers.
    Procedures change booking_passenger.Status and the triggers do the arithmetic.
R10 Lock order everywhere: seat_inventory -> booking -> booking_passenger -> seat_allocation /
    payment. Use SELECT ... FOR UPDATE. This prevents deadlocks.
R11 Backend: Java 17, Spring Boot 3.3.x, Maven, root package com.railway. SQL-first: use the
    shared SqlHelper (JdbcTemplate). NO JPA entities, NO Lombok. Request DTOs are Java records
    with jakarta.validation annotations. Responses are ApiResponse<T> where T is usually
    List<Map<String,Object>> from SqlHelper (keys already camelCase).
R12 A Spring service method that CALLs a non-helper stored procedure must NOT be @Transactional
    (the procedure manages its own transaction).
R13 Controllers live under /api/v1 and use @PreAuthorize for roles as the API table says.
    JSON keys are lowerCamelCase of the column names (Train_ID -> trainId, Available_CNF ->
    availableCnf). Dates yyyy-MM-dd, times HH:mm:ss, datetimes ISO-8601, money as numbers.
R14 Frontend: React 18 + Vite + Tailwind CSS 3 + react-router-dom 6 + axios + recharts, plain
    JavaScript (.jsx), no TypeScript, no other libraries. Use ONLY the shared components, hooks
    and API client from contract C10. Your files go under src/modules/<module>/ and you export
    pages through that module's routes.jsx. Never edit App.jsx, main.jsx or shared folders.
R15 No secrets in code. Configuration only through the application.yml keys in C2.
R16 Code must be readable and commented where non-obvious: students will be questioned on it
    in a viva. Use clear names, small functions, input validation, no clever tricks.
R17 Use only libraries listed in C2. Do not invent new endpoints, tables, props or routes.
R18 Do not ask me questions. If something is underspecified choose the simplest option that
    is consistent with the contract and list it under SELF-CHECK as an ASSUMPTION.

MASTER PROMPT - PART 2 OF 2 (CONTRACT, section A: layout, config, conventions, schema)

C1  REPOSITORY LAYOUT (fixed; repo name railway-system)
  db/00_database.sql                       (F3)  drop/create database railway_db
  db/01_schema_g1.sql .. 05_schema_g5.sql        tables, indexes, constraints (one per group)
  db/10_functions_gN.sql                         UDFs
  db/20_procedures_gN.sql                        stored procedures
  db/30_triggers_gN.sql                          triggers
  db/40_views_gN.sql                             views
  db/50_seed_g1.sql, 51_seed_g2.sql, 52_seed_g4.sql   master seed data (G3, G5 have no seed)
  db/60_demo_data.sql                      (I1)  sample bookings created through procedures
  db/tests/gN_tests.sql                          SQL proof scripts (before / action / after)
  scripts/init-db.ps1, init-db.sh, verify-contract.sql     (F3)
  backend/pom.xml, backend/src/main/resources/application.yml           (F1)
  backend/src/main/java/com/railway/common/...                            (F1)
  backend/src/main/java/com/railway/{train|user|booking|payment|ops}/...  (G1..G5 backend)
  frontend/  (Vite project; foundation F2)  frontend/src/modules/{trains|users|booking|payments|ops}/
  postman/gN.postman_collection.json, postman/environment.json
  docs/gN/er.mmd (Mermaid erDiagram), docs/gN/data_dictionary.md, docs/gN/MODULE_REPORT.md,
  docs/MASTER_PROMPT.md, docs/INTEGRATION_MAPPING.md, docs/ARCHITECTURE.md, docs/PROJECT_REPORT.md,
  docs/VIVA_PREP.md, README.md, .gitignore
Module key: G1=train / trains, G2=user / users, G3=booking / booking, G4=payment / payments,
G5=ops / ops  (backend package / frontend folder).
DB execution order = numeric file order; within a number, g1..g5 order. So: all schemas, then
all functions, all procedures, all triggers, all views, then seeds.

C2  TECH AND CONFIG
Backend: Java 17, Spring Boot 3.3.5, Maven. Dependencies: spring-boot-starter-web, -jdbc,
-security, -validation, -data-mongodb, mysql-connector-j, io.jsonwebtoken:jjwt-api/impl/jackson
0.12.6. Nothing else (no JPA, no Lombok). Frontend: Node 20, Vite 5, React 18, react-router-dom
6, axios, recharts 2, tailwindcss 3.4 (+postcss, autoprefixer). Alias "@" = frontend/src.
application.yml keys (F1 creates; others only READ them with @Value):
  server.port=8080
  spring.datasource.url=jdbc:mysql://localhost:3306/railway_db?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Kolkata
  spring.datasource.username=${DB_USER:root}   spring.datasource.password=${DB_PASSWORD:root}
  spring.data.mongodb.uri=mongodb://localhost:27017/railway_ops?serverSelectionTimeoutMS=2000
  app.jwt.secret=${JWT_SECRET:change-me-change-me-change-me-change-me-1234}  (>=32 chars)
  app.jwt.expiry-minutes=120
  app.auth.dev-mode=true            (responses include devOtp so demos work without email/SMS)
  app.auth.require-login-otp=false  app.auth.require-payment-otp=true
  app.payment.mode=MOCK             (MOCK or RAZORPAY)
  app.payment.razorpay.key-id=${RAZORPAY_KEY_ID:}   app.payment.razorpay.key-secret=${RAZORPAY_KEY_SECRET:}
  app.mongo.enabled=false           (true only after MongoDB is installed)
  app.cors.allowed-origin=http://localhost:5173
Frontend dev server: port 5173, Vite proxy "/api" -> http://localhost:8080. API base "/api/v1".

C3  CONVENTIONS
Database railway_db. Tables snake_case singular. Columns Pascal_Snake (Train_ID, Fare_Amount).
PK = <Entity>_ID INT UNSIGNED AUTO_INCREMENT. FK column has the parent's PK name unless noted.
Java type for INT UNSIGNED ids = Long. DECIMAL = BigDecimal. TINYINT(1) = boolean in JSON.
Status values are UPPER_CASE strings guarded by CHECK (not ENUM). Procedures sp_*, functions fn_*,
triggers trg_*, views v_*, indexes idx_<table>_<cols>. Ownership: each table is written only by
its owner group's procedures/triggers/backend, except the cross-group writes listed in C11.
Abbreviations below: PK = INT UNSIGNED AUTO_INCREMENT PRIMARY KEY; FK->t = INT UNSIGNED NOT
NULL foreign key to t's PK (nullable if marked null); NN = NOT NULL; UQ = UNIQUE; DEF = DEFAULT;
CHK = CHECK; IDX = index. ISO weekday: 1=Mon..7=Sun = WEEKDAY(date)+1.

C4  SCHEMA (32 tables). Create exactly these. Table-level notes after each table.
--- G1 (file 01_schema_g1.sql) ---
station: Station_ID PK; Station_Code VARCHAR(5) NN UQ; Station_Name VARCHAR(80) NN;
  City VARCHAR(60) NN; State VARCHAR(60) NN
route: Route_ID PK; Route_Name VARCHAR(100) NN UQ; Source_Station_ID FK->station;
  Dest_Station_ID FK->station; CHK(Source_Station_ID <> Dest_Station_ID)
route_stop: Route_Stop_ID PK; Route_ID FK->route; Station_ID FK->station;
  Stop_Seq SMALLINT NN CHK(>=1); Arrival_Time TIME null; Departure_Time TIME null;
  Day_Offset TINYINT NN DEF 0 CHK(0..3); Distance_From_Source_Km SMALLINT NN DEF 0 CHK(>=0);
  UQ(Route_ID,Stop_Seq); UQ(Route_ID,Station_ID); IDX(Station_ID,Route_ID)
  (first stop: Arrival_Time NULL; last stop: Departure_Time NULL; Day_Offset = days since start)
train: Train_ID PK; Train_No CHAR(5) NN UQ CHK(REGEXP '^[0-9]{5}$'); Train_Name VARCHAR(80) NN;
  Train_Type VARCHAR(10) NN CHK IN ('EXPRESS','SUPERFAST','RAJDHANI','SHATABDI','LOCAL');
  Route_ID FK->route; Is_Active TINYINT(1) NN DEF 1
train_schedule: Schedule_ID PK; Train_ID FK->train; Day_Of_Week TINYINT NN CHK(1..7);
  UQ(Train_ID,Day_Of_Week)
coach_type: Coach_Type_ID PK; Class_Code VARCHAR(3) NN UQ CHK IN ('SL','3A','2A','1A','CC');
  Class_Name VARCHAR(40) NN; Seats_Per_Coach SMALLINT NN CHK(>0)
train_coach: Coach_ID PK; Train_ID FK->train; Coach_Type_ID FK->coach_type;
  Coach_Number VARCHAR(4) NN; UQ(Train_ID,Coach_Number)
seat: Seat_ID PK; Coach_ID FK->train_coach; Seat_No SMALLINT NN CHK(>0);
  Berth_Type VARCHAR(2) NN CHK IN ('LB','MB','UB','SL','SU','W','M','A'); UQ(Coach_ID,Seat_No)
train_run: Run_ID PK; Train_ID FK->train; Journey_Date DATE NN;
  Created_At DATETIME NN DEF CURRENT_TIMESTAMP; UQ(Train_ID,Journey_Date); IDX(Journey_Date)
route_stop_audit: Audit_ID PK; Route_Stop_ID INT UNSIGNED NN (no FK); Old_Arrival_Time TIME null;
  New_Arrival_Time TIME null; Old_Departure_Time TIME null; New_Departure_Time TIME null;
  Changed_At DATETIME NN DEF CURRENT_TIMESTAMP
--- G2 (02_schema_g2.sql) ---
role: Role_ID PK; Role_Name VARCHAR(20) NN UQ CHK IN ('PASSENGER','ADMIN','OPERATOR')
app_user: User_ID PK; Email VARCHAR(120) NN UQ; Password_Hash VARCHAR(100) NN;
  Full_Name VARCHAR(80) NN; Phone CHAR(10) NN CHK(REGEXP '^[0-9]{10}$');
  Is_Active TINYINT(1) NN DEF 1; Failed_Login_Count TINYINT NN DEF 0; Locked_Until DATETIME null;
  Created_At DATETIME NN DEF CURRENT_TIMESTAMP
user_role: User_ID FK->app_user; Role_ID FK->role; composite PRIMARY KEY(User_ID,Role_ID)
passenger: Passenger_ID PK; User_ID FK->app_user; Full_Name VARCHAR(80) NN; Date_Of_Birth DATE NN;
  Gender CHAR(1) NN CHK IN ('M','F','O'); Concession_Type VARCHAR(10) NN DEF 'NONE'
  CHK IN ('NONE','GOVT','SOLDIER'); IDX(User_ID)
  (SENIOR and CHILD concessions are derived from Date_Of_Birth by fn_effective_concession)
login_audit: Login_Audit_ID PK; User_ID INT UNSIGNED null (no FK); Email_Attempted VARCHAR(120) NN;
  Success TINYINT(1) NN; IP_Address VARCHAR(45) null; Attempted_At DATETIME NN DEF CURRENT_TIMESTAMP
user_role_audit: Audit_ID PK; User_ID INT UNSIGNED NN; Role_ID INT UNSIGNED NN;
  Action VARCHAR(6) NN CHK IN ('GRANT','REVOKE'); Changed_At DATETIME NN DEF CURRENT_TIMESTAMP
otp_challenge: Otp_ID PK; User_ID FK->app_user; Purpose VARCHAR(10) NN CHK IN ('LOGIN','PAYMENT');
  Otp_Hash VARCHAR(100) NN; Expires_At DATETIME NN; Is_Used TINYINT(1) NN DEF 0;
  Created_At DATETIME NN DEF CURRENT_TIMESTAMP
--- G3 (03_schema_g3.sql) ---
seat_inventory: Inventory_ID PK; Run_ID FK->train_run; Class_Code VARCHAR(3) NN FK->coach_type(Class_Code);
  Total_Seats SMALLINT NN; Available_CNF SMALLINT NN; RAC_Count SMALLINT NN DEF 0;
  WL_Count SMALLINT NN DEF 0; Max_RAC SMALLINT NN; Max_WL SMALLINT NN; UQ(Run_ID,Class_Code);
  CHK(Available_CNF BETWEEN 0 AND Total_Seats AND RAC_Count BETWEEN 0 AND Max_RAC AND
      WL_Count BETWEEN 0 AND Max_WL)
booking: Booking_ID PK; PNR CHAR(10) NN UQ; User_ID FK->app_user; Run_ID FK->train_run;
  Class_Code VARCHAR(3) NN; From_Station_ID FK->station; To_Station_ID FK->station;
  Booking_Status VARCHAR(16) NN DEF 'PENDING_PAYMENT'
  CHK IN ('PENDING_PAYMENT','CONFIRMED','CANCELLED','EXPIRED'); Total_Fare DECIMAL(10,2) NN DEF 0;
  Booked_At DATETIME NN DEF CURRENT_TIMESTAMP; CHK(From_Station_ID <> To_Station_ID);
  IDX(User_ID); IDX(Run_ID)
booking_passenger: Booking_Passenger_ID PK; Booking_ID FK->booking; Passenger_ID FK->passenger;
  Status VARCHAR(10) NN CHK IN ('CNF','RAC','WL','CANCELLED'); Base_Fare DECIMAL(10,2) NN;
  Concession_Type VARCHAR(10) NN; Fare_Amount DECIMAL(10,2) NN; UQ(Booking_ID,Passenger_ID)
seat_allocation: Allocation_ID PK; Run_ID FK->train_run; Seat_ID FK->seat;
  Booking_Passenger_ID FK->booking_passenger UQ; UQ(Run_ID,Seat_ID)
  (the UQ(Run_ID,Seat_ID) is the database-level guard against double booking of a seat)
booking_status_history: History_ID PK; Booking_Passenger_ID INT UNSIGNED NN (no FK);
  Old_Status VARCHAR(10) null; New_Status VARCHAR(10) NN; Changed_At DATETIME NN DEF CURRENT_TIMESTAMP
--- G4 (04_schema_g4.sql) ---
fare_rule: Fare_Rule_ID PK; Class_Code VARCHAR(3) NN UQ FK->coach_type(Class_Code);
  Base_Fare_Per_Km DECIMAL(6,2) NN CHK(>0); Min_Fare DECIMAL(8,2) NN CHK(>=0);
  Updated_At DATETIME NN DEF CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
concession_rule: Concession_Rule_ID PK; Concession_Type VARCHAR(10) NN UQ
  CHK IN ('NONE','SENIOR','GOVT','SOLDIER','CHILD'); Discount_Percent DECIMAL(5,2) NN CHK(0..100);
  Description VARCHAR(100) null
refund_rule: Refund_Rule_ID PK; Min_Hours_Before SMALLINT NN CHK(>=0) UQ;
  Max_Hours_Before SMALLINT null (null = no upper limit); Deduction_Percent DECIMAL(5,2) NN CHK(0..100)
payment: Payment_ID PK; Booking_ID FK->booking; Amount DECIMAL(10,2) NN CHK(>0);
  Payment_Mode VARCHAR(10) NN CHK IN ('RAZORPAY','MOCK'); Gateway_Order_ID VARCHAR(60) null UQ;
  Gateway_Payment_ID VARCHAR(60) null; Payment_Status VARCHAR(10) NN DEF 'CREATED'
  CHK IN ('CREATED','SUCCESS','FAILED'); Created_At DATETIME NN DEF CURRENT_TIMESTAMP;
  Paid_At DATETIME null; IDX(Booking_ID)
cancellation: Cancellation_ID PK; Booking_Passenger_ID FK->booking_passenger UQ;
  Hours_Before_Departure DECIMAL(8,2) NN; Reason VARCHAR(100) null;
  Cancelled_At DATETIME NN DEF CURRENT_TIMESTAMP
refund: Refund_ID PK; Cancellation_ID FK->cancellation UQ; Payment_ID FK->payment;
  Original_Fare DECIMAL(10,2) NN; Deduction_Percent DECIMAL(5,2) NN; Deduction_Amount DECIMAL(10,2) NN;
  Refund_Amount DECIMAL(10,2) NN CHK(>=0); Refund_Status VARCHAR(10) NN DEF 'PROCESSED'
  CHK IN ('PROCESSED','PENDING'); Processed_At DATETIME NN DEF CURRENT_TIMESTAMP
fare_audit_log: Audit_ID PK; Fare_Rule_ID INT UNSIGNED NN (no FK); Old_Base_Fare_Per_Km DECIMAL(6,2) NN;
  New_Base_Fare_Per_Km DECIMAL(6,2) NN; Old_Min_Fare DECIMAL(8,2) NN; New_Min_Fare DECIMAL(8,2) NN;
  Changed_By VARCHAR(100) NN; Changed_At DATETIME NN DEF CURRENT_TIMESTAMP
--- G5 (05_schema_g5.sql) ---
train_run_status: Run_ID INT UNSIGNED PRIMARY KEY + FK->train_run;
  Status VARCHAR(10) NN DEF 'SCHEDULED' CHK IN ('SCHEDULED','ON_TIME','DELAYED','CANCELLED','ARRIVED');
  Current_Station_ID INT UNSIGNED null FK->station; Delay_Minutes INT NN DEF 0 CHK(>=0);
  Last_Reason VARCHAR(100) null; Updated_At DATETIME NN DEF CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
delay_log: Delay_Log_ID PK; Run_ID FK->train_run; Station_ID INT UNSIGNED null FK->station;
  Delay_Minutes INT NN CHK(>=0); Reason VARCHAR(100) null; Logged_At DATETIME NN DEF CURRENT_TIMESTAMP;
  IDX(Run_ID)
station_daily_revenue: Revenue_ID PK; Station_ID FK->station; Revenue_Date DATE NN;
  Total_Revenue DECIMAL(12,2) NN; Ticket_Count INT NN; UQ(Station_ID,Revenue_Date)

MASTER PROMPT - PART 2 OF 2 (CONTRACT, section B: functions, procedures, triggers, views)

C5.1 FUNCTIONS (UDFs). IDs are INT UNSIGNED.
G1 fn_distance_km(p_run_id, p_from_station_id, p_to_station_id) RETURNS INT, READS SQL DATA.
   |Distance_From_Source_Km(to) - Distance_From_Source_Km(from)| on the route of the run's train;
   NULL if a station is not on that route.
G1 fn_departure_datetime(p_run_id, p_station_id) RETURNS DATETIME, READS SQL DATA.
   Journey_Date + Day_Offset days + Departure_Time of that stop (Arrival_Time if Departure_Time
   is NULL). NULL if the station is not on the route.
G1 fn_journey_duration_min(p_run_id, p_from_station_id, p_to_station_id) RETURNS INT, READS SQL DATA.
   Minutes from departure at "from" to arrival at "to" (arrival = Journey_Date + Day_Offset days +
   Arrival_Time). NULL if invalid or Stop_Seq(from) >= Stop_Seq(to).
G2 fn_age_category(p_dob DATE) RETURNS VARCHAR(10), NOT DETERMINISTIC NO SQL.
   age = TIMESTAMPDIFF(YEAR,p_dob,CURDATE()); 'CHILD' if age<12, 'SENIOR' if age>=60, else 'ADULT'.
G2 fn_effective_concession(p_dob DATE, p_declared VARCHAR(10)) RETURNS VARCHAR(10), NOT DETERMINISTIC
   NO SQL. 'SENIOR' if senior, 'CHILD' if child, otherwise p_declared (NONE/GOVT/SOLDIER).
G3 fn_generate_pnr() RETURNS CHAR(10), NOT DETERMINISTIC NO SQL. 10 digits, first digit 1-9:
   CONCAT(FLOOR(1+RAND()*9), LPAD(FLOOR(RAND()*1000000000),9,'0')).
G3 fn_availability_text(p_available_cnf INT, p_rac INT, p_wl INT, p_max_rac INT, p_max_wl INT)
   RETURNS VARCHAR(20), DETERMINISTIC. If p_available_cnf>0 -> 'AVL <n>'; else if p_rac<p_max_rac ->
   'RAC <p_rac+1>'; else if p_wl<p_max_wl -> 'WL <p_wl+1>'; else 'REGRET'.
G4 fn_base_fare(p_class_code VARCHAR(3), p_distance_km INT) RETURNS DECIMAL(10,2), READS SQL DATA.
   GREATEST(ROUND(p_distance_km*Base_Fare_Per_Km,2), Min_Fare) from fare_rule; NULL if no rule.
G4 fn_net_fare(p_base_fare DECIMAL(10,2), p_concession_type VARCHAR(10)) RETURNS DECIMAL(10,2),
   READS SQL DATA. ROUND(p_base_fare*(1-Discount_Percent/100),2) using concession_rule (0% if the
   type is not found).
G4 fn_refund_deduction_pct(p_hours_before DECIMAL(8,2)) RETURNS DECIMAL(5,2), READS SQL DATA.
   Deduction_Percent of the refund_rule row with Min_Hours_Before <= p_hours_before AND
   (Max_Hours_Before IS NULL OR p_hours_before < Max_Hours_Before); 100 if none matches.
G5 fn_delay_minutes(p_scheduled DATETIME, p_actual DATETIME) RETURNS INT, DETERMINISTIC.
   GREATEST(TIMESTAMPDIFF(MINUTE,p_scheduled,p_actual),0).

C5.2 STORED PROCEDURES. Result set = the single final SELECT with exactly these columns.
G1 sp_add_coaches_generate_seats(IN p_train_id, IN p_coach_type_id, IN p_coach_count TINYINT)
   Adds p_coach_count coaches to the train (Coach_Number = class prefix + running number per
   class: S1,S2.. for SL; B1.. for 3A; A1.. for 2A; H1.. for 1A; C1.. for CC) and generates
   Seats_Per_Coach seats per coach, Seat_No 1..n, Berth_Type pattern by class: SL/3A cycle
   LB,MB,UB,LB,MB,UB,SL,SU; 2A cycle LB,UB,LB,UB,SL,SU; 1A cycle LB,UB; CC cycle W,M,A,A,M,W.
   One transaction. Errors: NOT_FOUND. Result: Coaches_Added, Seats_Added.
G1 sp_generate_train_runs(IN p_train_id, IN p_from_date DATE, IN p_to_date DATE)
   For each date in range insert a train_run if the train has a train_schedule row for that ISO
   weekday and no run exists yet (re-runnable). Errors: NOT_FOUND, VALIDATION_ERROR (to<from, or
   range > 60 days). Result: Runs_Created.
G2 sp_register_user(IN p_email VARCHAR(120), IN p_password_hash VARCHAR(100),
   IN p_full_name VARCHAR(80), IN p_phone CHAR(10))
   Inserts app_user and a user_role row with role PASSENGER, one transaction.
   Errors: EMAIL_EXISTS. Result: User_ID.
G2 sp_record_login_attempt(IN p_email VARCHAR(120), IN p_success TINYINT, IN p_ip VARCHAR(45))
   Inserts login_audit. On failure for an existing user: Failed_Login_Count+1 and when it reaches 5
   Locked_Until = NOW()+15 minutes and Failed_Login_Count reset to 0. On success: count=0,
   Locked_Until=NULL. Result: Failed_Login_Count, Locked_Until.
G3 sp_book_ticket(IN p_user_id, IN p_run_id, IN p_class_code VARCHAR(3), IN p_from_station_id,
   IN p_to_station_id, IN p_passenger_ids JSON)         e.g. '[3,4]'
   Steps: (1) validate 1..6 passengers (TOO_MANY_PASSENGERS / VALIDATION_ERROR); run exists
   (RUN_NOT_FOUND); both stations on the train's route and from Stop_Seq < to Stop_Seq
   (INVALID_STATIONS); fn_departure_datetime(run,from) > NOW() (RUN_DEPARTED).
   (2) START TRANSACTION; SELECT the seat_inventory row (run,class) FOR UPDATE (none ->
   SEAT_UNAVAILABLE). (3) PNR: loop fn_generate_pnr() until unused (max 10 tries).
   (4) INSERT booking (status PENDING_PAYMENT, Total_Fare 0). (5) For each passenger id in order
   (cursor over JSON_TABLE ... FOR ORDINALITY): passenger must belong to p_user_id
   (PASSENGER_NOT_OWNED); concession = fn_effective_concession(dob, Concession_Type);
   base = fn_base_fare(class, fn_distance_km(run,from,to)); net = fn_net_fare(base, concession);
   re-read counters: status = 'CNF' if Available_CNF>0, else 'RAC' if RAC_Count<Max_RAC, else 'WL';
   INSERT booking_passenger (triggers update counters; trg_block_if_wl_full may raise
   BOOKING_CLOSED_WL_FULL); if CNF allocate the lowest free Seat_ID of that class on the train
   (not in seat_allocation for the run) and INSERT seat_allocation. (6) UPDATE booking.Total_Fare =
   SUM(Fare_Amount). (7) COMMIT. The procedure NEVER updates seat_inventory directly.
   Result: Booking_ID, PNR, Total_Fare.
G3 sp_promote_rac_wl(IN p_run_id, IN p_class_code VARCHAR(3), OUT p_promoted INT)   *** HELPER ***
   No transaction control, no result set. Locks the inventory row FOR UPDATE, then repeats until
   nothing changes: (a) while Available_CNF>0 and an RAC passenger exists: oldest RAC (lowest
   Booking_Passenger_ID) -> status CNF and allocate the lowest free seat; (b) while RAC_Count<
   Max_RAC and a WL passenger exists: oldest WL -> RAC. Counts promotions in p_promoted. Only
   status UPDATEs and seat_allocation INSERTs; triggers adjust counters. Caller holds the lock.
G3 sp_expire_unpaid_bookings(IN p_minutes INT)
   For each booking with status PENDING_PAYMENT and Booked_At older than p_minutes: in its own
   transaction mark all its non-cancelled passengers CANCELLED, delete their seat_allocation rows,
   CALL sp_promote_rac_wl for the run/class, set booking EXPIRED. Result: Expired_Count.
G4 sp_create_payment(IN p_user_id, IN p_booking_id, IN p_mode VARCHAR(10),
   IN p_gateway_order_id VARCHAR(60))
   Booking must exist (BOOKING_NOT_FOUND), belong to the user (NOT_OWNER) and be PENDING_PAYMENT
   (PAYMENT_NOT_ALLOWED). Inserts payment (Amount = booking.Total_Fare, status CREATED).
   Result: Payment_ID, Amount.
G4 sp_confirm_payment(IN p_payment_id, IN p_gateway_payment_id VARCHAR(60), IN p_success TINYINT)
   Payment must be CREATED (PAYMENT_NOT_ALLOWED). Sets Payment_Status SUCCESS/FAILED, Paid_At,
   Gateway_Payment_ID. trg_payment_confirm then sets booking CONFIRMED on success.
   Result: Payment_Status, Booking_Status.
G4 sp_cancel_ticket(IN p_user_id, IN p_booking_passenger_id)
   (1) booking_passenger exists (BOOKING_NOT_FOUND), booking belongs to p_user_id (NOT_OWNER),
   status not CANCELLED (ALREADY_CANCELLED). hours = TIMESTAMPDIFF(MINUTE,NOW(),
   fn_departure_datetime(run, From_Station_ID))/60; hours<0 -> CANCEL_NOT_ALLOWED.
   (2) START TRANSACTION; lock inventory row (run,class) FOR UPDATE, then booking_passenger row;
   re-check status. (3) pct = fn_refund_deduction_pct(hours); original = Fare_Amount; deduction =
   ROUND(original*pct/100,2); refund = original-deduction; if booking is not CONFIRMED (unpaid)
   refund = 0 and no refund row. (4) INSERT cancellation; UPDATE booking_passenger Status =
   'CANCELLED'; DELETE its seat_allocation; INSERT refund (Payment_ID = latest SUCCESS payment of
   the booking) when paid. (5) CALL sp_promote_rac_wl(run,class,v_promoted). (6) If every passenger
   of the booking is CANCELLED set booking CANCELLED. (7) COMMIT.
   Result: Cancellation_ID, Original_Fare, Deduction_Percent, Refund_Amount, Promoted_Count.
G5 sp_update_train_status(IN p_run_id, IN p_status VARCHAR(10), IN p_delay_minutes INT,
   IN p_current_station_id INT UNSIGNED, IN p_reason VARCHAR(100))
   Updates train_run_status (row exists via trigger). Errors: RUN_NOT_FOUND, INVALID_STATUS.
   p_current_station_id may be NULL. Result: Run_ID, Status, Delay_Minutes, Updated_At.
G5 sp_generate_daily_revenue(IN p_date DATE)
   Upserts station_daily_revenue (INSERT ... ON DUPLICATE KEY UPDATE) per origin station
   (booking.From_Station_ID) from payments with Payment_Status SUCCESS and DATE(Paid_At)=p_date:
   Total_Revenue = SUM(Amount), Ticket_Count = COUNT(DISTINCT Booking_ID). Result: Rows_Affected.

C5.3 TRIGGERS (name | table | timing event | behaviour)
G1 trg_route_stop_audit | route_stop | AFTER UPDATE | if arrival/departure changed insert route_stop_audit.
G1 trg_route_stop_bi | route_stop | BEFORE INSERT | VALIDATION_ERROR if Arrival_Time and Departure_Time
   are both set and Departure_Time < Arrival_Time (a halt never crosses midnight).
G2 trg_user_role_ai | user_role | AFTER INSERT | insert user_role_audit action GRANT.
G2 trg_user_role_ad | user_role | AFTER DELETE | insert user_role_audit action REVOKE.
G2 trg_passenger_bi | passenger | BEFORE INSERT | VALIDATION_ERROR if Date_Of_Birth > CURDATE().
G3 trg_run_init_inventory | train_run | AFTER INSERT | for each distinct class of the train's coaches
   insert seat_inventory: Total_Seats = coaches*Seats_Per_Coach, Available_CNF = Total_Seats,
   Max_RAC = ROUND(Total_Seats*0.10), Max_WL = ROUND(Total_Seats*0.20). (Coaches must exist first.)
G3 trg_block_if_wl_full | booking_passenger | BEFORE INSERT | if NEW.Status='WL' and the inventory row
   (via booking Run_ID/Class_Code) has WL_Count >= Max_WL: SIGNAL BOOKING_CLOSED_WL_FULL.
G3 trg_dec_inventory | booking_passenger | AFTER INSERT | CNF: Available_CNF-1; RAC: RAC_Count+1;
   WL: WL_Count+1 (on the inventory row of the booking's run and class).
G3 trg_adjust_inventory_on_status | booking_passenger | AFTER UPDATE | when Status changed: CNF->CANCELLED
   Available_CNF+1; RAC->CANCELLED RAC_Count-1; WL->CANCELLED WL_Count-1; RAC->CNF RAC_Count-1 and
   Available_CNF-1; WL->RAC WL_Count-1 and RAC_Count+1. Also insert booking_status_history.
G4 trg_fare_audit | fare_rule | AFTER UPDATE | if rate or minimum changed insert fare_audit_log with
   Changed_By = USER().
G4 trg_payment_confirm | payment | AFTER UPDATE | when Payment_Status becomes SUCCESS set the booking
   Booking_Status = 'CONFIRMED'.
G4 trg_refund_check | refund | BEFORE INSERT | REFUND_EXCEEDS_FARE if Refund_Amount > Original_Fare.
G5 trg_run_init_status | train_run | AFTER INSERT | insert train_run_status (Run_ID,'SCHEDULED',0).
G5 trg_status_flag | train_run_status | BEFORE UPDATE | if NEW.Delay_Minutes>=15 and NEW.Status in
   ('SCHEDULED','ON_TIME') set 'DELAYED'; if NEW.Delay_Minutes=0 and NEW.Status='DELAYED' set 'ON_TIME'.
G5 trg_delay_log | train_run_status | AFTER UPDATE | when Delay_Minutes changed insert delay_log
   (Run_ID, Current_Station_ID, new Delay_Minutes, Last_Reason).

C5.4 VIEWS (exact column names, in this order)
G1 v_train_timetable: Train_ID, Train_No, Train_Name, Route_ID, Stop_Seq, Station_ID, Station_Code,
   Station_Name, Arrival_Time, Departure_Time, Day_Offset, Distance_From_Source_Km
G1 v_train_stop_pairs (self-join of route_stop on same route with from.Stop_Seq < to.Stop_Seq, joined
   to active trains): Train_ID, Train_No, Train_Name, Train_Type, Route_ID, From_Station_ID,
   To_Station_ID, From_Stop_Seq, To_Stop_Seq, Departure_Time, Arrival_Time, Day_Offset_From,
   Day_Offset_To, Distance_Km
G2 v_user_account: User_ID, Email, Full_Name, Phone, Is_Active, Roles (GROUP_CONCAT of Role_Name,
   comma separated), Created_At
G2 v_passenger_booking_history: User_ID, Passenger_ID, Passenger_Name, Booking_ID, Booking_Passenger_ID,
   PNR, Train_No, Train_Name, Journey_Date, From_Station_Code, To_Station_Code, Class_Code, Status,
   Fare_Amount, Booked_At
G3 v_seat_availability: Run_ID, Train_ID, Train_No, Train_Name, Journey_Date, Class_Code, Total_Seats,
   Available_CNF, RAC_Count, WL_Count, Max_RAC, Max_WL, Availability_Text (fn_availability_text)
G3 v_run_occupancy: Run_ID, Train_No, Journey_Date, Class_Code, Total_Seats, Booked_Seats
   (Total_Seats-Available_CNF), Occupancy_Pct (ROUND, 1 decimal), Occupancy_Rank
   (RANK() OVER (PARTITION BY Journey_Date ORDER BY Occupancy_Pct DESC))
G4 v_payment_history: User_ID, Payment_ID, Booking_ID, PNR, Amount, Payment_Mode, Payment_Status,
   Created_At, Paid_At
G4 v_refund_summary: User_ID, Cancellation_ID, PNR, Passenger_Name, Original_Fare, Deduction_Percent,
   Deduction_Amount, Refund_Amount, Refund_Status, Cancelled_At
G5 v_train_live_status: Run_ID, Train_No, Train_Name, Journey_Date, Status, Delay_Minutes,
   Current_Station_ID, Current_Station_Name, Last_Reason, Updated_At
G5 v_station_daily_revenue (live from payments, JOIN + GROUP BY): Station_ID, Station_Code,
   Station_Name, Revenue_Date, Total_Revenue, Ticket_Count
G5 v_popular_routes: Route_ID, Route_Name, Booking_Count, Popularity_Rank (RANK() OVER ORDER BY
   Booking_Count DESC; bookings counted if status is not EXPIRED)
G5 v_delay_metrics: Train_ID, Train_No, Train_Name, Total_Runs, Delayed_Runs, Avg_Delay_Min (ROUND 1),
   Max_Delay_Min

MASTER PROMPT - PART 2 OF 2 (CONTRACT, section C: seed, errors, backend shared, API, frontend, writes)

C6  SEED DATA (fixed ids; all tasks that need sample data use these)
Password of every seeded user = Test@1234 ; bcrypt hash (use verbatim in 51_seed_g2.sql):
  $2a$10$Ggra/EJAY81g3MUp5ZRx8ukeDAXlA/NBVyQUlUz0AXv/3vZ0FQjOq
Stations (id,code,name,city,state): 1 PUNE Pune Junction Pune Maharashtra; 2 CSMT Mumbai CSMT Mumbai
 Maharashtra; 3 KYN Kalyan Junction Kalyan Maharashtra; 4 LNL Lonavala Lonavala Maharashtra;
 5 NK Nashik Road Nashik Maharashtra; 6 BSL Bhusawal Junction Bhusawal Maharashtra; 7 NGP Nagpur
 Junction Nagpur Maharashtra; 8 SUR Solapur Junction Solapur Maharashtra; 9 HYB Hyderabad Deccan
 Hyderabad Telangana.
Routes: 1 "Mumbai CSMT - Pune Jn" (src 2, dest 1); 2 "Pune Jn - Hyderabad Deccan" (src 1, dest 9);
 3 "Mumbai CSMT - Nagpur" (src 2, dest 7).
Route stops (route: station seq arr/dep offset km):
 R1: CSMT 1 -/06:00 0 0 | KYN 2 06:55/06:57 0 54 | LNL 3 08:25/08:27 0 124 | PUNE 4 10:10/- 0 192
 R2: PUNE 1 -/17:30 0 0 | SUR 2 21:45/21:50 0 249 | HYB 3 05:30/- 1 559
 R3: CSMT 1 -/18:00 0 0 | KYN 2 18:50/18:52 0 54 | NK 3 21:15/21:20 0 188 | BSL 4 00:45/00:55 1 423 |
     NGP 5 07:30/- 1 837
Trains (id,no,name,type,route): 1 11001 Mumbai Pune Express EXPRESS 1; 2 12002 Pune Shatabdi
 SHATABDI 1; 3 12301 Deccan Odyssey SF SUPERFAST 2; 4 12401 Vidarbha Express EXPRESS 3.
 All four run every day (train_schedule Day_Of_Week 1..7).
Coach types: 1 SL Sleeper Class 72; 2 3A AC 3 Tier 64; 3 2A AC 2 Tier 48; 4 1A AC First Class 24;
 5 CC AC Chair Car 78.   (id, Class_Code, Class_Name, Seats_Per_Coach)
Coaches (generated by CALL sp_add_coaches_generate_seats(train, coach_type, count)):
 T1: SL x2, 3A x1, CC x1 | T2: CC x2 | T3: SL x3, 3A x2, 2A x1 | T4: SL x3, 3A x2, 2A x1, 1A x1.
Runs: CALL sp_generate_train_runs(t, CURDATE(), DATE_ADD(CURDATE(), INTERVAL 14 DAY)) for t=1..4,
 AFTER coaches exist (so triggers create inventory and status rows).
Roles: 1 PASSENGER, 2 ADMIN, 3 OPERATOR.
Users (id,email,name,phone,role): 1 admin@railway.test System Admin 9000000001 ADMIN;
 2 operator@railway.test Control Room Operator 9000000002 OPERATOR; 3 asha@railway.test Asha Patil
 9000000003 PASSENGER; 4 rohan@railway.test Rohan Deshmukh 9000000004 PASSENGER; 5 meera@railway.test
 Meera Kulkarni 9000000005 PASSENGER.
Passengers (id,user,name,dob,gender,concession): 1 u3 Asha Patil 1990-05-15 F NONE; 2 u3 Suresh Patil
 1955-03-10 M NONE; 3 u3 Aarav Patil 2018-07-01 M NONE; 4 u4 Rohan Deshmukh 1988-01-20 M SOLDIER;
 5 u4 Priya Deshmukh 1992-11-02 F NONE; 6 u5 Meera Kulkarni 1985-09-09 F GOVT; 7 u5 Kabir Kulkarni
 2001-04-18 M NONE; 8 u5 Leela Kulkarni 1962-12-25 F NONE.
fare_rule (id,class,per km,min): 1 SL 0.55 120; 2 3A 1.45 300; 3 2A 2.10 450; 4 1A 3.60 700;
 5 CC 1.60 350.
concession_rule (id,type,%): 1 NONE 0; 2 SENIOR 40; 3 GOVT 25; 4 SOLDIER 50; 5 CHILD 50.
refund_rule (Min_Hours_Before,Max_Hours_Before,%): (48,NULL,10) (12,48,25) (4,12,50) (0,4,100).

C7  ERROR CODES (SQL message prefix = code; HTTP status in brackets)
VALIDATION_ERROR[400] INVALID_STATIONS[400] TOO_MANY_PASSENGERS[400] INVALID_STATUS[400]
INVALID_CREDENTIALS[401] UNAUTHORIZED[401] OTP_INVALID[401]
FORBIDDEN[403] NOT_OWNER[403] PASSENGER_NOT_OWNED[403]
NOT_FOUND[404] RUN_NOT_FOUND[404] BOOKING_NOT_FOUND[404]
EMAIL_EXISTS[409] DUPLICATE[409] CONSTRAINT_VIOLATION[409] PASSENGER_IN_USE[409]
SEAT_UNAVAILABLE[409] BOOKING_CLOSED_WL_FULL[409] RUN_DEPARTED[409] ALREADY_CANCELLED[409]
CANCEL_NOT_ALLOWED[409] PAYMENT_NOT_ALLOWED[409] REFUND_EXCEEDS_FARE[409]
ACCOUNT_LOCKED[423]   INTERNAL_ERROR[500]
JSON envelope: success -> {"success":true,"data":<payload>}; failure ->
{"success":false,"error":{"code":"SEAT_UNAVAILABLE","message":"readable text"}}.

C8  BACKEND SHARED CODE (created by task F1 in com.railway.common; every other task only USES it)
common.api.ApiResponse<T> record(boolean success, T data, ApiError error): static ok(T), static fail(code,msg)
common.api.ApiError record(String code, String message)
common.exception.ApiException(String code, String message, HttpStatus status); factories:
  notFound(String msg), badRequest(String code,String msg), forbidden(String msg), conflict(String code,String msg)
common.exception.GlobalExceptionHandler (@RestControllerAdvice): ApiException; bean validation ->
  VALIDATION_ERROR (field messages joined); AccessDenied -> FORBIDDEN; walks the cause chain for a
  java.sql.SQLException with SQLState "45000" and parses its message "CODE: text" using the C7 table;
  DuplicateKeyException -> DUPLICATE; DataIntegrityViolationException -> CONSTRAINT_VIOLATION; else
  INTERNAL_ERROR (log it, generic message).
common.db.SqlHelper (@Component, wraps JdbcTemplate). Result maps use lowerCamelCase keys
  (Train_ID -> trainId, Available_CNF -> availableCnf) and java.time values (java.sql.Date -> LocalDate,
  Time -> LocalTime, Timestamp -> LocalDateTime):
    List<Map<String,Object>> query(String sql, Object... args)
    Map<String,Object> queryOne(String sql, Object... args)      // null when no row
    Map<String,Object> call(String sql, Object... args)          // first row of a procedure result set
    int update(String sql, Object... args)
    long insert(String sql, Object... args)                      // returns generated key
    <T> T scalar(String sql, Class<T> type, Object... args)      // null when no row
  Procedure call example:  sql.call("CALL sp_book_ticket(?,?,?,?,?,?)", uid, runId, cls, from, to, jsonIds)
  where jsonIds = "[3,4]" (build it from the list of ids).
common.security.JwtService: String generateToken(Long userId, String email, List<String> roles);
  AuthUser parse(String token); record AuthUser(Long userId, String email, List<String> roles).
  JWT HS256, claims: sub=userId, email, roles (names WITHOUT the ROLE_ prefix), expiry app.jwt.expiry-minutes.
common.security.SecurityUtil: static Long currentUserId(); static AuthUser currentUser();
  static boolean hasRole(String role).
common.security.SecurityConfig (also exposes @Bean PasswordEncoder = BCryptPasswordEncoder): stateless; @EnableMethodSecurity; CORS for app.cors.allowed-origin; 401/403
  answered as JSON envelope. Rules: permitAll for POST /api/v1/auth/register|login|verify-otp, GET /api/v1/health,
  GET /api/v1/{stations,routes,coach-types,trains,runs,availability,tickets,ops}/** ; /api/v1/admin/** needs
  role ADMIN; everything else authenticated. Authorities are ROLE_<name>. Use @PreAuthorize in controllers for
  OPERATOR endpoints: hasAnyRole('OPERATOR','ADMIN').
common.otp.OtpVerifier (interface, implemented by G2 as com.railway.user.service.OtpVerifierImpl @Service):
  boolean verify(Long userId, String purpose, Long challengeId, String otp)   // purpose LOGIN or PAYMENT
common.web.HealthController: GET /api/v1/health -> {"status":"UP","db":"UP"|"DOWN"}
Class name prefixes (avoid bean clashes): G1 Train*/Station*/Route*/Coach*, G2 Auth*/User*/Passenger*/Otp*,
G3 Booking*/Availability*/Ticket*/Seat*, G4 Payment*/Fare*/Cancellation*/Refund*, G5 Ops*/Report*/Dashboard*.
Sub-packages per module: controller, service, dto.

C9  REST API (base /api/v1). Auth legend: PUBLIC, AUTH (any logged-in user), ADMIN, OPERATOR (OPERATOR or
ADMIN). Rows "= view V" mean: return the rows of view V as List<Map> (camelCase keys of its columns).
--- G2 ---
POST /auth/register PUBLIC {email,password(min 8),fullName,phone} -> {userId}
POST /auth/login PUBLIC {email,password} -> {token|null,otpRequired,challengeId|null,devOtp|null,
  user|null}; user={userId,email,fullName,roles[]}. Flow: load user; locked -> ACCOUNT_LOCKED; BCrypt check;
  call sp_record_login_attempt; wrong -> INVALID_CREDENTIALS. If app.auth.require-login-otp=true return
  otpRequired=true, challengeId (+devOtp when dev-mode) and token=null, else issue token.
POST /auth/verify-otp PUBLIC {challengeId,otp} -> {token,user}   (LOGIN OTP, 5 min, single use)
POST /auth/payment-otp AUTH {} -> {challengeId,expiresAt,devOtp|null}   (PAYMENT OTP, 5 min)
GET /users/me AUTH -> {userId,email,fullName,phone,roles[]};  PUT /users/me AUTH {fullName,phone} -> same
GET /passengers AUTH -> [{passengerId,fullName,dateOfBirth,gender,concessionType,ageCategory}] (own only;
  ageCategory = fn_age_category)
POST /passengers AUTH {fullName,dateOfBirth,gender,concessionType} -> passenger object
PUT /passengers/{id} AUTH same body -> passenger object;  DELETE /passengers/{id} AUTH -> {deleted:true}
  (PASSENGER_IN_USE when referenced by bookings; own passengers only, else NOT_OWNER)
GET /admin/users ADMIN = view v_user_account
PUT /admin/users/{id}/roles ADMIN {roles:["ADMIN"]} -> {userId,roles[]} (replaces roles, at least one)
PUT /admin/users/{id}/active ADMIN {active:boolean} -> {userId,active}
--- G1 ---
GET /stations PUBLIC -> [{stationId,stationCode,stationName,city,state}]
POST /admin/stations ADMIN {stationCode,stationName,city,state} -> station;  PUT /admin/stations/{id} ADMIN
  same body -> station;  DELETE /admin/stations/{id} ADMIN -> {deleted:true}
GET /routes PUBLIC -> [{routeId,routeName,sourceStationId,destStationId}]
GET /routes/{id}/stops PUBLIC -> [{routeStopId,stopSeq,stationId,stationCode,stationName,arrivalTime,
  departureTime,dayOffset,distanceFromSourceKm}] ordered by stopSeq
POST /admin/routes ADMIN {routeName,sourceStationId,destStationId,stops:[{stationId,stopSeq,arrivalTime,
  departureTime,dayOffset,distanceFromSourceKm}]} -> {routeId}
PUT /admin/route-stops/{id} ADMIN {arrivalTime,departureTime} -> stop row (fires trg_route_stop_audit)
GET /coach-types PUBLIC -> [{coachTypeId,classCode,className,seatsPerCoach}]
GET /trains PUBLIC (optional ?q= matches name or number) -> [{trainId,trainNo,trainName,trainType,routeId,
  routeName,isActive}]
GET /trains/{id} PUBLIC -> one train row;  GET /trains/{id}/timetable PUBLIC = view v_train_timetable
GET /trains/{id}/coaches PUBLIC -> [{coachId,coachNumber,classCode,className,seatCount}]
GET /trains/{id}/runs PUBLIC (?from,to dates) -> [{runId,journeyDate}]
GET /runs/{runId} PUBLIC -> {runId,trainId,trainNo,trainName,journeyDate,routeId}
GET /trains/search PUBLIC ?fromStationId&toStationId&date -> [{runId,trainId,trainNo,trainName,trainType,
  fromStationId,toStationId,journeyDate,departureTime,arrivalTime,durationMin,distanceKm}] (v_train_stop_pairs
  joined to train_run on the date; durationMin = fn_journey_duration_min)
POST /admin/trains ADMIN {trainNo,trainName,trainType,routeId,runDays:[1..7]} -> {trainId}
PUT /admin/trains/{id} ADMIN {trainName,trainType,routeId,isActive,runDays} -> train row
POST /admin/trains/{id}/coaches ADMIN {coachTypeId,coachCount} -> {coachesAdded,seatsAdded}
POST /admin/trains/{id}/runs/generate ADMIN {fromDate,toDate} -> {runsCreated}
--- G3 ---
GET /availability PUBLIC ?runId -> rows of v_seat_availability for that run (all classes)
POST /bookings AUTH {runId,classCode,fromStationId,toStationId,passengerIds:[..]} ->
  {bookingId,pnr,totalFare,passengers:[{bookingPassengerId,passengerId,passengerName,status,baseFare,
  concessionType,fareAmount}]}
GET /bookings/my AUTH -> [{bookingId,pnr,trainNo,trainName,journeyDate,fromStationCode,toStationCode,
  classCode,bookingStatus,totalFare,bookedAt}] newest first
GET /bookings/{bookingId} AUTH (owner or ADMIN) -> the fields above plus runId,fromStationId,toStationId and
  passengers:[{bookingPassengerId,passengerId,passengerName,status,coachNumber,seatNo,berthType,baseFare,
  concessionType,fareAmount}]
GET /tickets/{pnr} PUBLIC -> {pnr,trainNo,trainName,journeyDate,fromStationCode,toStationCode,classCode,
  bookingStatus,passengers:[{index,status,coachNumber,seatNo,berthType}]} (no passenger names)
GET /runs/{runId}/seat-map PUBLIC ?classCode -> [{seatId,coachNumber,seatNo,berthType,occupied}]
GET /admin/occupancy ADMIN ?date -> rows of v_run_occupancy for that Journey_Date
POST /admin/bookings/expire-unpaid ADMIN {minutes} -> {expiredCount}
--- G4 ---
GET /fares/quote AUTH ?runId&classCode&fromStationId&toStationId&passengerIds=1,2 -> {distanceKm,totalFare,
  passengers:[{passengerId,passengerName,concessionType,baseFare,netFare}]} (SQL functions only; passengers
  must belong to the user)
POST /payments/orders AUTH {bookingId,otpChallengeId,otp} (otp fields required only when
  app.auth.require-payment-otp=true; verify through OtpVerifier purpose PAYMENT) ->
  {paymentId,mode,amount,gatewayOrderId,razorpayKeyId}  (MOCK: gatewayOrderId "MOCK_"+uuid, razorpayKeyId null)
POST /payments/verify AUTH {paymentId,razorpayPaymentId,razorpaySignature} -> {paymentStatus,bookingStatus}
  (RAZORPAY mode: HMAC-SHA256 of orderId+"|"+paymentId with key-secret must equal the signature)
POST /payments/mock-confirm AUTH {paymentId,success:boolean} -> {paymentStatus,bookingStatus} (MOCK mode only)
GET /payments/my AUTH = view v_payment_history (own);  GET /refunds/my AUTH = view v_refund_summary (own)
GET /cancellations/preview AUTH ?bookingPassengerId -> {bookingPassengerId,fareAmount,hoursBeforeDeparture,
  deductionPercent,estimatedRefund}
POST /cancellations AUTH {bookingPassengerId,reason} -> {cancellationId,originalFare,deductionPercent,
  refundAmount,promotedCount}
GET /admin/fare-rules ADMIN -> [{fareRuleId,classCode,baseFarePerKm,minFare,updatedAt}]
PUT /admin/fare-rules/{id} ADMIN {baseFarePerKm,minFare} -> same row (fires trg_fare_audit)
GET /admin/concession-rules ADMIN -> [{concessionRuleId,concessionType,discountPercent,description}]
PUT /admin/concession-rules/{id} ADMIN {discountPercent} -> same row;  GET /admin/fare-audit ADMIN -> rows of
  fare_audit_log newest first
--- G5 ---
GET /ops/status PUBLIC ?date (default today) = view v_train_live_status for Journey_Date;
GET /ops/status/{runId} PUBLIC -> one row of that view
PUT /ops/status/{runId} OPERATOR {status,delayMinutes,currentStationId,reason} -> {runId,status,delayMinutes,
  updatedAt}; after success write a Mongo event when app.mongo.enabled=true (never fail the request on Mongo errors)
GET /admin/reports/revenue ADMIN ?from&to = view v_station_daily_revenue filtered by Revenue_Date
POST /admin/reports/revenue/generate ADMIN {date} -> {rowsAffected}
GET /admin/reports/popular-routes ADMIN = view v_popular_routes;  GET /admin/reports/delay-metrics ADMIN = view
  v_delay_metrics
GET /admin/reports/delayed-trains ADMIN ?thresholdMinutes=15 -> [{trainId,trainNo,trainName,avgDelayMin,
  delayedRuns}] (GROUP BY train HAVING AVG(Delay_Minutes) > threshold)
GET /admin/reports/top-stations ADMIN -> [{stationId,stationName,totalRevenue}] stations whose total revenue
  is above the average per-station revenue (subquery)
GET /admin/dashboard/summary ADMIN -> {totalBookings,confirmedBookings,totalRevenue,activeTrains,
  delayedRunsToday,cancellationsToday}
GET /admin/ops-events ADMIN ?limit=50 -> [{runId,status,delayMinutes,reason,changedBy,at}] from Mongo
  collection ops_event_log; empty list when app.mongo.enabled=false

C10 FRONTEND SHARED CODE (created by F2; other tasks only USE it; import with the "@" alias)
@/api/client (default export "client"): client.get(url,{params}), client.post(url,body), client.put(url,body),
  client.delete(url) return the UNWRAPPED ApiResponse.data (url relative to /api/v1, e.g. "/trains/search").
  Failures throw ApiError {code,message,status}. Sends Authorization: Bearer <railway_token>. On 401 it clears the
  token and navigates to /login.
@/auth/AuthContext: AuthProvider; useAuth() -> {user,token,isAuthenticated,hasRole(...roles),login(token,user),
  logout()}; user={userId,email,fullName,roles[]}; localStorage keys railway_token and railway_user.
@/hooks/useAsync: named export useAsync(asyncFn, deps=[]) -> {data,loading,error,reload}; runs on mount and when
  deps change; error is an ApiError or null.
@/utils/format: formatMoney(n)->"₹1,234.50"; formatDate("2026-10-27")->"27 Oct 2026"; formatTime("06:00:00")->"06:00";
  formatDateTime(iso); todayISO()->"yyyy-MM-dd".
@/components/ui (named exports; Tailwind styled):
  Button{variant:'primary'|'secondary'|'danger'='primary', loading, disabled, type='button', onClick, className, children}
  Card{title, actions, className, children}
  Input{label, name, type='text', value, onChange(event), error, placeholder, required, ...rest}
  Select{label, name, value, onChange(event), options:[{value,label}], error, placeholder}
  Table{columns:[{key,header,render?(row)}], rows, rowKey (string field or fn), emptyText}
  Badge{tone:'green'|'yellow'|'red'|'blue'|'gray', children}
  StatusBadge{status}  (CNF/CONFIRMED/SUCCESS/ON_TIME green; RAC/PENDING_PAYMENT/SCHEDULED yellow;
     WL/DELAYED/CREATED blue-or-yellow; CANCELLED/FAILED/EXPIRED red; ARRIVED gray)
  Alert{tone:'error'|'success'|'info', children}   Spinner{}   EmptyState{message}
  PageHeader{title, subtitle, actions}   Modal{open, title, onClose, children}
Route registry: every module owns src/modules/<folder>/routes.jsx whose default export is an array of
  { path, element, label?, section?, order?, roles?, public? }. label => shown in nav; roles => login needed
  and user must have one of them; public:true => no login; otherwise any logged-in user. App.jsx loads all of
  them with import.meta.glob('./modules/*/routes.jsx',{eager:true}). Each module also has api.js (functions that
  call client) and pages/*.jsx.
Canonical routes (module folder):
  trains: /trains/search (public,"Search Trains") /trains (public) /trains/:trainId (public timetable)
    /admin/trains /admin/stations /admin/routes (roles ADMIN)
  users: /login /register (public) /profile /passengers (login) /admin/users (ADMIN)
  booking: /availability/:runId (public; query from,to = station ids) /book/:runId/:classCode (login; query from,to)
    /my-bookings (login) /tickets (public PNR lookup) /tickets/:pnr (public) /seat-map/:runId/:classCode (public)
    /admin/occupancy (ADMIN)
  payments: /payment/:bookingId (login) /cancel/:bookingPassengerId (login) /payments/history (login)
    /admin/fares (ADMIN)
  ops: /ops/board (public) /ops/update (OPERATOR,ADMIN) /admin/dashboard /admin/reports/revenue
    /admin/reports/routes /admin/reports/delays (ADMIN)
Navigation flow (links between modules): search result -> /availability/:runId?from=&to= -> /book/:runId/:classCode
  ?from=&to= -> POST booking -> /payment/:bookingId -> success -> /tickets/:pnr ; /my-bookings lists bookings and
  links each passenger row to /cancel/:bookingPassengerId.  "/" is a Home page created by F2.

C11 ALLOWED WRITES INTO ANOTHER GROUP'S TABLES (everything else is forbidden)
 1. G4 trg_payment_confirm updates booking.Booking_Status (G3 table).
 2. G4 sp_cancel_ticket updates booking_passenger.Status and booking.Booking_Status, deletes seat_allocation
    rows (G3 tables) and CALLs G3's sp_promote_rac_wl.
 3. G3 trg_run_init_inventory (on G1 table train_run) and G5 trg_run_init_status (on train_run) insert into
    their OWN tables only.
 4. Backends never write to tables of other groups; they call the owner's procedure or the endpoint.
