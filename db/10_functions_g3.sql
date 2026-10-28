-- Task G3.2 | Owner: G3 (Reservation & Seat) | UDFs: fn_generate_pnr, fn_availability_text
-- Runs after all schema files (01..05). Re-runnable: every function is dropped before it is created.

DELIMITER $$

-- ---------------------------------------------------------------------------
-- fn_generate_pnr
-- Purpose : produce a random 10-digit PNR candidate (first digit 1-9, so the
--           number never starts with 0 and always keeps all 10 digits).
-- Params  : none
-- Returns : CHAR(10), e.g. '4829301175'
-- Notes   : NOT DETERMINISTIC because RAND() gives a different value per call.
--           NO SQL because it reads no table. Uniqueness is NOT guaranteed here;
--           sp_book_ticket loops until it finds a PNR not yet used in booking.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_generate_pnr$$
CREATE FUNCTION fn_generate_pnr()
RETURNS CHAR(10)
NOT DETERMINISTIC
NO SQL
BEGIN
    -- first digit: 1..9 ; remaining 9 digits: 0..999999999 left-padded with zeros
    RETURN CONCAT(
        FLOOR(1 + RAND() * 9),
        LPAD(FLOOR(RAND() * 1000000000), 9, '0')
    );
END$$

-- ---------------------------------------------------------------------------
-- fn_availability_text
-- Purpose : turn the seat counters of one (run, class) into the text shown to
--           passengers: 'AVL 12', 'RAC 3', 'WL 5' or 'REGRET'.
-- Params  : p_available_cnf - free confirmed seats
--           p_rac           - RAC tickets already issued
--           p_wl            - waiting-list tickets already issued
--           p_max_rac       - RAC capacity
--           p_max_wl        - waiting-list capacity
-- Returns : VARCHAR(20)
-- Notes   : DETERMINISTIC - the result depends only on the arguments.
--           The number after RAC / WL is the position the NEXT booking would get.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_availability_text$$
CREATE FUNCTION fn_availability_text(
    p_available_cnf INT,
    p_rac           INT,
    p_wl            INT,
    p_max_rac       INT,
    p_max_wl        INT
)
RETURNS VARCHAR(20)
DETERMINISTIC
BEGIN
    IF p_available_cnf > 0 THEN
        RETURN CONCAT('AVL ', p_available_cnf);
    ELSEIF p_rac < p_max_rac THEN
        RETURN CONCAT('RAC ', p_rac + 1);
    ELSEIF p_wl < p_max_wl THEN
        RETURN CONCAT('WL ', p_wl + 1);
    END IF;

    RETURN 'REGRET';   -- no seat, no RAC, no waiting-list place left
END$$

DELIMITER ;
