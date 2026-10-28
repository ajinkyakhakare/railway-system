package com.railway.payment.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/**
 * Body of POST /api/v1/payments/verify (RAZORPAY mode).
 *
 * After the customer pays in the Razorpay checkout popup, the browser receives
 * razorpay_payment_id and razorpay_signature and sends them to us together with
 * our own paymentId.
 */
public record PaymentVerifyRequest(
        @NotNull(message = "paymentId is required")
        Long paymentId,

        @NotBlank(message = "razorpayPaymentId is required")
        @Size(max = 60, message = "razorpayPaymentId must be at most 60 characters")
        String razorpayPaymentId,

        @NotBlank(message = "razorpaySignature is required")
        @Size(max = 200, message = "razorpaySignature must be at most 200 characters")
        String razorpaySignature
) {
}
