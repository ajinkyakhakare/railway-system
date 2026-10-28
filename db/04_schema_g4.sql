-- Task G4.1 | Owner: G4 (Payment, Cancellation & Refund) | Purpose: schema (tables, constraints, indexes) for the 7 G4 tables
-- Runs AFTER 01_schema_g1.sql, 02_schema_g2.sql and 03_schema_g3.sql (needs coach_type, booking, booking_passenger).
-- No USE / CREATE DATABASE here: scripts/init-db does that. Plain CREATE TABLE because the database is rebuilt from scratch.
-- Creation order = dependency order: rule tables first, then payment, cancellation, refund, and the audit log.

-- ---------------------------------------------------------------------------
-- fare_rule: one pricing rule per travel class (rate per km + minimum fare).
-- Used by fn_base_fare. Every change is logged into fare_audit_log by trg_fare_audit.
-- Class_Code is both UNIQUE here (1 rule per class) and a foreign key to coach_type(Class_Code).
-- ---------------------------------------------------------------------------
CREATE TABLE fare_rule (
    Fare_Rule_ID     INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    Class_Code       VARCHAR(3)    NOT NULL,
    Base_Fare_Per_Km DECIMAL(6,2)  NOT NULL,
    Min_Fare         DECIMAL(8,2)  NOT NULL,
    Updated_At       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (Fare_Rule_ID),
    UNIQUE KEY uq_fare_rule_class_code (Class_Code),
    CONSTRAINT fk_fare_rule_coach_type FOREIGN KEY (Class_Code) REFERENCES coach_type (Class_Code),
    CONSTRAINT chk_fare_rule_base_fare CHECK (Base_Fare_Per_Km > 0),
    CONSTRAINT chk_fare_rule_min_fare  CHECK (Min_Fare >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='G4: fare per km and minimum fare for each travel class';

-- ---------------------------------------------------------------------------
-- concession_rule: discount percentage for each concession type (data, not code).
-- Used by fn_net_fare. Changing a discount is an UPDATE of this table, no code change.
-- ---------------------------------------------------------------------------
CREATE TABLE concession_rule (
    Concession_Rule_ID INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    Concession_Type    VARCHAR(10)   NOT NULL,
    Discount_Percent   DECIMAL(5,2)  NOT NULL,
    Description        VARCHAR(100)  NULL,
    PRIMARY KEY (Concession_Rule_ID),
    UNIQUE KEY uq_concession_rule_type (Concession_Type),
    CONSTRAINT chk_concession_rule_type
        CHECK (Concession_Type IN ('NONE','SENIOR','GOVT','SOLDIER','CHILD')),
    CONSTRAINT chk_concession_rule_discount
        CHECK (Discount_Percent BETWEEN 0 AND 100)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='G4: discount percent per concession type';

-- ---------------------------------------------------------------------------
-- refund_rule: deduction percentage by "hours before departure" band (data, not code).
-- A band covers Min_Hours_Before <= hours < Max_Hours_Before (Max NULL = no upper limit).
-- Used by fn_refund_deduction_pct.
-- ---------------------------------------------------------------------------
CREATE TABLE refund_rule (
    Refund_Rule_ID    INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    Min_Hours_Before  SMALLINT      NOT NULL,
    Max_Hours_Before  SMALLINT      NULL,
    Deduction_Percent DECIMAL(5,2)  NOT NULL,
    PRIMARY KEY (Refund_Rule_ID),
    UNIQUE KEY uq_refund_rule_min_hours (Min_Hours_Before),
    CONSTRAINT chk_refund_rule_min_hours CHECK (Min_Hours_Before >= 0),
    CONSTRAINT chk_refund_rule_deduction CHECK (Deduction_Percent BETWEEN 0 AND 100)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='G4: cancellation deduction percent by hours-before-departure band';

-- ---------------------------------------------------------------------------
-- payment: one payment attempt for a booking (a booking can have several attempts).
-- Status flow: CREATED -> SUCCESS or FAILED. trg_payment_confirm confirms the booking on SUCCESS.
-- Gateway_Order_ID is UNIQUE (NULLs allowed); it holds the Razorpay order id or "MOCK_<uuid>".
-- ---------------------------------------------------------------------------
CREATE TABLE payment (
    Payment_ID         INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    Booking_ID         INT UNSIGNED  NOT NULL,
    Amount             DECIMAL(10,2) NOT NULL,
    Payment_Mode       VARCHAR(10)   NOT NULL,
    Gateway_Order_ID   VARCHAR(60)   NULL,
    Gateway_Payment_ID VARCHAR(60)   NULL,
    Payment_Status     VARCHAR(10)   NOT NULL DEFAULT 'CREATED',
    Created_At         DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    Paid_At            DATETIME      NULL,
    PRIMARY KEY (Payment_ID),
    UNIQUE KEY uq_payment_gateway_order_id (Gateway_Order_ID),
    KEY idx_payment_booking_id (Booking_ID),
    CONSTRAINT fk_payment_booking FOREIGN KEY (Booking_ID) REFERENCES booking (Booking_ID),
    CONSTRAINT chk_payment_amount CHECK (Amount > 0),
    CONSTRAINT chk_payment_mode   CHECK (Payment_Mode IN ('RAZORPAY','MOCK')),
    CONSTRAINT chk_payment_status CHECK (Payment_Status IN ('CREATED','SUCCESS','FAILED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='G4: payment attempts for bookings (Razorpay or MOCK gateway)';

-- ---------------------------------------------------------------------------
-- cancellation: one row per cancelled passenger (UNIQUE Booking_Passenger_ID = cancel only once).
-- Hours_Before_Departure is stored so the refund percentage can be explained later.
-- ---------------------------------------------------------------------------
CREATE TABLE cancellation (
    Cancellation_ID        INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    Booking_Passenger_ID   INT UNSIGNED  NOT NULL,
    Hours_Before_Departure DECIMAL(8,2)  NOT NULL,
    Reason                 VARCHAR(100)  NULL,
    Cancelled_At           DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (Cancellation_ID),
    UNIQUE KEY uq_cancellation_booking_passenger_id (Booking_Passenger_ID),
    CONSTRAINT fk_cancellation_booking_passenger
        FOREIGN KEY (Booking_Passenger_ID) REFERENCES booking_passenger (Booking_Passenger_ID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='G4: one cancellation per cancelled passenger';

-- ---------------------------------------------------------------------------
-- refund: money returned for one cancellation (UNIQUE Cancellation_ID = one refund per cancellation).
-- Payment_ID points to the SUCCESS payment the money is returned against, so one payment
-- can have many refunds (one per cancelled passenger of that booking).
-- Refund_Amount = Original_Fare - Deduction_Amount; trg_refund_check blocks Refund_Amount > Original_Fare.
-- ---------------------------------------------------------------------------
CREATE TABLE refund (
    Refund_ID         INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    Cancellation_ID   INT UNSIGNED  NOT NULL,
    Payment_ID        INT UNSIGNED  NOT NULL,
    Original_Fare     DECIMAL(10,2) NOT NULL,
    Deduction_Percent DECIMAL(5,2)  NOT NULL,
    Deduction_Amount  DECIMAL(10,2) NOT NULL,
    Refund_Amount     DECIMAL(10,2) NOT NULL,
    Refund_Status     VARCHAR(10)   NOT NULL DEFAULT 'PROCESSED',
    Processed_At      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (Refund_ID),
    UNIQUE KEY uq_refund_cancellation_id (Cancellation_ID),
    KEY idx_refund_payment_id (Payment_ID),
    CONSTRAINT fk_refund_cancellation FOREIGN KEY (Cancellation_ID) REFERENCES cancellation (Cancellation_ID),
    CONSTRAINT fk_refund_payment      FOREIGN KEY (Payment_ID)      REFERENCES payment (Payment_ID),
    CONSTRAINT chk_refund_amount CHECK (Refund_Amount >= 0),
    CONSTRAINT chk_refund_status CHECK (Refund_Status IN ('PROCESSED','PENDING'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='G4: refund calculated for each cancellation';

-- ---------------------------------------------------------------------------
-- fare_audit_log: written only by trg_fare_audit when a fare_rule row changes.
-- Fare_Rule_ID has NO foreign key on purpose (the audit history must survive any rule change).
-- ---------------------------------------------------------------------------
CREATE TABLE fare_audit_log (
    Audit_ID             INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    Fare_Rule_ID         INT UNSIGNED  NOT NULL,
    Old_Base_Fare_Per_Km DECIMAL(6,2)  NOT NULL,
    New_Base_Fare_Per_Km DECIMAL(6,2)  NOT NULL,
    Old_Min_Fare         DECIMAL(8,2)  NOT NULL,
    New_Min_Fare         DECIMAL(8,2)  NOT NULL,
    Changed_By           VARCHAR(100)  NOT NULL,
    Changed_At           DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (Audit_ID),
    KEY idx_fare_audit_log_fare_rule_id (Fare_Rule_ID),
    KEY idx_fare_audit_log_changed_at (Changed_At)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='G4: audit trail of fare rule changes (no FK, written by trg_fare_audit)';
