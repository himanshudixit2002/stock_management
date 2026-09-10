package com.smartshelfkart.reporting.service;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.transaction.annotation.Transactional;

/**
 * The reports, against a real schema built by the real migration.
 *
 * <p>Rows are inserted with SQL rather than through the repositories on
 * purpose. The subject here is the query, and going in through JPA would let a
 * mapping bug and a query bug cancel each other out — the projection has its
 * own tests for that.
 *
 * <p>Every expected figure is arithmetic stated in a comment above the
 * assertion. A test that computes its expectation the same way the code does
 * proves only that the code agrees with itself.
 */
@SpringBootTest
@Transactional
class FinancialQueriesTest {

    private static final String ACME = "acme";
    private static final LocalDate MARCH = LocalDate.of(2026, 3, 1);

    @Autowired
    private FinancialQueries queries;

    @Autowired
    private NamedParameterJdbcTemplate jdbc;

    @BeforeEach
    void clean() {
        for (String table : List.of(
                "invoice_lines", "payments", "invoices", "expenses", "purchase_bills")) {
            jdbc.update("DELETE FROM " + table, Map.of());
        }
    }

    // ------------------------------------------------------------------
    // Fixtures
    // ------------------------------------------------------------------

    private void invoice(String company, String id, LocalDate issued, LocalDate due,
            String status, long total, long tax, long paid, String customerId) {
        jdbc.update("""
                INSERT INTO invoices (company_id, id, invoice_number, customer_id,
                        customer_name, issued_on, due_on, status, subtotal_minor,
                        discount_minor, tax_minor, total_minor, paid_minor, currency, synced_at)
                VALUES (:company, :id, :id, :customerId, :customerName, :issued, :due,
                        :status, :subtotal, 0, :tax, :total, :paid, 'INR', CURRENT_TIMESTAMP)
                """,
                new MapSqlParameterSource()
                        .addValue("company", company)
                        .addValue("id", id)
                        .addValue("customerId", customerId)
                        .addValue("customerName", "Customer " + customerId)
                        .addValue("issued", issued)
                        .addValue("due", due == null ? issued : due)
                        .addValue("status", status)
                        .addValue("subtotal", total - tax)
                        .addValue("tax", tax)
                        .addValue("total", total)
                        .addValue("paid", paid));
    }

    private void line(String company, String id, String invoiceId, String rate,
            long lineTotal, long tax, long cost, double qty) {
        jdbc.update("""
                INSERT INTO invoice_lines (company_id, id, invoice_id, product_id,
                        product_name, quantity, unit_price_minor, discount_minor,
                        tax_rate, tax_minor, line_total_minor, cost_price_minor)
                VALUES (:company, :id, :invoiceId, 'p1', 'Widget', :qty, 0, 0,
                        :rate, :tax, :lineTotal, :cost)
                """,
                new MapSqlParameterSource()
                        .addValue("company", company)
                        .addValue("id", id)
                        .addValue("invoiceId", invoiceId)
                        .addValue("qty", qty)
                        .addValue("rate", new java.math.BigDecimal(rate))
                        .addValue("tax", tax)
                        .addValue("lineTotal", lineTotal)
                        .addValue("cost", cost));
    }

    private void expense(String company, String id, LocalDate on, String head, long amount) {
        jdbc.update("""
                INSERT INTO expenses (company_id, id, incurred_on, head, amount_minor,
                        tax_minor, synced_at)
                VALUES (:company, :id, :on, :head, :amount, 0, CURRENT_TIMESTAMP)
                """,
                new MapSqlParameterSource()
                        .addValue("company", company)
                        .addValue("id", id)
                        .addValue("on", on)
                        .addValue("head", head)
                        .addValue("amount", amount));
    }

    private void bill(String company, String id, LocalDate on, String rate,
            long taxable, long tax) {
        jdbc.update("""
                INSERT INTO purchase_bills (company_id, id, vendor_id, vendor_name,
                        billed_on, taxable_minor, tax_rate, tax_minor, total_minor, synced_at)
                VALUES (:company, :id, 'v1', 'Vendor', :on, :taxable, :rate, :tax,
                        :total, CURRENT_TIMESTAMP)
                """,
                new MapSqlParameterSource()
                        .addValue("company", company)
                        .addValue("id", id)
                        .addValue("on", on)
                        .addValue("rate", new java.math.BigDecimal(rate))
                        .addValue("taxable", taxable)
                        .addValue("tax", tax)
                        .addValue("total", taxable + tax));
    }

    // ------------------------------------------------------------------
    // Tax
    // ------------------------------------------------------------------

