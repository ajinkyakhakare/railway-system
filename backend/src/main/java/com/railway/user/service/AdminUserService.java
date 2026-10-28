package com.railway.user.service;

import com.railway.common.db.SqlHelper;
import com.railway.common.exception.ApiException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

/**
 * Admin user management: list users, replace roles, activate / deactivate.
 * No stored procedure is CALLed here, so @Transactional is allowed (rule R12).
 */
@Service
public class AdminUserService {

    private final SqlHelper sql;
    private final UserService userService;

    public AdminUserService(SqlHelper sql, UserService userService) {
        this.sql = sql;
        this.userService = userService;
    }

    /** GET /admin/users = rows of view v_user_account. */
    public List<Map<String, Object>> listUsers() {
        return sql.query("SELECT * FROM v_user_account ORDER BY User_ID");
    }

    /**
     * PUT /admin/users/{id}/roles: replace ALL roles of the user (DELETE then INSERT).
     * Both statements are one transaction; triggers trg_user_role_ad / trg_user_role_ai write the audit rows.
     * Everything is validated BEFORE the first write.
     */
    @Transactional
    public Map<String, Object> replaceRoles(Long userId, List<String> requestedRoles) {
        requireUser(userId);

        // Clean the input: trim, upper-case, drop duplicates, keep order.
        Set<String> roleNames = new LinkedHashSet<>();
        if (requestedRoles != null) {
            for (String name : requestedRoles) {
                if (name == null || name.isBlank()) {
                    throw ApiException.badRequest("VALIDATION_ERROR", "Role names must not be blank");
                }
                roleNames.add(name.trim().toUpperCase(Locale.ROOT));
            }
        }
        if (roleNames.isEmpty()) {
            throw ApiException.badRequest("VALIDATION_ERROR", "A user must have at least one role");
        }

        // Translate names to ids; an unknown name is rejected.
        List<Long> roleIds = new ArrayList<>();
        for (String name : roleNames) {
            Long roleId = sql.scalar("SELECT Role_ID FROM role WHERE Role_Name = ?", Long.class, name);
            if (roleId == null) {
                throw ApiException.badRequest("VALIDATION_ERROR", "Unknown role: " + name);
            }
            roleIds.add(roleId);
        }

        sql.update("DELETE FROM user_role WHERE User_ID = ?", userId);
        for (Long roleId : roleIds) {
            sql.update("INSERT INTO user_role (User_ID, Role_ID) VALUES (?, ?)", userId, roleId);
        }

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("userId", userId);
        result.put("roles", userService.findRoles(userId));
        return result;
    }

    /** PUT /admin/users/{id}/active -> {userId, active}. */
    public Map<String, Object> setActive(Long userId, boolean active) {
        requireUser(userId);
        sql.update("UPDATE app_user SET Is_Active = ? WHERE User_ID = ?", active ? 1 : 0, userId);

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("userId", userId);
        result.put("active", active);
        return result;
    }

    private void requireUser(Long userId) {
        Long found = sql.scalar("SELECT User_ID FROM app_user WHERE User_ID = ?", Long.class, userId);
        if (found == null) {
            throw ApiException.notFound("User not found");
        }
    }
}
