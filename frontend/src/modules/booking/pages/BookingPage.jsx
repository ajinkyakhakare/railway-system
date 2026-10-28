// G3.5 - BookingPage  (route: /book/:runId/:classCode?from=&to=)
// 1. The user ticks up to 6 saved passengers.
// 2. The fare quote (GET /fares/quote) is reloaded whenever the selection changes.
// 3. "Book and continue" calls POST /bookings, shows the CNF/RAC/WL result for 1.5 s,
//    then moves on to /payment/<bookingId>.
import { useEffect, useRef, useState } from 'react';
import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { useAsync } from '@/hooks/useAsync';
import { formatDate, formatMoney } from '@/utils/format';
import {
  Alert,
  Badge,
  Button,
  Card,
  EmptyState,
  PageHeader,
  Spinner,
  StatusBadge,
  Table,
} from '@/components/ui';
import { createBooking, getFareQuote, getPassengers, getRun } from '../api.js';

const MAX_PASSENGERS = 6; // same limit as sp_book_ticket
const REDIRECT_DELAY_MS = 1500;

// Rounds money differences to 2 decimals (avoids 0.30000000000000004).
function roundMoney(value) {
  return Math.round(value * 100) / 100;
}

export default function BookingPage() {
  const { runId, classCode } = useParams();
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();

  // Station ids come from the query string; both must be valid and different.
  const fromId = Number(searchParams.get('from'));
  const toId = Number(searchParams.get('to'));
  const stationsValid =
    Number.isInteger(fromId) && fromId > 0 && Number.isInteger(toId) && toId > 0 && fromId !== toId;

  // Run header and the user's passengers load together.
  const { data, loading, error } = useAsync(
    () => Promise.all([getRun(runId), getPassengers()]),
    [runId]
  );

  const [selectedIds, setSelectedIds] = useState([]);
  const [quote, setQuote] = useState(null);
  const [quoteLoading, setQuoteLoading] = useState(false);
  const [quoteError, setQuoteError] = useState(null);
  const [submitting, setSubmitting] = useState(false);
  const [submitError, setSubmitError] = useState(null);
  const [booked, setBooked] = useState(null); // result of POST /bookings
  const redirectTimer = useRef(null);

  // Stop the pending redirect if the user leaves the page.
  useEffect(() => {
    return () => {
      if (redirectTimer.current) clearTimeout(redirectTimer.current);
    };
  }, []);

  // Reload the fare quote whenever the selection (or journey) changes.
  const selectionKey = selectedIds.join(',');
  useEffect(() => {
    if (!stationsValid || selectedIds.length === 0) {
      setQuote(null);
      setQuoteError(null);
      setQuoteLoading(false);
      return undefined;
    }

    // "cancelled" ignores the answer of an outdated request.
    let cancelled = false;
    setQuoteLoading(true);
    setQuoteError(null);

    getFareQuote({
      runId: Number(runId),
      classCode,
      fromStationId: fromId,
      toStationId: toId,
      passengerIds: selectedIds,
    })
      .then((result) => {
        if (!cancelled) setQuote(result);
      })
      .catch((err) => {
        if (!cancelled) {
          setQuote(null);
          setQuoteError(err);
        }
      })
      .finally(() => {
        if (!cancelled) setQuoteLoading(false);
      });

    return () => {
      cancelled = true;
    };
    // selectionKey stands for selectedIds (a new array on every change).
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [runId, classCode, fromId, toId, stationsValid, selectionKey]);

  function togglePassenger(passengerId) {
    setSelectedIds((current) => {
      if (current.includes(passengerId)) {
        return current.filter((id) => id !== passengerId);
      }
      if (current.length >= MAX_PASSENGERS) return current;
      return [...current, passengerId];
    });
  }

  async function handleBook() {
    setSubmitError(null);
    setSubmitting(true);
    try {
      const result = await createBooking({
        runId: Number(runId),
        classCode,
        fromStationId: fromId,
        toStationId: toId,
        passengerIds: selectedIds,
      });
      setBooked(result);
      // Keep "submitting" true so the button cannot be pressed twice.
      redirectTimer.current = setTimeout(() => {
        navigate(`/payment/${result.bookingId}`);
      }, REDIRECT_DELAY_MS);
    } catch (err) {
      // Server errors such as SEAT_UNAVAILABLE or BOOKING_CLOSED_WL_FULL.
      setSubmitError(err);
      setSubmitting(false);
    }
  }

  if (loading) return <Spinner />;
  if (error) return <Alert tone="error">{error.message}</Alert>;
  if (!data) return null;

  const [run, passengers] = data;
  const limitReached = selectedIds.length >= MAX_PASSENGERS;
  const canBook =
    stationsValid && selectedIds.length > 0 && !quoteLoading && !quoteError && !submitting;

  const quoteColumns = [
    { key: 'passengerName', header: 'Passenger' },
    {
      key: 'concessionType',
      header: 'Concession',
      render: (row) => <Badge tone={row.concessionType === 'NONE' ? 'gray' : 'green'}>{row.concessionType}</Badge>,
    },
    { key: 'baseFare', header: 'Base fare', render: (row) => formatMoney(row.baseFare) },
    {
      key: 'discount',
      header: 'Concession amount',
      render: (row) => formatMoney(roundMoney(row.baseFare - row.netFare)),
    },
    { key: 'netFare', header: 'Net fare', render: (row) => formatMoney(row.netFare) },
  ];

  return (
    <div className="space-y-4">
      <PageHeader
        title="Book tickets"
        subtitle={`${run.trainNo} ${run.trainName}, ${formatDate(run.journeyDate)}, class ${classCode}`}
        actions={
          <Link
            to={`/availability/${runId}?from=${fromId}&to=${toId}`}
            className="text-sm text-blue-700 hover:underline"
          >
            Back to availability
          </Link>
        }
      />

      {!stationsValid && (
        <Alert tone="error">
          The start or end station is missing in the link. Go to{' '}
          <Link to="/trains/search" className="underline">
            Search Trains
          </Link>{' '}
          and choose the train again.
        </Alert>
      )}

      <Card title={`Choose passengers (up to ${MAX_PASSENGERS})`}>
        {passengers.length === 0 ? (
          <div className="space-y-2">
            <EmptyState message="You have no saved passengers yet." />
            <p className="text-center text-sm">
              <Link to="/passengers" className="text-blue-700 hover:underline">
                Add a passenger
              </Link>{' '}
              and come back to book.
            </p>
          </div>
        ) : (
          <ul className="divide-y divide-gray-100">
            {passengers.map((p) => {
              const checked = selectedIds.includes(p.passengerId);
              // Block new ticks once 6 are chosen, but allow un-ticking.
              const disabled = !checked && limitReached;
              return (
                <li key={p.passengerId}>
                  <label
                    className={`flex items-center gap-3 py-2 ${
                      disabled ? 'cursor-not-allowed opacity-50' : 'cursor-pointer'
                    }`}
                  >
                    <input
                      type="checkbox"
                      className="h-4 w-4"
                      checked={checked}
                      disabled={disabled || submitting}
                      onChange={() => togglePassenger(p.passengerId)}
                    />
                    <span className="flex-1">
                      <span className="font-medium">{p.fullName}</span>
                      <span className="ml-2 text-sm text-gray-500">
                        born {formatDate(p.dateOfBirth)}, {p.gender}
                      </span>
                    </span>
                    <Badge tone={p.ageCategory === 'ADULT' ? 'gray' : 'blue'}>{p.ageCategory}</Badge>
                  </label>
                </li>
              );
            })}
          </ul>
        )}
        {limitReached && (
          <p className="mt-2 text-sm text-gray-600">
            You have chosen the maximum of {MAX_PASSENGERS} passengers.
          </p>
        )}
      </Card>

      <Card title="Fare quote">
        {selectedIds.length === 0 && (
          <EmptyState message="Choose at least one passenger to see the fare." />
        )}
        {selectedIds.length > 0 && quoteLoading && <Spinner />}
        {selectedIds.length > 0 && quoteError && (
          <Alert tone="error">{quoteError.message}</Alert>
        )}
        {selectedIds.length > 0 && !quoteLoading && !quoteError && quote && (
          <div className="space-y-3">
            <Table
              columns={quoteColumns}
              rows={quote.passengers}
              rowKey="passengerId"
              emptyText="No fare rows returned."
            />
            <div className="flex flex-wrap items-center justify-between gap-2 text-sm text-gray-600">
              <span>Distance: {quote.distanceKm} km</span>
              <span className="text-base font-semibold text-gray-900">
                Total fare: {formatMoney(quote.totalFare)}
              </span>
            </div>
          </div>
        )}
      </Card>

      {submitError && <Alert tone="error">{submitError.message}</Alert>}

      {booked && (
        <Alert tone="success">
          <p className="font-medium">
            Booking created. PNR {booked.pnr}. Taking you to payment...
          </p>
          <ul className="mt-2 space-y-1">
            {booked.passengers.map((p) => (
              <li key={p.bookingPassengerId} className="flex items-center gap-2">
                <span>{p.passengerName}</span>
                <StatusBadge status={p.status} />
              </li>
            ))}
          </ul>
        </Alert>
      )}

      <div className="flex justify-end">
        <Button onClick={handleBook} loading={submitting} disabled={!canBook}>
          Book and continue
        </Button>
      </div>
    </div>
  );
}
