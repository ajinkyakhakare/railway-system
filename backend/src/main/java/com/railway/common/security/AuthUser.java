package com.railway.common.security;

import java.util.List;

/**
 * The logged-in user as stored in the JWT and in Spring's SecurityContext (as the principal).
 *
 * @param userId id of the user (app_user.User_ID)
 * @param email  e-mail of the user
 * @param roles  role names WITHOUT the ROLE_ prefix, e.g. ["PASSENGER"]
 */
public record AuthUser(Long userId, String email, List<String> roles) {
}
