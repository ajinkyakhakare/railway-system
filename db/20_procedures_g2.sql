-- Task G2.2 | Owner: G2 (Passenger & User) | Purpose: stored procedures sp_register_user and sp_record_login_attempt (contract C5.2)

DELIMITER $$

-- ---------------------------------------------------------------------------
-- sp_register_user
-- Purpose    : create a new account and give it the PASSENGER role, atomically.
-- Parameters : p_email          VARCHAR(120)  stored lower-cased and trimmed
--              p_password_hash  VARCHAR(100)  bcrypt hash (hashing is done by the backend)
--              p_full_name      VARCHAR(80)
--              p_phone          CHAR(10)      exactly 10 digits
-- Result set : one row -> User_ID
-- Errors     : VALIDATION_ERROR  blank email / name / hash, or phone is not 10 digits
--              EMAIL_EXISTS      the e-mail is already registered
--              NOT_FOUND         the PASSENGER role row is missing (seed not loaded)
-- Notes      : the EMAIL_EXISTS check is done first (friendly error). If two
--              requests race past that check, the UNIQUE index on app_user.Email
--              fires (MySQL error 1062) and is converted to EMAIL_EXISTS as well.
-- ---------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_register_user$$
CREATE PROCEDURE sp_register_user(
    IN p_email         VARCHAR(120),
    IN p_password_hash VARCHAR(100),
    IN p_full_name     VARCHAR(80),
    IN p_phone         CHAR(10)
)
BEGIN
    DECLARE v_email   VARCHAR(120);
    DECLARE v_user_id INT UNSIGNED;
    DECLARE v_role_id INT UNSIGNED;

    -- Lost a race on the UNIQUE(Email) index: report it as a business error.
    DECLARE EXIT HANDLER FOR 1062
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'EMAIL_EXISTS: this e-mail is already registered';
    END;

    -- Any other SQL error: undo everything and pass the error to the caller.
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    -- ---- input validation (before any write) ----
    SET v_email = LOWER(TRIM(p_email));

    IF v_email IS NULL OR v_email = '' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'VALIDATION_ERROR: email is required';
    END IF;
    IF p_password_hash IS NULL OR p_password_hash = '' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'VALIDATION_ERROR: password hash is required';
    END IF;
    IF p_full_name IS NULL OR TRIM(p_full_name) = '' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'VALIDATION_ERROR: full name is required';
    END IF;
    IF p_phone IS NULL OR p_phone NOT REGEXP '^[0-9]{10}$' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'VALIDATION_ERROR: phone must be exactly 10 digits';
    END IF;

    -- ---- EMAIL_EXISTS check comes first ----
    IF (SELECT COUNT(*) FROM app_user WHERE Email = v_email) > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'EMAIL_EXISTS: this e-mail is already registered';
    END IF;

    START TRANSACTION;

    -- 1) create the account
    INSERT INTO app_user (Email, Password_Hash, Full_Name, Phone)
    VALUES (v_email, p_password_hash, TRIM(p_full_name), p_phone);

    -- Capture the new id IMMEDIATELY, before any other INSERT changes LAST_INSERT_ID().
    SET v_user_id = LAST_INSERT_ID();

    -- 2) grant the PASSENGER role
    SELECT Role_ID INTO v_role_id
      FROM `role`
     WHERE Role_Name = 'PASSENGER';

    IF v_role_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'NOT_FOUND: role PASSENGER does not exist (load the seed data)';
    END IF;

    INSERT INTO user_role (User_ID, Role_ID)
    VALUES (v_user_id, v_role_id);

    COMMIT;

    -- Single result set required by the contract.
    SELECT v_user_id AS User_ID;
END$$

-- ---------------------------------------------------------------------------
-- sp_record_login_attempt
-- Purpose    : write one login_audit row and maintain the brute-force lock.
-- Parameters : p_email    VARCHAR(120)  e-mail typed by the user (lower-cased here)
--              p_success  TINYINT       1 = correct password, 0 = wrong password
--              p_ip       VARCHAR(45)   client IP address (may be NULL)
-- Behaviour  : * unknown e-mail  -> audit row with User_ID NULL; returns 0 and NULL
--              * failure         -> Failed_Login_Count + 1; when it reaches 5,
--                                   Locked_Until = NOW() + 15 minutes and the
--                                   count is reset to 0
--              * success         -> Failed_Login_Count = 0, Locked_Until = NULL
-- Result set : one row -> Failed_Login_Count, Locked_Until (the final values)
-- Errors     : VALIDATION_ERROR  blank e-mail, or p_success not 0/1
-- ---------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_record_login_attempt$$
CREATE PROCEDURE sp_record_login_attempt(
    IN p_email   VARCHAR(120),
    IN p_success TINYINT,
    IN p_ip      VARCHAR(45)
)
BEGIN
    DECLARE v_email   VARCHAR(120);
    DECLARE v_user_id INT UNSIGNED DEFAULT NULL;   -- stays NULL for an unknown e-mail
    DECLARE v_count   INT          DEFAULT 0;      -- INT so count + 1 can never overflow
    DECLARE v_locked  DATETIME     DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    -- ---- input validation ----
    SET v_email = LOWER(TRIM(p_email));

    IF v_email IS NULL OR v_email = '' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'VALIDATION_ERROR: email is required';
    END IF;
    IF p_success IS NULL OR p_success NOT IN (0, 1) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'VALIDATION_ERROR: success must be 0 or 1';
    END IF;

    START TRANSACTION;

    -- Lock the user row so two simultaneous failures cannot lose a count.
    -- If the e-mail is unknown no row is found and the variables keep their defaults.
    SELECT User_ID, Failed_Login_Count, Locked_Until
      INTO v_user_id, v_count, v_locked
      FROM app_user
     WHERE Email = v_email
       FOR UPDATE;

    -- Always keep an audit trail (User_ID stays NULL for unknown e-mails).
    INSERT INTO login_audit (User_ID, Email_Attempted, Success, IP_Address)
    VALUES (v_user_id, v_email, p_success, p_ip);

    IF v_user_id IS NULL THEN
        -- Unknown e-mail: nothing to update, report "no failures, no lock".
        SET v_count  = 0;
        SET v_locked = NULL;
    ELSEIF p_success = 1 THEN
        -- Successful login: clear the counter and any lock.
        SET v_count  = 0;
        SET v_locked = NULL;
        UPDATE app_user
           SET Failed_Login_Count = 0,
               Locked_Until       = NULL
         WHERE User_ID = v_user_id;
    ELSE
        -- Failed login: count it; the 5th failure locks the account for 15 minutes.
        SET v_count = v_count + 1;
        IF v_count >= 5 THEN
            SET v_locked = NOW() + INTERVAL 15 MINUTE;
            SET v_count  = 0;
        END IF;
        UPDATE app_user
           SET Failed_Login_Count = v_count,
               Locked_Until       = v_locked
         WHERE User_ID = v_user_id;
    END IF;

    COMMIT;

    -- Single result set required by the contract.
    SELECT v_count AS Failed_Login_Count, v_locked AS Locked_Until;
END$$

DELIMITER ;
