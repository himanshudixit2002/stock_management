package com.smartshelfkart.reporting;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.autoconfigure.security.servlet.UserDetailsServiceAutoConfiguration;
import org.springframework.scheduling.annotation.EnableScheduling;

/**
 * Analytical read model over the operational store.
 *
 * <p>This service owns no business truth. Firestore does. Everything in the
 * database behind this application is a projection, rebuilt by the sync job,
 * and it exists for one reason: the questions asked of financial data are the
 * ones a document store answers worst. Group by tax rate across a quarter,
 * bucket receivables by age, join lines to invoices to payments and subtract.
 *
 * <p>Before this, those were answered by loading whole collections into memory
 * on the client and aggregating there — about two thousand lines of it, with no
 * pagination anywhere. That works until a workspace has a year of invoices.
 */
// The default user auto-configuration is excluded: this service has no
// username-and-password path at all, and leaving it on makes Spring print a
// generated password at every start, which reads like a credential someone
// could use.
@SpringBootApplication(exclude = UserDetailsServiceAutoConfiguration.class)
@EnableScheduling
public class ReportingApplication {

    public static void main(String[] args) {
        SpringApplication.run(ReportingApplication.class, args);
    }
}
