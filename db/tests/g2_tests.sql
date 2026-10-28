-- Task G2.3 | Owner: G2 (Passenger & User) | Purpose: SQL proof script (BEFORE / ACTION / AFTER) for all G2 functions, procedures, triggers and views
--
-- HOW TO RUN (MySQL Workbench):
--   1. Build the database first: db/00 .. db/51 (init script). Do NOT run 60_demo_data.sql before TEST 1.
--   2. Double-click railway_db in the SCHEMAS panel so it is the default schema (this file has no USE).
--   3. Run ONE STATEMENT AT A TIME (Ctrl+Enter) and take a screenshot of each result grid.
--   4. Statements below "-- EXPECT ERROR <CODE>" are SUPPOSED to fail. A raw MySQL error such as 1062 or 3819
--      is shown by Workbench; the Spring backend maps it to the code written in the marker (see contract C7).
--   5. Every block ends with a CLEANUP so the data is left exactly as found.
--
-- Test users: the seeded users 3 and 5 are used only temporarily. Login tests use the marker IP 203.0.113.7
-- so their login_audit rows can be removed precisely.

SET SQL_SAFE_UPDATES = 0;   -- allow the cleanup DELETE/UPDATE statements in Workbench safe-update mode


-- ============================================================================
-- TEST 1: the seed (51_seed_g2.sql) produced 3 roles, 5 users, 5 role links, 8 passengers and 5 GRANT audit rows
-- ============================================================================
-- BEFORE
SELECT 'Run on a freshly seeded database (before demo data and before other tests change anything).' AS Note;
-- ACTION
SELECT (SELECT COUNT(*) FROM role)                                      AS Roles,          -- expect 3
       (SELECT COUNT(*) FROM app_user)                                  AS Users,          -- expect 5
       (SELECT COUNT(*) FROM user_role)                                 AS Role_Links,     -- expect 5
       (SELECT COUNT(*) FROM passenger)                                 AS Passengers,     -- expect 8
       (SELECT COUNT(*) FROM user_role_audit WHERE Action = 'GRANT')    AS Grant_Audit_Rows; -- expect 5
-- AFTER  (each user with its role, and a check that the stored password hash is a 60-character bcrypt hash)
SELECT u.User_ID, u.Email, r.Role_Name,
       CHAR_LENGTH(u.Password_Hash)              AS Hash_Length,      -- expect 60
       LEFT(u.Password_Hash, 7)                  AS Hash_Prefix       -- expect $2a$10$
FROM app_user u
JOIN user_role ur ON ur.User_ID = u.User_ID
JOIN role r       ON r.Role_ID  = ur.Role_ID
ORDER BY u.User_ID;
-- (no cleanup needed: read-only)


-- ============================================================================
-- TEST 2: fn_age_category - normal cases on the seeded passengers
-- ============================================================================
-- BEFORE
SELECT Passenger_ID, Full_Name, Date_Of_Birth, TIMESTAMPDIFF(YEAR, Date_Of_Birth, CURDATE()) AS Age_Years
FROM passenger ORDER BY Passenger_ID;
-- ACTION
SELECT Passenger_ID, Full_Name, Date_Of_Birth, fn_age_category(Date_Of_Birth) AS Age_Category
FROM passenger ORDER BY Passenger_ID;
-- AFTER  (expected for the seed in 2026: 2 Suresh = SENIOR, 3 Aarav = CHILD, 8 Leela = SENIOR, all others ADULT)
SELECT fn_age_category(Date_Of_Birth) AS Age_Category, COUNT(*) AS Passengers
FROM passenger GROUP BY fn_age_category(Date_Of_Birth) ORDER BY Age_Category;
-- (no cleanup needed: read-only)


-- ============================================================================
-- TEST 3: fn_age_category - boundaries (age 0, 11, 12, 59, 60 and 90)
-- ============================================================================
-- BEFORE  (temporary table holds the inputs and the expected answers; it exists only in this session)
CREATE TEMPORARY TABLE tmp_age_cases (
    Label    VARCHAR(40) NOT NULL,
    Dob      DATE        NOT NULL,
    Expected VARCHAR(10) NOT NULL
);
INSERT INTO tmp_age_cases (Label, Dob, Expected) VALUES
    ('Born today (age 0)',        CURDATE(),                                                          'CHILD'),
    ('Turns 12 tomorrow (age 11)', DATE_ADD(DATE_SUB(CURDATE(), INTERVAL 12 YEAR), INTERVAL 1 DAY),     'CHILD'),
    ('Turned 12 today (age 12)',   DATE_SUB(CURDATE(), INTERVAL 12 YEAR),                              'ADULT'),
    ('Turns 60 tomorrow (age 59)', DATE_ADD(DATE_SUB(CURDATE(), INTERVAL 60 YEAR), INTERVAL 1 DAY),    'ADULT'),
    ('Turned 60 today (age 60)',   DATE_SUB(CURDATE(), INTERVAL 60 YEAR),                              'SENIOR'),
    ('Aged 90',                    DATE_SUB(CURDATE(), INTERVAL 90 YEAR),                              'SENIOR');
