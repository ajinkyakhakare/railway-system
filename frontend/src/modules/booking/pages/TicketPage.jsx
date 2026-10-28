// G3.5 - TicketPage  (route: /tickets/:pnr, public)
// Shows the status of one PNR: journey details and a list of passengers
// (index, status, coach, seat, berth). The public endpoint returns no passenger names.
import { Link, useParams } from 'react-router-dom';
import { useAsync } from '@/hooks/useAsync';
import { formatDate } from '@/utils/format';
import { Alert, Card, PageHeader, Spinner, StatusBadge, Table } from '@/components/ui';
import { berthName, getTicket } from '../api.js';

// Waiting-list and RAC passengers have no coach, seat or berth yet.
function orDash(value) {
  return value === null || value === undefined || value === '' ? '-' : value;
}

export default function TicketPage() {
  const { pnr } = useParams();
  const { data: ticket, loading, error } = useAsync(() => getTicket(pnr), [pnr]);

  const columns = [
    { key: 'index', header: 'Passenger' },
    {
      key: 'status',
      header: 'Status',
      render: (row) => <StatusBadge status={row.status} />,
    },
    { key: 'coachNumber', header: 'Coach', render: (row) => orDash(row.coachNumber) },
    { key: 'seatNo', header: 'Seat', render: (row) => orDash(row.seatNo) },
    {
      key: 'berthType',
      header: 'Berth',
      render: (row) => (row.berthType ? `${row.berthType} (${berthName(row.berthType)})` : '-'),
    },
  ];

  const backLink = (
    <Link to="/tickets" className="text-sm text-blue-700 hover:underline">
      Check another PNR
    </Link>
  );

  if (loading) return <Spinner />;

  if (error) {
    const notFound = error.status === 404 || error.code === 'NOT_FOUND';
    return (
      <div className="space-y-4">
        <PageHeader title="PNR status" actions={backLink} />
        <Alert tone="error">
          {notFound ? `No ticket was found for PNR ${pnr}. Check the number and try again.` : error.message}
        </Alert>
      </div>
    );
  }

  if (!ticket) return null;

  return (
    <div className="space-y-4">
      <PageHeader
        title={`PNR ${ticket.pnr}`}
        subtitle="Current status of this ticket"
        actions={backLink}
      />

      <Card
        title={`${ticket.trainNo} ${ticket.trainName}`}
        actions={<StatusBadge status={ticket.bookingStatus} />}
      >
        <dl className="grid gap-3 text-sm sm:grid-cols-4">
          <div>
            <dt className="text-gray-500">Journey date</dt>
            <dd className="font-medium">{formatDate(ticket.journeyDate)}</dd>
          </div>
          <div>
            <dt className="text-gray-500">From</dt>
            <dd className="font-medium">{ticket.fromStationCode}</dd>
          </div>
          <div>
            <dt className="text-gray-500">To</dt>
            <dd className="font-medium">{ticket.toStationCode}</dd>
          </div>
          <div>
            <dt className="text-gray-500">Class</dt>
            <dd className="font-medium">{ticket.classCode}</dd>
          </div>
        </dl>
      </Card>

      <Card title="Passengers">
        <Table
          columns={columns}
          rows={ticket.passengers || []}
          rowKey="index"
          emptyText="No passengers are listed for this PNR."
        />
      </Card>
    </div>
  );
}
