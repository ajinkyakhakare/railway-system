// Task G4.5 (Group 4: Payment, Cancellation & Refund) - page /payments/history
// Two read-only tables for the logged-in user:
//   payments (view v_payment_history via GET /payments/my)
//   refunds  (view v_refund_summary  via GET /refunds/my)
import { useAsync } from '@/hooks/useAsync';
import { formatDateTime, formatMoney } from '@/utils/format';
import { Alert, Button, Card, PageHeader, Spinner, StatusBadge, Table } from '@/components/ui';
import { getErrorMessage, getMyPayments, getMyRefunds } from '../api';

// Shows "-" instead of an empty cell when a datetime is missing (for example Paid_At of a failed payment).
function dateTimeOrDash(value) {
  return value ? formatDateTime(value) : '-';
}

const paymentColumns = [
  { key: 'paymentId', header: 'Payment' },
  { key: 'pnr', header: 'PNR' },
  { key: 'amount', header: 'Amount', render: (row) => formatMoney(row.amount) },
  { key: 'paymentMode', header: 'Mode' },
  {
    key: 'paymentStatus',
    header: 'Status',
    render: (row) => <StatusBadge status={row.paymentStatus} />,
  },
  { key: 'createdAt', header: 'Created', render: (row) => dateTimeOrDash(row.createdAt) },
  { key: 'paidAt', header: 'Paid', render: (row) => dateTimeOrDash(row.paidAt) },
];

const refundColumns = [
  { key: 'pnr', header: 'PNR' },
  { key: 'passengerName', header: 'Passenger' },
  { key: 'originalFare', header: 'Original fare', render: (row) => formatMoney(row.originalFare) },
  { key: 'deductionPercent', header: 'Deduction %', render: (row) => `${Number(row.deductionPercent)}%` },
  { key: 'deductionAmount', header: 'Deduction', render: (row) => formatMoney(row.deductionAmount) },
  { key: 'refundAmount', header: 'Refund', render: (row) => formatMoney(row.refundAmount) },
  {
    key: 'refundStatus',
    header: 'Status',
    render: (row) => <StatusBadge status={row.refundStatus} />,
  },
  { key: 'cancelledAt', header: 'Cancelled', render: (row) => dateTimeOrDash(row.cancelledAt) },
];

// One section = a Card with its own loading and error handling.
function HistorySection({ title, state, columns, rowKey, emptyText }) {
  return (
    <Card title={title}>
      {state.error && <Alert tone="error">{getErrorMessage(state.error)}</Alert>}
      {state.loading && !state.data && (
        <div className="flex justify-center py-8">
          <Spinner />
        </div>
      )}
      {state.data && (
        <Table columns={columns} rows={state.data} rowKey={rowKey} emptyText={emptyText} />
      )}
    </Card>
  );
}

export default function PaymentHistoryPage() {
  const payments = useAsync(() => getMyPayments(), []);
  const refunds = useAsync(() => getMyRefunds(), []);

  function reloadAll() {
    payments.reload();
    refunds.reload();
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="Payments"
        subtitle="Your payments and the refunds for cancelled tickets."
        actions={
          <Button
            variant="secondary"
            onClick={reloadAll}
            loading={payments.loading || refunds.loading}
          >
            Refresh
          </Button>
        }
      />

      <HistorySection
        title="Payments"
        state={payments}
        columns={paymentColumns}
        rowKey="paymentId"
        emptyText="You have not made any payments yet."
      />

      <HistorySection
        title="Refunds"
        state={refunds}
        columns={refundColumns}
        rowKey="cancellationId"
        emptyText="You have no refunds yet."
      />
    </div>
  );
}
