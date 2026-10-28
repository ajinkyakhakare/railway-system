package com.railway.user.service;

import com.railway.common.db.SqlHelper;
import com.railway.common.exception.ApiException;
import org.springframework.stereotype.Service;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Profile of the logged-in user (GET/PUT /users/me) plus the shared "roles of a user" lookup
 * that the other G2 services reuse.
 *
 * Not @Transactional: each method runs plain single statements and calls no stored procedure.
 */
@Service
public class UserService {

    private final SqlHelper sql;

    public UserService(SqlHelper sql) {
        this.sql = sql;
    }

    /** GET /users/me -> {userId,email,fullName,phone,roles[]}. */
    public Map<String, Object> getProfile(Long userId) {
        Map<String, Object> row = sql.queryOne(
                "SELECT User_ID, Email, Full_Name, Phone FROM app_user WHERE User_ID = ?", userId);
        if (row == null) {
            throw ApiException.notFound("User not found");
        }

        Map<String, Object> profile = new LinkedHashMap<>();
        profile.put("userId", row.get("userId"));
        profile.put("email", row.get("email"));
        profile.put("fullName", row.get("fullName"));
        profile.put("phone", row.get("phone"));
        profile.put("roles", findRoles(userId));
        return profile;
    }

    /** PUT /users/me: change name and phone only, then return the fresh profile. */
    public Map<String, Object> updateProfile(Long userId, String fullName, String phone) {
        sql.update("UPDATE app_user SET Full_Name = ?, Phone = ? WHERE User_ID = ?",
                fullName.trim(), phone, userId);
        // getProfile throws NOT_FOUND if the user does not exist (the update count can be 0
        // for identical values, so it is not a reliable existence check).
        return getProfile(userId);
    }

    /** Role names of a user (PASSENGER / ADMIN / OPERATOR), ordered by role id. */
    public List<String> findRoles(Long userId) {
        List<Map<String, Object>> rows = sql.query(
                "SELECT r.Role_Name FROM user_role ur "
                        + "JOIN role r ON r.Role_ID = ur.Role_ID "
                        + "WHERE ur.User_ID = ? ORDER BY r.Role_ID", userId);
        return rows.stream().map(row -> (String) row.get("roleName")).toList();
    }
}
