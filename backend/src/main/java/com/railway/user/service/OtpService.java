package com.railway.user.service;

import com.railway.common.db.SqlHelper;
import com.railway.common.exception.ApiException;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

import java.security.SecureRandom;
import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * One-time passwords for two purposes: LOGIN and PAYMENT.
 *
 * - create: 6-digit code from SecureRandom; only its BCrypt hash is stored in otp_challenge
 *   (valid for 5 minutes, enforced with the database clock NOW()).
 * - verify: the challenge must belong to the user, have the right purpose, be unused, unexpired
 *   and match the code. It is then marked used so it works exactly once.
 *
 * This class is NOT @Transactional: every statement is a single atomic SQL statement.
 */
@Service
public class OtpService {

    public static final String PURPOSE_LOGIN = "LOGIN";
    public static final String PURPOSE_PAYMENT = "PAYMENT";

    private static final int OTP_LENGTH = 6;
    private static final int MAX_WRONG_ATTEMPTS = 5;

    private final SqlHelper sql;
    private final PasswordEncoder passwordEncoder;
    private final boolean devMode;
    private final SecureRandom random = new SecureRandom();

    /** Wrong guesses per challenge (memory only). After 5 the challenge is burned so it cannot be brute-forced. */
    private final Map<Long, Integer> wrongAttempts = new ConcurrentHashMap<>();

    public OtpService(SqlHelper sql,
                      PasswordEncoder passwordEncoder,
                      @Value("${app.auth.dev-mode:false}") boolean devMode) {
        this.sql = sql;
        this.passwordEncoder = passwordEncoder;
        this.devMode = devMode;
    }

    /**
     * Creates a new OTP challenge for the user.
     *
     * @return map with challengeId, expiresAt and devOtp (devOtp is null unless app.auth.dev-mode=true)
     */
    public Map<String, Object> createOtp(Long userId, String purpose) {
        if (!PURPOSE_LOGIN.equals(purpose) && !PURPOSE_PAYMENT.equals(purpose)) {
            throw ApiException.badRequest("VALIDATION_ERROR", "OTP purpose must be LOGIN or PAYMENT");
        }

        String otp = generateOtp();
        String hash = passwordEncoder.encode(otp);

        long challengeId = sql.insert(
                "INSERT INTO otp_challenge (User_ID, Purpose, Otp_Hash, Expires_At) "
                        + "VALUES (?, ?, ?, DATE_ADD(NOW(), INTERVAL 5 MINUTE))",
                userId, purpose, hash);

        // Read the expiry back so the response shows exactly what the database stored.
        Map<String, Object> row = sql.queryOne(
                "SELECT Expires_At FROM otp_challenge WHERE Otp_ID = ?", challengeId);

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("challengeId", challengeId);
        result.put("expiresAt", row == null ? null : toLocalDateTime(row.get("expiresAt")));
        result.put("devOtp", devMode ? otp : null);
        return result;
    }

    /**
     * Verifies and consumes an OTP.
     *
     * @return true when the OTP is valid (the method never returns false: any problem throws)
     * @throws ApiException OTP_INVALID (401) when the OTP is wrong, expired, used, or not this user's
     */
    public boolean verify(Long userId, String purpose, Long challengeId, String otp) {
        if (userId == null || purpose == null || challengeId == null
                || otp == null || otp.length() != OTP_LENGTH) {
            throw otpInvalid();
        }

        Map<String, Object> row = sql.queryOne(
                "SELECT Otp_Hash, Is_Used, (Expires_At > NOW()) AS Is_Fresh "
                        + "FROM otp_challenge WHERE Otp_ID = ? AND User_ID = ? AND Purpose = ?",
                challengeId, userId, purpose);

        if (row == null || toBoolean(row.get("isUsed")) || !toBoolean(row.get("isFresh"))) {
            throw otpInvalid();
        }

        String hash = (String) row.get("otpHash");
        if (!passwordEncoder.matches(otp, hash)) {
            registerWrongAttempt(challengeId);
            throw otpInvalid();
        }

        // Atomic "use once": only one concurrent request can flip Is_Used from 0 to 1.
        int changed = sql.update(
                "UPDATE otp_challenge SET Is_Used = 1 WHERE Otp_ID = ? AND Is_Used = 0", challengeId);
        if (changed != 1) {
            throw otpInvalid();
        }
        wrongAttempts.remove(challengeId);
        return true;
    }

    // ------------------------------------------------------------------ helpers

    /** Counts a wrong guess and burns the challenge after MAX_WRONG_ATTEMPTS guesses. */
    private void registerWrongAttempt(Long challengeId) {
        int attempts = wrongAttempts.merge(challengeId, 1, Integer::sum);
        if (attempts >= MAX_WRONG_ATTEMPTS) {
            sql.update("UPDATE otp_challenge SET Is_Used = 1 WHERE Otp_ID = ?", challengeId);
            wrongAttempts.remove(challengeId);
        }
    }

    /** Six digits, zero padded, from a cryptographically secure generator. */
    private String generateOtp() {
        return String.format("%0" + OTP_LENGTH + "d", random.nextInt(1_000_000));
    }

    private static ApiException otpInvalid() {
        return new ApiException("OTP_INVALID", "The OTP is invalid or has expired", HttpStatus.UNAUTHORIZED);
    }

    /** MySQL may return TINYINT/expressions as Boolean or as a Number; accept both. */
    private static boolean toBoolean(Object value) {
        if (value instanceof Boolean b) {
            return b;
        }
        return value instanceof Number n && n.intValue() != 0;
    }

    private static LocalDateTime toLocalDateTime(Object value) {
        if (value instanceof LocalDateTime ldt) {
            return ldt;
        }
        if (value instanceof java.sql.Timestamp ts) {
            return ts.toLocalDateTime();
        }
        return null;
    }
}
