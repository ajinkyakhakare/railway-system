-- Task G4.3 | Owner: G4 (Payment, Cancellation & Refund) | Purpose: master seed for fare_rule, concession_rule, refund_rule (contract C6, explicit ids)
-- Needs coach_type rows from 50_seed_g1.sql (fare_rule.Class_Code is a foreign key). Inserts do not fire trg_fare_audit (it is AFTER UPDATE only).

-- Fare rules: (id, class, rate per km, minimum fare)
INSERT INTO fare_rule (Fare_Rule_ID, Class_Code, Base_Fare_Per_Km, Min_Fare) VALUES
    (1, 'SL', 0.55, 120.00),
    (2, '3A', 1.45, 300.00),
    (3, '2A', 2.10, 450.00),
    (4, '1A', 3.60, 700.00),
    (5, 'CC', 1.60, 350.00);

-- Concession rules: (id, type, discount %, description)
INSERT INTO concession_rule (Concession_Rule_ID, Concession_Type, Discount_Percent, Description) VALUES
    (1, 'NONE',    0.00, 'No concession'),
    (2, 'SENIOR', 40.00, 'Senior citizen (age 60 or above)'),
    (3, 'GOVT',   25.00, 'Government employee'),
    (4, 'SOLDIER',50.00, 'Armed forces personnel'),
    (5, 'CHILD',  50.00, 'Child (below 12 years)');

-- Refund rules: (id, Min_Hours_Before, Max_Hours_Before, deduction %)
-- A row applies when Min_Hours_Before <= hours < Max_Hours_Before (NULL max = no upper limit).
INSERT INTO refund_rule (Refund_Rule_ID, Min_Hours_Before, Max_Hours_Before, Deduction_Percent) VALUES
    (1, 48, NULL, 10.00),
    (2, 12, 48,   25.00),
    (3,  4, 12,   50.00),
    (4,  0,  4,  100.00);
