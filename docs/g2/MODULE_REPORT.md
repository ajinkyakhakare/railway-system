# Module Report - Passenger & User Management (Group 2)

National Railway Reservation & Management System - PICT, E&TCE, DBMS project.
Stack: MySQL 8.0, Spring Boot 3.3.5, React 18.

## 1. Module overview and scope

Group 2 answers the questions "who is using the system?" and "who is travelling?". It keeps two different ideas apart:

- **User account** - a person who logs in (`app_user`), with a role such as PASSENGER, ADMIN or OPERATOR.
- **Passenger** - a traveller saved under an account (`passenger`). One account can hold many passengers, for example a mother saving her family.

Scope of the module:

- Registration, login, JWT tokens, role-based access control (RBAC).
- OTP-based two-factor authentication (2FA) for login (optional) and for payments (required by default).
- Account lockout after repeated wrong passwords.
- Profile editing and passenger (traveller) management.
- Admin screens: list users, change roles, activate or deactivate accounts.
- Audit tables for logins and role changes.

Trains, bookings, payments and reports belong to other groups (see section 11).

## 2. ER diagram

The diagram is in `docs/g2/er.mmd` (Mermaid `erDiagram`). In words:

| Entity | Meaning |
|---|---|
| `role` | The three roles: PASSENGER, ADMIN, OPERATOR. |
| `app_user` | One login account: e-mail, BCrypt hash, name, phone, active flag, lockout fields. |
| `user_role` | Link table that gives users roles. |
| `passenger` | A traveller saved by a user: name, date of birth, gender, declared concession. |
| `otp_challenge` | One generated OTP for LOGIN or PAYMENT; only its hash is stored. |
| `login_audit` | One row per login attempt, successful or not. |
| `user_role_audit` | One row per role GRANT or REVOKE. |

Relationships and cardinality:

- `app_user` **1 : N** `passenger` - a user owns many passengers; each passenger belongs to exactly one user.
- `app_user` **M : N** `role` through `user_role` - a user may hold several roles and a role is held by many users. The composite key (User_ID, Role_ID) stops duplicate grants.
- `app_user` **1 : N** `otp_challenge` - a user can have many challenges over time.
- `login_audit` and `user_role_audit` keep User_ID **without a foreign key** on purpose. A failed login may use an e-mail that has no account, and audit history must survive even if a user row is ever removed.
- Group 3 links to this module: `booking.User_ID` -> `app_user`, `booking_passenger.Passenger_ID` -> `passenger`.

## 3. Normalization

| Table | 1NF | 2NF | 3NF |
|---|---|---|---|
| `role` | Atomic values. | Single-column key. | Role_Name depends only on Role_ID. |
| `app_user` | One value per cell; roles are NOT stored as a list but in `user_role`. | Single-column key. | Every column describes the user. No column depends on a non-key column. |
| `user_role` | Atomic ids. | Key is (User_ID, Role_ID) and there are no other columns, so no partial dependency. | Nothing to depend transitively. |
| `passenger` | Atomic values. | Single-column key. | Name, date of birth, gender describe the traveller, not the owner. |
| `otp_challenge` | Atomic values. | Single-column key. | Expiry and used flag depend on the challenge only. |
| `login_audit` | Atomic values. | Single-column key. | Each row is one event; see denormalization below. |
| `user_role_audit` | Atomic values. | Single-column key. | Each row is one event. |

**Derived data is not stored.** SENIOR and CHILD concessions depend on age, and age changes every day. If we stored "SENIOR" in `passenger`, a child would stay a child in the database after turning 12 and nobody would update it - an update anomaly and a transitive dependency (Date_Of_Birth -> age -> concession). So only the declared concessions NONE, GOVT and SOLDIER are stored. The function `fn_effective_concession` calculates SENIOR or CHILD from Date_Of_Birth whenever a fare is needed, so it is always correct.

**Deliberate denormalization (justified):**

- `app_user.Failed_Login_Count` and `Locked_Until` could be recalculated from `login_audit`, but counting audit rows at every login would be slow and complicated. Two small columns give an instant lockout check.
- `login_audit.Email_Attempted` repeats the e-mail even when User_ID is known, because attempts for unknown e-mails have no user to point to.
- `passenger.Full_Name` looks like a copy of `app_user.Full_Name`, but it is not: it is the traveller's name, which differs from the account holder's name.

## 4. Constraints

