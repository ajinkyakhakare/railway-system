-- Task G2.3 | Owner: G2 (Passenger & User) | Purpose: triggers trg_user_role_ai, trg_user_role_ad, trg_passenger_bi (contract C5.3)
-- Re-runnable: every trigger is dropped (IF EXISTS) before it is created.

DELIMITER $$

-- ---------------------------------------------------------------------------
-- trg_user_role_ai : every role granted to a user is recorded in user_role_audit
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_user_role_ai$$
CREATE TRIGGER trg_user_role_ai
AFTER INSERT ON user_role
FOR EACH ROW
BEGIN
    INSERT INTO user_role_audit (User_ID, Role_ID, Action)
    VALUES (NEW.User_ID, NEW.Role_ID, 'GRANT');
END$$

-- ---------------------------------------------------------------------------
-- trg_user_role_ad : every role taken away from a user is recorded as REVOKE
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_user_role_ad$$
CREATE TRIGGER trg_user_role_ad
AFTER DELETE ON user_role
FOR EACH ROW
BEGIN
    INSERT INTO user_role_audit (User_ID, Role_ID, Action)
    VALUES (OLD.User_ID, OLD.Role_ID, 'REVOKE');
END$$

-- ---------------------------------------------------------------------------
-- trg_passenger_bi : a passenger cannot be born in the future.
-- (A date of birth equal to today is allowed: a newborn is valid.)
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_passenger_bi$$
CREATE TRIGGER trg_passenger_bi
BEFORE INSERT ON passenger
FOR EACH ROW
BEGIN
    IF NEW.Date_Of_Birth > CURDATE() THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'VALIDATION_ERROR: Date of birth cannot be in the future';
    END IF;
END$$

DELIMITER ;
