// G3.5 - MyBookingsPage  (route: /my-bookings)
// Lists the logged-in user's bookings. A booking row can be expanded to show its
// passengers (loaded on first expand with GET /bookings/:id).
// Links: PNR -> /tickets/:pnr, "Pay now" -> /payment/:id, "Cancel" -> /cancel/:bookingPassengerId.
import { Fragment, useState } from 'react';
import { Link } from 'react-router-dom';
import { useAsync } from '@/hooks/useAsync';
import { formatDate, formatDateTime, formatMoney } from '@/utils/format';
import { Alert, Card, EmptyState, PageHeader, Spinner, StatusBadge } from '@/components/ui';
import { berthName, getBooking, getMyBookings } from '../api.js';

// Same look as a primary button, but it is a router link.
const PAY_LINK_CLASS =
  'inline-flex items-center rounded-md bg-blue-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-blue-700';

// Shows "S1 / 14 (Lower berth)" or "-" while a passenger has no seat (RAC or WL).
function seatText(passenger) {
  if (!passenger.coachNumber || !passenger.seatNo) return '-';
  const berth = berthName(passenger.berthType);
  return `${passenger.coachNumber} / ${passenger.seatNo}${berth ? ` (${berth})` : ''}`;
}

// The expanded part of one booking: its passenger table.
function PassengerRows({ state }) {
  if (!state || state.loading) return <Spinner />;
  if (state.error) return <Alert tone="error">{state.error.message}</Alert>;

  const passengers = state.data.passengers || [];
  if (passengers.length === 0) return <EmptyState message="This booking has no passengers." />;

  return (
    <table className="min-w-full text-sm">
      <thead>
        <tr className="text-left text-xs text-gray-500">
          <th className="px-3 py-2 font-medium">Passenger</th>
          <th className="px-3 py-2 font-medium">Status</th>
          <th className="px-3 py-2 font-medium">Coach / seat</th>
          <th className="px-3 py-2 font-medium">Fare</th>
          <th className="px-3 py-2 font-medium">Action</th>
        </tr>
      </thead>
      <tbody>
        {passengers.map((p) => (
          <tr key={p.bookingPassengerId} className="border-t border-gray-200">
            <td className="px-3 py-2">{p.passengerName}</td>
            <td className="px-3 py-2">
              <StatusBadge status={p.status} />
            </td>
            <td className="px-3 py-2">{seatText(p)}</td>
            <td className="px-3 py-2">{formatMoney(p.fareAmount)}</td>
            <td className="px-3 py-2">
              {p.status === 'CANCELLED' ? (
                <span className="text-gray-400">Cancelled</span>
              ) : (
                <Link
                  to={`/cancel/${p.bookingPassengerId}`}
                  className="text-red-700 hover:underline"
                >
                  Cancel
                </Link>
              )}
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

export default function MyBookingsPage() {
  const { data, loading, error, reload } = useAsync(() => getMyBookings(), []);

  // open:    { [bookingId]: true/false }   which rows are expanded
  // details: { [bookingId]: {loading, error, data} }   passenger data per booking
  const [open, setOpen] = useState({});
  const [details, setDetails] = useState({});

  async function loadDetails(bookingId) {
    setDetails((current) => ({ ...current, [bookingId]: { loading: true } }));
    try {
      const booking = await getBooking(bookingId);
      setDetails((current) => ({ ...current, [bookingId]: { data: booking } }));
    } catch (err) {
      setDetails((current) => ({ ...current, [bookingId]: { error: err } }));
    }
  }

  function toggleRow(bookingId) {
    const willOpen = !open[bookingId];
    setOpen((current) => ({ ...current, [bookingId]: willOpen }));
    // Load the passengers the first time (or again after an earlier error).
    const known = details[bookingId];
    if (willOpen && (!known || known.error)) loadDetails(bookingId);
  }

  const bookings = data || [];

  return (
    <div className="space-y-4">
      <PageHeader
        title="My bookings"
        subtitle="Your tickets, newest first"
        actions={
          <Link to="/trains/search" className="text-sm text-blue-700 hover:underline">
            Book a new ticket
          </Link>
        }
      />

      {loading && <Spinner />}

      {!loading && error && (
        <Alert tone="error">
          <div className="flex items-center justify-between gap-3">
            <span>{error.message}</span>
            <button type="button" onClick={reload} className="underline">
              Try again
            </button>
          </div>
        </Alert>
      )}

      {!loading && !error && bookings.length === 0 && (
        <Card>
          <EmptyState message="You have not booked any tickets yet." />
          <p className="mt-2 text-center text-sm">
            <Link to="/trains/search" className="text-blue-700 hover:underline">
              Search trains
            </Link>
          </p>
        </Card>
      )}

      {!loading && !error && bookings.length > 0 && (
        <Card>
          <div className="overflow-x-auto">
            <table className="min-w-full text-sm">
              <thead>
                <tr className="bg-gray-50 text-left text-xs text-gray-600">
                  <th className="px-3 py-2 font-medium">PNR</th>
                  <th className="px-3 py-2 font-medium">Train</th>
                  <th className="px-3 py-2 font-medium">Journey date</th>
                  <th className="px-3 py-2 font-medium">Route</th>
                  <th className="px-3 py-2 font-medium">Class</th>
                  <th className="px-3 py-2 font-medium">Status</th>
                  <th className="px-3 py-2 font-medium">Total fare</th>
                  <th className="px-3 py-2 font-medium">Booked at</th>
                  <th className="px-3 py-2 font-medium">Actions</th>
                </tr>
              </thead>
              <tbody>
                {bookings.map((b) => {
                  const isOpen = Boolean(open[b.bookingId]);
                  return (
                    <Fragment key={b.bookingId}>
                      <tr className="border-t border-gray-200">
                        <td className="px-3 py-2 font-mono">
                          <Link to={`/tickets/${b.pnr}`} className="text-blue-700 hover:underline">
                            {b.pnr}
                          </Link>
                        </td>
                        <td className="px-3 py-2">
                          {b.trainNo} {b.trainName}
                        </td>
                        <td className="px-3 py-2">{formatDate(b.journeyDate)}</td>
                        <td className="px-3 py-2">
                          {b.fromStationCode} to {b.toStationCode}
                        </td>
                        <td className="px-3 py-2">{b.classCode}</td>
                        <td className="px-3 py-2">
                          <StatusBadge status={b.bookingStatus} />
                        </td>
                        <td className="px-3 py-2">{formatMoney(b.totalFare)}</td>
                        <td className="px-3 py-2">{formatDateTime(b.bookedAt)}</td>
                        <td className="px-3 py-2">
                          <div className="flex items-center gap-3">
                            {b.bookingStatus === 'PENDING_PAYMENT' && (
                              <Link to={`/payment/${b.bookingId}`} className={PAY_LINK_CLASS}>
                                Pay now
                              </Link>
                            )}
                            <button
                              type="button"
                              onClick={() => toggleRow(b.bookingId)}
                              aria-expanded={isOpen}
                              className="text-blue-700 hover:underline"
                            >
                              {isOpen ? 'Hide passengers' : 'Show passengers'}
                            </button>
                          </div>
                        </td>
                      </tr>
                      {isOpen && (
                        <tr className="bg-gray-50">
                          <td colSpan={9} className="px-3 py-3">
                            <PassengerRows state={details[b.bookingId]} />
                          </td>
                        </tr>
                      )}
                    </Fragment>
                  );
                })}
              </tbody>
            </table>
          </div>
        </Card>
      )}
    </div>
  );
}
