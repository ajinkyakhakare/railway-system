# National Railway Reservation & Management System

A college DBMS project (PICT, E&TCE): an end-to-end railway ticketing platform with train search,
reservation with automatic PNR, CNF / RAC / WL handling, payments, cancellation with refund,
and an operations & analytics console. The database does the heavy lifting (stored procedures,
triggers, functions and views on **MySQL 8**), the web tier is **Spring Boot 3** with a **React 18**
front end, and **MongoDB** (optional) stores the live operations event log.

---

## 1. What the system does

- Search trains between two stations on a date, view timetables, coaches and seat availability.
- Register / log in with JWT, role-based access (PASSENGER, ADMIN, OPERATOR), optional OTP (2FA).
- Book up to 6 passengers per PNR. Seats are confirmed (CNF), or placed on RAC / waiting list (WL).
- Pay through a mock gateway or **Razorpay (test mode)**, protected by a payment OTP.
- Cancel a ticket: refund is calculated from hours before departure, and RAC / WL passengers are
  promoted automatically.
- Operators update train running status and delays; admins see revenue, popular routes and delay reports.

---

## 2. Modules

| Group | Module | Owner(s) | Backend package | Frontend folder | Tables owned |
|-------|--------|----------|-----------------|-----------------|--------------|
| G1 | Train, Station & Route | `<name>` | `com.railway.train` | `frontend/src/modules/trains` | station, route, route_stop, train, train_schedule, coach_type, train_coach, seat, train_run, route_stop_audit (10) |
| G2 | Passenger & User | `<name>` | `com.railway.user` | `frontend/src/modules/users` | role, app_user, user_role, passenger, login_audit, user_role_audit, otp_challenge (7) |
| G3 | Reservation & Seat | `<name>` | `com.railway.booking` | `frontend/src/modules/booking` | seat_inventory, booking, booking_passenger, seat_allocation, booking_status_history (5) |
| G4 | Payment, Cancellation & Refund | `<name>` | `com.railway.payment` | `frontend/src/modules/payments` | fare_rule, concession_rule, refund_rule, payment, cancellation, refund, fare_audit_log (7) |
| G5 | Railway Operations & Analytics | `<name>` | `com.railway.ops` | `frontend/src/modules/ops` | train_run_status, delay_log, station_daily_revenue (3) |

Total: **32 tables**. Shared parts:

| Part | Content | Owner |
|------|---------|-------|
| F1 | Backend foundation (`pom.xml`, `application.yml`, `com.railway.common`) | `<name>` |
| F2 | Frontend foundation (Vite project, shared components, API client, routing) | `<name>` |
| F3 | Database bootstrap (`db/00_database.sql`, `scripts/`) | `<name>` |
| I1 | Demo data (`db/60_demo_data.sql`) | `<name>` |

---

## 3. Tech stack

| Layer | Technology |
|-------|-----------|
| Database | MySQL 8.0 (InnoDB, utf8mb4): stored procedures, triggers, UDFs, views, window functions |
| Document store | MongoDB (optional): collection `ops_event_log` in database `railway_ops` |
| Backend | Java 17, Spring Boot 3.3.5, Maven, Spring Web / JDBC / Security / Validation / Data MongoDB, JJWT 0.12.6, MySQL Connector/J. SQL-first with `JdbcTemplate` (no JPA, no Lombok) |
| Frontend | Node 20, Vite 5, React 18, react-router-dom 6, axios, recharts 2, Tailwind CSS 3.4 (+ PostCSS, Autoprefixer) |
| Security | JWT (HS256), BCrypt password hashes, RBAC with `@PreAuthorize`, OTP for login / payment |
| Payments | Mock gateway or Razorpay in test mode |
| API testing | Postman collections (one per group) |

---

## 4. Repository layout

