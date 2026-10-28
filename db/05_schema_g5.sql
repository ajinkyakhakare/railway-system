-- Task G5.1 | Owner: Group 5 (Railway Operations & Analytics) | Purpose: schema for live train status, delay history and daily station revenue. Runs after 01_schema_g1.sql .. 04_schema_g4.sql (needs train_run and station from G1).

-- ---------------------------------------------------------------------------------------------
-- train_run_status: ONE row per train run holding its current live state (the "departure board").
-- Run_ID is both the primary key and a foreign key to train_run, which makes the relationship
-- strictly 1-to-1. The row is created automatically by trigger trg_run_init_status (status
-- 'SCHEDULED', delay 0) and later changed only through sp_update_train_status.
-- ---------------------------------------------------------------------------------------------
CREATE TABLE train_run_status (
    Run_ID             INT UNSIGNED NOT NULL,
    Status             VARCHAR(10)  NOT NULL DEFAULT 'SCHEDULED',
    Current_Station_ID INT UNSIGNED NULL,
    Delay_Minutes      INT          NOT NULL DEFAULT 0,
    Last_Reason        VARCHAR(100) NULL,
    Updated_At         DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (Run_ID),
    CONSTRAINT fk_train_run_status_train_run
        FOREIGN KEY (Run_ID) REFERENCES train_run (Run_ID),
    CONSTRAINT fk_train_run_status_station
        FOREIGN KEY (Current_Station_ID) REFERENCES station (Station_ID),
    CONSTRAINT chk_train_run_status_status
        CHECK (Status IN ('SCHEDULED', 'ON_TIME', 'DELAYED', 'CANCELLED', 'ARRIVED')),
    CONSTRAINT chk_train_run_status_delay
        CHECK (Delay_Minutes >= 0),
    INDEX idx_train_run_status_status (Status),
    INDEX idx_train_run_status_current_station_id (Current_Station_ID)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4
  COMMENT = 'G5: current live status and delay of each train run (1 row per train_run)';

-- ---------------------------------------------------------------------------------------------
-- delay_log: append-only history. A row is added by trigger trg_delay_log every time the
-- Delay_Minutes of a train_run_status row changes. Used for delay analytics (v_delay_metrics).
-- Station_ID is the station the train was at when the delay was reported (may be unknown).
-- ---------------------------------------------------------------------------------------------
CREATE TABLE delay_log (
    Delay_Log_ID  INT UNSIGNED NOT NULL AUTO_INCREMENT,
    Run_ID        INT UNSIGNED NOT NULL,
    Station_ID    INT UNSIGNED NULL,
    Delay_Minutes INT          NOT NULL,
    Reason        VARCHAR(100) NULL,
    Logged_At     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (Delay_Log_ID),
    CONSTRAINT fk_delay_log_train_run
        FOREIGN KEY (Run_ID) REFERENCES train_run (Run_ID),
    CONSTRAINT fk_delay_log_station
        FOREIGN KEY (Station_ID) REFERENCES station (Station_ID),
    CONSTRAINT chk_delay_log_delay
        CHECK (Delay_Minutes >= 0),
    INDEX idx_delay_log_run_id (Run_ID),
    INDEX idx_delay_log_station_id (Station_ID)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4
  COMMENT = 'G5: history of every delay change reported for a train run';

-- ---------------------------------------------------------------------------------------------
-- station_daily_revenue: pre-aggregated revenue per origin station per day. Filled by
-- sp_generate_daily_revenue (INSERT ... ON DUPLICATE KEY UPDATE), which is why the pair
-- (Station_ID, Revenue_Date) must be unique. It is a reporting snapshot; it has no foreign
-- key to payment or booking because it only stores totals.
-- ---------------------------------------------------------------------------------------------
CREATE TABLE station_daily_revenue (
    Revenue_ID    INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    Station_ID    INT UNSIGNED  NOT NULL,
    Revenue_Date  DATE          NOT NULL,
    Total_Revenue DECIMAL(12,2) NOT NULL,
    Ticket_Count  INT           NOT NULL,
    PRIMARY KEY (Revenue_ID),
    CONSTRAINT fk_station_daily_revenue_station
        FOREIGN KEY (Station_ID) REFERENCES station (Station_ID),
    CONSTRAINT uq_station_daily_revenue_station_date
        UNIQUE (Station_ID, Revenue_Date),
    INDEX idx_station_daily_revenue_revenue_date (Revenue_Date)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4
  COMMENT = 'G5: daily revenue and ticket count per origin station (report snapshot)';
