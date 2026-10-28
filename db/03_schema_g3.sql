-- Task G3.1 | Owner: G3 Reservation & Seat | Purpose: schema (tables, keys, checks, indexes) for the 5 G3 tables: seat_inventory, booking, booking_passenger, seat_allocation, booking_status_history.
-- Runs after db/01_schema_g1.sql (train_run, station, seat, coach_type) and db/02_schema_g2.sql (app_user, passenger).
-- MySQL 8.0, InnoDB, utf8mb4. The database is rebuilt from scratch, so plain CREATE TABLE is used.
-- Naming: fk_<child>_<parent>, uq_<table>_<cols>, chk_<table>_<rule>, idx_<table>_<cols>.

-- ---------------------------------------------------------------------------
-- seat_inventory: one row per (train run, class). Holds the live seat counters.
-- The counters Available_CNF, RAC_Count and WL_Count are changed ONLY by triggers
-- (trg_dec_inventory, trg_adjust_inventory_on_status). The row is created by
-- trg_run_init_inventory when a train_run is inserted.
-- chk_seat_inventory_counters is the last line of defence against overbooking:
-- even a buggy procedure cannot push a counter below 0 or above its limit.
-- ---------------------------------------------------------------------------
CREATE TABLE seat_inventory (
    Inventory_ID  INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    Run_ID        INT UNSIGNED  NOT NULL,
    Class_Code    VARCHAR(3)    NOT NULL,
    Total_Seats   SMALLINT      NOT NULL,
    Available_CNF SMALLINT      NOT NULL,
    RAC_Count     SMALLINT      NOT NULL DEFAULT 0,
    WL_Count      SMALLINT      NOT NULL DEFAULT 0,
    Max_RAC       SMALLINT      NOT NULL,
    Max_WL        SMALLINT      NOT NULL,
    PRIMARY KEY (Inventory_ID),
    CONSTRAINT uq_seat_inventory_run_class UNIQUE (Run_ID, Class_Code),
    CONSTRAINT fk_seat_inventory_train_run FOREIGN KEY (Run_ID)
        REFERENCES train_run (Run_ID),
    CONSTRAINT fk_seat_inventory_coach_type FOREIGN KEY (Class_Code)
        REFERENCES coach_type (Class_Code),
    CONSTRAINT chk_seat_inventory_counters CHECK (
        Available_CNF BETWEEN 0 AND Total_Seats
        AND RAC_Count BETWEEN 0 AND Max_RAC
        AND WL_Count BETWEEN 0 AND Max_WL
    )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='G3: live seat counters (CNF/RAC/WL) per train run and class; counters changed only by triggers';

-- ---------------------------------------------------------------------------
-- booking: one ticket (PNR) booked by a user for one run, one class and one
-- journey (From -> To). Created by sp_book_ticket as PENDING_PAYMENT; set to
-- CONFIRMED by trg_payment_confirm; CANCELLED / EXPIRED by cancellation or expiry.
-- Class_Code is deliberately not a foreign key (the contract defines none); it is
-- validated by sp_book_ticket through the seat_inventory lookup.
-- ---------------------------------------------------------------------------
CREATE TABLE booking (
    Booking_ID      INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    PNR             CHAR(10)      NOT NULL,
    User_ID         INT UNSIGNED  NOT NULL,
    Run_ID          INT UNSIGNED  NOT NULL,
    Class_Code      VARCHAR(3)    NOT NULL,
    From_Station_ID INT UNSIGNED  NOT NULL,
    To_Station_ID   INT UNSIGNED  NOT NULL,
    Booking_Status  VARCHAR(16)   NOT NULL DEFAULT 'PENDING_PAYMENT',
    Total_Fare      DECIMAL(10,2) NOT NULL DEFAULT 0,
    Booked_At       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (Booking_ID),
    CONSTRAINT uq_booking_pnr UNIQUE (PNR),
    CONSTRAINT fk_booking_app_user FOREIGN KEY (User_ID)
        REFERENCES app_user (User_ID),
    CONSTRAINT fk_booking_train_run FOREIGN KEY (Run_ID)
        REFERENCES train_run (Run_ID),
    CONSTRAINT fk_booking_station_from FOREIGN KEY (From_Station_ID)
        REFERENCES station (Station_ID),
    CONSTRAINT fk_booking_station_to FOREIGN KEY (To_Station_ID)
        REFERENCES station (Station_ID),
    CONSTRAINT chk_booking_status CHECK (
        Booking_Status IN ('PENDING_PAYMENT','CONFIRMED','CANCELLED','EXPIRED')
    ),
    CONSTRAINT chk_booking_stations CHECK (From_Station_ID <> To_Station_ID),
    INDEX idx_booking_user_id (User_ID),
    INDEX idx_booking_run_id (Run_ID),
    -- helps sp_expire_unpaid_bookings find old PENDING_PAYMENT bookings quickly
    INDEX idx_booking_status_booked_at (Booking_Status, Booked_At)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='G3: one PNR per booking (user, run, class, from/to stations, status, total fare)';

-- ---------------------------------------------------------------------------
-- booking_passenger: one row per passenger on a booking. Status is CNF, RAC, WL
-- or CANCELLED. Inserts and status updates fire the inventory triggers.
-- Base_Fare is the fare before concession; Fare_Amount is after concession.
-- Concession_Type is the effective concession applied (NONE, SENIOR, GOVT,
-- SOLDIER or CHILD), a snapshot taken at booking time.
-- ---------------------------------------------------------------------------
CREATE TABLE booking_passenger (
    Booking_Passenger_ID INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    Booking_ID           INT UNSIGNED  NOT NULL,
    Passenger_ID         INT UNSIGNED  NOT NULL,
    Status               VARCHAR(10)   NOT NULL,
    Base_Fare            DECIMAL(10,2) NOT NULL,
    Concession_Type      VARCHAR(10)   NOT NULL,
    Fare_Amount          DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (Booking_Passenger_ID),
    -- the same passenger cannot appear twice on one booking
    CONSTRAINT uq_booking_passenger_booking_passenger UNIQUE (Booking_ID, Passenger_ID),
    CONSTRAINT fk_booking_passenger_booking FOREIGN KEY (Booking_ID)
        REFERENCES booking (Booking_ID),
    CONSTRAINT fk_booking_passenger_passenger FOREIGN KEY (Passenger_ID)
        REFERENCES passenger (Passenger_ID),
    CONSTRAINT chk_booking_passenger_status CHECK (
        Status IN ('CNF','RAC','WL','CANCELLED')
    ),
    INDEX idx_booking_passenger_passenger_id (Passenger_ID),
    -- helps sp_promote_rac_wl find the oldest RAC / WL passenger
    INDEX idx_booking_passenger_status (Status, Booking_Passenger_ID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='G3: passengers of a booking with status (CNF/RAC/WL/CANCELLED) and fare';

-- ---------------------------------------------------------------------------
-- seat_allocation: the physical seat given to a CNF passenger on a run.
-- uq_seat_allocation_run_seat is the database-level guard against booking the
-- same seat twice on the same run. uq_seat_allocation_booking_passenger makes
-- the relationship with booking_passenger one-to-one.
-- ---------------------------------------------------------------------------
CREATE TABLE seat_allocation (
    Allocation_ID        INT UNSIGNED NOT NULL AUTO_INCREMENT,
    Run_ID               INT UNSIGNED NOT NULL,
    Seat_ID              INT UNSIGNED NOT NULL,
    Booking_Passenger_ID INT UNSIGNED NOT NULL,
    PRIMARY KEY (Allocation_ID),
    CONSTRAINT uq_seat_allocation_booking_passenger UNIQUE (Booking_Passenger_ID),
    CONSTRAINT uq_seat_allocation_run_seat UNIQUE (Run_ID, Seat_ID),
    CONSTRAINT fk_seat_allocation_train_run FOREIGN KEY (Run_ID)
        REFERENCES train_run (Run_ID),
    CONSTRAINT fk_seat_allocation_seat FOREIGN KEY (Seat_ID)
        REFERENCES seat (Seat_ID),
    CONSTRAINT fk_seat_allocation_booking_passenger FOREIGN KEY (Booking_Passenger_ID)
        REFERENCES booking_passenger (Booking_Passenger_ID),
    INDEX idx_seat_allocation_seat_id (Seat_ID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='G3: seat given to a confirmed passenger on a run; unique per run and seat (no double booking)';

-- ---------------------------------------------------------------------------
-- booking_status_history: audit trail of every Status change of a
-- booking_passenger. Written by trg_adjust_inventory_on_status.
-- Booking_Passenger_ID has no foreign key on purpose, so history rows are never
-- blocked by or lost with the passenger row.
-- ---------------------------------------------------------------------------
CREATE TABLE booking_status_history (
    History_ID           INT UNSIGNED NOT NULL AUTO_INCREMENT,
    Booking_Passenger_ID INT UNSIGNED NOT NULL,
    Old_Status           VARCHAR(10)  NULL,
    New_Status           VARCHAR(10)  NOT NULL,
    Changed_At           DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (History_ID),
    INDEX idx_booking_status_history_bp (Booking_Passenger_ID, Changed_At)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='G3: audit log of booking_passenger status changes (no foreign key by design)';
