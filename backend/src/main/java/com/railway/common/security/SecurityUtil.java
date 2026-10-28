package com.railway.common.security;

import com.railway.common.exception.ApiException;
import com.railway.common.exception.ErrorCodes;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;

/**
 * Static shortcuts to read the logged-in user of the current request.
 * Services use these instead of trusting a user id sent by the client.
 */
public final class SecurityUtil {

    private SecurityUtil() {
        // static helpers only
    }

    /**
     * Returns the user of the current request.
     *
     * @return the authenticated user
     * @throws ApiException 401 UNAUTHORIZED when nobody is logged in
     */
    public static AuthUser currentUser() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication != null && authentication.getPrincipal() instanceof AuthUser user) {
            return user;
        }
        throw new ApiException(ErrorCodes.UNAUTHORIZED, "Authentication is required. Please log in.",
                HttpStatus.UNAUTHORIZED);
    }

    /**
     * Returns the id of the user of the current request.
     *
     * @return User_ID of the logged-in user
     * @throws ApiException 401 UNAUTHORIZED when nobody is logged in
     */
    public static Long currentUserId() {
        return currentUser().userId();
    }

    /**
     * Tells whether the current user has a role.
     *
     * @param role role name such as "ADMIN" (a leading "ROLE_" is also accepted)
     * @return true when logged in and holding that role; false otherwise (never throws)
     */
    public static boolean hasRole(String role) {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null || role == null) {
            return false;
        }
        String authority = role.startsWith("ROLE_") ? role : "ROLE_" + role;
        return authentication.getAuthorities().stream()
                .anyMatch(granted -> authority.equals(granted.getAuthority()));
    }
}
