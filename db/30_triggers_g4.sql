-- Task G4.3 | Owner: G4 (Payment, Cancellation & Refund) | Purpose: triggers trg_fare_audit, trg_payment_confirm, trg_refund_check
DELIMITER $$

-- ---------------------------------------------------------------------------
-- trg_fare_audit : every change of the per-km rate or the minimum fare of a
-- fare_rule row is written to fare_audit_log (old value, new value, who, when).
-- Changed_By = USER() = the MySQL account that ran the UPDATE (e.g. root@localhost).
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_fare_audit$$
CREATE TRIGGER trg_fare_audit
AFTER UPDATE ON fare_rule
FOR EACH ROW
BEGIN
    -- Only log when something that affects fares really changed
    -- (an update that touches only Updated_At is not a fare change).
    IF OLD.Base_Fare_Per_Km <> NEW.Base_Fare_Per_Km
       OR OLD.Min_Fare <> NEW.Min_Fare THEN
        INSERT INTO fare_audit_log
            (Fare_Rule_ID, Old_Base_Fare_Per_Km, New_Base_Fare_Per_Km,
             Old_Min_Fare, New_Min_Fare, Changed_By)
        VALUES
            (OLD.Fare_Rule_ID, OLD.Base_Fare_Per_Km, NEW.Base_Fare_Per_Km,
             OLD.Min_Fare, NEW.Min_Fare, LEFT(USER(), 100));
    END IF;
END$$

-- ---------------------------------------------------------------------------
-- trg_payment_confirm : when a payment becomes SUCCESS the booking is CONFIRMED.
-- This is the only place that confirms a booking (sp_confirm_payment just
-- updates the payment row). Allowed cross-group write: contract C11 rule 1.
-- The booking is confirmed only while it is still PENDING_PAYMENT, so a late
-- payment can never bring a CANCELLED or EXPIRED booking back to life.
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_payment_confirm$$
CREATE TRIGGER trg_payment_confirm
AFTER UPDATE ON payment
FOR EACH ROW
BEGIN
    IF NEW.Payment_Status = 'SUCCESS' AND OLD.Payment_Status <> 'SUCCESS' THEN
        UPDATE booking
           SET Booking_Status = 'CONFIRMED'
         WHERE Booking_ID = NEW.Booking_ID
           AND Booking_Status = 'PENDING_PAYMENT';
    END IF;
END$$

-- ---------------------------------------------------------------------------
-- trg_refund_check : a refund can never be larger than the fare that was paid
-- for that passenger. Raises REFUND_EXCEEDS_FARE (HTTP 409 in the API).
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_refund_check$$
CREATE TRIGGER trg_refund_check
BEFORE INSERT ON refund
FOR EACH ROW
BEGIN
    IF NEW.Refund_Amount > NEW.Original_Fare THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'REFUND_EXCEEDS_FARE: refund amount cannot be greater than the original fare';
    END IF;
END$$

DELIMITER ;
