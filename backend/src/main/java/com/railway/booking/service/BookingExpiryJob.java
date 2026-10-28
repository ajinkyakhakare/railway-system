package com.railway.booking.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * Background job (task G3.4, group G3): releases seats held by bookings that were never paid.
 *
 * Every 60 seconds it calls sp_expire_unpaid_bookings(15) through BookingService, which expires
 * PENDING_PAYMENT bookings older than 15 minutes. Needs @EnableScheduling (BookingSchedulingConfig).
 */
@Component
public class BookingExpiryJob {

    private static final Logger log = LoggerFactory.getLogger(BookingExpiryJob.class);

    /** A booking must be paid within this many minutes. */
    private static final int UNPAID_LIMIT_MINUTES = 15;

    private final BookingService bookingService;

    public BookingExpiryJob(BookingService bookingService) {
        this.bookingService = bookingService;
    }

    /**
     * fixedDelay = the next run starts 60 s AFTER the previous one finished,
     * so two runs of the job can never overlap.
     */
    @Scheduled(fixedDelay = 60000)
    public void expireUnpaidBookings() {
        try {
            int expired = bookingService.expireUnpaidBookings(UNPAID_LIMIT_MINUTES);
            if (expired > 0) {
                log.info("Expired {} unpaid booking(s)", expired);
            }
        } catch (Exception e) {
            // A scheduled task must never throw: just log it and try again in a minute.
            log.error("Expiring unpaid bookings failed", e);
        }
    }
}
