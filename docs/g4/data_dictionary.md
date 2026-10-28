# G4 Data Dictionary - Payment, Cancellation & Refund

Schema file: `db/04_schema_g4.sql` (MySQL 8.0, InnoDB, utf8mb4). Seven tables.

Legend: **PK** = primary key, **UQ** = unique, **FK** = foreign key, **IDX** = index.
All `*_ID` primary keys are `INT UNSIGNED AUTO_INCREMENT`. Money columns are `DECIMAL`, so there are no floating-point rounding errors.

## Why concession and refund rules are data tables

The discount for a senior citizen, the fare per km of a class, or the deduction for a late cancellation are **business rules**, and business rules change (a new government order, a new fare notification). If these numbers were written inside a function, every change would need a code edit, a new deployment and fresh testing.

Instead, the rules live in the tables `fare_rule`, `concession_rule` and `refund_rule`:

- The functions (`fn_base_fare`, `fn_net_fare`, `fn_refund_deduction_pct`) only **read** these tables, so they never need to change.
- An administrator changes a rule with a simple `UPDATE` (for fares, through `PUT /admin/fare-rules/{id}`), and the next booking or cancellation automatically uses the new value.
- Fare changes are recorded by the trigger `trg_fare_audit` in `fare_audit_log`, so every change is traceable (who, when, old value, new value).
- The refund bands are rows, so a new band (for example 72+ hours before departure) is just one `INSERT`.

## fare_rule
Pricing rule per travel class. Exactly one row per class. Read by `fn_base_fare`; updates are audited by `trg_fare_audit`.

| Field | Type | Null | Key | Default | Description |
|---|---|---|---|---|---|
| Fare_Rule_ID | INT UNSIGNED | NO | PK | AUTO_INCREMENT | Unique id of the fare rule |
| Class_Code | VARCHAR(3) | NO | UQ, FK -> coach_type(Class_Code) | none | Travel class (SL, 3A, 2A, 1A, CC); one rule per class |
| Base_Fare_Per_Km | DECIMAL(6,2) | NO | | none | Rupees charged per km; CHECK > 0 |
| Min_Fare | DECIMAL(8,2) | NO | | none | Minimum fare for any journey in this class; CHECK >= 0 |
| Updated_At | DATETIME | NO | | CURRENT_TIMESTAMP, refreshed ON UPDATE | Time of the last change to this row |

Constraints and indexes: `uq_fare_rule_class_code` (UQ on Class_Code), `fk_fare_rule_coach_type`, `chk_fare_rule_base_fare`, `chk_fare_rule_min_fare`.

## concession_rule
Discount percentage for each concession type. Read by `fn_net_fare` (an unknown type means 0% discount).

| Field | Type | Null | Key | Default | Description |
|---|---|---|---|---|---|
| Concession_Rule_ID | INT UNSIGNED | NO | PK | AUTO_INCREMENT | Unique id of the concession rule |
| Concession_Type | VARCHAR(10) | NO | UQ | none | One of NONE, SENIOR, GOVT, SOLDIER, CHILD (CHECK); one rule per type |
| Discount_Percent | DECIMAL(5,2) | NO | | none | Discount on the base fare; CHECK between 0 and 100 |
| Description | VARCHAR(100) | YES | | NULL | Human-readable explanation of the concession |

Constraints and indexes: `uq_concession_rule_type`, `chk_concession_rule_type`, `chk_concession_rule_discount`.

## refund_rule
Cancellation deduction by how many hours remain before departure. A rule applies when `Min_Hours_Before <= hours < Max_Hours_Before`. Read by `fn_refund_deduction_pct`, which returns 100% if no band matches.

| Field | Type | Null | Key | Default | Description |
|---|---|---|---|---|---|
| Refund_Rule_ID | INT UNSIGNED | NO | PK | AUTO_INCREMENT | Unique id of the refund rule |
| Min_Hours_Before | SMALLINT | NO | UQ | none | Lower limit of the band in hours (inclusive); CHECK >= 0 |
| Max_Hours_Before | SMALLINT | YES | | NULL | Upper limit of the band in hours (exclusive); NULL means no upper limit |
| Deduction_Percent | DECIMAL(5,2) | NO | | none | Percentage of the fare kept as cancellation charge; CHECK between 0 and 100 |

Constraints and indexes: `uq_refund_rule_min_hours`, `chk_refund_rule_min_hours`, `chk_refund_rule_deduction`.

## payment
One payment attempt for a booking. A booking may have several attempts (for example one FAILED, then one SUCCESS). When a payment becomes SUCCESS, `trg_payment_confirm` marks the booking CONFIRMED.

