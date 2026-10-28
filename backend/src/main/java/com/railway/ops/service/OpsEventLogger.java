package com.railway.ops.service;

import com.railway.common.security.SecurityUtil;
import org.bson.Document;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.Sort;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.query.Query;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Writes and reads the MongoDB audit trail "ops_event_log".
 * MongoDB is optional: when app.mongo.enabled=false nothing is written and
 * the read method returns an empty list. A MongoDB failure must NEVER make
 * a request fail, so every call is wrapped in try/catch.
 */
@Service
public class OpsEventLogger {

    private static final Logger log = LoggerFactory.getLogger(OpsEventLogger.class);
    private static final String COLLECTION = "ops_event_log";
    private static final int MAX_LIMIT = 500;

    private final boolean mongoEnabled;
    private final ObjectProvider<MongoTemplate> mongoProvider;

    public OpsEventLogger(@Value("${app.mongo.enabled:false}") boolean mongoEnabled,
                          ObjectProvider<MongoTemplate> mongoProvider) {
        this.mongoEnabled = mongoEnabled;
        this.mongoProvider = mongoProvider;
    }

    /** Stores one status-change event. Never throws. */
    public void log(Long runId, String status, Integer delayMinutes, String reason) {
        if (!mongoEnabled) {
            return;
        }
        try {
            MongoTemplate mongo = mongoProvider.getIfAvailable();
            if (mongo == null) {
                log.warn("MongoDB is enabled but no MongoTemplate bean is available");
                return;
            }
            Document event = new Document()
                    .append("runId", runId)
                    .append("status", status)
                    .append("delayMinutes", delayMinutes)
                    .append("reason", reason)
                    .append("changedBy", SecurityUtil.currentUser().email())
                    .append("at", new Date());
            mongo.insert(event, COLLECTION);
        } catch (Exception ex) {
            log.warn("Could not write ops event to MongoDB: {}", ex.getMessage());
        }
    }

    /**
     * Returns the latest events (newest first) as maps with the keys
     * runId, status, delayMinutes, reason, changedBy, at.
     * Returns an empty list when MongoDB is disabled or unreachable.
     */
    public List<Map<String, Object>> latest(int limit) {
        List<Map<String, Object>> result = new ArrayList<>();
        if (!mongoEnabled) {
            return result;
        }
        int safeLimit = Math.max(1, Math.min(limit, MAX_LIMIT));
        try {
            MongoTemplate mongo = mongoProvider.getIfAvailable();
            if (mongo == null) {
                return result;
            }
            Query query = new Query().with(Sort.by(Sort.Direction.DESC, "at")).limit(safeLimit);
            for (Document doc : mongo.find(query, Document.class, COLLECTION)) {
                result.add(toMap(doc));
            }
        } catch (Exception ex) {
            log.warn("Could not read ops events from MongoDB: {}", ex.getMessage());
        }
        return result;
    }

    /** Converts a Mongo document to the JSON shape of the API. */
    private Map<String, Object> toMap(Document doc) {
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("runId", doc.get("runId"));
        row.put("status", doc.get("status"));
        row.put("delayMinutes", doc.get("delayMinutes"));
        row.put("reason", doc.get("reason"));
        row.put("changedBy", doc.get("changedBy"));
        Object at = doc.get("at");
        if (at instanceof Date date) {
            row.put("at", LocalDateTime.ofInstant(date.toInstant(), ZoneId.of("Asia/Kolkata")));
        } else {
            row.put("at", at);
        }
        return row;
    }
}
