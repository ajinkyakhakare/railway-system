// G5 - Admin Dashboard (ADMIN).
// Six KPI cards (GET /admin/dashboard/summary), a bar chart of the top stations by revenue
// (GET /admin/reports/top-stations) and, when MongoDB is enabled on the backend, a table of the
// most recent operations events (GET /admin/ops-events).
import { Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import { useAsync } from '@/hooks/useAsync';
import { formatDateTime, formatMoney } from '@/utils/format';
import { Alert, Button, Card, PageHeader, Spinner, StatusBadge, Table } from '@/components/ui';
import { getDashboardSummary, getOpsEvents, getTopStations } from '../api.js';

const EVENT_LIMIT = 20; // number of recent events shown on the dashboard

// One KPI card: a title and a big number.
function KpiCard({ title, value }) {
  return (
    <Card title={title}>
      <p className="text-3xl font-semibold text-gray-900">{value}</p>
    </Card>
  );
}

// Keep the dashboard readable when a number is missing.
function numberOrDash(value) {
  return value === null || value === undefined ? '-' : Number(value).toLocaleString('en-IN');
}

export default function DashboardPage() {
  const summary = useAsync(() => getDashboardSummary(), []);
  const topStations = useAsync(() => getTopStations(), []);
  const events = useAsync(() => getOpsEvents(EVENT_LIMIT), []);

  function reloadAll() {
    summary.reload();
    topStations.reload();
    events.reload();
  }

  const s = summary.data || {};
  const chartRows = (topStations.data || []).map((row) => ({
    stationName: row.stationName,
    totalRevenue: Number(row.totalRevenue) || 0,
  }));
  const eventRows = events.data || [];

  const eventColumns = [
    { key: 'at', header: 'Time', render: (row) => (row.at ? formatDateTime(row.at) : '-') },
    { key: 'runId', header: 'Run' },
    { key: 'status', header: 'Status', render: (row) => <StatusBadge status={row.status} /> },
    { key: 'delayMinutes', header: 'Delay (min)' },
    { key: 'reason', header: 'Reason', render: (row) => row.reason || '-' },
    { key: 'changedBy', header: 'Changed by', render: (row) => row.changedBy || '-' },
  ];

  return (
    <div className="space-y-6">
      <PageHeader
        title="Operations Dashboard"
        subtitle="Key numbers of the railway system"
        actions={
          <Button variant="secondary" onClick={reloadAll}>
            Refresh
          </Button>
        }
      />

      {/* ---- KPI cards ---- */}
      {summary.error && <Alert tone="error">{summary.error.message}</Alert>}
      {summary.loading && !summary.data ? (
        <Spinner />
      ) : (
        summary.data && (
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <KpiCard title="Total bookings" value={numberOrDash(s.totalBookings)} />
            <KpiCard title="Confirmed bookings" value={numberOrDash(s.confirmedBookings)} />
            <KpiCard
              title="Total revenue"
              value={s.totalRevenue === null || s.totalRevenue === undefined ? '-' : formatMoney(s.totalRevenue)}
            />
            <KpiCard title="Active trains" value={numberOrDash(s.activeTrains)} />
            <KpiCard title="Delayed runs today" value={numberOrDash(s.delayedRunsToday)} />
            <KpiCard title="Cancellations today" value={numberOrDash(s.cancellationsToday)} />
          </div>
        )
      )}

      {/* ---- Top stations chart ---- */}
      <Card title="Top stations by revenue (above the station average)">
        {topStations.error && <Alert tone="error">{topStations.error.message}</Alert>}
        {topStations.loading && !topStations.data ? (
          <Spinner />
        ) : chartRows.length === 0 ? (
          !topStations.error && (
            <p className="text-sm text-gray-500">No station is above the average revenue yet.</p>
          )
        ) : (
          <div className="h-72 w-full">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={chartRows} margin={{ top: 8, right: 16, left: 8, bottom: 8 }}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="stationName" tick={{ fontSize: 12 }} />
                <YAxis tick={{ fontSize: 12 }} />
                <Tooltip formatter={(value) => formatMoney(value)} />
                <Bar dataKey="totalRevenue" name="Total revenue" fill="#2563eb" />
              </BarChart>
            </ResponsiveContainer>
          </div>
        )}
      </Card>

      {/* ---- Recent operations events (only when the backend returns rows) ---- */}
      {events.error && <Alert tone="error">{events.error.message}</Alert>}
      {eventRows.length > 0 && (
        <Card title="Recent operations events">
          <Table
            columns={eventColumns}
            rows={eventRows}
            rowKey={(row) => `${row.runId}-${row.at}-${row.status}-${row.delayMinutes}`}
          />
        </Card>
      )}
    </div>
  );
}
