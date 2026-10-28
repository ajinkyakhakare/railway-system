// Task G4.5 (Group 4: Payment, Cancellation & Refund) - page /cancel/:bookingPassengerId
//
// Flow:  GET /cancellations/preview -> show fare, hours before departure, deduction %, estimated refund
//        -> person writes an optional reason -> "Cancel ticket" opens a confirmation Modal
//        -> POST /cancellations -> show the result and a link back to /my-bookings
import { useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { useAsync } from '@/hooks/useAsync';
import { formatMoney } from '@/utils/format';
import { Alert, Button, Card, Modal, PageHeader, Spinner } from '@/components/ui';
import { cancelTicket, getErrorMessage, previewCancellation } from '../api';

const MAX_REASON_LENGTH = 100; // cancellation.Reason is VARCHAR(100)

// One label/value line inside a Card.
function DetailRow({ label, children }) {
  return (
    <div className="flex items-start justify-between gap-4 py-1 text-sm">
      <dt className="text-gray-500">{label}</dt>
      <dd className="text-right font-medium text-gray-900">{children}</dd>
    </div>
  );
}

// 36.5 -> "36.5 hours"
function formatHours(hours) {
  return `${Number(hours).toFixed(1)} hours`;
}

export default function CancelPage() {
  const { bookingPassengerId } = useParams();
  const preview = useAsync(() => previewCancellation(bookingPassengerId), [bookingPassengerId]);

  const [reason, setReason] = useState('');
  const [confirmOpen, setConfirmOpen] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');
  const [result, setResult] = useState(null); // response of POST /cancellations

  async function handleConfirm() {
    setError('');
    setSubmitting(true);
    try {
      const trimmedReason = reason.trim();
      const response = await cancelTicket(
        Number(bookingPassengerId),
        trimmedReason === '' ? null : trimmedReason
      );
      setResult(response);
      setConfirmOpen(false);
    } catch (err) {
      setError(getErrorMessage(err));
    } finally {
      setSubmitting(false);
    }
  }

  const backLink = (
    <Link to="/my-bookings" className="text-sm text-blue-600 hover:underline">
      Back to my bookings
    </Link>
  );

  // ------------------------------------------------------------ rendering
  if (result) {
    return (
      <div className="space-y-6">
        <PageHeader title="Ticket cancelled" />
        <Alert tone="success">Your ticket has been cancelled.</Alert>
        <Card title="Refund details">
          <dl className="divide-y divide-gray-100">
            <DetailRow label="Cancellation number">{result.cancellationId}</DetailRow>
            <DetailRow label="Original fare">{formatMoney(result.originalFare)}</DetailRow>
            <DetailRow label="Deduction">{Number(result.deductionPercent)}%</DetailRow>
            <DetailRow label="Refund amount">{formatMoney(result.refundAmount)}</DetailRow>
            <DetailRow label="Waiting passengers promoted">{result.promotedCount}</DetailRow>
          </dl>
        </Card>
        {backLink}
      </div>
    );
  }

  if (preview.loading && !preview.data) {
    return (
      <div className="flex justify-center py-16">
        <Spinner />
      </div>
    );
  }

  if (preview.error) {
    return (
      <div className="space-y-4">
        <PageHeader title="Cancel ticket" />
        <Alert tone="error">{getErrorMessage(preview.error)}</Alert>
        {backLink}
      </div>
    );
  }

  const data = preview.data;
  if (!data) {
    return null;
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="Cancel ticket"
        subtitle="Check the refund below before you confirm. A cancelled ticket cannot be restored."
      />

      <Card title="Refund preview">
        <dl className="divide-y divide-gray-100">
          <DetailRow label="Fare paid for this passenger">{formatMoney(data.fareAmount)}</DetailRow>
          <DetailRow label="Time before departure">{formatHours(data.hoursBeforeDeparture)}</DetailRow>
          <DetailRow label="Deduction">{Number(data.deductionPercent)}%</DetailRow>
          <DetailRow label="Estimated refund">{formatMoney(data.estimatedRefund)}</DetailRow>
        </dl>
      </Card>

      <Card title="Reason (optional)">
        <label htmlFor="cancel-reason" className="sr-only">
          Reason for cancellation
        </label>
        <textarea
          id="cancel-reason"
          name="reason"
          rows={3}
          maxLength={MAX_REASON_LENGTH}
          value={reason}
          onChange={(event) => setReason(event.target.value)}
          placeholder="Tell us why you are cancelling"
          className="w-full rounded-md border border-gray-300 px-3 py-2 text-sm focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500"
        />
        <p className="mt-1 text-xs text-gray-500">
          {reason.length}/{MAX_REASON_LENGTH} characters
        </p>
      </Card>

      <div className="flex items-center gap-4">
        <Button
          variant="danger"
          onClick={() => {
            setError('');
            setConfirmOpen(true);
          }}
        >
          Cancel ticket
        </Button>
        {backLink}
      </div>

      <Modal
        open={confirmOpen}
        title="Confirm cancellation"
        onClose={() => {
          if (!submitting) setConfirmOpen(false);
        }}
      >
        <div className="space-y-4">
          <p className="text-sm text-gray-700">
            You will get back about <strong>{formatMoney(data.estimatedRefund)}</strong>. This cannot
            be undone.
          </p>
          {error && <Alert tone="error">{error}</Alert>}
          <div className="flex justify-end gap-3">
            <Button variant="secondary" onClick={() => setConfirmOpen(false)} disabled={submitting}>
              Keep ticket
            </Button>
            <Button variant="danger" onClick={handleConfirm} loading={submitting} disabled={submitting}>
              Confirm cancellation
            </Button>
          </div>
        </div>
      </Modal>
    </div>
  );
}
