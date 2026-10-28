// G5 - Station-wise daily revenue report (ADMIN).
// Table + bar chart come from the view v_station_daily_revenue (filtered by Revenue_Date).
// The "Generate daily summary" button calls sp_generate_daily_revenue through the backend,
// which stores one day of revenue in the table station_daily_revenue.
import { useState } from 'react';
import { Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import { useAsync } from '@/hooks/useAsync';
import { formatDate, formatMoney, todayISO } from '@/utils/format';
import { Alert, Button, Card, Input, PageHeader, Spinner, Table } from '@/components/ui';
import { generateDailyRevenue, getRevenueReport } from '../api.js';

const DEFAULT_DAYS_BACK = 30;

// Date as yyyy-MM-dd, moved by a number of days from today (negative = past).
function dateFromToday(days) {
  const d = new Date();
  d.setDate(d.getDate() + days);
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

// The view has one row per station AND date. For the chart we add the dates up per station.
function totalsByStation(rows) {
  const totals = new Map();
  rows.forEach((row) => {
    const old = totals.get(row.stationName) || 0;
    totals.set(row.stationName, old + (Number(row.totalRevenue) || 0));
  });
  return Array.from(totals, ([stationName, totalRevenue]) => ({ stationName, totalRevenue })).sort(
    (a, b) => b.totalRevenue - a.totalRevenue
  );
}

export default function RevenueReportPage() {
  // What the person typed (draft) and what is actually used for the query (range).
  const [fromInput, setFromInput] = useState(dateFromToday(-DEFAULT_DAYS_BACK));
  const [toInput, setToInput] = useState(todayISO());
  const [range, setRange] = useState({ from: fromInput, to: toInput });
  const [rangeError, setRangeError] = useState('');

  // "Generate daily summary" state.
  const [generateDate, setGenerateDate] = useState(todayISO());
  const [generating, setGenerating] = useState(false);
  const [generateMessage, setGenerateMessage] = useState(null); // {tone, text}

  const report = useAsync(() => getRevenueReport(range.from, range.to), [range.from, range.to]);

  function applyRange() {
    if (!fromInput || !toInput) {
      setRangeError('Please enter both dates');
      return;
    }
    if (fromInput > toInput) {
      setRangeError('"From" date must not be after "To" date'); // yyyy-MM-dd compares correctly as text
      return;
    }
    setRangeError('');
    setRange({ from: fromInput, to: toInput });
  }

  async function handleGenerate() {
    if (!generateDate) {
      setGenerateMessage({ tone: 'error', text: 'Please choose a date' });
      return;
    }
    setGenerating(true);
    setGenerateMessage(null);
    try {
      const answer = await generateDailyRevenue(generateDate);
      setGenerateMessage({
        tone: 'success',
        text: `Daily summary for ${formatDate(generateDate)} generated. Rows affected: ${answer.rowsAffected}.`,
      });
      report.reload();
    } catch (err) {
      setGenerateMessage({ tone: 'error', text: err.message || 'Could not generate the summary' });
    } finally {
      setGenerating(false);
    }
  }

  const rows = report.data || [];
  const chartRows = totalsByStation(rows);
  const grandTotal = rows.reduce((sum, row) => sum + (Number(row.totalRevenue) || 0), 0);
  const ticketTotal = rows.reduce((sum, row) => sum + (Number(row.ticketCount) || 0), 0);

  const columns = [
    { key: 'revenueDate', header: 'Date', render: (row) => formatDate(row.revenueDate) },
    { key: 'stationCode', header: 'Code' },
    { key: 'stationName', header: 'Station' },
    { key: 'ticketCount', header: 'Tickets' },
    { key: 'totalRevenue', header: 'Revenue', render: (row) => formatMoney(row.totalRevenue) },
  ];

  return (
    <div className="space-y-6">
      <PageHeader
        title="Station-wise Daily Revenue"
        subtitle="Revenue of successful payments, grouped by origin station and date"
      />

      {/* ---- Filter ---- */}
      <Card title="Date range">
        <div className="grid items-end gap-4 md:grid-cols-3">
          <Input
            label="From"
            name="from"
            type="date"
            value={fromInput}
            onChange={(event) => setFromInput(event.target.value)}
          />
          <Input
            label="To"
            name="to"
            type="date"
            value={toInput}
            onChange={(event) => setToInput(event.target.value)}
          />
          <div>
            <Button onClick={applyRange} loading={report.loading}>
              Show report
            </Button>
          </div>
        </div>
        {rangeError && (
          <div className="mt-3">
            <Alert tone="error">{rangeError}</Alert>
          </div>
        )}
      </Card>

      {/* ---- Generate summary ---- */}
      <Card title="Generate daily summary">
        <div className="grid items-end gap-4 md:grid-cols-3">
          <Input
            label="Date"
            name="generateDate"
            type="date"
            value={generateDate}
            onChange={(event) => setGenerateDate(event.target.value)}
          />
          <div>
            <Button variant="secondary" onClick={handleGenerate} loading={generating}>
              Generate daily summary
            </Button>
          </div>
        </div>
        {generateMessage && (
          <div className="mt-3">
            <Alert tone={generateMessage.tone}>{generateMessage.text}</Alert>
          </div>
        )}
      </Card>

      {/* ---- Results ---- */}
      {report.error && <Alert tone="error">{report.error.message}</Alert>}

      {report.loading && !report.data ? (
        <Spinner />
      ) : (
        <>
          <Card title={`Revenue by station (${formatDate(range.from)} to ${formatDate(range.to)})`}>
            {chartRows.length === 0 ? (
              <p className="text-sm text-gray-500">No revenue found for this period.</p>
            ) : (
              <div className="h-80 w-full">
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

          <Card title="Daily details">
            {rows.length > 0 && (
              <p className="mb-3 text-sm text-gray-600">
                Total: {formatMoney(grandTotal)} from {ticketTotal} ticket(s)
              </p>
            )}
            <Table
              columns={columns}
              rows={rows}
              rowKey={(row) => `${row.stationId}-${row.revenueDate}`}
              emptyText="No revenue found for this period."
            />
          </Card>
        </>
      )}
    </div>
  );
}
