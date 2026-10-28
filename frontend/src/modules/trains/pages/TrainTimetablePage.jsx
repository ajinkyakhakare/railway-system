// Task G1.5 | Group G1 (Train, Station & Route) | Public page: timetable and coaches of one train (/trains/:trainId).
//
// Three endpoints are loaded together:
//   GET /trains/{id}            -> header information
//   GET /trains/{id}/timetable  -> table of stops
//   GET /trains/{id}/coaches    -> coach list, summarised per class below

import { Link, useNavigate, useParams } from 'react-router-dom';
import { useAsync } from '@/hooks/useAsync';
import { Alert, Badge, Button, Card, PageHeader, Spinner, Table } from '@/components/ui';
import { formatTime } from '@/utils/format';
import { fetchTrain, fetchTrainCoaches, fetchTrainTimetable } from '../api';

/** Shows "06:00" or a dash when the time is missing (first stop has no arrival, last has no departure). */
function showTime(value) {
  return value ? formatTime(value) : '—';
}

/**
 * Turns the flat coach list into one summary row per class:
 * [{classCode, className, coachNumbers:['S1','S2'], seats: 144}]
 */
function summariseCoaches(coaches) {
  const byClass = new Map();
  coaches.forEach((coach) => {
    const entry = byClass.get(coach.classCode) || {
      classCode: coach.classCode,
      className: coach.className,
      coachNumbers: [],
      seats: 0,
    };
    entry.coachNumbers.push(coach.coachNumber);
    entry.seats += Number(coach.seatCount);
    byClass.set(coach.classCode, entry);
  });
  return Array.from(byClass.values());
}

/** Loads everything the page needs with one call so there is a single loading / error state. */
async function loadTimetable(trainId) {
  const [train, stops, coaches] = await Promise.all([
    fetchTrain(trainId),
    fetchTrainTimetable(trainId),
    fetchTrainCoaches(trainId),
  ]);
  return { train, stops, coaches };
}

export default function TrainTimetablePage() {
  const { trainId } = useParams();
  const navigate = useNavigate();

  const pageState = useAsync(() => loadTimetable(trainId), [trainId]);

  const stopColumns = [
    { key: 'stopSeq', header: 'Seq' },
    {
      key: 'stationName',
      header: 'Station',
      render: (row) => `${row.stationName} (${row.stationCode})`,
    },
    { key: 'arrivalTime', header: 'Arrival', render: (row) => showTime(row.arrivalTime) },
    { key: 'departureTime', header: 'Departure', render: (row) => showTime(row.departureTime) },
    // Day_Offset is "days since the journey started", so the first day is Day 1.
    { key: 'dayOffset', header: 'Day', render: (row) => `Day ${Number(row.dayOffset) + 1}` },
    { key: 'distanceFromSourceKm', header: 'Km', render: (row) => `${row.distanceFromSourceKm} km` },
  ];

  const coachColumns = [
    { key: 'className', header: 'Class', render: (row) => `${row.className} (${row.classCode})` },
    { key: 'coachCount', header: 'Coaches', render: (row) => row.coachNumbers.length },
    { key: 'coachNumbers', header: 'Coach numbers', render: (row) => row.coachNumbers.join(', ') },
    { key: 'seats', header: 'Total seats' },
  ];

  const headerActions = (
    <div className="flex gap-2">
      <Button variant="secondary" onClick={() => navigate('/trains')}>
        All trains
      </Button>
      <Button onClick={() => navigate('/trains/search')}>Search trains</Button>
    </div>
  );

  // ---- loading / error states ----
  if (pageState.loading && !pageState.data) {
    return <Spinner />;
  }

  if (pageState.error) {
    return (
      <div className="space-y-4">
        <Alert tone="error">{pageState.error.message}</Alert>
        <Link to="/trains" className="font-medium text-blue-600 hover:underline">
          Back to all trains
        </Link>
      </div>
    );
  }

  if (!pageState.data) {
    return null;
  }

  const { train, stops, coaches } = pageState.data;
  const coachSummary = summariseCoaches(coaches);

  return (
    <div className="space-y-6">
      <PageHeader
        title={`${train.trainNo} ${train.trainName}`}
        subtitle={`Route: ${train.routeName}`}
        actions={headerActions}
      />

      {/* Train information. */}
      <Card title="Train details">
        <dl className="grid gap-4 sm:grid-cols-2 md:grid-cols-4">
          <div>
            <dt className="text-sm text-gray-500">Train number</dt>
            <dd className="font-medium">{train.trainNo}</dd>
          </div>
          <div>
            <dt className="text-sm text-gray-500">Type</dt>
            <dd>
              <Badge tone="blue">{train.trainType}</Badge>
            </dd>
          </div>
          <div>
            <dt className="text-sm text-gray-500">Route</dt>
            <dd className="font-medium">{train.routeName}</dd>
          </div>
          <div>
            <dt className="text-sm text-gray-500">Status</dt>
            <dd>
              {train.isActive ? <Badge tone="green">Active</Badge> : <Badge tone="gray">Inactive</Badge>}
            </dd>
          </div>
        </dl>
      </Card>

      {/* Stops in running order. */}
      <Card title="Timetable">
        <Table columns={stopColumns} rows={stops} rowKey="stopSeq" emptyText="No stops defined for this train." />
      </Card>

      {/* Coach composition. */}
      <Card title="Coaches">
        <Table
          columns={coachColumns}
          rows={coachSummary}
          rowKey="classCode"
          emptyText="No coaches have been added to this train yet."
        />
      </Card>
    </div>
  );
}