```text
railway-system/
├── README.md
├── .gitignore
├── db/
│   ├── 00_database.sql                  drop / create database railway_db
│   ├── 01_schema_g1.sql .. 05_schema_g5.sql    tables, indexes, constraints (one per group)
│   ├── 10_functions_gN.sql              UDFs
│   ├── 20_procedures_gN.sql             stored procedures
│   ├── 30_triggers_gN.sql               triggers
│   ├── 40_views_gN.sql                  views
│   ├── 50_seed_g1.sql, 51_seed_g2.sql, 52_seed_g4.sql    master seed data
│   ├── 60_demo_data.sql                 sample bookings created through procedures (optional)
│   └── tests/gN_tests.sql               SQL proof scripts (before / action / after)
├── scripts/
│   ├── init-db.ps1                      create the database (Windows PowerShell)
│   ├── init-db.sh                       create the database (Linux / macOS / Git Bash)
│   └── verify-contract.sql              checks that every table, routine, trigger and view exists
├── backend/
│   ├── pom.xml
│   └── src/main/
│       ├── resources/application.yml
│       └── java/com/railway/
│           ├── common/                  shared code: api, exception, db, security, otp, web
│           ├── train/                   G1  (controller, service, dto)
│           ├── user/                    G2
│           ├── booking/                 G3
│           ├── payment/                 G4
│           └── ops/                     G5
├── frontend/                            Vite + React project
│   └── src/
│       ├── api/ auth/ hooks/ utils/ components/     shared code (alias "@" = frontend/src)
│       └── modules/
│           └── trains | users | booking | payments | ops
│               └── routes.jsx, api.js, pages/*.jsx
├── postman/
│   ├── g1.postman_collection.json .. g5.postman_collection.json
│   └── environment.json
└── docs/
    ├── MASTER_PROMPT.md  INTEGRATION_MAPPING.md  ARCHITECTURE.md
    ├── PROJECT_REPORT.md  VIVA_PREP.md
    └── g1 .. g5/   er.mmd, data_dictionary.md, MODULE_REPORT.md
```

The database files run in numeric order: all schemas, then all functions, procedures, triggers,
views, and finally the seed data.

---

## 5. Prerequisites

| Tool | Version | Check with | Needed for |
|------|---------|------------|------------|
| JDK | 17 | `java -version` | backend |
| Maven | 3.9 | `mvn -v` | backend |
| Node.js | 20 | `node -v` | frontend |
| MySQL Server + `mysql` client | 8.0 | `mysql --version` | database (the `mysql` command must be on your PATH) |
| MongoDB | 6 or newer (optional) | `mongod --version` | operations event log only |
| jq | 1.6 or newer (optional) | `jq --version` | the API smoke test script only |

Default ports: MySQL 3306, backend 8080, frontend 5173, MongoDB 27017.

---

## 6. Run the project

### Step 1 - Get the code

```bash
git clone <repository-url> railway-system
cd railway-system
```

### Step 2 - Set the database credentials

The backend and the database scripts read the same two variables. If you skip this step the
defaults of `application.yml` are used (`root` / `root`).

Linux / macOS / Git Bash:

```bash
export DB_USER=root
export DB_PASSWORD=your_mysql_password
```

Windows PowerShell:

```powershell
$env:DB_USER = "root"
$env:DB_PASSWORD = "your_mysql_password"
```

Variables set this way only live in the current terminal. Use the **same terminal** for steps 3 and 5.

### Step 3 - Create the database

This drops and re-creates `railway_db`, then runs every file under `db/` in the correct order
(schemas, functions, procedures, triggers, views, seed data). Run it from the repository root.

Linux / macOS / Git Bash:

```bash
./scripts/init-db.sh
```

Windows PowerShell:

```powershell
.\scripts\init-db.ps1
```

Optional check that all 32 tables, routines, triggers and views were created:

```bash
mysql -u root -p railway_db -e "source scripts/verify-contract.sql"
```

### Step 4 (optional) - Load demo bookings

`db/60_demo_data.sql` creates sample bookings by calling the stored procedures, so the screens are
not empty. Load it **once**, right after step 3. To start again from a clean state, re-run step 3.

```bash
mysql -u root -p railway_db -e "source db/60_demo_data.sql"
```

### Step 5 - Start the backend

```bash
cd backend
mvn spring-boot:run
```

Wait for the line `Started ... in ... seconds`, then check it:
`http://localhost:8080/api/v1/health` must report `"status":"UP"` and `"db":"UP"`.

### Step 6 - Start the frontend (new terminal)

```bash
cd frontend
npm install
npm run dev
```

### Step 7 - Open the application

Open **http://localhost:5173** and log in with one of the accounts below. The Vite dev server
forwards every `/api` call to `http://localhost:8080`, so the browser never talks to the backend directly.

---

## 7. Seeded accounts

Password of **every** seeded account: `Test@1234`

