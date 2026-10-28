# Module Report: Payment, Cancellation & Refund Management (Group 4)

National Railway Reservation & Management System, PICT E&TCE. Database: MySQL 8.0 `railway_db`. Backend: Spring Boot 3.3.5. Frontend: React 18.

## 1. Module overview and scope

Group 4 handles the money side of a ticket: what it costs, how it is paid, and how much comes back after a cancellation. The module owns seven tables (`fare_rule`, `concession_rule`, `refund_rule`, `payment`, `cancellation`, `refund`, `fare_audit_log`), three functions, three procedures, three triggers, two views, thirteen REST endpoints and four React screens.

**Fare pipeline.** A fare is built in four steps: distance, base fare, concession, net fare.

1. `fn_distance_km` (Group 1) returns the kilometres between the two stations on the train's route.
2. `fn_base_fare` multiplies the distance by the class rate, but never goes below the class minimum fare.
3. `fn_effective_concession` (Group 2) decides the concession from the date of birth (child, senior) or the declared type.
4. `fn_net_fare` applies the discount percentage from `concession_rule`.

Example: Mumbai CSMT to Pune is 192 km. In SL, 192 x 0.55 = 105.60 is below the minimum, so the base fare is 120.00. A senior citizen (40%) pays 72.00.

Out of scope: trains and routes (G1), users (G2), seats and booking creation (G3), reports (G5).

## 2. ER diagram

The Mermaid diagram is in `docs/g4/er.mmd`. In words:

- **fare_rule**: one row per travel class with the rate per km and the minimum fare. It has a 1:1 relationship with `coach_type` through `Class_Code`.
- **concession_rule**: a lookup of discount percent per concession type. It is matched by the text value, not by a foreign key, because passengers store the type as text.
- **refund_rule**: a lookup of cancellation time bands (hours before departure) and the deduction percent for each band.
- **payment**: one attempt to pay for a booking. One booking has many payments (1:N), for example a failed attempt followed by a successful one.
- **cancellation**: records one cancelled passenger. One `booking_passenger` has zero or one cancellation (1:0..1).
- **refund**: money returned for a cancellation. One cancellation has zero or one refund (1:0..1). One payment can have many refunds (1:N), because each passenger of a booking can be cancelled separately.
- **fare_audit_log**: history of fare changes. One fare rule has many audit rows (1:N), but there is deliberately no foreign key so the history survives any later change.

## 3. Normalization

| Table | 1NF | 2NF | 3NF |
|---|---|---|---|
| fare_rule | Atomic values, one row per class | Single-column PK, no partial dependency | Rate and minimum depend only on the rule |
| concession_rule | One discount per type | Single-column PK | Percent and description depend only on the type |
| refund_rule | One band per row | Single-column PK | Deduction depends only on the band |
| payment | One attempt per row | Single-column PK | Status, mode and ids describe the attempt only |
| cancellation | One cancelled passenger per row | Single-column PK | Reason and time describe the cancellation only |
| refund | One refund per cancellation | Single-column PK | Amounts depend on the refund (see below) |
| fare_audit_log | One change per row | Single-column PK | Old and new values describe one change |

**Deliberate denormalization.** `refund.Original_Fare`, `Deduction_Percent` and `Deduction_Amount` copy values that could be recomputed. `cancellation.Hours_Before_Departure` and `payment.Amount` are copies too. They are stored because rules and fares change over time, and a refund or payment must keep the numbers that were true on the day. `fare_audit_log` stores old and new values for the same reason.

## 4. Constraints

| Table | PK | FK | UNIQUE | CHECK | NOT NULL highlights |
|---|---|---|---|---|---|
| fare_rule | Fare_Rule_ID | Class_Code to coach_type | Class_Code | rate > 0, minimum >= 0 | Class_Code, rate, minimum |
| concession_rule | Concession_Rule_ID | none | Concession_Type | type in list, percent 0..100 | type, percent |
| refund_rule | Refund_Rule_ID | none | Min_Hours_Before | hours >= 0, percent 0..100 | Min_Hours_Before, percent |
| payment | Payment_ID | Booking_ID to booking | Gateway_Order_ID | Amount > 0, mode, status lists | Booking_ID, Amount, mode, status |
| cancellation | Cancellation_ID | Booking_Passenger_ID | Booking_Passenger_ID | none | passenger, hours |
| refund | Refund_ID | Cancellation_ID, Payment_ID | Cancellation_ID | Refund_Amount >= 0, status list | all amounts, status |
| fare_audit_log | Audit_ID | none (logical) | none | none | old and new values, Changed_By |

