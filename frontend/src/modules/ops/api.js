// G5 (Railway Operations & Analytics) - API functions.
// Every function wraps one REST endpoint from contract C9. The shared client
// (C10) already unwraps ApiResponse.data and throws ApiError on failure, so
// these functions simply return the payload.
import client from '@/api/client';

// ---------- G5 : live status (public) and status update (OPERATOR / ADMIN) ----------

// GET /ops/status?date=yyyy-MM-dd  -> rows of view v_train_live_status
export function getLiveStatus(date) {
  return client.get('/ops/status', { params: { date } });
}

// GET /ops/status/{runId} -> one row of v_train_live_status
export function getRunStatus(runId) {
  return client.get(`/ops/status/${runId}`);
}

// PUT /ops/status/{runId} body {status, delayMinutes, currentStationId, reason}
//   -> {runId, status, delayMinutes, updatedAt}
export function updateRunStatus(runId, body) {
  return client.put(`/ops/status/${runId}`, body);
}

// ---------- G5 : reports and dashboard (ADMIN) ----------

// GET /admin/reports/revenue?from&to -> rows of v_station_daily_revenue
export function getRevenueReport(from, to) {
  return client.get('/admin/reports/revenue', { params: { from, to } });
}

// POST /admin/reports/revenue/generate {date} -> {rowsAffected}
export function generateDailyRevenue(date) {
  return client.post('/admin/reports/revenue/generate', { date });
}

// GET /admin/reports/popular-routes -> rows of v_popular_routes
export function getPopularRoutes() {
  return client.get('/admin/reports/popular-routes');
}

// GET /admin/reports/delay-metrics -> rows of v_delay_metrics
export function getDelayMetrics() {
  return client.get('/admin/reports/delay-metrics');
}

// GET /admin/reports/delayed-trains?thresholdMinutes=15
//   -> [{trainId, trainNo, trainName, avgDelayMin, delayedRuns}]
export function getDelayedTrains(thresholdMinutes) {
  return client.get('/admin/reports/delayed-trains', { params: { thresholdMinutes } });
}

// GET /admin/reports/top-stations -> [{stationId, stationName, totalRevenue}]
export function getTopStations() {
  return client.get('/admin/reports/top-stations');
}

// GET /admin/dashboard/summary
//   -> {totalBookings, confirmedBookings, totalRevenue, activeTrains, delayedRunsToday, cancellationsToday}
export function getDashboardSummary() {
  return client.get('/admin/dashboard/summary');
}

// GET /admin/ops-events?limit=50 -> [{runId, status, delayMinutes, reason, changedBy, at}]
// (empty list when MongoDB is disabled on the backend)
export function getOpsEvents(limit = 50) {
  return client.get('/admin/ops-events', { params: { limit } });
}

// ---------- G1 / reference data used by the status update form ----------

// GET /trains -> list of trains (we use trainId, trainNo and trainName)
export function getTrains() {
  return client.get('/trains');
}

// GET /trains/{id}/runs?from&to -> [{runId, journeyDate}]
export function getTrainRuns(trainId, from, to) {
  return client.get(`/trains/${trainId}/runs`, { params: { from, to } });
}

// GET /stations -> [{stationId, stationCode, stationName, city, state}]
export function getStations() {
  return client.get('/stations');
}