| Field | Type | Null | Key | Default | Description |
|---|---|---|---|---|---|
| Payment_ID | INT UNSIGNED | NO | PK | AUTO_INCREMENT | Unique id of the payment attempt |
| Booking_ID | INT UNSIGNED | NO | FK -> booking(Booking_ID), IDX | none | Booking being paid for |
| Amount | DECIMAL(10,2) | NO | | none | Amount in rupees (the booking's Total_Fare); CHECK > 0 |
| Payment_Mode | VARCHAR(10) | NO | | none | RAZORPAY or MOCK (CHECK) |
| Gateway_Order_ID | VARCHAR(60) | YES | UQ | NULL | Gateway order id (Razorpay order id, or "MOCK_" + uuid); unique when present |
| Gateway_Payment_ID | VARCHAR(60) | YES | | NULL | Gateway payment id, filled when the payment is confirmed |
| Payment_Status | VARCHAR(10) | NO | | 'CREATED' | CREATED, SUCCESS or FAILED (CHECK) |
| Created_At | DATETIME | NO | | CURRENT_TIMESTAMP | When the attempt was created |
| Paid_At | DATETIME | YES | | NULL | When the payment was confirmed; NULL until then |

Constraints and indexes: `uq_payment_gateway_order_id`, `idx_payment_booking_id`, `fk_payment_booking`, `chk_payment_amount`, `chk_payment_mode`, `chk_payment_status`.

## cancellation
One row for each cancelled passenger. The UNIQUE key on `Booking_Passenger_ID` makes it impossible to cancel the same passenger twice.

| Field | Type | Null | Key | Default | Description |
|---|---|---|---|---|---|
| Cancellation_ID | INT UNSIGNED | NO | PK | AUTO_INCREMENT | Unique id of the cancellation |
| Booking_Passenger_ID | INT UNSIGNED | NO | UQ, FK -> booking_passenger(Booking_Passenger_ID) | none | The passenger ticket that was cancelled |
| Hours_Before_Departure | DECIMAL(8,2) | NO | | none | Hours between the cancellation and the departure; decides the deduction band |
| Reason | VARCHAR(100) | YES | | NULL | Reason entered by the user |
| Cancelled_At | DATETIME | NO | | CURRENT_TIMESTAMP | When the cancellation was made |

Constraints and indexes: `uq_cancellation_booking_passenger_id`, `fk_cancellation_booking_passenger`.

## refund
The refund calculated for one cancellation. Because a payment covers the whole booking, one payment can have many refunds (one for each cancelled passenger). `trg_refund_check` rejects a refund larger than the original fare.

| Field | Type | Null | Key | Default | Description |
|---|---|---|---|---|---|
| Refund_ID | INT UNSIGNED | NO | PK | AUTO_INCREMENT | Unique id of the refund |
| Cancellation_ID | INT UNSIGNED | NO | UQ, FK -> cancellation(Cancellation_ID) | none | Cancellation that caused this refund; one refund per cancellation |
| Payment_ID | INT UNSIGNED | NO | FK -> payment(Payment_ID), IDX | none | Successful payment the money is returned against |
| Original_Fare | DECIMAL(10,2) | NO | | none | Fare paid for the cancelled passenger |
| Deduction_Percent | DECIMAL(5,2) | NO | | none | Deduction percentage that was applied (copied from refund_rule at that time) |
| Deduction_Amount | DECIMAL(10,2) | NO | | none | Cancellation charge in rupees = Original_Fare x Deduction_Percent / 100 |
| Refund_Amount | DECIMAL(10,2) | NO | | none | Money returned = Original_Fare - Deduction_Amount; CHECK >= 0 |
| Refund_Status | VARCHAR(10) | NO | | 'PROCESSED' | PROCESSED or PENDING (CHECK) |
| Processed_At | DATETIME | NO | | CURRENT_TIMESTAMP | When the refund row was created |

Constraints and indexes: `uq_refund_cancellation_id`, `idx_refund_payment_id`, `fk_refund_cancellation`, `fk_refund_payment`, `chk_refund_amount`, `chk_refund_status`.

## fare_audit_log
History of fare rule changes. Written only by `trg_fare_audit` (AFTER UPDATE on `fare_rule`) when the rate or the minimum fare changes; read by `GET /admin/fare-audit`.

| Field | Type | Null | Key | Default | Description |
|---|---|---|---|---|---|
| Audit_ID | INT UNSIGNED | NO | PK | AUTO_INCREMENT | Unique id of the audit row |
| Fare_Rule_ID | INT UNSIGNED | NO | IDX (no FK) | none | Id of the fare rule that was changed; no foreign key so the history is never blocked or lost |
| Old_Base_Fare_Per_Km | DECIMAL(6,2) | NO | | none | Rate per km before the change |
| New_Base_Fare_Per_Km | DECIMAL(6,2) | NO | | none | Rate per km after the change |
| Old_Min_Fare | DECIMAL(8,2) | NO | | none | Minimum fare before the change |
| New_Min_Fare | DECIMAL(8,2) | NO | | none | Minimum fare after the change |
| Changed_By | VARCHAR(100) | NO | | none | Who made the change (database user or admin identity) |
| Changed_At | DATETIME | NO | IDX | CURRENT_TIMESTAMP | When the change was made |

Constraints and indexes: `idx_fare_audit_log_fare_rule_id`, `idx_fare_audit_log_changed_at`.

## Relationships (summary)

| Parent | Child | Cardinality | Enforced by |
|---|---|---|---|
| booking | payment | 1 : N | `fk_payment_booking` |
| booking_passenger | cancellation | 1 : 0..1 | `fk_cancellation_booking_passenger` + UQ |
| cancellation | refund | 1 : 0..1 | `fk_refund_cancellation` + UQ |
| payment | refund | 1 : N | `fk_refund_payment` |
| coach_type | fare_rule | 1 : 0..1 | `fk_fare_rule_coach_type` + UQ |
| fare_rule | fare_audit_log | 1 : N | logical only (no database FK) |
