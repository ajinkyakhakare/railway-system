package com.railway.common.db;

import org.springframework.jdbc.core.ArgumentPreparedStatementSetter;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.PreparedStatementCallback;
import org.springframework.jdbc.core.PreparedStatementCreator;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.jdbc.support.KeyHolder;
import org.springframework.stereotype.Component;

import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * Thin wrapper around JdbcTemplate used by all modules (the project is "SQL-first": no JPA).
 *
 * Result rows are returned as Map objects whose keys are lowerCamelCase versions of the
 * column names (Train_ID -> trainId) and whose date/time values are java.time objects, so
 * Jackson writes them as ISO-8601 strings.
 */
@Component
public class SqlHelper {

    private final JdbcTemplate jdbc;

    /** Turns one JDBC row into a camelCase map. */
    private final RowMapper<Map<String, Object>> rowMapper = (rs, rowNum) -> mapRow(rs);

    /**
     * Creates the helper.
     *
     * @param jdbc Spring's JdbcTemplate (auto-configured from spring.datasource.*)
     */
    public SqlHelper(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /**
     * Runs a SELECT and returns all rows.
     *
     * @param sql  SQL with ? placeholders
     * @param args values for the placeholders
     * @return list of rows (empty list when nothing matches)
     */
    public List<Map<String, Object>> query(String sql, Object... args) {
        return jdbc.query(sql, rowMapper, args);
    }

    /**
     * Runs a SELECT and returns only the first row.
     *
     * @param sql  SQL with ? placeholders
     * @param args values for the placeholders
     * @return the first row, or null when there is no row
     */
    public Map<String, Object> queryOne(String sql, Object... args) {
        List<Map<String, Object>> rows = query(sql, args);
        return rows.isEmpty() ? null : rows.get(0);
    }

    /**
     * Calls a stored procedure that returns one result set, e.g. "CALL sp_book_ticket(?,?,?,?,?,?)",
     * and returns the first row of that result set. SQL errors raised with SIGNAL 45000 are thrown as
     * Spring DataAccessExceptions and translated by GlobalExceptionHandler.
     * A procedure without any result set (HELPER procedures) gives null; call those with update().
     *
     * @param sql  the CALL statement with ? placeholders
     * @param args values for the placeholders
     * @return first row of the procedure's result set, or null when it returned no rows
     */
    public Map<String, Object> call(String sql, Object... args) {
        // The cast selects PreparedStatementCallback (JdbcTemplate also has a CallableStatement overload).
        return jdbc.execute(sql, (PreparedStatementCallback<Map<String, Object>>) ps -> {
            new ArgumentPreparedStatementSetter(args).setValues(ps);
            boolean isResultSet = ps.execute();
            // A procedure can emit update counts before its final SELECT, so skip until a result set shows up.
            while (true) {
                if (isResultSet) {
                    try (ResultSet rs = ps.getResultSet()) {
                        return rs.next() ? mapRow(rs) : null;
                    }
                }
                if (ps.getUpdateCount() == -1) {
                    return null;   // no more results at all
                }
                isResultSet = ps.getMoreResults();
            }
        });
    }

    /**
     * Runs INSERT, UPDATE or DELETE.
     *
     * @param sql  SQL with ? placeholders
     * @param args values for the placeholders
     * @return number of affected rows
     */
    public int update(String sql, Object... args) {
        return jdbc.update(sql, args);
    }

    /**
     * Runs an INSERT and returns the AUTO_INCREMENT key that MySQL generated.
     *
     * @param sql  INSERT statement with ? placeholders
     * @param args values for the placeholders
     * @return the generated key (first key for multi-row inserts), or 0 when the table has no generated key
     */
    public long insert(String sql, Object... args) {
        KeyHolder keyHolder = new GeneratedKeyHolder();
        PreparedStatementCreator creator = connection -> {
            PreparedStatement ps = connection.prepareStatement(sql, Statement.RETURN_GENERATED_KEYS);
            new ArgumentPreparedStatementSetter(args).setValues(ps);
            return ps;
        };
        jdbc.update(creator, keyHolder);

        List<Map<String, Object>> keys = keyHolder.getKeyList();
        if (keys.isEmpty() || keys.get(0).isEmpty()) {
            return 0L;
        }
        Object first = keys.get(0).values().iterator().next();
        return (first instanceof Number number) ? number.longValue() : 0L;
    }

    /**
     * Runs a query that returns one column and gives the value of the first row.
     *
     * @param sql  SQL with ? placeholders, e.g. "SELECT COUNT(*) FROM booking WHERE User_ID = ?"
     * @param type Java type wanted (Long.class, String.class, BigDecimal.class, ...)
     * @param args values for the placeholders
     * @param <T>  Java type wanted
     * @return the value, or null when there is no row (or the value is SQL NULL)
     */
    public <T> T scalar(String sql, Class<T> type, Object... args) {
        List<T> values = jdbc.queryForList(sql, type, args);
        return values.isEmpty() ? null : values.get(0);
    }

    // ------------------------------------------------------------------ private helpers

    /** Reads the current row of a ResultSet into a LinkedHashMap (keeps column order, allows null values). */
    private static Map<String, Object> mapRow(ResultSet rs) throws SQLException {
        ResultSetMetaData meta = rs.getMetaData();
        int columns = meta.getColumnCount();
        Map<String, Object> row = new LinkedHashMap<>(columns * 2);
        for (int i = 1; i <= columns; i++) {
            // getColumnLabel returns the alias (AS ...) when there is one, so aliases work as expected.
            row.put(toCamelCase(meta.getColumnLabel(i)), normalise(rs.getObject(i)));
        }
        return row;
    }

    /** Converts old java.sql date/time classes to java.time classes (Jackson writes those as ISO-8601). */
    private static Object normalise(Object value) {
        if (value instanceof java.sql.Timestamp timestamp) {
            return timestamp.toLocalDateTime();
        }
        if (value instanceof java.sql.Date date) {
            return date.toLocalDate();
        }
        if (value instanceof java.sql.Time time) {
            return time.toLocalTime();
        }
        return value;   // numbers, strings, booleans, BigDecimal and java.time values stay unchanged
    }

    /**
     * Converts a Pascal_Snake column name to lowerCamelCase.
     * Rule: split at "_", lower-case every part, upper-case the first letter of every part except the first.
     * So Available_CNF -> availableCnf, Train_ID -> trainId, PNR -> pnr, IP_Address -> ipAddress
     * (the special cases ID/CNF/RAC/WL follow automatically from "lower-case the rest").
     * A label that has no underscore and already starts with a lower-case letter (e.g. an alias
     * "totalRevenue") is returned unchanged so that existing camelCase aliases are not damaged.
     *
     * @param label column label from the result set
     * @return camelCase key
     */
    static String toCamelCase(String label) {
        if (label == null || label.isEmpty()) {
            return label;
        }
        if (label.indexOf('_') < 0 && Character.isLowerCase(label.charAt(0))) {
            return label;
        }
        StringBuilder result = new StringBuilder(label.length());
        boolean firstPart = true;
        for (String part : label.split("_")) {
            if (part.isEmpty()) {
                continue;
            }
            String lower = part.toLowerCase(Locale.ROOT);
            if (firstPart) {
                result.append(lower);
            } else {
                result.append(Character.toUpperCase(lower.charAt(0))).append(lower.substring(1));
            }
            firstPart = false;
        }
        return result.length() == 0 ? label : result.toString();
    }
}