## 5. Indexes

| Index | Query it serves |
|---|---|
| UNIQUE Class_Code on fare_rule | `fn_base_fare` finds the rule of a class |
| UNIQUE Concession_Type on concession_rule | `fn_net_fare` finds the discount |
| UNIQUE Min_Hours_Before on refund_rule | `fn_refund_deduction_pct` range lookup; stops two bands starting at the same hour |
| `idx_payment_booking_id` | latest SUCCESS payment of a booking in `sp_cancel_ticket`; `v_payment_history` join |
| UNIQUE Gateway_Order_ID on payment | find a payment by gateway order; no duplicate orders |
| UNIQUE Booking_Passenger_ID on cancellation | a passenger cannot be cancelled twice; join in `v_refund_summary` |
| UNIQUE Cancellation_ID on refund | one refund per cancellation; join in `v_refund_summary` |

## 6. Functions, procedures, triggers, views

**Data-driven refund tiers.** Refund percentages are not written in code. `refund_rule` holds the bands (48 h or more: 10%, 12 to 48 h: 25%, 4 to 12 h: 50%, under 4 h: 100%). An administrator can change a band without touching Java or SQL.

### Functions

**fn_base_fare(p_class_code, p_distance_km)** returns DECIMAL(10,2). Purpose: price a distance. Logic: read the class row in `fare_rule`; compute `ROUND(distance x rate, 2)`; return the larger of that and `Min_Fare`; NULL when no rule exists. Example: `SELECT fn_base_fare('SL', 192);` returns `120.00`.

**fn_net_fare(p_base_fare, p_concession_type)** returns DECIMAL(10,2). Purpose: apply a concession. Logic: look up `Discount_Percent`; use 0 if the type is missing; return `ROUND(base x (1 - percent/100), 2)`. Example: `SELECT fn_net_fare(120.00, 'SENIOR');` returns `72.00`.

**fn_refund_deduction_pct(p_hours_before)** returns DECIMAL(5,2). Purpose: pick the deduction for a cancellation time. Logic: find the `refund_rule` row where `Min_Hours_Before <= hours` and the hours are below `Max_Hours_Before` (or the maximum is NULL); return its percent; return 100 if no row matches. Example: `SELECT fn_refund_deduction_pct(6);` returns `50.00`.

### Procedures

**sp_create_payment(p_user_id, p_booking_id, p_mode, p_gateway_order_id)**. Purpose: open a payment for a booking. Logic: load the booking (`BOOKING_NOT_FOUND`); check the owner (`NOT_OWNER`); check it is `PENDING_PAYMENT` (`PAYMENT_NOT_ALLOWED`); insert a `payment` row with the booking's `Total_Fare` and status `CREATED`. Example: `CALL sp_create_payment(3, 1, 'MOCK', 'MOCK_a1b2');` returns `Payment_ID = 1, Amount = 192.00`.

**sp_confirm_payment(p_payment_id, p_gateway_payment_id, p_success)**. Purpose: record the gateway result. Logic: the payment must be `CREATED` (`PAYMENT_NOT_ALLOWED`); set `SUCCESS` or `FAILED`, `Paid_At` and `Gateway_Payment_ID`; the trigger confirms the booking. Example: `CALL sp_confirm_payment(1, 'MOCK_PAY_1', 1);` returns `SUCCESS, CONFIRMED`.

