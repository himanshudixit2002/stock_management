package com.smartshelfkart.reporting.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.smartshelfkart.reporting.security.CallerPrincipal;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.transaction.annotation.Transactional;

/**
 * The claim this service lives or dies on: one workspace's money never appears
 * in another's report.
 *
 * <p>Two workspaces are seeded with deliberately different magnitudes, so a leak
 * is not a subtle rounding difference but an obviously wrong number. Every
 * report is then run for each workspace and checked against what that workspace
 * alone should produce.
 *
 * <p>This is worth its own file rather than an assertion tacked onto the query
 * tests. Those seed one company, so every one of them would pass unchanged
 * against a query that had lost its {@code company_id} predicate entirely.
 */
@SpringBootTest
@Transactional
class TenantIsolationTest {

    private static final String ACME = "acme";
    private static final String RIVAL = "rival";
    private static final LocalDate MARCH = LocalDate.of(2026, 3, 1);
    private static final LocalDate APRIL = LocalDate.of(2026, 4, 1);

    @Autowired
    private FinancialQueries queries;

    @Autowired
    private NamedParameterJdbcTemplate jdbc;

    @BeforeEach
    void seedTwoWorkspaces() {
        for (String table : List.of(
                "invoice_lines", "payments", "invoices", "expenses", "purchase_bills")) {
            jdbc.update("DELETE FROM " + table, Map.of());
        }

        // acme: one invoice of 1,000.00 including 100.00 of tax, unpaid.
        invoice(ACME, "a1", 100_000, 10_000, 0);
        line(ACME, "al1", "a1", "10.00", 100_000, 10_000, 40_000);
        expense(ACME, "ae1", "rent", 20_000);
        bill(ACME, "ab1", "10.00", 30_000, 3_000);

        // rival: two orders of magnitude larger, so a leak is unmissable.
        invoice(RIVAL, "r1", 10_000_000, 1_000_000, 0);
        line(RIVAL, "rl1", "r1", "10.00", 10_000_000, 1_000_000, 4_000_000);
        expense(RIVAL, "re1", "rent", 2_000_000);
        bill(RIVAL, "rb1", "10.00", 3_000_000, 300_000);
    }

    @Test
    @DisplayName("the tax return contains only the caller's own invoices")
    void taxSummaryIsScoped() {
        Reports.TaxSummary acme = queries.taxSummary(ACME, MARCH, APRIL);
        Reports.TaxSummary rival = queries.taxSummary(RIVAL, MARCH, APRIL);

        assertThat(acme.outputTaxMinor()).isEqualTo(10_000L);
        assertThat(acme.inputTaxMinor()).isEqualTo(3_000L);
        assertThat(rival.outputTaxMinor()).isEqualTo(1_000_000L);
        assertThat(rival.inputTaxMinor()).isEqualTo(300_000L);

        // Neither total is the sum of both, which is what a missing predicate
        // would produce.
        assertThat(acme.outputTaxMinor() + rival.outputTaxMinor()).isEqualTo(1_010_000L);
    }

    @Test
    @DisplayName("aging contains only the caller's own receivables")
    void agingIsScoped() {
        assertThat(queries.aging(ACME, APRIL).totalOutstandingMinor()).isEqualTo(100_000L);
        assertThat(queries.aging(RIVAL, APRIL).totalOutstandingMinor()).isEqualTo(10_000_000L);
    }

    @Test
    @DisplayName("profit and loss is computed per workspace, including the join to lines")
    void profitAndLossIsScoped() {
        Reports.ProfitAndLoss acme = queries.profitAndLoss(ACME, MARCH, APRIL);

        // 100,000 billed less 10,000 tax = 90,000 revenue; cost 40,000 leaves
        // 50,000 gross; 20,000 rent leaves 30,000.
        assertThat(acme.revenueMinor()).isEqualTo(90_000L);
        assertThat(acme.costOfGoodsSoldMinor()).isEqualTo(40_000L);
        assertThat(acme.netProfitMinor()).isEqualTo(30_000L);

        Reports.ProfitAndLoss rival = queries.profitAndLoss(RIVAL, MARCH, APRIL);
        assertThat(rival.revenueMinor()).isEqualTo(9_000_000L);

        // The expense breakdown is the easiest place for a leak to hide: both
        // workspaces have a head called "rent".
        assertThat(acme.expenseBreakdown()).singleElement()
                .satisfies(head -> assertThat(head.amountMinor()).isEqualTo(20_000L));
    }

    @Test
    @DisplayName("customer balances never cross workspaces")
    void customerBalancesAreScoped() {
        List<Reports.CustomerBalance> acme = queries.customerBalances(ACME, 100);
        assertThat(acme).singleElement()
                .satisfies(balance -> assertThat(balance.outstandingMinor())
                        .isEqualTo(100_000L));

        assertThat(queries.customerBalances(RIVAL, 100)).singleElement()
                .satisfies(balance -> assertThat(balance.outstandingMinor())
                        .isEqualTo(10_000_000L));
    }

