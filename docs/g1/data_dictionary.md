# G1 Data Dictionary - Train, Station & Route

Database: `railway_db` (MySQL 8.0, InnoDB, utf8mb4). Source file: `db/01_schema_g1.sql`.
Key legend: **PK** = primary key, **FK** = foreign key, **UQ** = unique, **IDX** = plain index, **-** = none.
Composite unique keys are named in the "Constraints" line below each table.

## station

Master list of railway stations.

| Field | Type | Null | Key | Default | Description |
|---|---|---|---|---|---|
| Station_ID | INT UNSIGNED | NO | PK | AUTO_INCREMENT | Unique identifier of the station. |
| Station_Code | VARCHAR(5) | NO | UQ | - | Short unique station code such as PUNE or CSMT. |
| Station_Name | VARCHAR(80) | NO | - | - | Full public name of the station. |
| City | VARCHAR(60) | NO | - | - | City in which the station is located. |
| State | VARCHAR(60) | NO | - | - | State in which the station is located. |

Constraints: `uq_station_station_code (Station_Code)`.

## route

A named path from a source station to a destination station; the intermediate stops are stored in `route_stop`.

| Field | Type | Null | Key | Default | Description |
|---|---|---|---|---|---|
| Route_ID | INT UNSIGNED | NO | PK | AUTO_INCREMENT | Unique identifier of the route. |
| Route_Name | VARCHAR(100) | NO | UQ | - | Unique readable name of the route, for example "Mumbai CSMT - Pune Jn". |
| Source_Station_ID | INT UNSIGNED | NO | FK | - | Station (station.Station_ID) where the route begins. |
| Dest_Station_ID | INT UNSIGNED | NO | FK | - | Station (station.Station_ID) where the route ends. |

Constraints: `uq_route_route_name (Route_Name)`; `fk_route_station_source`; `fk_route_station_dest`; `chk_route_source_dest_differ` (source and destination must be different stations).

## route_stop

Ordered stops of a route with timings and distance from the route's source. The first stop has no arrival time and the last stop has no departure time.

| Field | Type | Null | Key | Default | Description |
|---|---|---|---|---|---|
| Route_Stop_ID | INT UNSIGNED | NO | PK | AUTO_INCREMENT | Unique identifier of the stop on a route. |
| Route_ID | INT UNSIGNED | NO | FK | - | Route (route.Route_ID) to which this stop belongs. |
| Station_ID | INT UNSIGNED | NO | FK | - | Station (station.Station_ID) where the train halts. |
| Stop_Seq | SMALLINT | NO | - | - | Position of the stop along the route, starting at 1. |
| Arrival_Time | TIME | YES | - | NULL | Scheduled arrival time at the stop; NULL for the first stop. |
| Departure_Time | TIME | YES | - | NULL | Scheduled departure time from the stop; NULL for the last stop. |
| Day_Offset | TINYINT | NO | - | 0 | Number of days since the journey started (0 to 3) at which this stop is reached. |
| Distance_From_Source_Km | SMALLINT | NO | - | 0 | Distance in kilometres from the route's first stop. |

Constraints: `uq_route_stop_route_id_stop_seq (Route_ID, Stop_Seq)`; `uq_route_stop_route_id_station_id (Route_ID, Station_ID)`; `idx_route_stop_station_id_route_id (Station_ID, Route_ID)`; `fk_route_stop_route`; `fk_route_stop_station`; `chk_route_stop_seq_min` (Stop_Seq >= 1); `chk_route_stop_day_offset` (0 to 3); `chk_route_stop_distance_min` (>= 0).

## coach_type

Catalogue of coach classes and the number of seats in one coach of each class.

| Field | Type | Null | Key | Default | Description |
|---|---|---|---|---|---|
| Coach_Type_ID | INT UNSIGNED | NO | PK | AUTO_INCREMENT | Unique identifier of the coach type. |
| Class_Code | VARCHAR(3) | NO | UQ | - | Class code, one of SL, 3A, 2A, 1A or CC (also referenced by seat_inventory and fare_rule). |
| Class_Name | VARCHAR(40) | NO | - | - | Readable class name such as "AC 3 Tier". |
| Seats_Per_Coach | SMALLINT | NO | - | - | Number of seats or berths in one coach of this type. |

Constraints: `uq_coach_type_class_code (Class_Code)`; `chk_coach_type_class_code` (allowed codes); `chk_coach_type_seats_positive` (> 0).

## train

A train identified by a 5-digit number that follows exactly one route.

