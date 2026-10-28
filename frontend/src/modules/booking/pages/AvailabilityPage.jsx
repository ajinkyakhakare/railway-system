// G3.5 - AvailabilityPage  (route: /availability/:runId?from=&to=)
// Shows the seat availability of every class of one train run.
// The "from" and "to" query parameters are station ids chosen on the search page;
// they are carried on to the booking page.
import { Link, useLocation, useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { useAuth } from '@/auth/AuthContext';
import { useAsync } from '@/hooks/useAsync';
import { formatDate } from '@/utils/format';
import { Alert, Badge, Button, Card, EmptyState, PageHeader, Spinner } from '@/components/ui';
import { getAvailability, getRun } from '../api.js';

// Availability_Text looks like "AVL 12", "RAC 3", "WL 5" or "REGRET".
// Colours: AVL green, RAC yellow, WL blue, REGRET red.
function availabilityTone(text) {
  const value = text || '';
  if (value.startsWith('AVL')) return 'green';
  if (value.startsWith('RAC')) return 'yellow';
  if (value.startsWith('WL')) return 'blue';
  return 'red';
}

export default function AvailabilityPage() {
  const { runId } = useParams();
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();
  const location = useLocation();
  const { isAuthenticated } = useAuth();

  const from = searchParams.get('from');
  const to = searchParams.get('to');
  const hasStations = Boolean(from && to);

  // Load the run (for the header) and the availability rows together.
  const { data, loading, error } = useAsync(
    () => Promise.all([getRun(runId), getAvailability(runId)]),
    [runId]
  );

  // Open the booking page; send anonymous visitors to the login page first.
  function handleBook(classCode) {
    const query = new URLSearchParams({ from, to }).toString();
    const target = { pathname: `/book/${runId}/${classCode}`, search: `?${query}` };
    if (!isAuthenticated) {
      // The login page can send the user back to "state.from" after sign-in.
      navigate('/login', { state: { from: target } });
      return;
    }
    navigate(target);
  }

  if (loading) return <Spinner />;
  if (error) return <Alert tone="error">{error.message}</Alert>;
  if (!data) return null;

  const [run, rows] = data;

  return (
    <div className="space-y-4">
      <PageHeader
        title={`${run.trainNo} ${run.trainName}`}
        subtitle={`Seat availability for ${formatDate(run.journeyDate)}`}
        actions={
          <Link to="/trains/search" className="text-sm text-blue-700 hover:underline">
            Search other trains
          </Link>
        }
      />

      {!hasStations && (
        <Alert tone="info">
          Booking needs a start and end station. Start from{' '}
          <Link to="/trains/search" className="underline">
            Search Trains
          </Link>{' '}
          and choose this train from the results.
        </Alert>
      )}

      {rows.length === 0 ? (
        <EmptyState message="No seat inventory exists for this run." />
      ) : (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {rows.map((row) => (
            <Card
              key={row.classCode}
              title={`Class ${row.classCode}`}
              actions={
                <Badge tone={availabilityTone(row.availabilityText)}>{row.availabilityText}</Badge>
              }
            >
              <dl className="space-y-1 text-sm text-gray-700">
                <div className="flex justify-between">
                  <dt>Confirmed seats free</dt>
                  <dd>
                    {row.availableCnf} of {row.totalSeats}
                  </dd>
                </div>
                <div className="flex justify-between">
                  <dt>RAC</dt>
                  <dd>
                    {row.racCount} of {row.maxRac}
                  </dd>
                </div>
                <div className="flex justify-between">
                  <dt>Waiting list</dt>
                  <dd>
                    {row.wlCount} of {row.maxWl}
                  </dd>
                </div>
              </dl>

              <div className="mt-4 flex items-center justify-between gap-3">
                <Button
                  onClick={() => handleBook(row.classCode)}
                  disabled={row.availabilityText === 'REGRET' || !hasStations}
                >
                  Book
                </Button>
                <Link
                  to={`/seat-map/${runId}/${row.classCode}`}
                  className="text-sm text-blue-700 hover:underline"
                >
                  View seat map
                </Link>
              </div>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
