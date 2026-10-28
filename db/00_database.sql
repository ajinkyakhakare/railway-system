-- F3 | owner group: F3 (database tooling) | purpose: drop and recreate the empty railway_db database
DROP DATABASE IF EXISTS railway_db;
CREATE DATABASE railway_db CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