| Table | PK | FK | UNIQUE | CHECK | NOT NULL highlights |
|---|---|---|---|---|---|
| `role` | Role_ID | - | Role_Name | Role_Name IN (PASSENGER, ADMIN, OPERATOR) | Role_Name |
| `app_user` | User_ID | - | Email | Phone matches 10 digits | Email, Password_Hash, Full_Name, Phone, Is_Active, Failed_Login_Count |
| `user_role` | (User_ID, Role_ID) | User_ID -> app_user, Role_ID -> role | the composite PK | - | both columns |
| `passenger` | Passenger_ID | User_ID -> app_user | - | Gender IN (M,F,O); Concession_Type IN (NONE,GOVT,SOLDIER) | Full_Name, Date_Of_Birth, Gender, Concession_Type |
| `otp_challenge` | Otp_ID | User_ID -> app_user | - | Purpose IN (LOGIN, PAYMENT) | Otp_Hash, Expires_At, Is_Used |
| `login_audit` | Login_Audit_ID | none | - | - | Email_Attempted, Success |
| `user_role_audit` | Audit_ID | none | - | Action IN (GRANT, REVOKE) | User_ID, Role_ID, Action |

## 5. Indexes and the query each one serves

| Index | Serves this query |
|---|---|
| UNIQUE on `app_user.Email` | Login and registration: `WHERE Email = ?` is one index lookup, and duplicates are impossible. |
| UNIQUE on `role.Role_Name` | Role lookup by name when roles are granted. |
| PRIMARY KEY (User_ID, Role_ID) on `user_role` | "Which roles does this user have?" - used for every JWT and for `v_user_account`. |
| `idx_passenger_user_id` on `passenger(User_ID)` | `GET /passengers`: all travellers of the logged-in user. |
| Foreign-key indexes InnoDB creates automatically (`otp_challenge.User_ID`, `user_role.Role_ID`) | Finding the latest challenge of a user; finding users of a role. |

## 6. Functions, procedures, triggers, views

### Functions

**fn_age_category(p_dob DATE) -> VARCHAR(10)** (NOT DETERMINISTIC, NO SQL)

- Purpose: classify a person by age.
- Logic: age = `TIMESTAMPDIFF(YEAR, p_dob, CURDATE())`; under 12 gives CHILD, 60 or more gives SENIOR, otherwise ADULT.
- Example: `SELECT fn_age_category('2018-07-01');` -> `CHILD` (age 8 on 28 Oct 2026).

**fn_effective_concession(p_dob DATE, p_declared VARCHAR(10)) -> VARCHAR(10)** (NOT DETERMINISTIC, NO SQL)

- Purpose: the concession that really applies.
- Logic: SENIOR if the age category is SENIOR; CHILD if CHILD; otherwise the declared value (NONE, GOVT, SOLDIER).
- Example: `SELECT fn_effective_concession('1955-03-10','NONE');` -> `SENIOR`; `SELECT fn_effective_concession('1988-01-20','SOLDIER');` -> `SOLDIER`.

### Stored procedures

**sp_register_user(p_email, p_password_hash, p_full_name, p_phone)**

- Purpose: create an account in one step.
- Logic: start transaction; reject a used e-mail with `EMAIL_EXISTS`; insert `app_user`; insert `user_role` with the PASSENGER role; commit. Any SQL error rolls everything back.
- Example: `CALL sp_register_user('new@railway.test','<bcrypt hash>','New User','9123456789');` -> one row `User_ID = 6` (the next free id after the five seeded users).

**sp_record_login_attempt(p_email, p_success, p_ip)**

- Purpose: write the audit row and maintain the lockout counter.
- Logic: insert `login_audit`. If the attempt failed and the user exists, add 1 to Failed_Login_Count; on reaching 5 set Locked_Until = NOW() + 15 minutes and reset the counter to 0. If it succeeded, set the counter to 0 and Locked_Until to NULL.
- Example: `CALL sp_record_login_attempt('asha@railway.test',0,'127.0.0.1');` -> `Failed_Login_Count = 1, Locked_Until = NULL`. After the fifth failure -> `0` and a time 15 minutes ahead.

### Triggers

