-- Task G2.3 | Owner: G2 (Passenger & User) | Purpose: master seed data for roles, users, user_role and passengers (contract C6)
-- Runs after schemas, functions, procedures and triggers. Password of every user = Test@1234 (bcrypt hash below).

-- 1. Roles
INSERT INTO role (Role_ID, Role_Name) VALUES
    (1, 'PASSENGER'),
    (2, 'ADMIN'),
    (3, 'OPERATOR');

-- 2. Users (inserted BEFORE user_role so that user_role rows can reference them)
INSERT INTO app_user (User_ID, Email, Password_Hash, Full_Name, Phone) VALUES
    (1, 'admin@railway.test',    '$2a$10$Ggra/EJAY81g3MUp5ZRx8ukeDAXlA/NBVyQUlUz0AXv/3vZ0FQjOq', 'System Admin',           '9000000001'),
    (2, 'operator@railway.test', '$2a$10$Ggra/EJAY81g3MUp5ZRx8ukeDAXlA/NBVyQUlUz0AXv/3vZ0FQjOq', 'Control Room Operator', '9000000002'),
    (3, 'asha@railway.test',     '$2a$10$Ggra/EJAY81g3MUp5ZRx8ukeDAXlA/NBVyQUlUz0AXv/3vZ0FQjOq', 'Asha Patil',            '9000000003'),
    (4, 'rohan@railway.test',    '$2a$10$Ggra/EJAY81g3MUp5ZRx8ukeDAXlA/NBVyQUlUz0AXv/3vZ0FQjOq', 'Rohan Deshmukh',        '9000000004'),
    (5, 'meera@railway.test',    '$2a$10$Ggra/EJAY81g3MUp5ZRx8ukeDAXlA/NBVyQUlUz0AXv/3vZ0FQjOq', 'Meera Kulkarni',        '9000000005');

-- 3. Role assignments (trg_user_role_ai writes one GRANT audit row for each of the 5 rows)
INSERT INTO user_role (User_ID, Role_ID) VALUES
    (1, 2),   -- admin    -> ADMIN
    (2, 3),   -- operator -> OPERATOR
    (3, 1),   -- asha     -> PASSENGER
    (4, 1),   -- rohan    -> PASSENGER
    (5, 1);   -- meera    -> PASSENGER

-- 4. Passengers (SENIOR / CHILD concessions are derived from Date_Of_Birth by fn_effective_concession)
INSERT INTO passenger (Passenger_ID, User_ID, Full_Name, Date_Of_Birth, Gender, Concession_Type) VALUES
    (1, 3, 'Asha Patil',      '1990-05-15', 'F', 'NONE'),
    (2, 3, 'Suresh Patil',    '1955-03-10', 'M', 'NONE'),
    (3, 3, 'Aarav Patil',     '2018-07-01', 'M', 'NONE'),
    (4, 4, 'Rohan Deshmukh',  '1988-01-20', 'M', 'SOLDIER'),
    (5, 4, 'Priya Deshmukh',  '1992-11-02', 'F', 'NONE'),
    (6, 5, 'Meera Kulkarni',  '1985-09-09', 'F', 'GOVT'),
    (7, 5, 'Kabir Kulkarni',  '2001-04-18', 'M', 'NONE'),
    (8, 5, 'Leela Kulkarni',  '1962-12-25', 'F', 'NONE');
