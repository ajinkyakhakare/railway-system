package com.railway.booking.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableScheduling;

/**
 * Switches on Spring's @Scheduled support for the whole application.
 * It is needed by BookingExpiryJob, which runs once a minute.
 * (Task G3.4, group G3.)
 */
@Configuration
@EnableScheduling
public class BookingSchedulingConfig {
}
