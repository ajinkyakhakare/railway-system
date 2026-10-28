package com.railway.ops.service;

import com.railway.common.db.SqlHelper;
import com.railway.common.exception.ApiException;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;

/**
 * Admin reports (G5). Mostly thin wrappers around views and report queries.
 * NOT @Transactional: sp_generate_daily_revenue manages its own transaction (R12).
 */
@Service
public class ReportService {

    private final SqlHelper sql;

    public ReportService(SqlHelper sql) {
        this.sql = sql;
    }

    /** Station-wise daily revenue between two dates (default: last 30 days up to today). */
    public List<Map<String, Object>> revenue(LocalDate from, LocalDate to) {
        LocalDate end = (to != null) ? to : LocalDate.now();
        LocalDate start = (from != null) ? from : end.minusDays(30);
        if (start.isAfter(end)) {
            throw ApiException.badRequest("VALIDATION_ERROR", "from must not be after to");
        }
        return sql.query("SELECT Station_ID, Station_Code, Station_Name, Revenue_Date, Total_Revenue, Ticket_Count "
                + "FROM v_station_daily_revenue WHERE Revenue_Date BETWEEN ? AND ? "
                + "ORDER BY Revenue_Date, Station_Name", start, end);
    }

    /** Runs sp_generate_daily_revenue for one date. Returns {rowsAffected}. */
    public Map<String, Object> generateRevenue(LocalDate date) {
        return sql.call("CALL sp_generate_daily_revenue(?)", date);
    }

    /** Routes ranked by number of bookings (view uses RANK()). */
    public List<Map<String, Object>> popularRoutes() {
        return sql.query("SELECT Route_ID, Route_Name, Booking_Count, Popularity_Rank "
                + "FROM v_popular_routes ORDER BY Popularity_Rank, Route_ID");
    }

    /** Delay statistics per train. */
    public List<Map<String, Object>> delayMetrics() {
        return sql.query("SELECT Train_ID, Train_No, Train_Name, Total_Runs, Delayed_Runs, "
                + "Avg_Delay_Min, Max_Delay_Min FROM v_delay_metrics ORDER BY Avg_Delay_Min DESC, Train_No");
    }

    /**
     * Trains whose AVERAGE delay is above the threshold (GROUP BY + HAVING).
     * delayedRuns = number of that train's runs currently flagged DELAYED.
     */
    public List<Map<String, Object>> delayedTrains(int thresholdMinutes) {
        if (thresholdMinutes < 0) {
            throw ApiException.badRequest("VALIDATION_ERROR", "thresholdMinutes must be 0 or more");
        }
        return sql.query(
                "SELECT t.Train_ID, t.Train_No, t.Train_Name, "
              + "       ROUND(AVG(s.Delay_Minutes), 1) AS Avg_Delay_Min, "
              + "       COUNT(CASE WHEN s.Status = 'DELAYED' THEN 1 END) AS Delayed_Runs "
              + "FROM train t "
              + "JOIN train_run r ON r.Train_ID = t.Train_ID "
              + "JOIN train_run_status s ON s.Run_ID = r.Run_ID "
              + "GROUP BY t.Train_ID, t.Train_No, t.Train_Name "
              + "HAVING AVG(s.Delay_Minutes) > ? "
              + "ORDER BY AVG(s.Delay_Minutes) DESC, t.Train_No",
                thresholdMinutes);
    }

    /**
     * Stations whose total revenue is above the average per-station revenue.
     * The inner subquery computes one total per station; the scalar subquery averages them.
     */
    public List<Map<String, Object>> topStations() {
        return sql.query(
                "SELECT st.Station_ID, st.Station_Name, st.Station_Total AS Total_Revenue "
              + "FROM (SELECT Station_ID, Station_Name, SUM(Total_Revenue) AS Station_Total "
              + "      FROM v_station_daily_revenue GROUP BY Station_ID, Station_Name) st "
              + "WHERE st.Station_Total > "
              + "      (SELECT AVG(per_station.Station_Total) "
              + "       FROM (SELECT SUM(Total_Revenue) AS Station_Total "
              + "             FROM v_station_daily_revenue GROUP BY Station_ID) per_station) "
              + "ORDER BY st.Station_Total DESC");
    }
}
