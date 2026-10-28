-- Task G4.3 | Owner: G4 (Payment, Cancellation & Refund) | Purpose: views v_payment_history and v_refund_summary
-- The backend filters both views with WHERE User_ID = <logged-in user>.

-- ---------------------------------------------------------------------------
-- v_payment_history : one row per payment attempt, together with the PNR and
-- the owner (User_ID) of the booking it belongs to.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_payment_history AS
SELECT b.User_ID        AS User_ID,
       p.Payment_ID     AS Payment_ID,
       p.Booking_ID     AS Booking_ID,
       b.PNR            AS PNR,
       p.Amount         AS Amount,
       p.Payment_Mode   AS Payment_Mode,
       p.Payment_Status AS Payment_Status,
       p.Created_At     AS Created_At,
       p.Paid_At        AS Paid_At
FROM payment p
JOIN booking b ON b.Booking_ID = p.Booking_ID;

-- ---------------------------------------------------------------------------
-- v_refund_summary : one row per refund. Path: refund -> cancellation ->
-- booking_passenger -> booking (PNR, owner) and -> passenger (name).
-- A cancellation of an unpaid ticket has no refund row, so it does not appear.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_refund_summary AS
SELECT b.User_ID            AS User_ID,
       c.Cancellation_ID    AS Cancellation_ID,
       b.PNR                AS PNR,
       pa.Full_Name         AS Passenger_Name,
       r.Original_Fare      AS Original_Fare,
       r.Deduction_Percent  AS Deduction_Percent,
       r.Deduction_Amount   AS Deduction_Amount,
       r.Refund_Amount      AS Refund_Amount,
       r.Refund_Status      AS Refund_Status,
       c.Cancelled_At       AS Cancelled_At
FROM refund r
JOIN cancellation c       ON c.Cancellation_ID       = r.Cancellation_ID
JOIN booking_passenger bp ON bp.Booking_Passenger_ID = c.Booking_Passenger_ID
JOIN booking b            ON b.Booking_ID            = bp.Booking_ID
JOIN passenger pa         ON pa.Passenger_ID         = bp.Passenger_ID;