| Trigger | Event | Logic | Example and result |
|---|---|---|---|
| `trg_user_role_ai` | AFTER INSERT on `user_role` | Inserts a GRANT row into `user_role_audit`. | `INSERT INTO user_role VALUES (6,3);` -> audit row (6, 3, GRANT). |
| `trg_user_role_ad` | AFTER DELETE on `user_role` | Inserts a REVOKE row. | `DELETE FROM user_role WHERE User_ID=6 AND Role_ID=3;` -> audit row (6, 3, REVOKE). |
| `trg_passenger_bi` | BEFORE INSERT on `passenger` | Raises `VALIDATION_ERROR` if Date_Of_Birth is in the future. | Insert with DOB `2099-01-01` -> error `VALIDATION_ERROR: ...`, no row stored. |

### Views

**v_user_account** - columns User_ID, Email, Full_Name, Phone, Is_Active, Roles, Created_At. It joins `app_user`, `user_role` and `role`, groups by user and builds Roles with `GROUP_CONCAT`. The password hash is deliberately left out. Example: `SELECT * FROM v_user_account WHERE User_ID = 3;` -> `3, asha@railway.test, Asha Patil, 9000000003, 1, PASSENGER, <created time>`.

**v_passenger_booking_history** - one row per booked traveller: User_ID, Passenger_ID, Passenger_Name, Booking_ID, Booking_Passenger_ID, PNR, Train_No, Train_Name, Journey_Date, From_Station_Code, To_Station_Code, Class_Code, Status, Fare_Amount, Booked_At. It joins passenger, booking_passenger, booking, train_run, train and station. Example: `SELECT PNR, Passenger_Name, Status FROM v_passenger_booking_history WHERE User_ID = 3;` -> one row per booked traveller of Asha, such as `<PNR>, Asha Patil, CNF` (needs demo data).

## 7. Transactions, ACID and locking

- **Atomicity** - `sp_register_user` writes two tables (user and role) inside one transaction with an exit handler that rolls back and re-raises the error. A user can never exist without a role.
- **Consistency** - CHECK, UNIQUE and foreign-key constraints, plus `trg_passenger_bi`, keep only valid rows in the tables.
- **Isolation** - updating `app_user` in `sp_record_login_attempt` takes an InnoDB row lock, so two parallel failed logins cannot both read the same counter and lose one increment. Group 2 never touches booking tables, so the system-wide lock order does not involve this module.
- **Durability** - InnoDB writes committed changes to its redo log.
- Spring services that call these procedures are not marked `@Transactional`, because each procedure owns its transaction.
- Deleting a passenger who is referenced by `booking_passenger` is stopped by the foreign key; the backend turns that into the clear error `PASSENGER_IN_USE`.

## 8. Backend design and endpoint summary

Package `com.railway.user` with sub-packages `controller`, `service` and `dto`. Classes use the prefixes Auth*, User*, Passenger* and Otp*. The code is SQL-first (`SqlHelper`/JdbcTemplate), with request DTOs as Java records and every response wrapped in `ApiResponse`.

**BCrypt + JWT + RBAC.**

- Passwords are never stored in plain text. BCrypt adds a random salt and is deliberately slow, so stolen hashes are hard to crack. All seed users share the hash of `Test@1234`.
- After a correct password the server issues a JWT (HS256, signed with `app.jwt.secret`). It carries the user id, e-mail and role names and expires after 120 minutes. The frontend sends it as `Authorization: Bearer <token>`.
- RBAC: a filter turns the roles into authorities `ROLE_<name>`. `/api/v1/admin/**` requires ADMIN; controllers use `@PreAuthorize` where needed. A passenger calling an admin URL gets `403 FORBIDDEN`; a missing token gets `401 UNAUTHORIZED`.

**OTP-based 2FA.** `POST /auth/payment-otp` creates a 6-digit one-time password that is valid for 5 minutes. Only its hash goes into `otp_challenge`, and in dev-mode the plain value is returned as `devOtp` so demos work without SMS. `OtpVerifierImpl` (interface `OtpVerifier`) checks the challenge id, the user, the purpose, the expiry, the hash and that it is unused, then marks it used - so an OTP works exactly once. Payment OTP is required by default; login OTP is optional (`app.auth.require-login-otp`).

**Account lockout.** The login service loads the user, refuses with `ACCOUNT_LOCKED (423)` if Locked_Until is in the future, compares the BCrypt hash, then always calls `sp_record_login_attempt`. Five failures lock the account for 15 minutes. The unknown-e-mail and wrong-password cases return the same `INVALID_CREDENTIALS` message, so attackers cannot find out which e-mails exist.

