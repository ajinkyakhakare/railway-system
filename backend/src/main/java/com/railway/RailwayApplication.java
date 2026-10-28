package com.railway;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Entry point of the Railway backend.
 * Because this class lives in the root package "com.railway", component scanning
 * automatically covers every module package (common, train, user, booking, payment, ops).
 */
@SpringBootApplication
public class RailwayApplication {

    /**
     * Starts the embedded Tomcat server and the Spring context.
     *
     * @param args command line arguments (not used)
     */
    public static void main(String[] args) {
        SpringApplication.run(RailwayApplication.class, args);
    }
}
