// Task G4.5 (Group 4: Payment, Cancellation & Refund) - API functions for the payments module.
// Every function returns the UNWRAPPED ApiResponse.data (the shared client does the unwrapping)
// and throws an ApiError {code, message, status} on failure.
import client from '@/api/client';

// ---------------------------------------------------------------------------
// Small helper used by all pages of this module to turn any thrown value into
// a readable message for an <Alert>.
// ---------------------------------------------------------------------------
export function getErrorMessage(error) {
  if (error && typeof error.message === 'string' && error.message.length > 0) {
    return error.message;
  }
  return 'Something went wrong. Please try again.';
}

// ---------------------------------------------------------------------------
// Payment flow
// ---------------------------------------------------------------------------

// G3 endpoint: one booking with its passengers (owner or ADMIN).
export function getBooking(bookingId) {
  return client.get(`/bookings/${bookingId}`);
}

// G2 endpoint: creates a PAYMENT OTP challenge -> {challengeId, expiresAt, devOtp|null}
export function sendPaymentOtp() {
  return client.post('/auth/payment-otp', {});
}

// body: {bookingId, otpChallengeId, otp}
// -> {paymentId, mode, amount, gatewayOrderId, razorpayKeyId}
export function createPaymentOrder(body) {
  return client.post('/payments/orders', body);
}

// RAZORPAY mode only. body: {paymentId, razorpayPaymentId, razorpaySignature}
// -> {paymentStatus, bookingStatus}
export function verifyPayment(body) {
  return client.post('/payments/verify', body);
}

// MOCK mode only. -> {paymentStatus, bookingStatus}
export function mockConfirmPayment(paymentId, success) {
  return client.post('/payments/mock-confirm', { paymentId, success });
}

// ---------------------------------------------------------------------------
// History (rows of the views v_payment_history and v_refund_summary, own rows only)
// ---------------------------------------------------------------------------
export function getMyPayments() {
  return client.get('/payments/my');
}

export function getMyRefunds() {
  return client.get('/refunds/my');
}

// ---------------------------------------------------------------------------
// Cancellation
// ---------------------------------------------------------------------------

// -> {bookingPassengerId, fareAmount, hoursBeforeDeparture, deductionPercent, estimatedRefund}
export function previewCancellation(bookingPassengerId) {
  return client.get('/cancellations/preview', { params: { bookingPassengerId } });
}

// -> {cancellationId, originalFare, deductionPercent, refundAmount, promotedCount}
export function cancelTicket(bookingPassengerId, reason) {
  return client.post('/cancellations', { bookingPassengerId, reason });
}

// ---------------------------------------------------------------------------
// Admin: fare rules, concession rules and the fare audit log
// ---------------------------------------------------------------------------

// -> [{fareRuleId, classCode, baseFarePerKm, minFare, updatedAt}]
export function getFareRules() {
  return client.get('/admin/fare-rules');
}

// body: {baseFarePerKm, minFare} -> the updated fare rule row
export function updateFareRule(fareRuleId, body) {
  return client.put(`/admin/fare-rules/${fareRuleId}`, body);
}

// -> [{concessionRuleId, concessionType, discountPercent, description}]
export function getConcessionRules() {
  return client.get('/admin/concession-rules');
}

// body: {discountPercent} -> the updated concession rule row
export function updateConcessionRule(concessionRuleId, body) {
  return client.put(`/admin/concession-rules/${concessionRuleId}`, body);
}

// -> rows of fare_audit_log, newest first
export function getFareAudit() {
  return client.get('/admin/fare-audit');
}