| Field | Type | Null | Key | Default | Description |
|---|---|---|---|---|---|
| Train_ID | INT UNSIGNED | NO | PK | AUTO_INCREMENT | Unique identifier of the train. |
| Train_No | CHAR(5) | NO | UQ | - | Unique 5-digit public train number. |
| Train_Name | VARCHAR(80) | NO | - | - | Public name of the train. |
| Train_Type | VARCHAR(10) | NO | - | - | Service category: EXPRESS, SUPERFAST, RAJDHANI, SHATABDI or LOCAL. |
| Route_ID | INT UNSIGNED | NO | FK | - | Route (route.Route_ID) that the train follows. |
| Is_Active | TINYINT(1) | NO | - | 1 | Flag that is 1 while the train is in service and 0 when it is withdrawn. |

Constraints: `uq_train_train_no (Train_No)`; `fk_train_route`; `chk_train_no_format` (exactly 5 digits); `chk_train_type_values` (allowed types).

## train_schedule

Weekdays on which a train operates; one row per train and weekday.

| Field | Type | Null | Key | Default | Description |
|---|---|---|---|---|---|
| Schedule_ID | INT UNSIGNED | NO | PK | AUTO_INCREMENT | Unique identifier of the schedule entry. |
| Train_ID | INT UNSIGNED | NO | FK | - | Train (train.Train_ID) that runs on this weekday. |
| Day_Of_Week | TINYINT | NO | - | - | ISO weekday number from 1 (Monday) to 7 (Sunday). |

Constraints: `uq_train_schedule_train_id_day_of_week (Train_ID, Day_Of_Week)`; `fk_train_schedule_train`; `chk_train_schedule_day_of_week` (1 to 7).

## train_coach

A physical coach attached to a train.

| Field | Type | Null | Key | Default | Description |
|---|---|---|---|---|---|
| Coach_ID | INT UNSIGNED | NO | PK | AUTO_INCREMENT | Unique identifier of the coach. |
| Train_ID | INT UNSIGNED | NO | FK | - | Train (train.Train_ID) to which the coach is attached. |
| Coach_Type_ID | INT UNSIGNED | NO | FK | - | Coach type (coach_type.Coach_Type_ID) that defines class and seat count. |
| Coach_Number | VARCHAR(4) | NO | - | - | Label of the coach within the train, such as S1, B2 or C1. |

Constraints: `uq_train_coach_train_id_coach_number (Train_ID, Coach_Number)`; `fk_train_coach_train`; `fk_train_coach_coach_type`.

## seat

A single numbered seat or berth inside a coach.

| Field | Type | Null | Key | Default | Description |
|---|---|---|---|---|---|
| Seat_ID | INT UNSIGNED | NO | PK | AUTO_INCREMENT | Unique identifier of the seat. |
| Coach_ID | INT UNSIGNED | NO | FK | - | Coach (train_coach.Coach_ID) that contains the seat. |
| Seat_No | SMALLINT | NO | - | - | Seat number inside the coach, starting at 1. |
| Berth_Type | VARCHAR(2) | NO | - | - | Berth position: LB, MB, UB, SL, SU (sleeper berths) or W, M, A (window, middle, aisle). |

Constraints: `uq_seat_coach_id_seat_no (Coach_ID, Seat_No)`; `fk_seat_train_coach`; `chk_seat_no_positive` (> 0); `chk_seat_berth_type_values` (allowed berth codes).

## train_run

One departure of a train on a specific calendar date; seat inventory and bookings are attached to a run.

| Field | Type | Null | Key | Default | Description |
|---|---|---|---|---|---|
| Run_ID | INT UNSIGNED | NO | PK | AUTO_INCREMENT | Unique identifier of the run. |
| Train_ID | INT UNSIGNED | NO | FK | - | Train (train.Train_ID) that makes this run. |
| Journey_Date | DATE | NO | IDX | - | Calendar date on which the run starts at the route's source. |
| Created_At | DATETIME | NO | - | CURRENT_TIMESTAMP | Date and time at which the run row was created. |

Constraints: `uq_train_run_train_id_journey_date (Train_ID, Journey_Date)`; `idx_train_run_journey_date (Journey_Date)`; `fk_train_run_train`.

## route_stop_audit

Audit trail of arrival and departure time changes on `route_stop`, written by trigger `trg_route_stop_audit`. It has no foreign key so audit history is kept even if the stop is removed.

| Field | Type | Null | Key | Default | Description |
|---|---|---|---|---|---|
| Audit_ID | INT UNSIGNED | NO | PK | AUTO_INCREMENT | Unique identifier of the audit row. |
| Route_Stop_ID | INT UNSIGNED | NO | - | - | Id of the changed route stop (logical reference only, no foreign key). |
| Old_Arrival_Time | TIME | YES | - | NULL | Arrival time before the change. |
| New_Arrival_Time | TIME | YES | - | NULL | Arrival time after the change. |
| Old_Departure_Time | TIME | YES | - | NULL | Departure time before the change. |
| New_Departure_Time | TIME | YES | - | NULL | Departure time after the change. |
| Changed_At | DATETIME | NO | - | CURRENT_TIMESTAMP | Date and time at which the change was made. |
