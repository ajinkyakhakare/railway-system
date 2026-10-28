package com.railway.payment.service;

import com.railway.common.db.SqlHelper;
import com.railway.common.exception.ApiException;
import com.railway.common.otp.OtpVerifier;
import com.railway.payment.dto.MockConfirmRequest;
import com.railway.payment.dto.PaymentOrderRequest;
import com.railway.payment.dto.PaymentVerifyRequest;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

/**
 * Payment flow:
 *   1. createOrder  -> sp_create_payment  (payment row, status CREATED)
 *   2. verify / mockConfirm -> sp_confirm_payment (status SUCCESS or FAILED; the trigger
 *      trg_payment_confirm then sets the booking to CONFIRMED)
 *
 * Rule R12: methods here CALL stored procedures that manage their own transaction, so this
 * class (and every method in it) is deliberately NOT @Transactional.
 */
@Service
public class PaymentService {

    private static final String MODE_MOCK = "MOCK";
    private static final String MODE_RAZORPAY = "RAZORPAY";
    private static final String OTP_PURPOSE_PAYMENT = "PAYMENT";

    private final SqlHelper sql;
    private final OtpVerifier otpVerifier;
    private final RazorpayGateway razorpayGateway;
    private final String paymentMode;
    private final boolean requirePaymentOtp;

    public PaymentService(SqlHelper sql,
                          OtpVerifier otpVerifier,
                          RazorpayGateway razorpayGateway,
                          @Value("${app.payment.mode:MOCK}") String paymentMode,
                          @Value("${app.auth.require-payment-otp:true}") boolean requirePaymentOtp) {
        this.sql = sql;
        this.otpVerifier = otpVerifier;
        this.razorpayGateway = razorpayGateway;
        this.requirePaymentOtp = requirePaymentOtp;
        this.paymentMode = normaliseMode(paymentMode);
    }

    // ------------------------------------------------------------ POST /payments/orders

    public Map<String, Object> createOrder(Long userId, PaymentOrderRequest request) {
        // Step 1: second factor for payments (2FA requirement of the faculty).
        checkPaymentOtp(userId, request);

        // Step 2: obtain the gateway order id.
        String gatewayOrderId;
        String razorpayKeyId = null;
        if (MODE_RAZORPAY.equals(paymentMode)) {
            // The amount must be known BEFORE calling Razorpay, so read the booking first.
            BigDecimal amount = loadPayableBookingAmount(userId, request.bookingId());
            gatewayOrderId = razorpayGateway.createOrder(toPaise(amount), "BK" + request.bookingId());
            razorpayKeyId = razorpayGateway.getKeyId();
        } else {
            // MOCK mode: no external call. sp_create_payment performs the booking checks.
            gatewayOrderId = "MOCK_" + UUID.randomUUID();
        }

        // Step 3: store the payment row. The procedure checks booking exists / owner / pending.
        Map<String, Object> row = sql.call("CALL sp_create_payment(?,?,?,?)",
                userId, request.bookingId(), paymentMode, gatewayOrderId);
        if (row == null) {
            throw internalError("sp_create_payment returned no result");
        }

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("paymentId", row.get("paymentId"));
        result.put("mode", paymentMode);
        result.put("amount", row.get("amount"));
        result.put("gatewayOrderId", gatewayOrderId);
        result.put("razorpayKeyId", razorpayKeyId);      // null in MOCK mode
        return result;
    }

    // ----------------------------------------------------------- POST /payments/verify

    public Map<String, Object> verifyRazorpayPayment(Long userId, PaymentVerifyRequest request) {
        Map<String, Object> payment = loadOwnedPayment(userId, request.paymentId());

        // Only payments that were created for Razorpay carry a real signature.
        if (!MODE_RAZORPAY.equals(payment.get("paymentMode"))) {
            throw ApiException.forbidden("This payment was not created in RAZORPAY mode");
        }
        requireStatusCreated(payment);

        String orderId = (String) payment.get("gatewayOrderId");
        boolean signatureOk = razorpayGateway.isSignatureValid(
                orderId, request.razorpayPaymentId(), request.razorpaySignature());

        if (!signatureOk) {
            // Record the failure, then tell the client. The booking stays PENDING_PAYMENT,
            // so the customer may start a new payment.
            sql.call("CALL sp_confirm_payment(?,?,?)", request.paymentId(), null, 0);
            throw ApiException.conflict("PAYMENT_FAILED", "Payment signature verification failed");
        }

        Map<String, Object> row = sql.call("CALL sp_confirm_payment(?,?,?)",
                request.paymentId(), request.razorpayPaymentId(), 1);
        return statusResult(row);
    }

    // ------------------------------------------------------ POST /payments/mock-confirm

    public Map<String, Object> mockConfirm(Long userId, MockConfirmRequest request) {
        if (!MODE_MOCK.equals(paymentMode)) {
            throw ApiException.forbidden("Mock confirmation is only available when app.payment.mode=MOCK");
        }
        Map<String, Object> payment = loadOwnedPayment(userId, request.paymentId());

        // Safety: a payment created for the real gateway must never be confirmed for free
        // just because the server was later switched to MOCK.
        if (!MODE_MOCK.equals(payment.get("paymentMode"))) {
            throw ApiException.forbidden("Only MOCK payments can be confirmed through this endpoint");
        }

        int success = Boolean.TRUE.equals(request.success()) ? 1 : 0;
        Map<String, Object> row = sql.call("CALL sp_confirm_payment(?,?,?)",
                request.paymentId(), "MOCKPAY_" + UUID.randomUUID(), success);
        return statusResult(row);
    }

