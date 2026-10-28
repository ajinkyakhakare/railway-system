-- G2.1 | Group 2 (Passenger & User) | Schema: role, app_user, user_role, passenger, login_audit, user_role_audit, otp_challenge
-- Runs on MySQL 8.0 after 01_schema_g1.sql. G2 tables do not reference any G1 table.
-- Tables are created in dependency order: role, app_user -> user_role, passenger, otp_challenge -> audit tables.

-- role: the three application roles (PASSENGER, ADMIN, OPERATOR) used for RBAC.
CREATE TABLE role (
  Role_ID   INT UNSIGNED NOT NULL AUTO_INCREMENT,
  Role_Name VARCHAR(20)  NOT NULL,
  CONSTRAINT pk_role PRIMARY KEY (Role_ID),
  CONSTRAINT uq_role_role_name UNIQUE (Role_Name),
  CONSTRAINT chk_role_role_name CHECK (Role_Name IN ('PASSENGER','ADMIN','OPERATOR'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- app_user: login account; Password_Hash stores a BCrypt hash, never the plain password.
CREATE TABLE app_user (
  User_ID            INT UNSIGNED NOT NULL AUTO_INCREMENT,
  Email              VARCHAR(120) NOT NULL,
  Password_Hash      VARCHAR(100) NOT NULL,
  Full_Name          VARCHAR(80)  NOT NULL,
  Phone              CHAR(10)     NOT NULL,
  Is_Active          TINYINT(1)   NOT NULL DEFAULT 1,
  Failed_Login_Count TINYINT      NOT NULL DEFAULT 0,
  Locked_Until       DATETIME     NULL,
  Created_At         DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT pk_app_user PRIMARY KEY (User_ID),
  CONSTRAINT uq_app_user_email UNIQUE (Email),
  CONSTRAINT chk_app_user_phone CHECK (Phone REGEXP '^[0-9]{10}$')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- user_role: many-to-many link between app_user and role (composite primary key).
CREATE TABLE user_role (
  User_ID INT UNSIGNED NOT NULL,
  Role_ID INT UNSIGNED NOT NULL,
  CONSTRAINT pk_user_role PRIMARY KEY (User_ID, Role_ID),
  CONSTRAINT fk_user_role_app_user FOREIGN KEY (User_ID) REFERENCES app_user (User_ID),
  CONSTRAINT fk_user_role_role FOREIGN KEY (Role_ID) REFERENCES role (Role_ID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- passenger: a traveller saved by a user; senior/child concessions are derived from Date_Of_Birth by fn_effective_concession.
CREATE TABLE passenger (
  Passenger_ID    INT UNSIGNED NOT NULL AUTO_INCREMENT,
  User_ID         INT UNSIGNED NOT NULL,
  Full_Name       VARCHAR(80)  NOT NULL,
  Date_Of_Birth   DATE         NOT NULL,
  Gender          CHAR(1)      NOT NULL,
  Concession_Type VARCHAR(10)  NOT NULL DEFAULT 'NONE',
  CONSTRAINT pk_passenger PRIMARY KEY (Passenger_ID),
  CONSTRAINT fk_passenger_app_user FOREIGN KEY (User_ID) REFERENCES app_user (User_ID),
  CONSTRAINT chk_passenger_gender CHECK (Gender IN ('M','F','O')),
  CONSTRAINT chk_passenger_concession_type CHECK (Concession_Type IN ('NONE','GOVT','SOLDIER')),
  INDEX idx_passenger_user_id (User_ID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- login_audit: every login attempt; User_ID has no FK so attempts for unknown emails can be stored.
CREATE TABLE login_audit (
  Login_Audit_ID  INT UNSIGNED NOT NULL AUTO_INCREMENT,
  User_ID         INT UNSIGNED NULL,
  Email_Attempted VARCHAR(120) NOT NULL,
  Success         TINYINT(1)   NOT NULL,
  IP_Address      VARCHAR(45)  NULL,
  Attempted_At    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT pk_login_audit PRIMARY KEY (Login_Audit_ID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- user_role_audit: GRANT/REVOKE history written by triggers; no FKs so history survives deletions.
CREATE TABLE user_role_audit (
  Audit_ID   INT UNSIGNED NOT NULL AUTO_INCREMENT,
  User_ID    INT UNSIGNED NOT NULL,
  Role_ID    INT UNSIGNED NOT NULL,
  Action     VARCHAR(6)   NOT NULL,
  Changed_At DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT pk_user_role_audit PRIMARY KEY (Audit_ID),
  CONSTRAINT chk_user_role_audit_action CHECK (Action IN ('GRANT','REVOKE'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- otp_challenge: one-time passwords for 2FA (LOGIN or PAYMENT); Otp_Hash stores a BCrypt hash of the OTP.
CREATE TABLE otp_challenge (
  Otp_ID     INT UNSIGNED NOT NULL AUTO_INCREMENT,
  User_ID    INT UNSIGNED NOT NULL,
  Purpose    VARCHAR(10)  NOT NULL,
  Otp_Hash   VARCHAR(100) NOT NULL,
  Expires_At DATETIME     NOT NULL,
  Is_Used    TINYINT(1)   NOT NULL DEFAULT 0,
  Created_At DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT pk_otp_challenge PRIMARY KEY (Otp_ID),
  CONSTRAINT fk_otp_challenge_app_user FOREIGN KEY (User_ID) REFERENCES app_user (User_ID),
  CONSTRAINT chk_otp_challenge_purpose CHECK (Purpose IN ('LOGIN','PAYMENT'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
