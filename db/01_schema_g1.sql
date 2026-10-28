-- Task G1.1 | Owner group: G1 (Train, Station & Route) | Purpose: schema for the 10 G1 tables (stations, routes, trains, coaches, seats, train runs).
-- Runs on MySQL 8.0 (InnoDB, utf8mb4) after db/00_database.sql. The database is rebuilt from scratch, so plain CREATE TABLE is used.

-- station: master list of railway stations (one row per station).
CREATE TABLE station (
  Station_ID   INT UNSIGNED NOT NULL AUTO_INCREMENT,
  Station_Code VARCHAR(5)   NOT NULL,
  Station_Name VARCHAR(80)  NOT NULL,
  City         VARCHAR(60)  NOT NULL,
  State        VARCHAR(60)  NOT NULL,
  PRIMARY KEY (Station_ID),
  CONSTRAINT uq_station_station_code UNIQUE (Station_Code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- route: a named path between a source and a destination station; its stops live in route_stop.
CREATE TABLE route (
  Route_ID          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  Route_Name        VARCHAR(100) NOT NULL,
  Source_Station_ID INT UNSIGNED NOT NULL,
  Dest_Station_ID   INT UNSIGNED NOT NULL,
  PRIMARY KEY (Route_ID),
  CONSTRAINT uq_route_route_name UNIQUE (Route_Name),
  CONSTRAINT fk_route_station_source FOREIGN KEY (Source_Station_ID) REFERENCES station (Station_ID),
  CONSTRAINT fk_route_station_dest   FOREIGN KEY (Dest_Station_ID)   REFERENCES station (Station_ID),
  CONSTRAINT chk_route_source_dest_differ CHECK (Source_Station_ID <> Dest_Station_ID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- route_stop: ordered list of stations on a route with timings and distance from the route's source.
-- First stop has Arrival_Time NULL, last stop has Departure_Time NULL; Day_Offset = days since the journey started.
CREATE TABLE route_stop (
  Route_Stop_ID           INT UNSIGNED NOT NULL AUTO_INCREMENT,
  Route_ID                INT UNSIGNED NOT NULL,
  Station_ID              INT UNSIGNED NOT NULL,
  Stop_Seq                SMALLINT     NOT NULL,
  Arrival_Time            TIME         NULL,
  Departure_Time          TIME         NULL,
  Day_Offset              TINYINT      NOT NULL DEFAULT 0,
  Distance_From_Source_Km SMALLINT     NOT NULL DEFAULT 0,
  PRIMARY KEY (Route_Stop_ID),
  CONSTRAINT uq_route_stop_route_id_stop_seq   UNIQUE (Route_ID, Stop_Seq),
  CONSTRAINT uq_route_stop_route_id_station_id UNIQUE (Route_ID, Station_ID),
  KEY idx_route_stop_station_id_route_id (Station_ID, Route_ID),
  CONSTRAINT fk_route_stop_route   FOREIGN KEY (Route_ID)   REFERENCES route (Route_ID),
  CONSTRAINT fk_route_stop_station FOREIGN KEY (Station_ID) REFERENCES station (Station_ID),
  CONSTRAINT chk_route_stop_seq_min      CHECK (Stop_Seq >= 1),
  CONSTRAINT chk_route_stop_day_offset   CHECK (Day_Offset BETWEEN 0 AND 3),
  CONSTRAINT chk_route_stop_distance_min CHECK (Distance_From_Source_Km >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- coach_type: catalogue of coach classes (SL, 3A, 2A, 1A, CC) and how many seats one coach holds.
CREATE TABLE coach_type (
  Coach_Type_ID   INT UNSIGNED NOT NULL AUTO_INCREMENT,
  Class_Code      VARCHAR(3)   NOT NULL,
  Class_Name      VARCHAR(40)  NOT NULL,
  Seats_Per_Coach SMALLINT     NOT NULL,
  PRIMARY KEY (Coach_Type_ID),
  CONSTRAINT uq_coach_type_class_code UNIQUE (Class_Code),
  CONSTRAINT chk_coach_type_class_code CHECK (Class_Code IN ('SL','3A','2A','1A','CC')),
  CONSTRAINT chk_coach_type_seats_positive CHECK (Seats_Per_Coach > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- train: a named train (5-digit number) that follows one route; Is_Active = 0 hides it from search.
CREATE TABLE train (
  Train_ID   INT UNSIGNED NOT NULL AUTO_INCREMENT,
  Train_No   CHAR(5)      NOT NULL,
  Train_Name VARCHAR(80)  NOT NULL,
  Train_Type VARCHAR(10)  NOT NULL,
  Route_ID   INT UNSIGNED NOT NULL,
  Is_Active  TINYINT(1)   NOT NULL DEFAULT 1,
  PRIMARY KEY (Train_ID),
  CONSTRAINT uq_train_train_no UNIQUE (Train_No),
  CONSTRAINT fk_train_route FOREIGN KEY (Route_ID) REFERENCES route (Route_ID),
  CONSTRAINT chk_train_no_format CHECK (Train_No REGEXP '^[0-9]{5}$'),
  CONSTRAINT chk_train_type_values CHECK (Train_Type IN ('EXPRESS','SUPERFAST','RAJDHANI','SHATABDI','LOCAL'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- train_schedule: the ISO weekdays (1=Mon .. 7=Sun) on which a train runs.
CREATE TABLE train_schedule (
  Schedule_ID  INT UNSIGNED NOT NULL AUTO_INCREMENT,
  Train_ID     INT UNSIGNED NOT NULL,
  Day_Of_Week  TINYINT      NOT NULL,
  PRIMARY KEY (Schedule_ID),
  CONSTRAINT uq_train_schedule_train_id_day_of_week UNIQUE (Train_ID, Day_Of_Week),
  CONSTRAINT fk_train_schedule_train FOREIGN KEY (Train_ID) REFERENCES train (Train_ID),
  CONSTRAINT chk_train_schedule_day_of_week CHECK (Day_Of_Week BETWEEN 1 AND 7)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- train_coach: one physical coach attached to a train (for example S1 of class SL).
CREATE TABLE train_coach (
  Coach_ID      INT UNSIGNED NOT NULL AUTO_INCREMENT,
  Train_ID      INT UNSIGNED NOT NULL,
  Coach_Type_ID INT UNSIGNED NOT NULL,
  Coach_Number  VARCHAR(4)   NOT NULL,
  PRIMARY KEY (Coach_ID),
  CONSTRAINT uq_train_coach_train_id_coach_number UNIQUE (Train_ID, Coach_Number),
  CONSTRAINT fk_train_coach_train      FOREIGN KEY (Train_ID)      REFERENCES train (Train_ID),
  CONSTRAINT fk_train_coach_coach_type FOREIGN KEY (Coach_Type_ID) REFERENCES coach_type (Coach_Type_ID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- seat: one numbered seat or berth inside a coach.
CREATE TABLE seat (
  Seat_ID    INT UNSIGNED NOT NULL AUTO_INCREMENT,
  Coach_ID   INT UNSIGNED NOT NULL,
  Seat_No    SMALLINT     NOT NULL,
  Berth_Type VARCHAR(2)   NOT NULL,
  PRIMARY KEY (Seat_ID),
  CONSTRAINT uq_seat_coach_id_seat_no UNIQUE (Coach_ID, Seat_No),
  CONSTRAINT fk_seat_train_coach FOREIGN KEY (Coach_ID) REFERENCES train_coach (Coach_ID),
  CONSTRAINT chk_seat_no_positive CHECK (Seat_No > 0),
  CONSTRAINT chk_seat_berth_type_values CHECK (Berth_Type IN ('LB','MB','UB','SL','SU','W','M','A'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- train_run: one departure of a train on a calendar date; seat inventory and bookings attach to a run.
CREATE TABLE train_run (
  Run_ID       INT UNSIGNED NOT NULL AUTO_INCREMENT,
  Train_ID     INT UNSIGNED NOT NULL,
  Journey_Date DATE         NOT NULL,
  Created_At   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (Run_ID),
  CONSTRAINT uq_train_run_train_id_journey_date UNIQUE (Train_ID, Journey_Date),
  KEY idx_train_run_journey_date (Journey_Date),
  CONSTRAINT fk_train_run_train FOREIGN KEY (Train_ID) REFERENCES train (Train_ID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- route_stop_audit: history of timetable changes on route_stop, filled by trigger trg_route_stop_audit.
-- Route_Stop_ID is a logical reference only (no foreign key) so audit rows survive later deletes.
CREATE TABLE route_stop_audit (
  Audit_ID            INT UNSIGNED NOT NULL AUTO_INCREMENT,
  Route_Stop_ID       INT UNSIGNED NOT NULL,
  Old_Arrival_Time    TIME         NULL,
  New_Arrival_Time    TIME         NULL,
  Old_Departure_Time  TIME         NULL,
  New_Departure_Time  TIME         NULL,
  Changed_At          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (Audit_ID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
