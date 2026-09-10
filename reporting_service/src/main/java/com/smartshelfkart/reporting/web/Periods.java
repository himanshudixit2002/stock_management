package com.smartshelfkart.reporting.web;

import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

/** Bounds checking for reporting periods. */
final class Periods {

    /**
     * Five years. Not a technical limit — the queries are indexed and would
     * survive more — but a request for a hundred-year period is a bug in the
     * caller, and answering it means scanning a table to prove it.
     */
    private static final long MAX_DAYS = 366L * 5;

    private Periods() {
    }

    static void validate(LocalDate from, LocalDate to) {
        if (from == null || to == null) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "Both from and to are required.");
        }
        if (to.isBefore(from)) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "The period ends before it starts.");
        }
        if (ChronoUnit.DAYS.between(from, to) > MAX_DAYS) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "That period is longer than five years.");
        }
    }
}
