package com.smartshelfkart.reporting.web;

import com.smartshelfkart.reporting.security.CallerPrincipal;
import com.smartshelfkart.reporting.service.FinancialQueries;
import com.smartshelfkart.reporting.service.Reports;
import java.time.LocalDate;
import java.util.List;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * The reports.
 *
 * <p>Every handler takes its workspace from the authenticated principal and
 * never from a query parameter. That is the whole tenancy story at this layer:
 * there is no code path where a caller can name the company whose revenue they
 * want to read, so there is no code path where forgetting to validate it leaks
 * one workspace into another.
 *
 * <p>Permissions are declared with {@code @PreAuthorize} against the same grant
 * keys the client uses. A caller who cannot see reports in the application
 * cannot see them here either.
 */
@RestController
@RequestMapping("/api/reports")
public class ReportController {

    /** The grant the client requires for the reporting screens. */
    private static final String VIEW_REPORTS = "hasAuthority('canViewReports') or hasAuthority('*')";

    private static final String VIEW_TAX = "hasAuthority('canViewTaxReports') or hasAuthority('*')";

    private static final String VIEW_CREDIT =
            "hasAuthority('canViewCreditControl') or hasAuthority('*')";

    private final FinancialQueries queries;

    public ReportController(FinancialQueries queries) {
        this.queries = queries;
    }

    /**
     * Output and input tax by rate, and the net position for the period.
     */
    @GetMapping("/tax-summary")
    @PreAuthorize(VIEW_TAX)
    public Reports.TaxSummary taxSummary(
            @AuthenticationPrincipal CallerPrincipal caller,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to) {
        Periods.validate(from, to);
        return queries.taxSummary(caller.companyId(), from, to);
    }

    /**
     * Receivables by age. Defaults to today, but takes an explicit date so a
     * month-end report can be reproduced later and still match.
     */
    @GetMapping("/aging")
    @PreAuthorize(VIEW_REPORTS)
    public Reports.AgingReport aging(
            @AuthenticationPrincipal CallerPrincipal caller,
            @RequestParam(required = false)
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate asOf) {
        return queries.aging(caller.companyId(), asOf == null ? LocalDate.now() : asOf);
    }

    /**
     * Revenue net of tax, cost of goods sold, operating expenses, and what is
     * left. The figure the inventory screens cannot produce, because they know
     * about margin and not about rent.
     */
    @GetMapping("/profit-and-loss")
    @PreAuthorize(VIEW_REPORTS)
    public Reports.ProfitAndLoss profitAndLoss(
            @AuthenticationPrincipal CallerPrincipal caller,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to) {
        Periods.validate(from, to);
        return queries.profitAndLoss(caller.companyId(), from, to);
    }

    /** Who owes what, worst first. Feeds credit control. */
    @GetMapping("/customer-balances")
    @PreAuthorize(VIEW_CREDIT)
    public List<Reports.CustomerBalance> customerBalances(
            @AuthenticationPrincipal CallerPrincipal caller,
            @RequestParam(defaultValue = "50") int limit) {
        return queries.customerBalances(caller.companyId(), Math.max(1, Math.min(limit, 500)));
    }
}
