package com.railway.user.service;

import com.railway.common.otp.OtpVerifier;
import org.springframework.stereotype.Service;

/**
 * G2's implementation of the shared OtpVerifier interface (used by the G4 payment module).
 * It only delegates to OtpService, so there is a single place that knows how OTPs work.
 *
 * Behaviour: returns true when the OTP is valid; throws ApiException OTP_INVALID (401)
 * otherwise, so a caller can never accidentally ignore a failed check.
 */
@Service
public class OtpVerifierImpl implements OtpVerifier {

    private final OtpService otpService;

    public OtpVerifierImpl(OtpService otpService) {
        this.otpService = otpService;
    }

    @Override
    public boolean verify(Long userId, String purpose, Long challengeId, String otp) {
        return otpService.verify(userId, purpose, challengeId, otp);
    }
}
