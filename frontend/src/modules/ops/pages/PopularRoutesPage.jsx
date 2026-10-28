// G5 - Popular routes (ADMIN).
// Data comes from the view v_popular_routes, where the database already ranks routes with
// RANK() OVER (ORDER BY Booking_Count DESC). We show a ranking table and a horizontal bar chart.
import { Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import { useAsync } from '@/hooks/useAsync';
import { Alert, Button, Card, PageHeader, Spinner, Table } from '@/components/ui';
import { getPopularRoutes } from '../api.js';

const ROW_HEIGHT = 48; // chart height per route, so long lists stay readable

export default function PopularRoutesPage() {
  const { data, loading, error, reload } = useAsync(() => getPopularRoutes(), []);

  // Best rank first (rank 1 on top).
  const rows = [...(data || [])].sort((a, b) => a.popularityRank - b.popularityRank);

  const columns = [
    { key: 'popularityRank', header: 'Rank' },
    { key: 'routeName', header: 'Route' },
    { key: 'bookingCount', header: 'Bookings' },
  ];

  const chartRows = rows.map((row) => ({
    routeName: row.routeName,
    bookingCount: Number(row.bookingCount) || 0,
  }));

  return (
    <div className="space-y-6">
      <PageHeader
        title="Popular Routes"
        subtitle="Routes ranked by number of bookings (expired bookings are not counted)"
        actions={
          <Button variant="secondary" onClick={() => reload()} loading={loading}>
            Refresh
          </Button>
        }
      />

      {error && <Alert tone="error">{error.message}</Alert>}

      {loading && !data ? (
        <Spinner />
      ) : (
        <>
          <Card title="Ranking">
            <Table
              columns={columns}
              rows={rows}
              rowKey="routeId"
              emptyText="No bookings found yet."
            />
          </Card>

          {chartRows.length > 0 && (
            <Card title="Bookings per route">
              <div className="w-full" style={{ height: Math.max(240, chartRows.length * ROW_HEIGHT) }}>
                <ResponsiveContainer width="100%" height="100%">
                  {/* layout="vertical" turns the chart into horizontal bars */}
                  <BarChart
                    data={chartRows}
                    layout="vertical"
                    margin={{ top: 8, right: 24, left: 8, bottom: 8 }}
                  >
                    <CartesianGrid strokeDasharray="3 3" />
                    <XAxis type="number" allowDecimals={false} tick={{ fontSize: 12 }} />
                    <YAxis type="category" dataKey="routeName" width={200} tick={{ fontSize: 12 }} />
                    <Tooltip />
                    <Bar dataKey="bookingCount" name="Bookings" fill="#2563eb" />
                  </BarChart>
                </ResponsiveContainer>
              </div>
            </Card>
          )}
        </>
      )}
    </div>
  );
}
