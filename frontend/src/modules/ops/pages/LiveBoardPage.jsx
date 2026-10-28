// G5 - Live Board (public).
// Shows the running status of every train run on a chosen date (view v_train_live_status).
// The list refreshes by itself every 30 seconds; the person can also refresh manually.
import { useEffect, useRef, useState } from 'react';
import { useAsync } from '@/hooks/useAsync';
import { formatDateTime, todayISO } from '@/utils/format';
import { Alert, Button, Card, Input, PageHeader, Spinner, StatusBadge, Table } from '@/components/ui';
import { getLiveStatus } from '../api.js';

const REFRESH_MS = 30 * 1000; // auto-refresh interval

// Current clock time as hh:mm:ss (24 hour), shown after every successful load.
function clockTime() {
  return new Date().toLocaleTimeString('en-GB');
}

export default function LiveBoardPage() {
  const [date, setDate] = useState(todayISO());
  const [updatedAt, setUpdatedAt] = useState(null);

  // An empty date input would make a bad request, so in that case we just return an empty list.
  const { data, loading, error, reload } = useAsync(
    () => (date ? getLiveStatus(date) : Promise.resolve([])),
    [date]
  );

  // Keep the newest reload function in a ref, so the timer below can be created only once.
  const reloadRef = useRef(reload);
  useEffect(() => {
    reloadRef.current = reload;
  });

  // Every time new data arrives, remember when it arrived.
  useEffect(() => {
    if (data) setUpdatedAt(clockTime());
  }, [data]);

  // Auto-refresh timer (cleaned up when the page is left).
  useEffect(() => {
    const timerId = setInterval(() => reloadRef.current(), REFRESH_MS);
    return () => clearInterval(timerId);
  }, []);

  const columns = [
    {
      key: 'train',
      header: 'Train',
      render: (row) => `${row.trainNo} - ${row.trainName}`,
    },
    {
      key: 'status',
      header: 'Status',
      render: (row) => <StatusBadge status={row.status} />,
    },
    {
      key: 'delayMinutes',
      header: 'Delay',
      render: (row) =>
        row.delayMinutes > 0 ? (
          <span className="font-medium text-red-600">+{row.delayMinutes} min</span>
        ) : (
          <span className="text-gray-500">-</span>
        ),
    },
    {
      key: 'currentStationName',
      header: 'Current station',
      render: (row) => row.currentStationName || '-',
    },
    {
      key: 'lastReason',
      header: 'Reason',
      render: (row) => row.lastReason || '-',
    },
    {
      key: 'updatedAt',
      header: 'Last update',
      render: (row) => (row.updatedAt ? formatDateTime(row.updatedAt) : '-'),
    },
  ];

  // Spinner only on the very first load; later refreshes keep the old table visible.
  const showSpinner = loading && !data;

  return (
    <div className="space-y-6">
      <PageHeader
        title="Live Train Board"
        subtitle="Running status of all trains for the selected date"
        actions={
          <div className="flex items-center gap-3">
            <span className="text-sm text-gray-600">
              {updatedAt ? `Updated ${updatedAt}` : 'Not updated yet'} (auto-refresh every 30 s)
            </span>
            <Button variant="secondary" onClick={() => reload()} loading={loading}>
              Refresh
            </Button>
          </div>
        }
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

      {error && <Alert tone="error">{error.message}</Alert>}

      <Card>
        {showSpinner ? (
          <Spinner />
        ) : (
          <Table
            columns={columns}
            rows={data || []}
            rowKey="runId"
            emptyText="No train runs found for this date."
          />
        )}
      </Card>
    </div>
  );
}