**sp_cancel_ticket(p_user_id, p_booking_passenger_id)**. Purpose: cancel one passenger and compute the refund. Logic: validate the passenger, owner and status; compute hours to departure from `fn_departure_datetime` (negative means `CANCEL_NOT_ALLOWED`); lock inventory then passenger; get the deduction percent and refund; insert `cancellation`; set the passenger `CANCELLED`; delete the seat; insert `refund` when the booking was paid; call `sp_promote_rac_wl`; mark the booking `CANCELLED` if everyone is cancelled. Example: `CALL sp_cancel_ticket(3, 1);` returns `Cancellation_ID 1, Original_Fare 120.00, Deduction_Percent 10.00, Refund_Amount 108.00, Promoted_Count 0`.

### Triggers

**trg_fare_audit** (AFTER UPDATE on `fare_rule`). If the rate or the minimum changed, it inserts an audit row with old values, new values, `USER()` and the time. Example: `UPDATE fare_rule SET Base_Fare_Per_Km = 0.60 WHERE Fare_Rule_ID = 1;` adds one row with old 0.55 and new 0.60.

**trg_payment_confirm** (AFTER UPDATE on `payment`). When the status becomes `SUCCESS`, it sets the booking to `CONFIRMED`. Example: confirming payment 1 changes booking 1 from `PENDING_PAYMENT` to `CONFIRMED`.

**trg_refund_check** (BEFORE INSERT on `refund`). If `Refund_Amount > Original_Fare` it raises `REFUND_EXCEEDS_FARE`. Example: inserting a refund of 130.00 on a 120.00 fare fails with that error.

### Views

**v_payment_history** (User_ID, Payment_ID, Booking_ID, PNR, Amount, Payment_Mode, Payment_Status, Created_At, Paid_At). Joins `payment` and `booking`. Example: `SELECT * FROM v_payment_history WHERE User_ID = 3;` returns one row with amount 192.00, mode MOCK, status SUCCESS.

**v_refund_summary** (User_ID, Cancellation_ID, PNR, Passenger_Name, Original_Fare, Deduction_Percent, Deduction_Amount, Refund_Amount, Refund_Status, Cancelled_At). Joins `refund`, `cancellation`, `booking_passenger`, `passenger` and `booking`. Example: for user 3 it returns Asha Patil, 120.00, 10.00, 12.00, 108.00, PROCESSED.

## 7. Transactions, ACID and locking

`sp_cancel_ticket` is the main transaction. Atomicity: the cancellation, status change, seat release, refund and promotions commit together or not at all, because an exit handler rolls back and re-raises any error. Consistency: CHECK constraints, `trg_refund_check` and the rule that only triggers change `seat_inventory` counters keep the data valid. Isolation: locks follow the project order seat_inventory, booking, booking_passenger, then seat_allocation or payment, using `SELECT ... FOR UPDATE`. Two simultaneous cancels of the same passenger therefore queue, and the second sees `CANCELLED` after re-checking. Durability comes from InnoDB.

`sp_confirm_payment` updates the payment and the trigger updates the booking inside the same transaction, so a payment never succeeds while its booking stays pending. Spring methods that call these procedures are not `@Transactional`, because the procedures manage their own transactions.

## 8. Backend design and endpoint summary

Package `com.railway.payment` with `controller`, `service` and `dto`. Classes start with Payment, Fare, Cancellation or Refund. The code is SQL-first: services call procedures, functions and views through `SqlHelper`, with no JPA. Request DTOs are records with validation. Errors raised by SQL (`CODE: text`) are mapped by `GlobalExceptionHandler`.

| Method and path | Access | Purpose |
|---|---|---|
| GET /fares/quote | logged in | price a trip using the functions |
| POST /payments/orders | logged in | create a payment (OTP checked) |
| POST /payments/verify | logged in | verify a Razorpay payment |
| POST /payments/mock-confirm | logged in | confirm in MOCK mode |
| GET /payments/my | logged in | own payments |
| GET /refunds/my | logged in | own refunds |
| GET /cancellations/preview | logged in | estimate a refund |
| POST /cancellations | logged in | cancel a passenger |
| GET, PUT /admin/fare-rules | ADMIN | read or change fares |
| GET, PUT /admin/concession-rules | ADMIN | read or change discounts |
| GET /admin/fare-audit | ADMIN | fare change history |