| User ID | Email | Name | Role | Saved passengers |
|---------|-------|------|------|------------------|
| 1 | admin@railway.test | System Admin | ADMIN | - |
| 2 | operator@railway.test | Control Room Operator | OPERATOR | - |
| 3 | asha@railway.test | Asha Patil | PASSENGER | Asha Patil, Suresh Patil (senior), Aarav Patil (child) |
| 4 | rohan@railway.test | Rohan Deshmukh | PASSENGER | Rohan Deshmukh (soldier), Priya Deshmukh |
| 5 | meera@railway.test | Meera Kulkarni | PASSENGER | Meera Kulkarni (govt), Kabir Kulkarni, Leela Kulkarni (senior) |

Seeded master data: 9 stations (Pune, Mumbai CSMT, Kalyan, Lonavala, Nashik Road, Bhusawal,
Nagpur, Solapur, Hyderabad Deccan), 3 routes and 4 trains that run every day:

| Train | Name | Type | Route |
|-------|------|------|-------|
| 11001 | Mumbai Pune Express | EXPRESS | Mumbai CSMT - Pune Jn |
| 12002 | Pune Shatabdi | SHATABDI | Mumbai CSMT - Pune Jn |
| 12301 | Deccan Odyssey SF | SUPERFAST | Pune Jn - Hyderabad Deccan |
| 12401 | Vidarbha Express | EXPRESS | Mumbai CSMT - Nagpur |

Train runs are generated for **today and the next 14 days** when the database is created.
Routes are directional: to find trains between Mumbai and Pune search *from* Mumbai CSMT *to* Pune Jn.

---

## 8. Configuration keys

All settings live in `backend/src/main/resources/application.yml`. Every key can also be overridden
with an environment variable (Spring relaxed binding: upper-case, dots and dashes become underscores).
Never commit real secrets: put them in environment variables.

| Key | Default | Environment variable | Meaning |
|-----|---------|----------------------|---------|
| `server.port` | `8080` | `SERVER_PORT` | Backend port (the Vite proxy expects 8080) |
| `spring.datasource.url` | `jdbc:mysql://localhost:3306/railway_db?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Kolkata` | `SPRING_DATASOURCE_URL` | MySQL connection |
| `spring.datasource.username` | `${DB_USER:root}` | `DB_USER` | MySQL user |
| `spring.datasource.password` | `${DB_PASSWORD:root}` | `DB_PASSWORD` | MySQL password |
| `spring.data.mongodb.uri` | `mongodb://localhost:27017/railway_ops?serverSelectionTimeoutMS=2000` | `SPRING_DATA_MONGODB_URI` | MongoDB connection |
| `app.jwt.secret` | `${JWT_SECRET:change-me-change-me-change-me-change-me-1234}` | `JWT_SECRET` | HS256 signing secret, at least 32 characters |
| `app.jwt.expiry-minutes` | `120` | `APP_JWT_EXPIRY_MINUTES` | Token lifetime |
| `app.auth.dev-mode` | `true` | `APP_AUTH_DEV_MODE` | Responses include `devOtp`, so demos work without email / SMS |
| `app.auth.require-login-otp` | `false` | `APP_AUTH_REQUIRE_LOGIN_OTP` | Ask for an OTP after the password at login |
| `app.auth.require-payment-otp` | `true` | `APP_AUTH_REQUIRE_PAYMENT_OTP` | Ask for an OTP before a payment order is created |
| `app.payment.mode` | `MOCK` | `APP_PAYMENT_MODE` | `MOCK` or `RAZORPAY` |
| `app.payment.razorpay.key-id` | `${RAZORPAY_KEY_ID:}` | `RAZORPAY_KEY_ID` | Razorpay test key id |
| `app.payment.razorpay.key-secret` | `${RAZORPAY_KEY_SECRET:}` | `RAZORPAY_KEY_SECRET` | Razorpay test key secret |
| `app.mongo.enabled` | `false` | `APP_MONGO_ENABLED` | Write operations events to MongoDB |
| `app.cors.allowed-origin` | `http://localhost:5173` | `APP_CORS_ALLOWED_ORIGIN` | Browser origin allowed by CORS |

---

## 9. Enable MongoDB (optional)