    // ---------------------------------------------------------------- GET /payments/my

    public List<Map<String, Object>> myPayments(Long userId) {
        return sql.query("SELECT * FROM v_payment_history WHERE User_ID = ? "
                + "ORDER BY Created_At DESC, Payment_ID DESC", userId);
    }

    // ---------------------------------------------------------------- helpers

    /** Mode comes from configuration; a typo must stop the application at start-up. */
    private static String normaliseMode(String configured) {
        String mode = (configured == null) ? "" : configured.trim().toUpperCase(Locale.ROOT);
        if (!MODE_MOCK.equals(mode) && !MODE_RAZORPAY.equals(mode)) {
            throw new IllegalStateException("app.payment.mode must be MOCK or RAZORPAY but was '" + configured + "'");
        }
        return mode;
    }

    /** Verifies the payment OTP when app.auth.require-payment-otp=true. */
    private void checkPaymentOtp(Long userId, PaymentOrderRequest request) {
        if (!requirePaymentOtp) {
            return;
        }
        if (request.otpChallengeId() == null || request.otp() == null || request.otp().isBlank()) {
            throw otpInvalid("otpChallengeId and otp are required for payments");
        }
        boolean valid = otpVerifier.verify(userId, OTP_PURPOSE_PAYMENT, request.otpChallengeId(), request.otp());
        if (!valid) {
            throw otpInvalid("The OTP is invalid or has expired");
        }
    }

    /**
     * RAZORPAY mode only: reads the booking amount and runs the same checks as
     * sp_create_payment, so we never create a gateway order for a booking that could not be paid.
     * (sp_create_payment repeats the checks inside the database, which stays the final authority.)
     */
    private BigDecimal loadPayableBookingAmount(Long userId, Long bookingId) {
        Map<String, Object> booking = sql.queryOne(
                "SELECT User_ID, Booking_Status, Total_Fare FROM booking WHERE Booking_ID = ?", bookingId);
        if (booking == null) {
            throw new ApiException("BOOKING_NOT_FOUND", "Booking not found", HttpStatus.NOT_FOUND);
        }
        if (toLong(booking.get("userId")) != userId.longValue()) {
            throw new ApiException("NOT_OWNER", "This booking belongs to another user", HttpStatus.FORBIDDEN);
        }
        if (!"PENDING_PAYMENT".equals(booking.get("bookingStatus"))) {
            throw ApiException.conflict("PAYMENT_NOT_ALLOWED", "Booking is not waiting for payment");
        }
        return new BigDecimal(booking.get("totalFare").toString());
    }

    /** Loads a payment and makes sure it belongs to the current user (through its booking). */
    private Map<String, Object> loadOwnedPayment(Long userId, Long paymentId) {
        Map<String, Object> payment = sql.queryOne(
                "SELECT pay.Payment_ID, pay.Gateway_Order_ID, pay.Payment_Mode, pay.Payment_Status, b.User_ID "
              + "FROM payment pay JOIN booking b ON b.Booking_ID = pay.Booking_ID "
              + "WHERE pay.Payment_ID = ?", paymentId);
        if (payment == null) {
            throw ApiException.notFound("Payment not found");
        }
        if (toLong(payment.get("userId")) != userId.longValue()) {
            throw new ApiException("NOT_OWNER", "This payment belongs to another user", HttpStatus.FORBIDDEN);
        }
        return payment;
    }

    private static void requireStatusCreated(Map<String, Object> payment) {
        if (!"CREATED".equals(payment.get("paymentStatus"))) {
            throw ApiException.conflict("PAYMENT_NOT_ALLOWED",
                    "Payment is already " + payment.get("paymentStatus"));
        }
    }

    /** Builds {paymentStatus, bookingStatus} from the result of sp_confirm_payment. */
    private static Map<String, Object> statusResult(Map<String, Object> row) {
        if (row == null) {
            throw internalError("sp_confirm_payment returned no result");
        }
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("paymentStatus", row.get("paymentStatus"));
        result.put("bookingStatus", row.get("bookingStatus"));
        return result;
    }

    /** Rupees to paise (Razorpay expects the smallest currency unit as an integer). */
    private static long toPaise(BigDecimal rupees) {
        return rupees.movePointRight(2).setScale(0, RoundingMode.HALF_UP).longValueExact();
    }

    private static long toLong(Object value) {
        return (value instanceof Number n) ? n.longValue() : -1L;
    }

    private static ApiException otpInvalid(String message) {
        return new ApiException("OTP_INVALID", message, HttpStatus.UNAUTHORIZED);
    }

    private static ApiException internalError(String message) {
        return new ApiException("INTERNAL_ERROR", message, HttpStatus.INTERNAL_SERVER_ERROR);
    }
}