**OTP-protected payment flow.** The passenger asks `POST /auth/payment-otp` for a five-minute, single-use code. `POST /payments/orders` sends `otpChallengeId` and `otp`; the service verifies them through `OtpVerifier` (purpose PAYMENT) and only then calls `sp_create_payment`. This check is required while `app.auth.require-payment-otp` is true. In dev mode the response includes `devOtp`.

**MOCK mode versus Razorpay test mode.** With `app.payment.mode=MOCK` the order id is `MOCK_` plus a UUID and no gateway is called; the demo user confirms with `/payments/mock-confirm`. With `RAZORPAY` the backend uses the test keys from configuration, returns `razorpayKeyId`, and `/payments/verify` accepts the payment only if the HMAC-SHA256 of `orderId|paymentId` made with the key secret equals the signature. Both modes end in `sp_confirm_payment`.

## 9. Frontend screens

Files live in `src/modules/payments/`.

- **/payment/:bookingId**: shows the booking and amount, requests the OTP, takes the OTP, creates the order and confirms (MOCK) or opens Razorpay Checkout; on success it goes to `/tickets/:pnr`.
- **/cancel/:bookingPassengerId**: shows the refund preview (fare, hours, deduction, estimated refund), asks for a reason and cancels.
- **/payments/history**: tables for own payments and own refunds.
- **/admin/fares** (ADMIN): edit fare and concession rules and read the audit log.

## 10. Test cases

| ID | Objective | Input | Expected | Actual | Screenshot |
|---|---|---|---|---|---|
| T01 | Fare quote | runId, SL, CSMT to Pune, passengers 1,2 | distance 192; total 192.00 | | |
| T02 | Create order with valid OTP | booking id, challenge id, devOtp | payment CREATED, amount = total fare | | |
| T03 | Wrong OTP | wrong code | 401 OTP_INVALID | | |
| T04 | Mock-confirm success | paymentId, success true | SUCCESS, booking CONFIRMED | | |
| T05 | Pay a confirmed booking | same booking again | 409 PAYMENT_NOT_ALLOWED | | |
| T06 | Cancellation preview | passenger 1, more than 48 h before | 10% deduction, refund 108.00 | | |
| T07 | Cancel a paid ticket | passenger 1 | refund row, seat released | | |
| T08 | Cancel twice | same passenger | 409 ALREADY_CANCELLED | | |
| T09 | Cancel another user's ticket | other user's token | 403 NOT_OWNER | | |
| T10 | Non-admin changes fare | passenger token on PUT fare rule | 403 FORBIDDEN | | |
| T11 | Fare audit trigger | admin changes SL rate | one `fare_audit_log` row | | |
| T12 | RAC promotion | cancel a CNF seat with an RAC passenger waiting | Promoted_Count 1 | | |
| T13 | Refund above fare | SQL insert of refund > fare | REFUND_EXCEEDS_FARE | | |

## 11. Integration points with other groups

- **Group 1**: `fn_distance_km` and `fn_departure_datetime` feed the fare and the hours before departure; `train_run` identifies the journey.
- **Group 2**: JWT identifies the user; `fn_effective_concession` and `passenger` give the concession; `OtpVerifier` and `/auth/payment-otp` provide the payment OTP.
- **Group 3**: `sp_book_ticket` prices each passenger with `fn_base_fare` and `fn_net_fare`. **Cancel and promote contract**: `sp_cancel_ticket` may update `booking_passenger.Status` and `booking.Booking_Status`, delete `seat_allocation` rows, and must then `CALL sp_promote_rac_wl` while holding the inventory lock. It never edits `seat_inventory`; G3 triggers do the counting. `trg_payment_confirm` confirms bookings that G3 created.
- **Group 5**: revenue reports read payments with status `SUCCESS`.

## 12. Assumptions and limitations

- MOCK mode is the default; no real money moves, and refunds are only recorded in the database (`PROCESSED`), not sent back through Razorpay.
- Refunds are per passenger and use the departure time at the boarding station.
- An unpaid booking cancels with refund 0 and no refund row.
- Rule changes affect only future bookings and cancellations; stored fares stay unchanged.
- A booking may have several payment attempts, but only one can succeed.
- This report follows the contract; adjust wording if the final code differs.
