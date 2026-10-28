package com.railway.payment.service;

import com.railway.common.exception.ApiException;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestClientResponseException;

/**
 * Thin wrapper around the two things we need from Razorpay:
 *   1. create an order (HTTP POST https://api.razorpay.com/v1/orders), and
 *   2. check the signature Razorpay returns after the customer pays.
 *
 * It is only used when app.payment.mode=RAZORPAY. The key id / secret come from
 * application.yml (environment variables RAZORPAY_KEY_ID / RAZORPAY_KEY_SECRET);
 * they are never written in code and the secret is never logged.
 */
@Service
public class RazorpayGateway {

    private static final Logger log = LoggerFactory.getLogger(RazorpayGateway.class);

    private static final String ORDERS_URL = "https://api.razorpay.com/v1/orders";
    private static final String HMAC_ALGORITHM = "HmacSHA256";

    private final String keyId;
    private final String keySecret;
    private final RestClient restClient;

    public RazorpayGateway(@Value("${app.payment.razorpay.key-id:}") String keyId,
                           @Value("${app.payment.razorpay.key-secret:}") String keySecret) {
        this.keyId = keyId;
        this.keySecret = keySecret;

        // Timeouts so that a slow gateway cannot block a request thread forever.
        SimpleClientHttpRequestFactory requestFactory = new SimpleClientHttpRequestFactory();
        requestFactory.setConnectTimeout(10_000);
        requestFactory.setReadTimeout(15_000);
        this.restClient = RestClient.builder().requestFactory(requestFactory).build();
    }

    /** Public key id. It is meant to be shown to the browser (Razorpay checkout needs it). */
    public String getKeyId() {
        requireKeysConfigured();
        return keyId;
    }

    /**
     * Creates an order at Razorpay and returns its id (for example "order_Abc123").
     *
     * @param amountPaise amount in paise (rupees * 100), as Razorpay requires
     * @param receipt     our own reference, "BK" + bookingId
     */
    public String createOrder(long amountPaise, String receipt) {
        requireKeysConfigured();

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("amount", amountPaise);
        body.put("currency", "INR");
        body.put("receipt", receipt);

        Map<?, ?> response;
        try {
            response = restClient.post()
                    .uri(ORDERS_URL)
                    .headers(headers -> headers.setBasicAuth(keyId, keySecret))
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(body)
                    .retrieve()
                    .body(Map.class);
        } catch (RestClientResponseException e) {
            // Razorpay answered with an error status (for example wrong keys or a bad amount).
            log.error("Razorpay rejected the order request: HTTP {}", e.getStatusCode().value());
            throw gatewayError("The payment gateway rejected the order request");
        } catch (RestClientException e) {
            // Network problem: DNS failure, timeout or connection refused.
            log.error("Could not reach Razorpay: {}", e.getMessage());
            throw gatewayError("The payment gateway is not reachable, please try again");
        }

        Object id = (response == null) ? null : response.get("id");
        if (!(id instanceof String orderId) || orderId.isBlank()) {
            log.error("Razorpay response did not contain an order id");
            throw gatewayError("The payment gateway returned an unexpected response");
        }
        return orderId;
    }

    /**
     * Checks the signature sent by the browser after payment.
     *
     * Razorpay defines: signature = HMAC-SHA256(key-secret, orderId + "|" + paymentId), as a
     * lowercase hex string. We recompute it and compare in constant time
     * (MessageDigest.isEqual) so the comparison time does not leak how many characters matched.
     */
    public boolean isSignatureValid(String orderId, String paymentId, String signature) {
        requireKeysConfigured();
        if (orderId == null || paymentId == null || signature == null) {
            return false;
        }
        try {
            Mac mac = Mac.getInstance(HMAC_ALGORITHM);
            mac.init(new SecretKeySpec(keySecret.getBytes(StandardCharsets.UTF_8), HMAC_ALGORITHM));
            byte[] hash = mac.doFinal((orderId + "|" + paymentId).getBytes(StandardCharsets.UTF_8));
            String expected = HexFormat.of().formatHex(hash);
            String provided = signature.trim().toLowerCase(Locale.ROOT);
            return MessageDigest.isEqual(
                    expected.getBytes(StandardCharsets.UTF_8),
                    provided.getBytes(StandardCharsets.UTF_8));
        } catch (GeneralSecurityException e) {
            log.error("Could not compute the HMAC signature: {}", e.getMessage());
            throw gatewayError("Could not verify the payment signature");
        }
    }

    // ---------------------------------------------------------------- helpers

    private void requireKeysConfigured() {
        if (keyId == null || keyId.isBlank() || keySecret == null || keySecret.isBlank()) {
            throw new ApiException("INTERNAL_ERROR",
                    "Razorpay keys are not configured (set RAZORPAY_KEY_ID and RAZORPAY_KEY_SECRET)",
                    HttpStatus.INTERNAL_SERVER_ERROR);
        }
    }

    private ApiException gatewayError(String message) {
        return new ApiException("INTERNAL_ERROR", message, HttpStatus.INTERNAL_SERVER_ERROR);
    }
}
