package com.railway.user.service;

import com.railway.common.db.SqlHelper;
import com.railway.common.exception.ApiException;
import com.railway.common.security.JwtService;
import com.railway.user.dto.LoginRequest;
import com.railway.user.dto.RegisterRequest;
import com.railway.user.dto.VerifyOtpRequest;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * Registration, login (with optional LOGIN OTP) and the PAYMENT OTP request.
 *
 * IMPORTANT (rule R12): methods here CALL stored procedures that manage their own
 * transaction, so this class must NOT be @Transactional.
 */
@Service
public class AuthService {

    /** Same user query for password login and OTP login; Is_Locked uses the DB clock (no timezone mix-ups). */
    private static final String USER_LOGIN_COLUMNS =
            "SELECT User_ID, Email, Password_Hash, Full_Name, Is_Active, "
                    + "(Locked_Until IS NOT NULL AND Locked_Until > NOW()) AS Is_Locked FROM app_user ";

    private final SqlHelper sql;
    private final PasswordEncoder passwordEncoder;
    private final JwtService jwtService;
    private final OtpService otpService;
    private final UserService userService;
    private final boolean requireLoginOtp;

    public AuthService(SqlHelper sql,
                       PasswordEncoder passwordEncoder,
                       JwtService jwtService,
                       OtpService otpService,
                       UserService userService,
                       @Value("${app.auth.require-login-otp:false}") boolean requireLoginOtp) {
        this.sql = sql;
        this.passwordEncoder = passwordEncoder;
        this.jwtService = jwtService;
        this.otpService = otpService;
        this.userService = userService;
        this.requireLoginOtp = requireLoginOtp;
    }

    // ------------------------------------------------------------------ register

    /** POST /auth/register -> {userId}. The stored procedure also grants the PASSENGER role. */
    public Map<String, Object> register(RegisterRequest request) {
        String email = normalizeEmail(request.email());
        String hash = passwordEncoder.encode(request.password());

        Map<String, Object> row;
        try {
            row = sql.call("CALL sp_register_user(?,?,?,?)",
                    email, hash, request.fullName().trim(), request.phone());
        } catch (DuplicateKeyException e) {
            // Safety net: two simultaneous sign-ups with the same e-mail.
            throw ApiException.conflict("EMAIL_EXISTS", "An account with this e-mail already exists");
        }

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("userId", row == null ? null : row.get("userId"));
        return result;
    }

    // ------------------------------------------------------------------ login

    /**
     * POST /auth/login. Order of checks (contract C9):
     * unknown or inactive user -> INVALID_CREDENTIALS, locked -> ACCOUNT_LOCKED (423),
     * wrong password -> INVALID_CREDENTIALS, else token (or OTP challenge when enabled).
     */
    public Map<String, Object> login(LoginRequest request, String ipAddress) {
        String email = normalizeEmail(request.email());
        Map<String, Object> user = sql.queryOne(USER_LOGIN_COLUMNS + "WHERE Email = ?", email);

        if (user == null || !toBoolean(user.get("isActive"))) {
            recordAttempt(email, false, ipAddress);
            throw invalidCredentials();
        }
        if (toBoolean(user.get("isLocked"))) {
            throw accountLocked();
        }

        boolean passwordOk = passwordEncoder.matches(request.password(), (String) user.get("passwordHash"));
        recordAttempt(email, passwordOk, ipAddress);   // updates the failure counter / lock
        if (!passwordOk) {
            throw invalidCredentials();
        }

        Long userId = toLong(user.get("userId"));
        Map<String, Object> response = new LinkedHashMap<>();

        if (requireLoginOtp) {
            // Step 1 of 2: password was right, now the user must prove the OTP.
            Map<String, Object> otp = otpService.createOtp(userId, OtpService.PURPOSE_LOGIN);
            response.put("token", null);
            response.put("otpRequired", true);
            response.put("challengeId", otp.get("challengeId"));
            response.put("devOtp", otp.get("devOtp"));
            response.put("user", null);
            return response;
        }

        response.put("token", null);
        response.put("otpRequired", false);
        response.put("challengeId", null);
        response.put("devOtp", null);
        response.put("user", null);
        fillTokenAndUser(response, user);
        return response;
    }

    /** POST /auth/verify-otp -> {token,user}. Completes a login that required a LOGIN OTP. */
    public Map<String, Object> verifyLoginOtp(VerifyOtpRequest request) {
        // The request carries no user id, so find the owner of the LOGIN challenge first.
        Map<String, Object> challenge = sql.queryOne(
                "SELECT User_ID FROM otp_challenge WHERE Otp_ID = ? AND Purpose = 'LOGIN'",
                request.challengeId());
        if (challenge == null) {
            throw new ApiException("OTP_INVALID", "The OTP is invalid or has expired", HttpStatus.UNAUTHORIZED);
        }
        Long userId = toLong(challenge.get("userId"));

        otpService.verify(userId, OtpService.PURPOSE_LOGIN, request.challengeId(), request.otp());

        // The account may have been disabled or locked between the two steps.
        Map<String, Object> user = sql.queryOne(USER_LOGIN_COLUMNS + "WHERE User_ID = ?", userId);
        if (user == null || !toBoolean(user.get("isActive"))) {
            throw invalidCredentials();
        }
        if (toBoolean(user.get("isLocked"))) {
            throw accountLocked();
        }

        Map<String, Object> response = new LinkedHashMap<>();
        fillTokenAndUser(response, user);
        return response;
    }

    // ------------------------------------------------------------------ payment OTP

    /** POST /auth/payment-otp -> {challengeId,expiresAt,devOtp|null} for the logged-in user. */
    public Map<String, Object> createPaymentOtp(Long userId) {
        return otpService.createOtp(userId, OtpService.PURPOSE_PAYMENT);
    }

    // ------------------------------------------------------------------ helpers

    /** Adds "token" and "user" to the response for a verified user row. */
    private void fillTokenAndUser(Map<String, Object> response, Map<String, Object> user) {
        Long userId = toLong(user.get("userId"));
        String email = (String) user.get("email");
        List<String> roles = userService.findRoles(userId);

        Map<String, Object> userInfo = new LinkedHashMap<>();
        userInfo.put("userId", userId);
        userInfo.put("email", email);
        userInfo.put("fullName", user.get("fullName"));
        userInfo.put("roles", roles);

        response.put("token", jwtService.generateToken(userId, email, roles));
        response.put("user", userInfo);
    }

    /** Stores the attempt in login_audit and updates the failure counter (stored procedure). */
    private void recordAttempt(String email, boolean success, String ipAddress) {
        sql.call("CALL sp_record_login_attempt(?,?,?)", email, success ? 1 : 0, ipAddress);
    }

    private static String normalizeEmail(String email) {
        return email == null ? "" : email.trim().toLowerCase(Locale.ROOT);
    }

    private static ApiException invalidCredentials() {
        return new ApiException("INVALID_CREDENTIALS", "Invalid e-mail or password", HttpStatus.UNAUTHORIZED);
    }

    private static ApiException accountLocked() {
        return new ApiException("ACCOUNT_LOCKED",
                "Account is temporarily locked after too many failed attempts. Try again later.",
                HttpStatus.LOCKED);
    }

    /** MySQL may return TINYINT/expressions as Boolean or as a Number; accept both. */
    private static boolean toBoolean(Object value) {
        if (value instanceof Boolean b) {
            return b;
        }
        return value instanceof Number n && n.intValue() != 0;
    }

    private static Long toLong(Object value) {
        return value == null ? null : ((Number) value).longValue();
    }
}
