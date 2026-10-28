// Task G4.5 (Group 4: Payment, Cancellation & Refund) - page /payment/:bookingId
//
// Flow:  load booking -> Step 1 "Send OTP" -> Step 2 "Pay" (creates the payment order)
//        -> MOCK mode:     "Mock payment" panel with two buttons (POST /payments/mock-confirm)
//        -> RAZORPAY mode: Razorpay checkout popup, then POST /payments/verify
//        -> on success go to /tickets/<pnr>
import { useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { useAuth } from '@/auth/AuthContext';
import { useAsync } from '@/hooks/useAsync';
import { formatDate, formatDateTime, formatMoney } from '@/utils/format';
import {
  Alert,
  Button,
  Card,
  Input,
  PageHeader,
  Spinner,
  StatusBadge,
  Table,
} from '@/components/ui';
import {
  createPaymentOrder,
  getBooking,
  getErrorMessage,
  mockConfirmPayment,
  sendPaymentOtp,
  verifyPayment,
} from '../api';

const RAZORPAY_SCRIPT_URL = 'https://checkout.razorpay.com/v1/checkout.js';

// Loads the Razorpay checkout script only when it is needed (RAZORPAY mode).
function loadRazorpayScript() {
  return new Promise((resolve, reject) => {
    if (window.Razorpay) {
      resolve();
      return;
    }
    const script = document.createElement('script');
    script.src = RAZORPAY_SCRIPT_URL;
    script.async = true;
    script.onload = () => resolve();
    script.onerror = () =>
      reject(new Error('Could not load Razorpay checkout. Check your internet connection.'));
    document.body.appendChild(script);
  });
}

// One label/value line inside a Card.
function DetailRow({ label, children }) {
  return (
    <div className="flex items-start justify-between gap-4 py-1 text-sm">
      <dt className="text-gray-500">{label}</dt>
      <dd className="text-right font-medium text-gray-900">{children}</dd>
    </div>
  );
}

// "S1/14 LB" for a confirmed seat, a dash when no seat is allotted (RAC / WL).
function seatText(passenger) {
  if (passenger.coachNumber && passenger.seatNo) {
    return `${passenger.coachNumber}/${passenger.seatNo} ${passenger.berthType ?? ''}`.trim();
  }
  return '-';
}

const passengerColumns = [
  { key: 'passengerName', header: 'Passenger' },
  { key: 'status', header: 'Status', render: (row) => <StatusBadge status={row.status} /> },
  { key: 'seat', header: 'Seat', render: (row) => seatText(row) },
  { key: 'concessionType', header: 'Concession' },
  { key: 'fareAmount', header: 'Fare', render: (row) => formatMoney(row.fareAmount) },
];

export default function PaymentPage() {
  const { bookingId } = useParams();
  const navigate = useNavigate();
  const { user } = useAuth();

  const booking = useAsync(() => getBooking(bookingId), [bookingId]);

  const [otpChallenge, setOtpChallenge] = useState(null); // {challengeId, expiresAt, devOtp}
  const [otp, setOtp] = useState('');
  const [order, setOrder] = useState(null); // {paymentId, mode, amount, gatewayOrderId, razorpayKeyId}
  const [busy, setBusy] = useState(''); // '', 'otp', 'order', 'confirm' or 'razorpay'
  const [error, setError] = useState('');

  const bookingData = booking.data;

  // After a failed payment we go back to Step 1 because an OTP can be used only once.
  function resetPaymentSteps() {
    setOrder(null);
    setOtpChallenge(null);
    setOtp('');
  }

  // Step 1: ask the server for a payment OTP.
  async function handleSendOtp() {
    setError('');
    setBusy('otp');
    try {
      const challenge = await sendPaymentOtp();
      setOtpChallenge(challenge);
      setOtp('');
    } catch (err) {
      setError(getErrorMessage(err));
    } finally {
      setBusy('');
    }
  }

  // Step 2: create the payment order (the server checks the OTP).
  async function handlePay(event) {
    event.preventDefault();
    setError('');
    if (!otpChallenge) {
      setError('Send an OTP first.');
      return;
    }
    if (otp.trim() === '') {
      setError('Enter the OTP.');
      return;
    }
    setBusy('order');
    try {
      const newOrder = await createPaymentOrder({
        bookingId: Number(bookingId),
        otpChallengeId: otpChallenge.challengeId,
        otp: otp.trim(),
      });
      setOrder(newOrder);
      setBusy('');
      if (newOrder.mode === 'RAZORPAY') {
        await openRazorpay(newOrder);
      }
    } catch (err) {
      setError(getErrorMessage(err));
      setBusy('');
    }
  }

  // MOCK mode: pretend the gateway answered with success or failure.
  async function handleMockConfirm(success) {
    setError('');
    setBusy('confirm');
    try {
      const result = await mockConfirmPayment(order.paymentId, success);
      finishPayment(result);
    } catch (err) {
      setError(getErrorMessage(err));
    } finally {
      setBusy('');
    }
  }

  // RAZORPAY mode: open the checkout popup for the order we just created.
  async function openRazorpay(razorpayOrder) {
    if (!razorpayOrder.razorpayKeyId) {
      setError('The server did not send a Razorpay key. Payment cannot start.');
      return;
    }
    setError('');
    setBusy('razorpay');
    try {
      await loadRazorpayScript();
      const checkout = new window.Razorpay({
        key: razorpayOrder.razorpayKeyId,
        order_id: razorpayOrder.gatewayOrderId,
        amount: Math.round(Number(razorpayOrder.amount) * 100), // Razorpay wants paise
        currency: 'INR',
        name: 'National Railway Reservation',
        description: `PNR ${bookingData?.pnr ?? ''}`.trim(),
        prefill: { name: user?.fullName, email: user?.email },
        // Called by Razorpay after the customer paid.
        handler: (response) => handleRazorpaySuccess(razorpayOrder, response),
      });
      checkout.on('payment.failed', (response) => {
        setError(response?.error?.description || 'The payment failed. You can try again.');
      });
      checkout.open();
    } catch (err) {
      setError(getErrorMessage(err));
    } finally {
      setBusy('');
    }
  }

  // The server re-computes the HMAC signature, so we only forward what Razorpay gave us.
  async function handleRazorpaySuccess(razorpayOrder, response) {
    setError('');
    setBusy('confirm');
    try {
      const result = await verifyPayment({
        paymentId: razorpayOrder.paymentId,
        razorpayPaymentId: response.razorpay_payment_id,
        razorpaySignature: response.razorpay_signature,
      });
      finishPayment(result);
    } catch (err) {
      setError(getErrorMessage(err));
    } finally {
      setBusy('');
    }
  }

  // Common end of both payment modes: {paymentStatus, bookingStatus}.
  function finishPayment(result) {
    if (result.paymentStatus === 'SUCCESS') {
      navigate(`/tickets/${bookingData.pnr}`);
    } else {
      setError('The payment failed. Your booking is still waiting for payment. Request a new OTP to try again.');
      resetPaymentSteps();
    }
  }

  // ---------------------------------------------------------------- rendering
  if (booking.loading && !bookingData) {
    return (
      <div className="flex justify-center py-16">
        <Spinner />
      </div>
    );
  }

  if (booking.error) {
    return (
      <div className="space-y-4">
        <PageHeader title="Payment" />
        <Alert tone="error">{getErrorMessage(booking.error)}</Alert>
        <Link to="/my-bookings" className="text-sm text-blue-600 hover:underline">
          Back to my bookings
        </Link>
      </div>
    );
  }

  if (!bookingData) {
    return null;
  }

  const isPayable = bookingData.bookingStatus === 'PENDING_PAYMENT';
  const passengers = bookingData.passengers ?? [];

  return (
    <div className="space-y-6">
      <PageHeader
        title="Pay for your ticket"
        subtitle={`PNR ${bookingData.pnr} - ${bookingData.trainNo} ${bookingData.trainName}`}
      />

      <div className="grid gap-6 lg:grid-cols-3">
        {/* Left side: what the person is paying for */}
        <div className="space-y-6 lg:col-span-2">
          <Card title="Journey">
            <dl className="divide-y divide-gray-100">
              <DetailRow label="Train">
                {bookingData.trainNo} {bookingData.trainName}
              </DetailRow>
              <DetailRow label="Journey date">{formatDate(bookingData.journeyDate)}</DetailRow>
              <DetailRow label="Route">
                {bookingData.fromStationCode} to {bookingData.toStationCode}
              </DetailRow>
              <DetailRow label="Class">{bookingData.classCode}</DetailRow>
              <DetailRow label="Booked at">{formatDateTime(bookingData.bookedAt)}</DetailRow>
              <DetailRow label="Booking status">
                <StatusBadge status={bookingData.bookingStatus} />
              </DetailRow>
            </dl>
          </Card>

          <Card title="Passengers">
            <Table
              columns={passengerColumns}
              rows={passengers}
              rowKey="bookingPassengerId"
              emptyText="No passengers found for this booking."
            />
            <div className="mt-4 flex justify-between border-t border-gray-100 pt-3 text-base font-semibold text-gray-900">
              <span>Total fare</span>
              <span>{formatMoney(bookingData.totalFare)}</span>
            </div>
          </Card>
        </div>

        {/* Right side: the two payment steps */}
        <div className="space-y-4">
          {error && <Alert tone="error">{error}</Alert>}

          {!isPayable && (
            <Card title="Payment">
              <div className="space-y-3">
                <Alert tone="info">
                  This booking is {bookingData.bookingStatus.replaceAll('_', ' ').toLowerCase()}, so
                  no payment is needed.
                </Alert>
                <Link to="/my-bookings" className="text-sm text-blue-600 hover:underline">
                  Go to my bookings
                </Link>
              </div>
            </Card>
          )}

          {isPayable && !order && (
            <Card title="Payment">
              <form className="space-y-4" onSubmit={handlePay}>
                <div className="space-y-2">
                  <p className="text-sm font-medium text-gray-900">Step 1: verify with an OTP</p>
                  <Button
                    variant="secondary"
                    onClick={handleSendOtp}
                    loading={busy === 'otp'}
                    disabled={busy !== ''}
                  >
                    {otpChallenge ? 'Resend OTP' : 'Send OTP'}
                  </Button>
                  {otpChallenge && (
                    <Alert tone="info">
                      OTP sent. It is valid until {formatDateTime(otpChallenge.expiresAt)}.
                      {otpChallenge.devOtp && <> Demo OTP: <strong>{otpChallenge.devOtp}</strong></>}
                    </Alert>
                  )}
                </div>

                {otpChallenge && (
                  <div className="space-y-2">
                    <p className="text-sm font-medium text-gray-900">Step 2: pay</p>
                    <Input
                      label="OTP"
                      name="otp"
                      value={otp}
                      onChange={(event) => setOtp(event.target.value)}
                      placeholder="Enter the OTP"
                      inputMode="numeric"
                      autoComplete="one-time-code"
                      maxLength={8}
                      required
                    />
                    <Button
                      type="submit"
                      loading={busy === 'order'}
                      disabled={busy !== '' || otp.trim() === ''}
                    >
                      Pay {formatMoney(bookingData.totalFare)}
                    </Button>
                  </div>
                )}
              </form>
            </Card>
          )}

          {isPayable && order && order.mode === 'MOCK' && (
            <Card title="Mock payment">
              <div className="space-y-3">
                <Alert tone="info">
                  Test mode: no real money is charged. Choose how the payment of{' '}
                  {formatMoney(order.amount)} should end.
                </Alert>
                <div className="flex flex-wrap gap-3">
                  <Button
                    onClick={() => handleMockConfirm(true)}
                    loading={busy === 'confirm'}
                    disabled={busy !== ''}
                  >
                    Pay successfully
                  </Button>
                  <Button
                    variant="danger"
                    onClick={() => handleMockConfirm(false)}
                    disabled={busy !== ''}
                  >
                    Simulate failure
                  </Button>
                </div>
              </div>
            </Card>
          )}

          {isPayable && order && order.mode === 'RAZORPAY' && (
            <Card title="Razorpay payment">
              <div className="space-y-3">
                <Alert tone="info">
                  Complete the payment of {formatMoney(order.amount)} in the Razorpay window. If you
                  closed it by mistake, open it again.
                </Alert>
                <Button
                  onClick={() => openRazorpay(order)}
                  loading={busy === 'razorpay' || busy === 'confirm'}
                  disabled={busy !== ''}
                >
                  Open Razorpay checkout
                </Button>
              </div>
            </Card>
          )}
        </div>
      </div>
    </div>
  );
}
