package com.railway.common.otp;

/**
 * Contract between modules for one-time passwords. The user module (G2) implements it as
 * com.railway.user.service.OtpVerifierImpl; the payment module (G4) only depends on this interface.
 */
public interface OtpVerifier {

    /**
     * Checks a one-time password and marks the challenge as used when it is correct.
     *
     * @param userId      the user the OTP was issued to
     * @param purpose     "LOGIN" or "PAYMENT"
     * @param challengeId id of the OTP challenge returned when the OTP was requested
     * @param otp         the code typed by the user
     * @return true when the OTP is correct, not expired and not used before; false otherwise
     */
    boolean verify(Long userId, String purpose, Long challengeId, String otp);
}
