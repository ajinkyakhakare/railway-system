// G3.5 - SeatMapPage  (route: /seat-map/:runId/:classCode, public)
// Draws every coach of the class as a grid of seats. Occupied seats are greyed out.
// The berth type of a seat is shown in its tooltip (title attribute).
import { useNavigate, useParams } from 'react-router-dom';
import { useAsync } from '@/hooks/useAsync';
import { formatDate } from '@/utils/format';
import { Alert, Button, Card, EmptyState, PageHeader, Spinner } from '@/components/ui';
import { berthName, getRun, getSeatMap } from '../api.js';

// Groups the flat seat list into coaches: [{coachNumber, seats:[...]}], both sorted.
function groupByCoach(seats) {
  const byCoach = new Map();
  seats.forEach((seat) => {
    if (!byCoach.has(seat.coachNumber)) byCoach.set(seat.coachNumber, []);
    byCoach.get(seat.coachNumber).push(seat);
  });

  return Array.from(byCoach.entries())
    .map(([coachNumber, coachSeats]) => ({
      coachNumber,
      seats: [...coachSeats].sort((a, b) => a.seatNo - b.seatNo),
    }))
    .sort((a, b) => a.coachNumber.localeCompare(b.coachNumber, undefined, { numeric: true }));
}

// One seat square. Free = green outline, occupied = grey.
function Seat({ seat }) {
  const berth = berthName(seat.berthType);
  const state = seat.occupied ? 'Occupied' : 'Free';
  const colours = seat.occupied
    ? 'border-gray-300 bg-gray-200 text-gray-400'
    : 'border-green-500 bg-green-50 text-green-800';
  return (
    <li
      title={`Seat ${seat.seatNo}: ${berth || seat.berthType} (${state})`}
      aria-label={`Seat ${seat.seatNo}, ${berth || seat.berthType}, ${state}`}
      className={`flex h-12 flex-col items-center justify-center rounded border text-xs ${colours}`}
    >
      <span className="font-semibold">{seat.seatNo}</span>
      <span className="text-[10px]">{seat.berthType}</span>
    </li>
  );
}

export default function SeatMapPage() {
  const { runId, classCode } = useParams();
  const navigate = useNavigate();

  const { data, loading, error } = useAsync(
    () => Promise.all([getRun(runId), getSeatMap(runId, classCode)]),
    [runId, classCode]
  );

  if (loading) return <Spinner />;
  if (error) return <Alert tone="error">{error.message}</Alert>;
  if (!data) return null;

  const [run, seats] = data;
  const coaches = groupByCoach(seats);
  const freeCount = seats.filter((seat) => !seat.occupied).length;

  return (
    <div className="space-y-4">
      <PageHeader
        title={`Seat map, class ${classCode}`}
        subtitle={`${run.trainNo} ${run.trainName}, ${formatDate(run.journeyDate)}`}
        actions={
          <Button variant="secondary" onClick={() => navigate(-1)}>
            Back
          </Button>
        }
      />

      {coaches.length === 0 ? (
        <EmptyState message={`This train has no seats in class ${classCode}.`} />
      ) : (
        <>
          <div className="flex flex-wrap items-center gap-4 text-sm text-gray-700">
            <span>
              {freeCount} free of {seats.length} seats
            </span>
            <span className="flex items-center gap-2">
              <span className="inline-block h-4 w-4 rounded border border-green-500 bg-green-50" />
              Free
            </span>
            <span className="flex items-center gap-2">
              <span className="inline-block h-4 w-4 rounded border border-gray-300 bg-gray-200" />
              Occupied
            </span>
            <span className="text-gray-500">Hover over a seat to see its berth type.</span>
          </div>

          {coaches.map((coach) => {
            const coachFree = coach.seats.filter((seat) => !seat.occupied).length;
            return (
              <Card
                key={coach.coachNumber}
                title={`Coach ${coach.coachNumber}`}
                actions={
                  <span className="text-sm text-gray-600">
                    {coachFree} of {coach.seats.length} free
                  </span>
                }
              >
                <ul className="grid grid-cols-6 gap-2 sm:grid-cols-8 md:grid-cols-12">
                  {coach.seats.map((seat) => (
                    <Seat key={seat.seatId} seat={seat} />
                  ))}
                </ul>
              </Card>
            );
          })}
        </>
      )}
    </div>
  );
}
