// G3.5 - AdminOccupancyPage  (route: /admin/occupancy, role ADMIN)
// Date picker + table of v_run_occupancy for that journey date.
// Occupancy_Rank is RANK() per date: 1 = fullest run and class.
import { useState } from 'react';
import { useAsync } from '@/hooks/useAsync';
import { formatDate, todayISO } from '@/utils/format';
import { Alert, Card, Input, PageHeader, Spinner, Table } from '@/components/ui';
import { getOccupancy } from '../api.js';

// Lowest rank first, then train number and class so equal ranks stay stable.
function sortRows(rows) {
  return [...rows].sort(
    (a, b) =>
      a.occupancyRank - b.occupancyRank ||
      String(a.trainNo).localeCompare(String(b.trainNo)) ||
      String(a.classCode).localeCompare(String(b.classCode))
  );
}

// Text plus a thin bar so the fullest runs stand out.
function OccupancyBar({ percent }) {
  const value = Math.min(Math.max(Number(percent) || 0, 0), 100);
  return (
    <div className="flex items-center gap-2">
      <div className="h-2 w-24 rounded bg-gray-200">
        <div className="h-2 rounded bg-blue-600" style={{ width: `${value}%` }} />
      </div>
      <span className="tabular-nums">{value.toFixed(1)}%</span>
    </div>
  );
}

const COLUMNS = [
  { key: 'occupancyRank', header: 'Rank', render: (row) => `#${row.occupancyRank}` },
  { key: 'trainNo', header: 'Train no.' },
  { key: 'journeyDate', header: 'Journey date', render: (row) => formatDate(row.journeyDate) },
  { key: 'classCode', header: 'Class' },
  { key: 'totalSeats', header: 'Total seats' },
  { key: 'bookedSeats', header: 'Booked seats' },
  {
    key: 'occupancyPct',
    header: 'Occupancy',
    render: (row) => <OccupancyBar percent={row.occupancyPct} />,
  },
];

export default function AdminOccupancyPage() {
  const [date, setDate] = useState(todayISO());

  // Without a date there is nothing to ask the server for.
  const { data, loading, error } = useAsync(
    () => (date ? getOccupancy(date) : Promise.resolve([])),
    [date]
  );

  const rows = sortRows(data || []);

  return (
    <div className="space-y-4">
      <PageHeader
        title="Occupancy"
        subtitle="How full each train run is, ranked per journey date"
      />

      <Card>
        <div className="max-w-xs">
          <Input
            label="Journey date"
            name="date"
            type="date"
            value={date}
            onChange={(event) => setDate(event.target.value)}
          />
        </div>
      </Card>

      {!date && <Alert tone="info">Choose a journey date to see the occupancy.</Alert>}

      {date && loading && <Spinner />}

      {date && !loading && error && <Alert tone="error">{error.message}</Alert>}

      {date && !loading && !error && (
        <Card title={`Runs on ${formatDate(date)}`}>
          <Table
            columns={COLUMNS}
            rows={rows}
            rowKey={(row) => `${row.runId ?? row.trainNo}-${row.classCode}`}
            emptyText="No runs found for this date."
          />
        </Card>
      )}
    </div>
  );
}