SELECT Label, Dob, TIMESTAMPDIFF(YEAR, Dob, CURDATE()) AS Age_Years, Expected FROM tmp_age_cases;
-- ACTION
SELECT Label, Dob, Expected, fn_age_category(Dob) AS Actual,
       IF(fn_age_category(Dob) = Expected, 'PASS', 'FAIL') AS Result
FROM tmp_age_cases;
-- AFTER  (expect Passed = Total = 6)
SELECT SUM(fn_age_category(Dob) = Expected) AS Passed, COUNT(*) AS Total FROM tmp_age_cases;
-- CLEANUP
DROP TEMPORARY TABLE tmp_age_cases;


-- ============================================================================
-- TEST 4: fn_effective_concession - normal: an adult keeps the declared concession (NONE / GOVT / SOLDIER)
-- ============================================================================
-- BEFORE  (declared concession and date of birth of the seeded passengers)
SELECT Passenger_ID, Full_Name, Date_Of_Birth, Concession_Type AS Declared FROM passenger ORDER BY Passenger_ID;
-- ACTION
SELECT Passenger_ID, Full_Name, Concession_Type AS Declared,
       fn_age_category(Date_Of_Birth)                                  AS Age_Category,
       fn_effective_concession(Date_Of_Birth, Concession_Type)         AS Effective
FROM passenger ORDER BY Passenger_ID;
-- AFTER  (expected for the 2026 seed: 1 NONE, 2 SENIOR, 3 CHILD, 4 SOLDIER, 5 NONE, 6 GOVT, 7 NONE, 8 SENIOR)
SELECT Passenger_ID, fn_effective_concession(Date_Of_Birth, Concession_Type) AS Effective,
       IF(fn_age_category(Date_Of_Birth) = 'ADULT',
          IF(fn_effective_concession(Date_Of_Birth, Concession_Type) = Concession_Type, 'PASS', 'FAIL'),
          'n/a (senior or child)') AS Adult_Keeps_Declared
FROM passenger ORDER BY Passenger_ID;
-- (no cleanup needed: read-only)


-- ============================================================================
-- TEST 5: fn_effective_concession - edge: SENIOR and CHILD override the declared type; boundaries 11/12 and 59/60
-- ============================================================================
-- BEFORE
CREATE TEMPORARY TABLE tmp_conc_cases (
    Label    VARCHAR(50) NOT NULL,
    Dob      DATE        NOT NULL,
    Declared VARCHAR(10) NOT NULL,
    Expected VARCHAR(10) NOT NULL
);
INSERT INTO tmp_conc_cases (Label, Dob, Declared, Expected) VALUES
    ('Age 60, declared NONE   -> SENIOR',          DATE_SUB(CURDATE(), INTERVAL 60 YEAR),                                  'NONE',    'SENIOR'),
    ('Age 70, declared SOLDIER -> SENIOR wins',    DATE_SUB(CURDATE(), INTERVAL 70 YEAR),                                  'SOLDIER', 'SENIOR'),
    ('Age 59, declared GOVT   -> GOVT kept',       DATE_ADD(DATE_SUB(CURDATE(), INTERVAL 60 YEAR), INTERVAL 1 DAY),        'GOVT',    'GOVT'),
    ('Age 11, declared GOVT   -> CHILD wins',      DATE_ADD(DATE_SUB(CURDATE(), INTERVAL 12 YEAR), INTERVAL 1 DAY),        'GOVT',    'CHILD'),
    ('Age 12, declared SOLDIER -> SOLDIER kept',   DATE_SUB(CURDATE(), INTERVAL 12 YEAR),                                  'SOLDIER', 'SOLDIER'),
    ('Born today, declared NONE -> CHILD',         CURDATE(),                                                              'NONE',    'CHILD');
SELECT Label, Dob, TIMESTAMPDIFF(YEAR, Dob, CURDATE()) AS Age_Years, Declared, Expected FROM tmp_conc_cases;
-- ACTION
SELECT Label, Declared, Expected, fn_effective_concession(Dob, Declared) AS Actual,
       IF(fn_effective_concession(Dob, Declared) = Expected, 'PASS', 'FAIL') AS Result
