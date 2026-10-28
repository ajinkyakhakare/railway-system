// Task G1.5 | Group G1 (Train, Station & Route) | API functions for the trains module.
//
// One function per backend endpoint used by this module's pages.
// The shared client (C10) already:
//   - prefixes the base URL "/api/v1",
//   - sends the JWT (Authorization: Bearer ...),
//   - returns the UNWRAPPED "data" part of the ApiResponse envelope,
//   - throws an ApiError {code, message, status} on failure.
// So every function below simply returns a Promise of the payload.

import client from '@/api/client';

// ---------------------------------------------------------------- stations

/** GET /stations (PUBLIC) -> [{stationId, stationCode, stationName, city, state}] */
export function fetchStations() {
  return client.get('/stations');
}

/** POST /admin/stations (ADMIN) body {stationCode, stationName, city, state} -> station */
export function createStation(body) {
  return client.post('/admin/stations', body);
}

/** PUT /admin/stations/{id} (ADMIN) same body -> station */
export function updateStation(stationId, body) {
  return client.put(`/admin/stations/${stationId}`, body);
}

/** DELETE /admin/stations/{id} (ADMIN) -> {deleted: true} */
export function deleteStation(stationId) {
  return client.delete(`/admin/stations/${stationId}`);
}

// ------------------------------------------------------------------ routes

/** GET /routes (PUBLIC) -> [{routeId, routeName, sourceStationId, destStationId}] */
export function fetchRoutes() {
  return client.get('/routes');
}

/** GET /routes/{id}/stops (PUBLIC) -> stops ordered by stopSeq */
export function fetchRouteStops(routeId) {
  return client.get(`/routes/${routeId}/stops`);
}

/**
 * POST /admin/routes (ADMIN)
 * body {routeName, sourceStationId, destStationId,
 *       stops:[{stationId, stopSeq, arrivalTime, departureTime, dayOffset, distanceFromSourceKm}]}
 * -> {routeId}
 */
export function createRoute(body) {
  return client.post('/admin/routes', body);
}

// ------------------------------------------------------------- coach types

/** GET /coach-types (PUBLIC) -> [{coachTypeId, classCode, className, seatsPerCoach}] */
export function fetchCoachTypes() {
  return client.get('/coach-types');
}

// ------------------------------------------------------------------ trains

/** GET /trains (PUBLIC), optional q matches train name or number. */
export function fetchTrains(q) {
  const params = q ? { q } : {};
  return client.get('/trains', { params });
}

/** GET /trains/{id} (PUBLIC) -> one train row */
export function fetchTrain(trainId) {
  return client.get(`/trains/${trainId}`);
}

/** GET /trains/{id}/timetable (PUBLIC) = rows of view v_train_timetable */
export function fetchTrainTimetable(trainId) {
  return client.get(`/trains/${trainId}/timetable`);
}

/** GET /trains/{id}/coaches (PUBLIC) -> [{coachId, coachNumber, classCode, className, seatCount}] */
export function fetchTrainCoaches(trainId) {
  return client.get(`/trains/${trainId}/coaches`);
}

/**
 * GET /trains/search (PUBLIC) ?fromStationId&toStationId&date
 * -> [{runId, trainId, trainNo, trainName, trainType, fromStationId, toStationId,
 *      journeyDate, departureTime, arrivalTime, durationMin, distanceKm}]
 */
export function searchTrains({ fromStationId, toStationId, date }) {
  return client.get('/trains/search', { params: { fromStationId, toStationId, date } });
}

/** POST /admin/trains (ADMIN) body {trainNo, trainName, trainType, routeId, runDays:[1..7]} -> {trainId} */
export function createTrain(body) {
  return client.post('/admin/trains', body);
}

/** POST /admin/trains/{id}/coaches (ADMIN) body {coachTypeId, coachCount} -> {coachesAdded, seatsAdded} */
export function addCoaches(trainId, body) {
  return client.post(`/admin/trains/${trainId}/coaches`, body);
}

/** POST /admin/trains/{id}/runs/generate (ADMIN) body {fromDate, toDate} -> {runsCreated} */
export function generateRuns(trainId, body) {
  return client.post(`/admin/trains/${trainId}/runs/generate`, body);
}
