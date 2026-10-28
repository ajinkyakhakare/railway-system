package com.railway.payment.service;

import com.railway.common.db.SqlHelper;
import com.railway.common.exception.ApiException;
import com.railway.payment.dto.ConcessionUpdateRequest;
import com.railway.payment.dto.FareRuleUpdateRequest;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Service;

/**
 * Admin maintenance of fare_rule and concession_rule, plus the fare audit log.
 *
 * Fare changes are logged automatically by the database trigger trg_fare_audit (AFTER UPDATE
 * on fare_rule), so this class only runs a plain UPDATE. The trigger stores USER() as
 * Changed_By, which is the database account the backend connects with.
 *
 * Value ranges (positive rate, 0..100 percent) are validated by the request DTOs and
 * again by the CHECK constraints of the tables.
 */
@Service
public class AdminFareService {

    private static final String FARE_RULE_SELECT =
            "SELECT Fare_Rule_ID, Class_Code, Base_Fare_Per_Km, Min_Fare, Updated_At FROM fare_rule";

    private static final String CONCESSION_RULE_SELECT =
            "SELECT Concession_Rule_ID, Concession_Type, Discount_Percent, Description FROM concession_rule";

    private final SqlHelper sql;

    public AdminFareService(SqlHelper sql) {
        this.sql = sql;
    }

    // -------------------------------------------------------------- fare rules

    public List<Map<String, Object>> listFareRules() {
        return sql.query(FARE_RULE_SELECT + " ORDER BY Fare_Rule_ID");
    }

    public Map<String, Object> updateFareRule(Long id, FareRuleUpdateRequest request) {
        requireFareRule(id);
        sql.update("UPDATE fare_rule SET Base_Fare_Per_Km = ?, Min_Fare = ? WHERE Fare_Rule_ID = ?",
                request.baseFarePerKm(), request.minFare(), id);
        return requireFareRule(id);   // re-read so the response shows the stored values and Updated_At
    }

    // --------------------------------------------------------- concession rules

    public List<Map<String, Object>> listConcessionRules() {
        return sql.query(CONCESSION_RULE_SELECT + " ORDER BY Concession_Rule_ID");
    }

    public Map<String, Object> updateConcessionRule(Long id, ConcessionUpdateRequest request) {
        requireConcessionRule(id);
        sql.update("UPDATE concession_rule SET Discount_Percent = ? WHERE Concession_Rule_ID = ?",
                request.discountPercent(), id);
        return requireConcessionRule(id);
    }

    // -------------------------------------------------------------- audit log

    /** All fare changes, newest first. */
    public List<Map<String, Object>> listFareAudit() {
        return sql.query("SELECT * FROM fare_audit_log ORDER BY Changed_At DESC, Audit_ID DESC");
    }

    // ---------------------------------------------------------------- helpers

    private Map<String, Object> requireFareRule(Long id) {
        Map<String, Object> row = sql.queryOne(FARE_RULE_SELECT + " WHERE Fare_Rule_ID = ?", id);
        if (row == null) {
            throw ApiException.notFound("Fare rule " + id + " not found");
        }
        return row;
    }

    private Map<String, Object> requireConcessionRule(Long id) {
        Map<String, Object> row = sql.queryOne(CONCESSION_RULE_SELECT + " WHERE Concession_Rule_ID = ?", id);
        if (row == null) {
            throw ApiException.notFound("Concession rule " + id + " not found");
        }
        return row;
    }
}