FROM tmp_conc_cases;
-- AFTER  (expect Passed = Total = 6)
SELECT SUM(fn_effective_concession(Dob, Declared) = Expected) AS Passed, COUNT(*) AS Total FROM tmp_conc_cases;
-- CLEANUP
DROP TEMPORARY TABLE tmp_conc_cases;


-- ============================================================================
-- TEST 6: sp_register_user - normal: creates the user AND a PASSENGER role link in one transaction
-- ============================================================================
-- BEFORE
SELECT COUNT(*) AS Users_With_This_Email FROM app_user WHERE Email = 'test.register@railway.test';   -- expect 0
SELECT COUNT(*) AS Total_Users FROM app_user;                                                        -- expect 5
-- ACTION  (result set: User_ID of the new user)
CALL sp_register_user('test.register@railway.test',
                      '$2a$10$Ggra/EJAY81g3MUp5ZRx8ukeDAXlA/NBVyQUlUz0AXv/3vZ0FQjOq',
                      'Test Register', '9111111111');
-- AFTER  (expect 1 user, role PASSENGER, one GRANT audit row written by trg_user_role_ai)
SET @new_uid = (SELECT User_ID FROM app_user WHERE Email = 'test.register@railway.test');
SELECT u.User_ID, u.Email, u.Full_Name, u.Phone, u.Is_Active, r.Role_Name
FROM app_user u
JOIN user_role ur ON ur.User_ID = u.User_ID
JOIN role r       ON r.Role_ID  = ur.Role_ID
WHERE u.User_ID = @new_uid;
SELECT * FROM user_role_audit WHERE User_ID = @new_uid;
-- CLEANUP
DELETE FROM user_role       WHERE User_ID = @new_uid;   -- fires trg_user_role_ad (REVOKE row) ...
DELETE FROM user_role_audit WHERE User_ID = @new_uid;   -- ... which is removed again here
DELETE FROM app_user        WHERE User_ID = @new_uid;


-- ============================================================================
-- TEST 7: sp_register_user - a duplicate e-mail is rejected and nothing is written
-- EXPECT ERROR EMAIL_EXISTS
-- ============================================================================
-- BEFORE
SELECT User_ID, Email FROM app_user WHERE Email = 'asha@railway.test';   -- expect 1 row (seeded user 3)
SELECT COUNT(*) AS Total_Users FROM app_user;                            -- expect 5
-- ACTION  (must fail with EMAIL_EXISTS)
CALL sp_register_user('asha@railway.test',
                      '$2a$10$Ggra/EJAY81g3MUp5ZRx8ukeDAXlA/NBVyQUlUz0AXv/3vZ0FQjOq',
                      'Duplicate Asha', '9222222222');
-- AFTER  (expect the same: 1 row for the e-mail, still 5 users, no extra role links)
SELECT COUNT(*) AS Users_With_This_Email FROM app_user WHERE Email = 'asha@railway.test';
SELECT COUNT(*) AS Total_Users FROM app_user;
SELECT COUNT(*) AS Total_Role_Links FROM user_role;                       -- expect 5
-- (no cleanup needed: the procedure rolled back)


-- ============================================================================
-- TEST 8: sp_register_user - a phone number that is not 10 digits is rejected (CHECK constraint) and rolled back
-- EXPECT ERROR CONSTRAINT_VIOLATION   (raw MySQL error 3819: check constraint on Phone is violated)
-- ============================================================================
-- BEFORE
SELECT COUNT(*) AS Users_With_This_Email FROM app_user WHERE Email = 'bad.phone@railway.test';   -- expect 0
-- ACTION  (must fail)
CALL sp_register_user('bad.phone@railway.test',
                      '$2a$10$Ggra/EJAY81g3MUp5ZRx8ukeDAXlA/NBVyQUlUz0AXv/3vZ0FQjOq',
                      'Bad Phone', '98ABC12345');
-- AFTER  (expect 0 users and no role link: the transaction was rolled back, nothing half-written)
SELECT COUNT(*) AS Users_With_This_Email FROM app_user WHERE Email = 'bad.phone@railway.test';
SELECT COUNT(*) AS Total_Role_Links FROM user_role;                       -- expect 5
-- (no cleanup needed)