**Audit tables.** `login_audit` shows who tried to log in, when and from which IP; `user_role_audit` shows every privilege change, written by triggers so it cannot be forgotten by application code.

| Method and path | Access | Result |
|---|---|---|
| POST /auth/register | PUBLIC | `{userId}` |
| POST /auth/login | PUBLIC | token or OTP challenge, plus user |
| POST /auth/verify-otp | PUBLIC | `{token, user}` |
| POST /auth/payment-otp | AUTH | `{challengeId, expiresAt, devOtp}` |
| GET, PUT /users/me | AUTH | own profile |
| GET, POST /passengers | AUTH | own travellers |
| PUT, DELETE /passengers/{id} | AUTH | own traveller only |
| GET /admin/users | ADMIN | rows of `v_user_account` |
| PUT /admin/users/{id}/roles | ADMIN | `{userId, roles}` |
| PUT /admin/users/{id}/active | ADMIN | `{userId, active}` |

## 9. Frontend screens

Folder `frontend/src/modules/users/`, routes exported from `routes.jsx`, API calls in `api.js`.

- `/login` - e-mail and password form; shows an OTP step when the server asks for it.
- `/register` - e-mail, password (minimum 8), name and phone.
- `/profile` - view and edit name and phone.
- `/passengers` - table of saved travellers with age category and concession; add, edit and delete forms.
- `/admin/users` (ADMIN) - user table with role editing and an activate/deactivate button.

## 10. Test cases

| ID | Objective | Input | Expected | Actual | Screenshot |
|---|---|---|---|---|---|
| G2-T01 | Register a new user | New e-mail, strong password | Success, `userId` returned | | |
| G2-T02 | Duplicate e-mail | E-mail `asha@railway.test` | 409 `EMAIL_EXISTS` | | |
| G2-T03 | Weak password | Password `abc123` | 400 `VALIDATION_ERROR` | | |
| G2-T04 | Valid login | asha / `Test@1234` | Token and user returned | | |
| G2-T05 | Wrong password | Wrong password | 401 `INVALID_CREDENTIALS` | | |
| G2-T06 | Lockout | 5 wrong passwords, then the right one | 6th call is 423 `ACCOUNT_LOCKED` | | |
| G2-T07 | Payment OTP | Passenger token | `challengeId` and `devOtp` | | |
| G2-T08 | Wrong OTP | Unknown challenge | 401 `OTP_INVALID` | | |
| G2-T09 | Derived concession | Passenger with DOB 1955-03-10 | `ageCategory` = SENIOR, stored concession NONE | | |
| G2-T10 | Foreign passenger | PUT `/passengers/4` as Asha | 403 `NOT_OWNER` | | |
| G2-T11 | RBAC | GET `/admin/users` with a passenger token | 403 `FORBIDDEN` | | |
| G2-T12 | Delete used passenger | DELETE `/passengers/1` after demo data | 409 `PASSENGER_IN_USE` | | |
| G2-T13 | Role audit | Grant, then revoke a role | GRANT and REVOKE audit rows | | |

All API cases are automated in `postman/g2.postman_collection.json`.

## 11. Integration points with other groups

- **Foundation (F1):** `SecurityConfig`, `JwtService`, `SecurityUtil`, `PasswordEncoder` and `GlobalExceptionHandler` are used by this module. Group 2 supplies `OtpVerifierImpl` for the `OtpVerifier` interface.
- **Group 3:** `sp_book_ticket` checks that each passenger belongs to the user, then calls `fn_effective_concession` for the fare. `booking.User_ID` and `booking_passenger.Passenger_ID` reference this module's tables. `v_passenger_booking_history` reads Group 3 and Group 1 tables.
- **Group 4:** `fn_net_fare` uses the concession name returned by `fn_effective_concession`. `POST /payments/orders` verifies the payment OTP through `OtpVerifier`.

## 12. Assumptions and limitations

- OTPs are shown as `devOtp` in dev-mode. No e-mail or SMS service exists.
- Lockout works per account, not per IP address, so someone could lock another user's account on purpose.
- A JWT is stateless. A deactivated or re-roled user keeps the old token until it expires unless the backend rechecks the database.
- `login_audit` and `otp_challenge` have no extra index in the contract; very large tables would need one on the e-mail and on the user and time.
- The `PASSENGER_IN_USE` test needs `db/60_demo_data.sql`.