MongoDB is used only for the operations event log (who changed a train's status, when, and why).
Everything else works without it.

1. Install MongoDB Community Edition and start the server (`mongod`, or the MongoDB service on Windows).
   It must listen on `localhost:27017`.
2. Switch the feature on and restart the backend, either by setting `app.mongo.enabled: true` in
   `application.yml` or with an environment variable:

   ```bash
   export APP_MONGO_ENABLED=true        # PowerShell: $env:APP_MONGO_ENABLED = "true"
   cd backend && mvn spring-boot:run
   ```
3. Log in as the operator, update a train's status on the page `/ops/update`, then log in as admin and
   call `GET /api/v1/admin/ops-events`. The event appears in the collection `ops_event_log` of the
   database `railway_ops`.

If MongoDB is switched off or unreachable, a status update still succeeds; the event is just not stored,
and `GET /api/v1/admin/ops-events` returns an empty list.

---

## 10. Enable Razorpay test mode (optional)

By default `app.payment.mode=MOCK`: the payment page confirms a payment without any external service.
To use the real Razorpay checkout with test money:

1. Create a free Razorpay account and switch the dashboard to **Test Mode**.
2. Open **Account & Settings -> API Keys** and generate a test key. You get a Key Id (starts with `rzp_test_`)
   and a Key Secret. The secret is shown only once, so save it.
3. Set the keys and the mode as environment variables **in the terminal that starts the backend**:

   ```bash
   export RAZORPAY_KEY_ID=rzp_test_xxxxxxxxxxxx
   export RAZORPAY_KEY_SECRET=your_test_secret
   export APP_PAYMENT_MODE=RAZORPAY
   ```

   PowerShell: `$env:RAZORPAY_KEY_ID = "..."`, `$env:RAZORPAY_KEY_SECRET = "..."`, `$env:APP_PAYMENT_MODE = "RAZORPAY"`.
4. Restart the backend and pay for a booking. Use the test card and UPI details listed in the Razorpay
   documentation for test mode; no real money moves.

In RAZORPAY mode the backend creates the order through `POST /api/v1/payments/orders` and checks the
payment signature (HMAC-SHA256 of `orderId|paymentId` with the key secret) in `POST /api/v1/payments/verify`.
Never commit the key secret to Git.

---

## 11. Quick tour

1. Open `http://localhost:5173/trains/search` and search **Mumbai CSMT -> Pune Jn** for tomorrow.
2. Choose a train and a class, log in as `asha@railway.test`, select passengers and book.
   Fares come from SQL functions (distance x class rate, minimum fare, concessions for senior / child / govt / soldier).
3. On the payment page request the payment OTP (with `app.auth.dev-mode=true` the API returns it as
   `devOtp`, so no email or SMS is needed), then confirm the payment. The booking becomes CONFIRMED and the PNR page `/tickets/<pnr>` shows the seats.
4. Open **My bookings**, cancel one passenger, and watch the refund slab and the automatic RAC -> CNF promotion.
5. Log in as `operator@railway.test` to update a train's delay, and as `admin@railway.test` for fares and reports.

---

## 12. Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `ERROR 1418 ... This function has none of DETERMINISTIC, NO SQL, or READS SQL DATA` (or `ERROR 1419` when creating triggers) while running `init-db` | MySQL has binary logging on and refuses to create routines / triggers for non-privileged users | Run once as an administrator: `SET GLOBAL log_bin_trust_function_creators = 1;`. To keep it after a restart, add `log_bin_trust_function_creators=1` under `[mysqld]` in `my.ini` / `my.cnf`. Then re-run `init-db`. |
| Backend: `Web server failed to start. Port 8080 was already in use` (or the frontend starts on 5174 instead of 5173) | Another program, or an old copy of this app, holds the port | Find and stop it. Windows: `netstat -ano \| findstr :8080` then `taskkill /PID <pid> /F`. Linux / macOS: `lsof -i :8080` then `kill <pid>`. Do the same for 5173. Do not change the ports; the proxy and the CORS setting assume 8080 and 5173. |
| Browser console: `blocked by CORS policy` | The page was opened from an origin other than `app.cors.allowed-origin` (for example `127.0.0.1:5173` instead of `localhost:5173`, or port 5174 because 5173 was busy) | Open exactly `http://localhost:5173`. Free port 5173 if Vite moved to another port. Or set `APP_CORS_ALLOWED_ORIGIN` to your real origin and restart the backend. |
| Every request returns `401` after restarting the backend, or after a long break | The token was signed with a different `JWT_SECRET` than the one now running, or it has expired (`app.jwt.expiry-minutes`, 120 by default) | Log in again. Always start the backend with the same `JWT_SECRET` (or none at all, so the default is used). |
| `The server time zone value '...' is unrecognized` or `Unknown or incorrect time zone: 'Asia/Kolkata'` | Connector/J cannot map the MySQL server time zone, or MySQL has no time zone tables loaded | Keep `serverTimezone=Asia/Kolkata` in the JDBC URL. If MySQL still rejects the name, load its time zone tables (Linux / macOS: `mysql_tzinfo_to_sql /usr/share/zoneinfo \| mysql -u root -p mysql`; Windows: import the time zone tables package from the MySQL downloads page) or, as a local-only workaround, use `serverTimezone=GMT%2B05:30` in `SPRING_DATASOURCE_URL`. |
| `Table 'railway_db.xxx' doesn't exist` or `Unknown database 'railway_db'` | `init-db` was not run, failed half-way, or ran against another MySQL server | Run step 3 again and read its output for the first error. Check with `mysql -u root -p railway_db -e "SHOW TABLES;"`: there must be 32 tables. Run `scripts/verify-contract.sql` for a full list of what is missing. |
| `ERROR 3140 / 3141: Invalid JSON text ...` when calling `sp_book_ticket` | The passenger list is not valid JSON. The procedure expects a JSON array of numbers, for example `'[3,4]'` | In SQL write `CALL sp_book_ticket(3, 5, 'SL', 2, 1, '[1,2]');` with single quotes around the array. In the API send `"passengerIds": [1,2]` (a list of numbers, not a string such as `"1,2"`, and not empty). |
| `Access denied for user 'root'@'localhost'` | Wrong MySQL user or password | Set `DB_USER` and `DB_PASSWORD` in the terminal you use for `init-db` **and** for `mvn spring-boot:run`. |
| `mysql` is not recognised / `command not found` | MySQL client folder is not on PATH | Add the MySQL `bin` folder (for example `C:\Program Files\MySQL\MySQL Server 8.0\bin`) to PATH and open a new terminal. |
| PowerShell: `init-db.ps1 cannot be loaded because running scripts is disabled` | Execution policy | In the same window run `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`, then run the script again. |
| Linux / macOS: `Permission denied` on `init-db.sh` | The file is not executable | `chmod +x scripts/init-db.sh` or run `bash scripts/init-db.sh`. |
| Train search shows no trains | Runs exist only for 15 days (today + 14) from the day the database was created, or the route direction is reversed | Search from Mumbai CSMT to Pune Jn (not the reverse), pick a date inside the window, or re-run `init-db` / use the admin function to generate more runs. |
| Booking fails with `RUN_DEPARTED` | The train already left today | Choose tomorrow or a later date. |
| Login fails with `ACCOUNT_LOCKED` | Five wrong passwords lock the account for 15 minutes | Wait 15 minutes, or for a development database run `UPDATE app_user SET Failed_Login_Count = 0, Locked_Until = NULL WHERE Email = 'asha@railway.test';` |
| Operations event list is empty or Mongo timeout in the log | `app.mongo.enabled=true` but MongoDB is not running, or it is disabled | Start `mongod` (see section 9) or set `APP_MONGO_ENABLED=false`. The rest of the application is not affected. |
| `release version 17 not supported` or `invalid target release` | Maven uses an older JDK | Set `JAVA_HOME` to a JDK 17 and check with `mvn -v`. |

---

## 13. More documentation

| Document | Content |
|----------|---------|
| `docs/ARCHITECTURE.md` | Layers, request flow, security, transaction design |
| `docs/INTEGRATION_MAPPING.md` | How the five modules connect and who writes which table |
| `docs/gN/er.mmd`, `docs/gN/data_dictionary.md`, `docs/gN/MODULE_REPORT.md` | Per-module ER diagram, data dictionary and report |
| `docs/PROJECT_REPORT.md` | Faculty report skeleton |
| `docs/VIVA_PREP.md` | Likely viva questions with answers |
| `postman/` | API collections and environment |

---

## 14. Team

| Group | Member(s) | Roll no. |
|-------|-----------|----------|
| G1 Train, Station & Route | `<name>` | `<roll no>` |
| G2 Passenger & User | `<name>` | `<roll no>` |
| G3 Reservation & Seat | `<name>` | `<roll no>` |
| G4 Payment, Cancellation & Refund | `<name>` | `<roll no>` |
| G5 Railway Operations & Analytics | `<name>` | `<roll no>` |

Guide: `<faculty name>`