    @Test
    @DisplayName("output tax groups by rate, and voided invoices are excluded")
    void taxByRate() {
        invoice(ACME, "i1", MARCH, MARCH, "paid", 11_800, 1_800, 11_800, "c1");
        line(ACME, "l1", "i1", "18.00", 11_800, 1_800, 0, 1);

        invoice(ACME, "i2", MARCH, MARCH, "sent", 10_500, 500, 0, "c2");
        line(ACME, "l2", "i2", "5.00", 10_500, 500, 0, 1);

        // Voided. Its tax must not reach the return; a cancelled invoice was
        // never charged and filing it would overstate what is owed.
        invoice(ACME, "i3", MARCH, MARCH, "void", 100_000, 20_000, 0, "c3");
        line(ACME, "l3", "i3", "18.00", 100_000, 20_000, 0, 1);

        Reports.TaxSummary summary =
                queries.taxSummary(ACME, MARCH, MARCH.plusMonths(1));

        assertThat(summary.output()).extracting(Reports.TaxBand::rate)
                .containsExactly("5", "18");
        // 1,800 at 18% and 500 at 5% = 2,300. The voided 20,000 is absent.
        assertThat(summary.outputTaxMinor()).isEqualTo(2_300L);
        assertThat(summary.output().get(1).taxableMinor()).isEqualTo(10_000L);
    }

    @Test
    @DisplayName("the net position is output tax less input tax, and can be reclaimable")
    void netPosition() {
        invoice(ACME, "i1", MARCH, MARCH, "paid", 11_800, 1_800, 11_800, "c1");
        line(ACME, "l1", "i1", "18.00", 11_800, 1_800, 0, 1);
        // Bought more than was sold this month, which happens and must not
        // report as a negative liability dressed up as a positive one.
        bill(ACME, "b1", MARCH, "18.00", 50_000, 9_000);

        Reports.TaxSummary summary = queries.taxSummary(ACME, MARCH, MARCH.plusMonths(1));

        assertThat(summary.outputTaxMinor()).isEqualTo(1_800L);
        assertThat(summary.inputTaxMinor()).isEqualTo(9_000L);
        // 1,800 - 9,000 = -7,200, i.e. reclaimable.
        assertThat(summary.netPayableMinor()).isEqualTo(-7_200L);
    }

    @Test
    @DisplayName("a period with nothing in it reports zero rather than failing")
    void emptyPeriod() {
        Reports.TaxSummary summary = queries.taxSummary(
                ACME, LocalDate.of(2020, 1, 1), LocalDate.of(2020, 12, 31));
        assertThat(summary.output()).isEmpty();
        assertThat(summary.outputTaxMinor()).isZero();
        assertThat(summary.netPayableMinor()).isZero();
    }

    // ------------------------------------------------------------------
    // Aging
    // ------------------------------------------------------------------

    @Test
    @DisplayName("receivables land in the right age bucket")
    void agingBuckets() {
        LocalDate asOf = LocalDate.of(2026, 6, 30);

        invoice(ACME, "cur", MARCH, asOf.plusDays(5), "sent", 10_000, 0, 0, "c1");
        invoice(ACME, "b30", MARCH, asOf.minusDays(10), "sent", 20_000, 0, 0, "c1");
        invoice(ACME, "b60", MARCH, asOf.minusDays(45), "sent", 30_000, 0, 0, "c2");
        invoice(ACME, "b90", MARCH, asOf.minusDays(75), "sent", 40_000, 0, 0, "c2");
        invoice(ACME, "old", MARCH, asOf.minusDays(200), "sent", 50_000, 0, 0, "c3");
        // Settled: excluded entirely, whatever its due date.
        invoice(ACME, "paid", MARCH, asOf.minusDays(300), "paid", 99_000, 0, 99_000, "c1");

        Reports.AgingReport aging = queries.aging(ACME, asOf);

        assertThat(aging.buckets()).extracting(Reports.AgingBucket::bucket)
                .containsExactly("current", "1-30", "31-60", "61-90", "90+");
        assertThat(aging.buckets()).extracting(Reports.AgingBucket::outstandingMinor)
                .containsExactly(10_000L, 20_000L, 30_000L, 40_000L, 50_000L);
        // 10+20+30+40+50 = 150,000 outstanding; everything but the first is late.
        assertThat(aging.totalOutstandingMinor()).isEqualTo(150_000L);
        assertThat(aging.overdueMinor()).isEqualTo(140_000L);
    }