    @Test
    @DisplayName("a workspace with no rows reports zero, not another workspace's figures")
    void unknownWorkspaceSeesNothing() {
        // The failure this catches is a query whose scoping silently falls back
        // to "everything" when it matches nothing.
        Reports.TaxSummary summary = queries.taxSummary("no-such-company", MARCH, APRIL);
        assertThat(summary.outputTaxMinor()).isZero();
        assertThat(summary.output()).isEmpty();

        assertThat(queries.aging("no-such-company", APRIL).totalOutstandingMinor()).isZero();
        assertThat(queries.customerBalances("no-such-company", 100)).isEmpty();
        assertThat(queries.profitAndLoss("no-such-company", MARCH, APRIL).revenueMinor())
                .isZero();
    }

    @Test
    @DisplayName("a principal carrying no grants is refused, and null grants too")
    void permissionsFailClosed() {
        // The reporting endpoints are gated on these. An empty set is a member
        // holding nothing; null is grants that could not be read, and a storage
        // outage must not open the ledger.
        assertThat(new CallerPrincipal("u", ACME, Set.of()).has("canViewReports")).isFalse();
        assertThat(new CallerPrincipal("u", ACME, null).has("canViewReports")).isFalse();
        assertThat(new CallerPrincipal("u", ACME, Set.of("canViewProducts"))
                .has("canViewReports")).isFalse();

        assertThat(new CallerPrincipal("u", ACME, Set.of("canViewReports"))
                .has("canViewReports")).isTrue();
        assertThat(new CallerPrincipal("u", ACME, Set.of("*")).has("canViewReports")).isTrue();
    }

    // ------------------------------------------------------------------

    private void invoice(String company, String id, long total, long tax, long paid) {
        jdbc.update("""
                INSERT INTO invoices (company_id, id, invoice_number, customer_id,
                        customer_name, issued_on, due_on, status, subtotal_minor,
                        discount_minor, tax_minor, total_minor, paid_minor, currency, synced_at)
                VALUES (:company, :id, :id, :customer, :customer, :issued, :due, 'sent',
                        :subtotal, 0, :tax, :total, :paid, 'INR', CURRENT_TIMESTAMP)
                """,
                new MapSqlParameterSource()
                        .addValue("company", company)
                        .addValue("id", id)
                        .addValue("customer", company + "-customer")
                        .addValue("issued", MARCH.plusDays(5))
                        .addValue("due", MARCH.plusDays(20))
                        .addValue("subtotal", total - tax)
                        .addValue("tax", tax)
                        .addValue("total", total)
                        .addValue("paid", paid));
    }

    private void line(String company, String id, String invoiceId, String rate,
            long lineTotal, long tax, long cost) {
        jdbc.update("""
                INSERT INTO invoice_lines (company_id, id, invoice_id, product_id,
                        product_name, quantity, unit_price_minor, discount_minor,
                        tax_rate, tax_minor, line_total_minor, cost_price_minor)
                VALUES (:company, :id, :invoiceId, 'p1', 'Widget', 1, 0, 0,
                        :rate, :tax, :lineTotal, :cost)
                """,
                new MapSqlParameterSource()
                        .addValue("company", company)
                        .addValue("id", id)
                        .addValue("invoiceId", invoiceId)
                        .addValue("rate", new java.math.BigDecimal(rate))
                        .addValue("tax", tax)
                        .addValue("lineTotal", lineTotal)
                        .addValue("cost", cost));
    }

    private void expense(String company, String id, String head, long amount) {
        jdbc.update("""
                INSERT INTO expenses (company_id, id, incurred_on, head, amount_minor,
                        tax_minor, synced_at)
                VALUES (:company, :id, :on, :head, :amount, 0, CURRENT_TIMESTAMP)
                """,
                new MapSqlParameterSource()
                        .addValue("company", company)
                        .addValue("id", id)
                        .addValue("on", MARCH.plusDays(3))
                        .addValue("head", head)
                        .addValue("amount", amount));
    }

    private void bill(String company, String id, String rate, long taxable, long tax) {
        jdbc.update("""
                INSERT INTO purchase_bills (company_id, id, vendor_id, vendor_name,
                        billed_on, taxable_minor, tax_rate, tax_minor, total_minor, synced_at)
                VALUES (:company, :id, 'v1', 'Vendor', :on, :taxable, :rate, :tax,
                        :total, CURRENT_TIMESTAMP)
                """,
                new MapSqlParameterSource()
                        .addValue("company", company)
                        .addValue("id", id)
                        .addValue("on", MARCH.plusDays(2))
                        .addValue("rate", new java.math.BigDecimal(rate))
                        .addValue("taxable", taxable)
                        .addValue("tax", tax)
                        .addValue("total", taxable + tax));
    }
}
