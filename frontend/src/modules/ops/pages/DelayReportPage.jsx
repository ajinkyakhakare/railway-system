// G5 - Train delay report (ADMIN).
// Part 1: delay metrics per train (view v_delay_metrics) as a table and a bar chart of the average delay.
// Part 2: "delayed trains" report - trains whose AVERAGE delay is above a threshold chosen here
// (the backend uses GROUP BY train HAVING AVG(Delay_Minutes) > threshold).
import { useState } from 'react';
import { Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import { useAsync } from '@/hooks/useAsync';
import { Alert, Button, Card, Input, PageHeader, Spinner, Table } from '@/components/ui';
import { getDelayMetrics, getDelayedTrains } from '../api.js';

const DEFAULT_THRESHOLD = 15;

// Show a number with one decimal, or "-" when the database returned NULL.
function oneDecimal(value) {
  return value === null || value === undefined ? '-' : Number(value).toFixed(1);
}

export default function DelayReportPage() {
  // Threshold: what is typed (draft) and what is used for the query (applied).
  const [thresholdInput, setThresholdInput] = useState(String(DEFAULT_THRESHOLD));
  const [threshold, setThreshold] = useState(DEFAULT_THRESHOLD);
  const [thresholdError, setThresholdError] = useState('');

  const metrics = useAsync(() => getDelayMetrics(), []);
  const delayed = useAsync(() => getDelayedTrains(threshold), [threshold]);

  function applyThreshold() {
    if (!/^\d+$/.test(thresholdInput.trim())) {
      setThresholdError('Enter a whole number of minutes, 0 or more');
      return;
    }
    setThresholdError('');
    setThreshold(Number(thresholdInput.trim()));
  }

  const metricRows = metrics.data || [];
  const delayedRows = delayed.data || [];

  const chartRows = metricRows.map((row) => ({
    trainLabel: row.trainNo,
    trainName: row.trainName,
    avgDelayMin: Number(row.avgDelayMin) || 0,
  }));

  const metricColumns = [
    { key: 'trainNo', header: 'Train no.' },
    { key: 'trainName', header: 'Train' },
    { key: 'totalRuns', header: 'Total runs' },
    { key: 'delayedRuns', header: 'Delayed runs' },
    { key: 'avgDelayMin', header: 'Avg delay (min)', render: (row) => oneDecimal(row.avgDelayMin) },
    { key: 'maxDelayMin', header: 'Max delay (min)' },
  ];

  const delayedColumns = [
    { key: 'trainNo', header: 'Train no.' },
    { key: 'trainName', header: 'Train' },
    { key: 'avgDelayMin', header: 'Avg delay (min)', render: (row) => oneDecimal(row.avgDelayMin) },
    { key: 'delayedRuns', header: 'Delayed runs' },
  ];

  return (
    <div className="space-y-6">
      <PageHeader
        title="Train Delay Report"
        subtitle="How late the trains are running"
        actions={
          <Button
            variant="secondary"
            onClick={() => {
              metrics.reload();
              delayed.reload();
            }}
          >
            Refresh
          </Button>
        }
      />

      {/* ---- Part 1: delay metrics ---- */}
      {metrics.error && <Alert tone="error">{metrics.error.message}</Alert>}

      {metrics.loading && !metrics.data ? (
        <Spinner />
      ) : (
        <>
          <Card title="Delay metrics per train">
            <Table
              columns={metricColumns}
              rows={metricRows}
              rowKey="trainId"
              emptyText="No delay data found yet."
            />
          </Card>

          {chartRows.length > 0 && (
            <Card title="Average delay per train (minutes)">
              <div className="h-72 w-full">
                <ResponsiveContainer width="100%" height="100%">
                  <BarChart data={chartRows} margin={{ top: 8, right: 16, left: 8, bottom: 8 }}>
                    <CartesianGrid strokeDasharray="3 3" />
                    <XAxis dataKey="trainLabel" tick={{ fontSize: 12 }} />
                    <YAxis tick={{ fontSize: 12 }} />
                    <Tooltip
                      formatter={(value) => [`${Number(value).toFixed(1)} min`, 'Average delay']}
                      labelFormatter={(label, payload) =>
                        payload && payload.length > 0 ? `${label} - ${payload[0].payload.trainName}` : label
                      }
                    />
                    <Bar dataKey="avgDelayMin" name="Average delay" fill="#dc2626" />
                  </BarChart>
                </ResponsiveContainer>
              </div>
            </Card>
          )}
        </>
      )}

      {/* ---- Part 2: trains above a delay threshold ---- */}
      <Card title="Trains with average delay above a threshold">
        <div className="grid items-end gap-4 md:grid-cols-3">
          <Input
            label="Threshold (minutes)"
            name="thresholdMinutes"
            type="number"
            min="0"
            value={thresholdInput}
            onChange={(event) => setThresholdInput(event.target.value)}
            error={thresholdError}
          />
          <div>
            <Button onClick={applyThreshold} loading={delayed.loading}>
              Show trains
            </Button>
          </div>
        </div>

        <div className="mt-4">
          {delayed.error && <Alert tone="error">{delayed.error.message}</Alert>}
          {delayed.loading && !delayed.data ? (
            <Spinner />
          ) : (
            <Table
              columns={delayedColumns}
              rows={delayedRows}
              rowKey="trainId"
              emptyText={`No train has an average delay above ${threshold} minutes.`}
            />
          )}
        </div>
      </Card>
    </div>
  );
}