    @Test
    @DisplayName("partly paid invoices show only what is still owed")
    void partialPayments() {
        LocalDate asOf = LocalDate.of(2026, 6, 30);
        invoice(ACME, "i1", MARCH, asOf.plusDays(5), "partial", 100_000, 0, 60_000, "c1");

        Reports.AgingReport aging = queries.aging(ACME, asOf);
        // 100,000 billed less 60,000 collected leaves 40,000.
        assertThat(aging.totalOutstandingMinor()).isEqualTo(40_000L);
    }

    @Test
    @DisplayName("every bucket is reported, including the empty ones")
    void emptyBucketsStillAppear() {
        Reports.AgingReport aging = queries.aging(ACME, LocalDate.of(2026, 6, 30));
        assertThat(aging.buckets()).hasSize(5);
        assertThat(aging.totalOutstandingMinor()).isZero();
    }

    // ------------------------------------------------------------------
    // Profit and loss
    // ------------------------------------------------------------------

    @Test
    @DisplayName("revenue is net of tax, and expenses come off the gross profit")
    void profitAndLoss() {
        invoice(ACME, "i1", MARCH, MARCH, "paid", 118_000, 18_000, 118_000, "c1");
        // 10 units at a cost of 5,000 each.
        line(ACME, "l1", "i1", "18.00", 118_000, 18_000, 5_000, 10);

        expense(ACME, "e1", MARCH, "rent", 25_000);
        expense(ACME, "e2", MARCH, "wages", 15_000);

        Reports.ProfitAndLoss pnl = queries.profitAndLoss(ACME, MARCH, MARCH.plusMonths(1));

        // 118,000 billed less 18,000 tax = 100,000 of revenue. Tax collected was
        // never income.
        assertThat(pnl.revenueMinor()).isEqualTo(100_000L);
        // 10 units x 5,000 = 50,000.
        assertThat(pnl.costOfGoodsSoldMinor()).isEqualTo(50_000L);
        assertThat(pnl.grossProfitMinor()).isEqualTo(50_000L);
        // 25,000 + 15,000 = 40,000 of overhead, leaving 10,000.
        assertThat(pnl.operatingExpenseMinor()).isEqualTo(40_000L);
        assertThat(pnl.netProfitMinor()).isEqualTo(10_000L);
    }

    @Test
    @DisplayName("expenses break down by head, largest first")
    void expenseBreakdown() {
        expense(ACME, "e1", MARCH, "rent", 25_000);
        expense(ACME, "e2", MARCH, "wages", 60_000);
        expense(ACME, "e3", MARCH, "rent", 5_000);

        Reports.ProfitAndLoss pnl = queries.profitAndLoss(ACME, MARCH, MARCH.plusMonths(1));

        assertThat(pnl.expenseBreakdown()).extracting(Reports.ExpenseHead::head)
                .containsExactly("wages", "rent");
        // The two rent rows add up rather than appearing twice.
        assertThat(pnl.expenseBreakdown().get(1).amountMinor()).isEqualTo(30_000L);
    }

    @Test
    @DisplayName("a month with expenses and no sales still reports, as a loss")
    void expensesWithoutRevenue() {
        expense(ACME, "e1", MARCH, "rent", 25_000);

        Reports.ProfitAndLoss pnl = queries.profitAndLoss(ACME, MARCH, MARCH.plusMonths(1));

        // The cross join of three CTEs must not drop the period because two of
        // them are empty; without COALESCE on each branch this returns null.
        assertThat(pnl.revenueMinor()).isZero();
        assertThat(pnl.netProfitMinor()).isEqualTo(-25_000L);
    }

    // ------------------------------------------------------------------
    // Customer balances
    // ------------------------------------------------------------------

    @Test
    @DisplayName("exposure is aggregated per customer, worst first")
    void customerBalances() {
        invoice(ACME, "i1", MARCH, MARCH.plusDays(30), "sent", 30_000, 0, 0, "c1");
        invoice(ACME, "i2", MARCH, MARCH.plusDays(10), "sent", 20_000, 0, 0, "c1");
        invoice(ACME, "i3", MARCH, MARCH.plusDays(5), "sent", 90_000, 0, 0, "c2");

        List<Reports.CustomerBalance> balances = queries.customerBalances(ACME, 10);

        assertThat(balances).extracting(Reports.CustomerBalance::customerId)
                .containsExactly("c2", "c1");
        // c1's two invoices add to 50,000 and the oldest due date is the earlier
        // of the two, which is what a collections call is prioritised on.
        Reports.CustomerBalance c1 = balances.get(1);
        assertThat(c1.outstandingMinor()).isEqualTo(50_000L);
        assertThat(c1.invoices()).isEqualTo(2);
        assertThat(c1.oldestDueOn()).isEqualTo(MARCH.plusDays(10));
    }
}