-- ============================================================================
-- TEST 9: sp_record_login_attempt - one failed login for an existing user adds an audit row and Failed_Login_Count = 1
-- ============================================================================
-- BEFORE
SELECT User_ID, Email, Failed_Login_Count, Locked_Until FROM app_user WHERE User_ID = 5;   -- expect 0, NULL
SELECT COUNT(*) AS Audit_Rows_For_Test_IP FROM login_audit WHERE IP_Address = '203.0.113.7'; -- expect 0
-- ACTION  (result set: Failed_Login_Count, Locked_Until)
CALL sp_record_login_attempt('meera@railway.test', 0, '203.0.113.7');
-- AFTER  (expect Failed_Login_Count = 1, Locked_Until NULL, one audit row with Success = 0 and the user's id)
SELECT User_ID, Email, Failed_Login_Count, Locked_Until FROM app_user WHERE User_ID = 5;
SELECT User_ID, Email_Attempted, Success, IP_Address FROM login_audit WHERE IP_Address = '203.0.113.7';
-- CLEANUP
UPDATE app_user SET Failed_Login_Count = 0, Locked_Until = NULL WHERE User_ID = 5;
DELETE FROM login_audit WHERE IP_Address = '203.0.113.7';


-- ============================================================================
-- TEST 10: sp_record_login_attempt - edge: unknown e-mail is audited (User_ID NULL) and changes no user
-- ============================================================================
-- BEFORE
SELECT SUM(Failed_Login_Count) AS Sum_Of_Failed_Counts FROM app_user;                      -- expect 0
SELECT COUNT(*) AS Audit_Rows_For_Test_IP FROM login_audit WHERE IP_Address = '203.0.113.7'; -- expect 0
-- ACTION
CALL sp_record_login_attempt('nobody@railway.test', 0, '203.0.113.7');
-- AFTER  (expect 1 audit row with User_ID NULL, Success 0; the sum of failed counts is still 0)
SELECT User_ID, Email_Attempted, Success, IP_Address FROM login_audit WHERE IP_Address = '203.0.113.7';
SELECT SUM(Failed_Login_Count) AS Sum_Of_Failed_Counts FROM app_user;
-- CLEANUP
DELETE FROM login_audit WHERE IP_Address = '203.0.113.7';


-- ============================================================================
-- TEST 11: sp_record_login_attempt - a successful login resets the failed counter (3 failures, then success)
-- ============================================================================
-- BEFORE
SELECT User_ID, Email, Failed_Login_Count, Locked_Until FROM app_user WHERE User_ID = 5;   -- expect 0, NULL
-- ACTION  (three failures: counts 1, 2, 3 and no lock yet)
CALL sp_record_login_attempt('meera@railway.test', 0, '203.0.113.7');
CALL sp_record_login_attempt('meera@railway.test', 0, '203.0.113.7');
CALL sp_record_login_attempt('meera@railway.test', 0, '203.0.113.7');
SELECT User_ID, Failed_Login_Count, Locked_Until FROM app_user WHERE User_ID = 5;           -- expect 3, NULL
--         then a success
CALL sp_record_login_attempt('meera@railway.test', 1, '203.0.113.7');
-- AFTER  (expect Failed_Login_Count = 0, Locked_Until NULL; audit shows 3 failures and 1 success)
SELECT User_ID, Email, Failed_Login_Count, Locked_Until FROM app_user WHERE User_ID = 5;
SELECT Success, COUNT(*) AS Attempts FROM login_audit WHERE IP_Address = '203.0.113.7' GROUP BY Success ORDER BY Success;
-- CLEANUP
UPDATE app_user SET Failed_Login_Count = 0, Locked_Until = NULL WHERE User_ID = 5;
DELETE FROM login_audit WHERE IP_Address = '203.0.113.7';


-- ============================================================================
-- TEST 12: sp_record_login_attempt - five failed logins lock the account for 15 minutes and reset the counter to 0
-- ============================================================================
-- BEFORE
SELECT User_ID, Email, Failed_Login_Count, Locked_Until FROM app_user WHERE User_ID = 5;   -- expect 0, NULL
-- ACTION  (attempts 1-4 return counts 1..4 with Locked_Until NULL; attempt 5 returns count 0 and a Locked_Until value)
CALL sp_record_login_attempt('meera@railway.test', 0, '203.0.113.7');
CALL sp_record_login_attempt('meera@railway.test', 0, '203.0.113.7');
CALL sp_record_login_attempt('meera@railway.test', 0, '203.0.113.7');
CALL sp_record_login_attempt('meera@railway.test', 0, '203.0.113.7');
CALL sp_record_login_attempt('meera@railway.test', 0, '203.0.113.7');
-- AFTER  (expect Failed_Login_Count = 0, Locked_Until about 15 minutes ahead, 5 audit rows with Success = 0)
SELECT User_ID, Email, Failed_Login_Count, Locked_Until,
       ROUND(TIMESTAMPDIFF(SECOND, NOW(), Locked_Until) / 60) AS Minutes_Until_Unlock   -- expect 15
FROM app_user WHERE User_ID = 5;
SELECT COUNT(*) AS Failed_Audit_Rows FROM login_audit WHERE IP_Address = '203.0.113.7' AND Success = 0;   -- expect 5
-- CLEANUP
UPDATE app_user SET Failed_Login_Count = 0, Locked_Until = NULL WHERE User_ID = 5;
DELETE FROM login_audit WHERE IP_Address = '203.0.113.7';


-- ============================================================================
-- TEST 13: sp_record_login_attempt - a successful login clears an existing lock
-- ============================================================================
-- BEFORE  (put the user into a locked state first)
UPDATE app_user SET Failed_Login_Count = 0, Locked_Until = DATE_ADD(NOW(), INTERVAL 15 MINUTE) WHERE User_ID = 5;
SELECT User_ID, Email, Failed_Login_Count, Locked_Until FROM app_user WHERE User_ID = 5;   -- expect Locked_Until in the future
-- ACTION
CALL sp_record_login_attempt('meera@railway.test', 1, '203.0.113.7');
-- AFTER  (expect Failed_Login_Count = 0 and Locked_Until NULL; one audit row with Success = 1)
SELECT User_ID, Email, Failed_Login_Count, Locked_Until FROM app_user WHERE User_ID = 5;
SELECT User_ID, Email_Attempted, Success FROM login_audit WHERE IP_Address = '203.0.113.7';
-- CLEANUP
DELETE FROM login_audit WHERE IP_Address = '203.0.113.7';


-- ============================================================================
-- TEST 14: trg_user_role_ai - granting a role writes a GRANT row into user_role_audit
-- ============================================================================
-- BEFORE  (user 5 has only the seeded PASSENGER grant)
SELECT Audit_ID, User_ID, Role_ID, Action FROM user_role_audit WHERE User_ID = 5 ORDER BY Audit_ID;   -- expect 1 row
-- ACTION
INSERT INTO user_role (User_ID, Role_ID) VALUES (5, 3);   -- grant OPERATOR to Meera
-- AFTER  (expect a second row: Role_ID 3, Action GRANT)
SELECT Audit_ID, User_ID, Role_ID, Action FROM user_role_audit WHERE User_ID = 5 ORDER BY Audit_ID;
-- CLEANUP
DELETE FROM user_role       WHERE User_ID = 5 AND Role_ID = 3;   -- fires trg_user_role_ad ...
DELETE FROM user_role_audit WHERE User_ID = 5 AND Role_ID = 3;   -- ... so remove both audit rows of this test


-- ============================================================================
-- TEST 15: trg_user_role_ai - edge: granting a role the user already has fails and writes NO audit row
-- EXPECT ERROR DUPLICATE   (raw MySQL error 1062: duplicate entry for the composite primary key)
-- ============================================================================
-- BEFORE
SELECT COUNT(*) AS Audit_Rows_User5_Role1 FROM user_role_audit WHERE User_ID = 5 AND Role_ID = 1;   -- expect 1
-- ACTION  (must fail)
INSERT INTO user_role (User_ID, Role_ID) VALUES (5, 1);
-- AFTER  (expect still 1 audit row and 1 role link)
SELECT COUNT(*) AS Audit_Rows_User5_Role1 FROM user_role_audit WHERE User_ID = 5 AND Role_ID = 1;
SELECT COUNT(*) AS Links_User5_Role1 FROM user_role WHERE User_ID = 5 AND Role_ID = 1;
-- (no cleanup needed)


-- ============================================================================
-- TEST 16: trg_user_role_ad - removing a role writes a REVOKE row into user_role_audit
-- ============================================================================
-- BEFORE  (first give Meera the OPERATOR role so there is something to revoke; this also writes a GRANT row)
INSERT INTO user_role (User_ID, Role_ID) VALUES (5, 3);
SELECT Audit_ID, User_ID, Role_ID, Action FROM user_role_audit WHERE User_ID = 5 AND Role_ID = 3 ORDER BY Audit_ID;   -- expect GRANT only
-- ACTION
DELETE FROM user_role WHERE User_ID = 5 AND Role_ID = 3;
-- AFTER  (expect two rows: GRANT then REVOKE, and the role link is gone)
SELECT Audit_ID, User_ID, Role_ID, Action FROM user_role_audit WHERE User_ID = 5 AND Role_ID = 3 ORDER BY Audit_ID;
SELECT COUNT(*) AS Links_User5_Role3 FROM user_role WHERE User_ID = 5 AND Role_ID = 3;   -- expect 0
-- CLEANUP
DELETE FROM user_role_audit WHERE User_ID = 5 AND Role_ID = 3;


-- ============================================================================
-- TEST 17: trg_user_role_ad - edge: deleting a role link that does not exist removes 0 rows and writes NO audit row
-- ============================================================================
-- BEFORE  (user 5 does not have role 2 = ADMIN)
SELECT COUNT(*) AS Links_User5_Role2 FROM user_role WHERE User_ID = 5 AND Role_ID = 2;           -- expect 0
SELECT COUNT(*) AS Audit_Rows_User5_Role2 FROM user_role_audit WHERE User_ID = 5 AND Role_ID = 2; -- expect 0
-- ACTION
DELETE FROM user_role WHERE User_ID = 5 AND Role_ID = 2;
SELECT ROW_COUNT() AS Rows_Deleted;   -- expect 0
-- AFTER  (expect 0 audit rows: AFTER DELETE fires once per deleted row, and no row was deleted)
SELECT COUNT(*) AS Audit_Rows_User5_Role2 FROM user_role_audit WHERE User_ID = 5 AND Role_ID = 2;
-- (no cleanup needed)


-- ============================================================================
-- TEST 18: trg_passenger_bi - normal: a passenger with a past date of birth is accepted
-- ============================================================================
-- BEFORE
SELECT COUNT(*) AS Test_Passengers FROM passenger WHERE Full_Name = 'Trigger Test Adult';   -- expect 0
-- ACTION
INSERT INTO passenger (User_ID, Full_Name, Date_Of_Birth, Gender, Concession_Type)
VALUES (5, 'Trigger Test Adult', '1995-06-15', 'F', 'NONE');
-- AFTER  (expect 1 row; Concession_Type NONE)
SELECT Passenger_ID, User_ID, Full_Name, Date_Of_Birth, Gender, Concession_Type
FROM passenger WHERE Full_Name = 'Trigger Test Adult';
-- CLEANUP
DELETE FROM passenger WHERE Full_Name = 'Trigger Test Adult';


-- ============================================================================
-- TEST 19: trg_passenger_bi - boundary: a date of birth equal to TODAY is accepted (only future dates are rejected)
-- ============================================================================
-- BEFORE
SELECT CURDATE() AS Today;
SELECT COUNT(*) AS Test_Passengers FROM passenger WHERE Full_Name = 'Trigger Test Newborn';   -- expect 0
-- ACTION
INSERT INTO passenger (User_ID, Full_Name, Date_Of_Birth, Gender, Concession_Type)
VALUES (5, 'Trigger Test Newborn', CURDATE(), 'O', 'NONE');
-- AFTER  (expect 1 row and fn_age_category = CHILD)
SELECT Passenger_ID, Full_Name, Date_Of_Birth, fn_age_category(Date_Of_Birth) AS Age_Category
FROM passenger WHERE Full_Name = 'Trigger Test Newborn';
-- CLEANUP
DELETE FROM passenger WHERE Full_Name = 'Trigger Test Newborn';


-- ============================================================================
-- TEST 20: trg_passenger_bi - a date of birth in the future (tomorrow) is rejected
-- EXPECT ERROR VALIDATION_ERROR
-- ============================================================================
-- BEFORE
SELECT CURDATE() AS Today, DATE_ADD(CURDATE(), INTERVAL 1 DAY) AS Tomorrow;
SELECT COUNT(*) AS Test_Passengers FROM passenger WHERE Full_Name = 'Trigger Test Future';   -- expect 0
-- ACTION  (must fail: "VALIDATION_ERROR: Date of birth cannot be in the future")
INSERT INTO passenger (User_ID, Full_Name, Date_Of_Birth, Gender, Concession_Type)
VALUES (5, 'Trigger Test Future', DATE_ADD(CURDATE(), INTERVAL 1 DAY), 'M', 'NONE');
-- AFTER  (expect 0 rows: nothing was inserted; the passenger count is still 8)
SELECT COUNT(*) AS Test_Passengers FROM passenger WHERE Full_Name = 'Trigger Test Future';
SELECT COUNT(*) AS Total_Passengers FROM passenger;   -- expect 8
-- (no cleanup needed)


-- ============================================================================
-- TEST 21: v_user_account - normal: one row per user, exact column list and order, role names joined
-- ============================================================================
-- BEFORE
SELECT COUNT(*) AS Users_In_Table FROM app_user;   -- expect 5
-- ACTION  (expect 5 rows; Roles: 1 ADMIN, 2 OPERATOR, 3-5 PASSENGER)
SELECT * FROM v_user_account ORDER BY User_ID;
-- AFTER  (the column list of the view must equal the contract C5.4 list, in this order)
SELECT GROUP_CONCAT(COLUMN_NAME ORDER BY ORDINAL_POSITION) AS View_Columns,
       IF(GROUP_CONCAT(COLUMN_NAME ORDER BY ORDINAL_POSITION) = 'User_ID,Email,Full_Name,Phone,Is_Active,Roles,Created_At',
          'PASS', 'FAIL') AS Result
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'v_user_account';
-- (no cleanup needed: read-only)


-- ============================================================================
-- TEST 22: v_user_account - edge: a user with two roles shows both names, alphabetical, comma separated
-- ============================================================================
-- BEFORE
SELECT User_ID, Email, Roles FROM v_user_account WHERE User_ID = 5;   -- expect PASSENGER
-- ACTION
INSERT INTO user_role (User_ID, Role_ID) VALUES (5, 2);   -- add ADMIN
-- AFTER  (expect Roles = ADMIN,PASSENGER and still exactly one row for the user)
SELECT User_ID, Email, Roles FROM v_user_account WHERE User_ID = 5;
-- CLEANUP
DELETE FROM user_role       WHERE User_ID = 5 AND Role_ID = 2;   -- fires trg_user_role_ad
DELETE FROM user_role_audit WHERE User_ID = 5 AND Role_ID = 2;   -- remove the GRANT and REVOKE rows of this test


-- ============================================================================
-- TEST 23: v_user_account - edge: a user without any role is still listed, with Roles = NULL (LEFT JOIN)
-- ============================================================================
-- BEFORE
SELECT COUNT(*) AS Users_With_This_Email FROM v_user_account WHERE Email = 'no.role@railway.test';   -- expect 0
-- ACTION  (direct insert, so no role link is created)
INSERT INTO app_user (Email, Password_Hash, Full_Name, Phone)
VALUES ('no.role@railway.test', '$2a$10$Ggra/EJAY81g3MUp5ZRx8ukeDAXlA/NBVyQUlUz0AXv/3vZ0FQjOq', 'No Role User', '9444444444');
-- AFTER  (expect 1 row with Roles NULL)
SELECT User_ID, Email, Roles FROM v_user_account WHERE Email = 'no.role@railway.test';
-- CLEANUP
DELETE FROM app_user WHERE Email = 'no.role@railway.test';


-- ============================================================================
-- TEST 24: v_passenger_booking_history - exact columns; returns 0 rows until bookings exist
-- ============================================================================
-- BEFORE
SELECT COUNT(*) AS Bookings_In_Table FROM booking;   -- 0 on a fresh database (G3 owns this table)
-- ACTION  (NOTE: 0 rows is the CORRECT result before any booking exists. After 60_demo_data.sql rows appear.)
SELECT * FROM v_passenger_booking_history ORDER BY User_ID, Passenger_ID, Booking_ID LIMIT 20;
-- AFTER  (the column list of the view must equal the contract C5.4 list, in this order)
SELECT GROUP_CONCAT(COLUMN_NAME ORDER BY ORDINAL_POSITION) AS View_Columns,
       IF(GROUP_CONCAT(COLUMN_NAME ORDER BY ORDINAL_POSITION) =
          'User_ID,Passenger_ID,Passenger_Name,Booking_ID,Booking_Passenger_ID,PNR,Train_No,Train_Name,Journey_Date,From_Station_Code,To_Station_Code,Class_Code,Status,Fare_Amount,Booked_At',
          'PASS', 'FAIL') AS Result
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'v_passenger_booking_history';
-- (no cleanup needed: read-only)


-- ============================================================================
-- TEST 25: v_passenger_booking_history - one booking passenger appears with train, station codes and fare;
--          a passenger that was never booked does not appear
-- Needs train runs from 50_seed_g1.sql. The temporary booking uses Status 'CANCELLED' on purpose: the inventory
-- triggers only count CNF/RAC/WL rows, so seat_inventory is not touched (rule R9). PNR '0000000000' can never
-- be produced by fn_generate_pnr (its first digit is 1-9), so it cannot clash with a real booking.
-- ============================================================================
-- BEFORE
SET @run_id = (SELECT Run_ID FROM train_run WHERE Train_ID = 1 ORDER BY Journey_Date LIMIT 1);   -- train 11001, route CSMT -> PUNE
SELECT @run_id AS Run_ID_Used;   -- must not be NULL
SELECT COUNT(*) AS Rows_For_Passenger1 FROM v_passenger_booking_history WHERE Passenger_ID = 1;
-- ACTION
INSERT INTO booking (PNR, User_ID, Run_ID, Class_Code, From_Station_ID, To_Station_ID, Booking_Status, Total_Fare)
VALUES ('0000000000', 3, @run_id, 'SL', 2, 1, 'CANCELLED', 0);
SET @bk_id = LAST_INSERT_ID();
INSERT INTO booking_passenger (Booking_ID, Passenger_ID, Status, Base_Fare, Concession_Type, Fare_Amount)
VALUES (@bk_id, 1, 'CANCELLED', 100.00, 'NONE', 100.00);
-- AFTER  (expect 1 row: Asha Patil, 11001 Mumbai Pune Express, CSMT -> PUNE, SL, CANCELLED, 100.00)
SELECT * FROM v_passenger_booking_history WHERE PNR = '0000000000';
SELECT COUNT(*) AS Rows_For_Passenger2_Suresh FROM v_passenger_booking_history WHERE Passenger_ID = 2;   -- expect 0 (never booked)
-- CLEANUP
DELETE FROM booking_passenger WHERE Booking_ID = @bk_id;
DELETE FROM booking           WHERE Booking_ID = @bk_id;


-- ============================================================================
-- FINAL CLEANUP: give the AUTO_INCREMENT counters back (a smaller value is silently raised to MAX+1 by InnoDB)
-- and switch Workbench safe-update mode on again
-- ============================================================================
ALTER TABLE app_user          AUTO_INCREMENT = 1;
ALTER TABLE passenger         AUTO_INCREMENT = 1;
ALTER TABLE user_role_audit   AUTO_INCREMENT = 1;
ALTER TABLE login_audit       AUTO_INCREMENT = 1;
ALTER TABLE booking           AUTO_INCREMENT = 1;
ALTER TABLE booking_passenger AUTO_INCREMENT = 1;
SET SQL_SAFE_UPDATES = 1;


-- SUMMARY (what each test proves)
--  TEST  1  Seed: 3 roles, 5 users, 5 role links, 8 passengers, 5 GRANT audit rows, bcrypt hashes of length 60.
--  TEST  2  fn_age_category: seeded passengers are classified ADULT / SENIOR / CHILD correctly.
--  TEST  3  fn_age_category boundaries: age 0 and 11 = CHILD, 12 and 59 = ADULT, 60 and 90 = SENIOR.
--  TEST  4  fn_effective_concession: an adult keeps the declared NONE / GOVT / SOLDIER concession.
--  TEST  5  fn_effective_concession edge: SENIOR and CHILD override the declared type; boundaries 11/12 and 59/60.
--  TEST  6  sp_register_user: creates app_user + PASSENGER role link in one transaction; GRANT audit row appears.
--  TEST  7  sp_register_user: duplicate e-mail raises EMAIL_EXISTS and nothing is written.
--  TEST  8  sp_register_user: invalid phone breaks the CHECK constraint (CONSTRAINT_VIOLATION) and the transaction rolls back.
--  TEST  9  sp_record_login_attempt: a failed login writes login_audit and raises Failed_Login_Count to 1.
--  TEST 10  sp_record_login_attempt: an unknown e-mail is audited with User_ID NULL and changes no user.
--  TEST 11  sp_record_login_attempt: a successful login resets the failed-login counter to 0.
--  TEST 12  sp_record_login_attempt: five failures lock the account for 15 minutes and reset the counter.
--  TEST 13  sp_record_login_attempt: a successful login clears Locked_Until.
--  TEST 14  trg_user_role_ai: granting a role inserts a GRANT row in user_role_audit.
--  TEST 15  trg_user_role_ai: a duplicate grant fails (DUPLICATE) and writes no audit row.
--  TEST 16  trg_user_role_ad: removing a role inserts a REVOKE row in user_role_audit.
--  TEST 17  trg_user_role_ad: deleting a non-existent role link writes no audit row.
--  TEST 18  trg_passenger_bi: a passenger with a past date of birth is accepted.
--  TEST 19  trg_passenger_bi: a date of birth equal to today is accepted (boundary).
--  TEST 20  trg_passenger_bi: a future date of birth is rejected with VALIDATION_ERROR and nothing is stored.
--  TEST 21  v_user_account: one row per user, exact contract columns, role names listed.
--  TEST 22  v_user_account: several roles are joined alphabetically with commas (ADMIN,PASSENGER).
--  TEST 23  v_user_account: a user with no role is still listed, Roles = NULL.
--  TEST 24  v_passenger_booking_history: exact contract columns; 0 rows before any booking exists is correct.
--  TEST 25  v_passenger_booking_history: a booking passenger shows train, station codes, class, status and fare;
--           a never-booked passenger does not appear.
