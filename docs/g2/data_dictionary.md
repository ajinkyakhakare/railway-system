# G2 Data Dictionary - Passenger & User

Database: `railway_db` (MySQL 8.0, InnoDB, utf8mb4). Schema file: `db/02_schema_g2.sql`.

Security notes:
- `app_user.Password_Hash` holds a **BCrypt hash** of the password. The plain password is never stored.
- `otp_challenge.Otp_Hash` holds a **BCrypt hash** of the one-time password. The plain OTP is never stored.

## role

Application roles used for role-based access control (RBAC).

| Field | Type | Null | Key | Default | Description |
|---|---|---|---|---|---|
| Role_ID | INT UNSIGNED | NO | PK | AUTO_INCREMENT | Role identifier. |
| Role_Name | VARCHAR(20) | NO | UQ | - | Role name; CHECK: PASSENGER, ADMIN or OPERATOR. |

## app_user

Login account of a person using the system.

| Field | Type | Null | Key | Default | Description |
|---|---|---|---|---|---|
| User_ID | INT UNSIGNED | NO | PK | AUTO_INCREMENT | User identifier. |
| Email | VARCHAR(120) | NO | UQ | - | Login e-mail address; unique. |
| Password_Hash | VARCHAR(100) | NO | - | - | BCrypt hash of the password (never the plain password). |
| Full_Name | VARCHAR(80) | NO | - | - | Full name of the account holder. |
| Phone | CHAR(10) | NO | - | - | 10-digit phone number; CHECK matches `^[0-9]{10}$`. |
| Is_Active | TINYINT(1) | NO | - | 1 | 1 = account enabled, 0 = disabled by an admin. |
| Failed_Login_Count | TINYINT | NO | - | 0 | Consecutive failed logins; reset to 0 on success or when the account is locked. |
| Locked_Until | DATETIME | YES | - | NULL | Account is locked until this time (after 5 failed logins); NULL = not locked. |
| Created_At | DATETIME | NO | - | CURRENT_TIMESTAMP | Registration time. |

## user_role

Link table giving each user one or more roles (many-to-many between `app_user` and `role`).

| Field | Type | Null | Key | Default | Description |
|---|---|---|---|---|---|
| User_ID | INT UNSIGNED | NO | PK, FK -> app_user | - | User who holds the role. |
| Role_ID | INT UNSIGNED | NO | PK, FK -> role | - | Role granted to the user. |

Composite primary key: (User_ID, Role_ID).

## passenger

A traveller saved by a user; bookings are made for passengers.

| Field | Type | Null | Key | Default | Description |
|---|---|---|---|---|---|
| Passenger_ID | INT UNSIGNED | NO | PK | AUTO_INCREMENT | Passenger identifier. |
| User_ID | INT UNSIGNED | NO | FK -> app_user, IDX | - | User who owns this passenger record. |
| Full_Name | VARCHAR(80) | NO | - | - | Passenger's name. |
| Date_Of_Birth | DATE | NO | - | - | Date of birth; used to derive age category and SENIOR/CHILD concession. |
| Gender | CHAR(1) | NO | - | - | CHECK: M, F or O. |
| Concession_Type | VARCHAR(10) | NO | - | 'NONE' | Declared concession; CHECK: NONE, GOVT or SOLDIER. SENIOR and CHILD are derived from Date_Of_Birth by `fn_effective_concession`. |

## login_audit

Log of every login attempt (successful or not). No foreign key, so attempts with unknown e-mails can be recorded.

| Field | Type | Null | Key | Default | Description |
|---|---|---|---|---|---|
| Login_Audit_ID | INT UNSIGNED | NO | PK | AUTO_INCREMENT | Audit row identifier. |
| User_ID | INT UNSIGNED | YES | - (logical -> app_user) | NULL | User of the attempt; NULL if the e-mail does not exist. |
| Email_Attempted | VARCHAR(120) | NO | - | - | E-mail that was typed in at login. |
| Success | TINYINT(1) | NO | - | - | 1 = login succeeded, 0 = failed. |
| IP_Address | VARCHAR(45) | YES | - | NULL | Client IP address (IPv4 or IPv6). |
| Attempted_At | DATETIME | NO | - | CURRENT_TIMESTAMP | Time of the attempt. |

## user_role_audit

History of role changes, filled by triggers `trg_user_role_ai` (GRANT) and `trg_user_role_ad` (REVOKE). No foreign keys, so history is kept even after rows are deleted.

| Field | Type | Null | Key | Default | Description |
|---|---|---|---|---|---|
| Audit_ID | INT UNSIGNED | NO | PK | AUTO_INCREMENT | Audit row identifier. |
| User_ID | INT UNSIGNED | NO | - (logical -> user_role) | - | User whose role changed. |
| Role_ID | INT UNSIGNED | NO | - (logical -> user_role) | - | Role that was granted or revoked. |
| Action | VARCHAR(6) | NO | - | - | CHECK: GRANT or REVOKE. |
| Changed_At | DATETIME | NO | - | CURRENT_TIMESTAMP | Time of the change. |

## otp_challenge

One-time passwords for two-factor authentication (login and payment).

| Field | Type | Null | Key | Default | Description |
|---|---|---|---|---|---|
| Otp_ID | INT UNSIGNED | NO | PK | AUTO_INCREMENT | Challenge identifier (returned to the client as challengeId). |
| User_ID | INT UNSIGNED | NO | FK -> app_user | - | User the OTP was issued to. |
| Purpose | VARCHAR(10) | NO | - | - | CHECK: LOGIN or PAYMENT. |
| Otp_Hash | VARCHAR(100) | NO | - | - | BCrypt hash of the OTP (never the plain OTP). |
| Expires_At | DATETIME | NO | - | - | OTP is invalid after this time (5 minutes after creation). |
| Is_Used | TINYINT(1) | NO | - | 0 | 1 once the OTP has been used; each OTP is single use. |
| Created_At | DATETIME | NO | - | CURRENT_TIMESTAMP | Time the OTP was issued. |
