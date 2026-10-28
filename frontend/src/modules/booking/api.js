// G3.5 - Booking module API functions.
// Every function calls the shared axios client (C10). The client already prefixes
// "/api/v1" and returns the unwrapped ApiResponse.data, so callers get plain data.
// Failures throw ApiError {code, message, status}.
import client from '@/api/client';

// ---- Endpoints owned by G1 (train) that this module needs for page headers ----

// GET /runs/{runId} -> {runId, trainId, trainNo, trainName, journeyDate, routeId}
export function getRun(runId) {
  return client.get(`/runs/${runId}`);
}

// ---- Endpoints owned by G2 (user) ----

// GET /passengers -> the logged-in user's saved passengers
export function getPassengers() {
  return client.get('/passengers');
}

// ---- Endpoints owned by G4 (payment) ----

// GET /fares/quote -> {distanceKm, totalFare, passengers:[{passengerId, passengerName,
// concessionType, baseFare, netFare}]}. passengerIds is sent as "1,2,3".
export function getFareQuote({ runId, classCode, fromStationId, toStationId, passengerIds }) {
  return client.get('/fares/quote', {
    params: {
      runId,
      classCode,
      fromStationId,
      toStationId,
      passengerIds: passengerIds.join(','),
    },
  });
}

// ---- Endpoints owned by G3 (booking) ----

// GET /availability?runId= -> rows of v_seat_availability (one per class)
export function getAvailability(runId) {
  return client.get('/availability', { params: { runId } });
}

// POST /bookings -> {bookingId, pnr, totalFare, passengers:[...]}
// body = {runId, classCode, fromStationId, toStationId, passengerIds:[...]}
export function createBooking(body) {
  return client.post('/bookings', body);
}

// GET /bookings/my -> list of the user's bookings, newest first
export function getMyBookings() {
  return client.get('/bookings/my');
}

// GET /bookings/{bookingId} -> one booking with its passengers (owner or ADMIN)
export function getBooking(bookingId) {
  return client.get(`/bookings/${bookingId}`);
}

// GET /tickets/{pnr} -> public PNR status (no passenger names)
export function getTicket(pnr) {
  return client.get(`/tickets/${encodeURIComponent(pnr)}`);
}

// GET /runs/{runId}/seat-map?classCode= -> [{seatId, coachNumber, seatNo, berthType, occupied}]
export function getSeatMap(runId, classCode) {
  return client.get(`/runs/${runId}/seat-map`, { params: { classCode } });
}

// GET /admin/occupancy?date= -> rows of v_run_occupancy for that journey date
export function getOccupancy(date) {
  return client.get('/admin/occupancy', { params: { date } });
}

// ---- Small display helper shared by the pages of this module ----

// Berth codes come from the seat.Berth_Type column (see contract C4).
const BERTH_NAMES = {
  LB: 'Lower berth',
  MB: 'Middle berth',
  UB: 'Upper berth',
  SL: 'Side lower berth',
  SU: 'Side upper berth',
  W: 'Window seat',
  M: 'Middle seat',
  A: 'Aisle seat',
};

// Returns a readable name for a berth code; unknown codes are shown as they are.
export function berthName(code) {
  if (!code) return '';
  return BERTH_NAMES[code] || code;
}
