package com.smartshelfkart.reporting.service;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Repository;

/**
 * The reports, as SQL.
 *
 * <p>These are written out rather than expressed through a criteria API on
 * purpose. They are set-based aggregates and the shape of the query <em>is</em>
 * the logic — a reviewer should be able to read what the tax return computes
 * without reconstructing it from a chain of builder calls.
 *
 * <p>Two rules hold in every query here.
 *
 * <p><strong>Company id is always the first predicate</strong>, and it is always
 * a bound parameter. It is the leading column of every index, so scoping is
 * also what makes these queries fast; a query that forgot it would be both a
 * tenancy bug and a full scan.
 *
 * <p><strong>The SQL stays portable.</strong> No {@code date_trunc}, no
 * {@code FILTER}, no interval arithmetic — bucket boundaries are computed in
 * Java and bound as dates. Production is PostgreSQL and the test suite runs on
 * H2 in PostgreSQL mode so it needs no container runtime; CI then runs the same
 * suite again against a real PostgreSQL. Portability is what makes those three
 * agree.
 */
@Repository
public class FinancialQueries {

    // The predicate that excludes voided documents is written out in each query
    // rather than shared as a constant. Concatenating it in produced `ANDi.status`
    // — a text block strips the trailing space from every line, so `AND """`
    // ends with no separator at all. Four lines of duplication beat a runtime
    // syntax error that only the database can see.

    private final NamedParameterJdbcTemplate jdbc;

    public FinancialQueries(NamedParameterJdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    // ------------------------------------------------------------------
    // Tax
    // ------------------------------------------------------------------

    private static final String OUTPUT_TAX_BY_RATE = """
            SELECT l.tax_rate                        AS rate,
                   SUM(l.line_total_minor - l.tax_minor) AS taxable_minor,
                   SUM(l.tax_minor)                  AS tax_minor,
                   COUNT(DISTINCT l.invoice_id)      AS documents
              FROM invoice_lines l
              JOIN invoices i
                ON i.company_id = l.company_id
               AND i.id = l.invoice_id
             WHERE l.company_id = :companyId
               AND i.issued_on >= :fromDate
               AND i.issued_on <= :toDate
               AND i.status <> 'void'
             GROUP BY l.tax_rate
             ORDER BY l.tax_rate
            """;

    private static final String INPUT_TAX_BY_RATE = """
            SELECT b.tax_rate            AS rate,
                   SUM(b.taxable_minor)  AS taxable_minor,
                   SUM(b.tax_minor)      AS tax_minor,
                   COUNT(*)              AS documents
              FROM purchase_bills b
             WHERE b.company_id = :companyId
               AND b.billed_on >= :fromDate
               AND b.billed_on <= :toDate
             GROUP BY b.tax_rate
             ORDER BY b.tax_rate
            """;

    public Reports.TaxSummary taxSummary(String companyId, LocalDate from, LocalDate to) {
        MapSqlParameterSource params = new MapSqlParameterSource()
                .addValue("companyId", companyId)
                .addValue("fromDate", from)
                .addValue("toDate", to);

        List<Reports.TaxBand> output = jdbc.query(OUTPUT_TAX_BY_RATE, params, this::taxBand);
        List<Reports.TaxBand> input = jdbc.query(INPUT_TAX_BY_RATE, params, this::taxBand);

        long outputTax = output.stream().mapToLong(Reports.TaxBand::taxMinor).sum();
        long inputTax = input.stream().mapToLong(Reports.TaxBand::taxMinor).sum();

        return new Reports.TaxSummary(
                from, to, output, input, outputTax, inputTax, outputTax - inputTax);
    }

    private Reports.TaxBand taxBand(java.sql.ResultSet rs, int row) throws java.sql.SQLException {
        java.math.BigDecimal rate = rs.getBigDecimal("rate");
        return new Reports.TaxBand(
                rate == null ? "0" : rate.stripTrailingZeros().toPlainString(),
                rs.getLong("taxable_minor"),
                rs.getLong("tax_minor"),
                rs.getLong("documents"));
    }

    // ------------------------------------------------------------------
    // Receivables
    // ------------------------------------------------------------------

    /**
     * Bucket boundaries arrive as four bound dates rather than being computed
     * in SQL. Date arithmetic is the least portable corner of SQL — PostgreSQL
     * subtracts dates to an integer, other engines want DATEDIFF — and none of
     * that belongs in a report whose logic is "how late is this".
     *
     * <p>An invoice with no due date counts as current. It is not overdue until
     * something says when it was due, and guessing a date here would put real
     * money in a bucket nobody agreed to.
     *
     * <p>The bucketing sits in a subquery and the outer statement groups by its
     * alias, rather than repeating the CASE in both SELECT and GROUP BY. The
     * repeated form works on H2 and is rejected by PostgreSQL: a named
     * parameter used twice expands to two <em>different</em> positional
     * placeholders, so the two CASE expressions are no longer syntactically
     * identical and the planner demands due_on in the GROUP BY. Computing the
     * bucket once is both portable and the clearer statement of intent.
     */
    private static final String AGING = """
            SELECT bucket,
                   COUNT(*)                 AS invoices,
                   SUM(outstanding_minor)   AS outstanding_minor
              FROM (
                    SELECT CASE
                             WHEN i.due_on IS NULL     THEN 'current'
                             WHEN i.due_on >= :asOf    THEN 'current'
                             WHEN i.due_on >= :days30  THEN '1-30'
                             WHEN i.due_on >= :days60  THEN '31-60'
                             WHEN i.due_on >= :days90  THEN '61-90'
                             ELSE '90+'
                           END                               AS bucket,
                           i.total_minor - i.paid_minor      AS outstanding_minor
                      FROM invoices i
                     WHERE i.company_id = :companyId
                       AND i.status <> 'void'
                       AND i.total_minor > i.paid_minor
                   ) aged
             GROUP BY bucket
            """;

    private static final List<String> BUCKET_ORDER =
            List.of("current", "1-30", "31-60", "61-90", "90+");

    public Reports.AgingReport aging(String companyId, LocalDate asOf) {
        MapSqlParameterSource params = new MapSqlParameterSource()
                .addValue("companyId", companyId)
                .addValue("asOf", asOf)
                .addValue("days30", asOf.minusDays(30))
                .addValue("days60", asOf.minusDays(60))
                .addValue("days90", asOf.minusDays(90));

        Map<String, Reports.AgingBucket> found = new HashMap<>();
        jdbc.query(AGING, params, rs -> {
            String bucket = rs.getString("bucket");
            found.put(bucket, new Reports.AgingBucket(
                    bucket, rs.getLong("invoices"), rs.getLong("outstanding_minor")));
        });

        // Every bucket appears, including the empty ones. A report that omits a
        // bucket with nothing in it makes the reader work out whether the query
        // found nothing or the bucket does not exist.
        List<Reports.AgingBucket> buckets = new ArrayList<>();
        long total = 0;
        long overdue = 0;
        for (String name : BUCKET_ORDER) {
            Reports.AgingBucket bucket =
                    found.getOrDefault(name, new Reports.AgingBucket(name, 0, 0));
            buckets.add(bucket);
            total += bucket.outstandingMinor();
            if (!"current".equals(name)) {
                overdue += bucket.outstandingMinor();
            }
        }
        return new Reports.AgingReport(asOf, buckets, total, overdue);
    }

    // ------------------------------------------------------------------
    // Profit and loss
    // ------------------------------------------------------------------

    /**
     * Revenue, cost of goods sold and operating expenses in one pass.
     *
     * <p>The three aggregates are unrelated — they scan different tables — so
     * they are computed as separate CTEs and cross-joined. Written as one query
     * they would need a join key they do not share, and would either multiply
     * rows or silently drop a period with no expenses in it. {@code COALESCE}
     * on each branch is what keeps a period with no sales reporting zero rather
     * than null.
     *
     * <p>Revenue is net of tax. Tax collected on a sale was never income; it is
     * money held on behalf of the authority, and counting it as revenue
     * overstates the top line by the tax rate.
     */
    private static final String PROFIT_AND_LOSS = """
            WITH revenue AS (
                SELECT COALESCE(SUM(i.total_minor - i.tax_minor), 0) AS amount_minor
                  FROM invoices i
                 WHERE i.company_id = :companyId
                   AND i.issued_on >= :fromDate
                   AND i.issued_on <= :toDate
                   AND i.status <> 'void'
            ),
            cogs AS (
                SELECT COALESCE(SUM(CAST(l.quantity * l.cost_price_minor AS BIGINT)), 0)
                           AS amount_minor
                  FROM invoice_lines l
                  JOIN invoices i
                    ON i.company_id = l.company_id
                   AND i.id = l.invoice_id
                 WHERE l.company_id = :companyId
                   AND i.issued_on >= :fromDate
                   AND i.issued_on <= :toDate
                   AND i.status <> 'void'
            ),
            opex AS (
                SELECT COALESCE(SUM(e.amount_minor), 0) AS amount_minor
                  FROM expenses e
                 WHERE e.company_id = :companyId
                   AND e.incurred_on >= :fromDate
                   AND e.incurred_on <= :toDate
            )
            SELECT revenue.amount_minor AS revenue_minor,
                   cogs.amount_minor    AS cogs_minor,
                   opex.amount_minor    AS opex_minor
              FROM revenue, cogs, opex
            """;

    private static final String EXPENSES_BY_HEAD = """
            SELECT e.head                      AS head,
                   SUM(e.amount_minor)         AS amount_minor
              FROM expenses e
             WHERE e.company_id = :companyId
               AND e.incurred_on >= :fromDate
               AND e.incurred_on <= :toDate
             GROUP BY e.head
             ORDER BY SUM(e.amount_minor) DESC
            """;

    public Reports.ProfitAndLoss profitAndLoss(String companyId, LocalDate from, LocalDate to) {
        MapSqlParameterSource params = new MapSqlParameterSource()
                .addValue("companyId", companyId)
                .addValue("fromDate", from)
                .addValue("toDate", to);

        Map<String, Object> row = jdbc.queryForMap(PROFIT_AND_LOSS, params);
        long revenue = ((Number) row.get("revenue_minor")).longValue();
        long cogs = ((Number) row.get("cogs_minor")).longValue();
        long opex = ((Number) row.get("opex_minor")).longValue();

        List<Reports.ExpenseHead> breakdown = jdbc.query(
                EXPENSES_BY_HEAD, params,
                (rs, i) -> new Reports.ExpenseHead(
                        rs.getString("head"), rs.getLong("amount_minor")));

        long gross = revenue - cogs;
        return new Reports.ProfitAndLoss(
                from, to, revenue, cogs, gross, opex, gross - opex, breakdown);
    }

    // ------------------------------------------------------------------
    // Customer exposure
    // ------------------------------------------------------------------

    private static final String CUSTOMER_BALANCES = """
            SELECT i.customer_id                          AS customer_id,
                   MAX(i.customer_name)                   AS customer_name,
                   COUNT(*)                               AS invoices,
                   SUM(i.total_minor)                     AS billed_minor,
                   SUM(i.paid_minor)                      AS paid_minor,
                   SUM(i.total_minor - i.paid_minor)      AS outstanding_minor,
                   MIN(i.due_on)                          AS oldest_due_on
              FROM invoices i
             WHERE i.company_id = :companyId
               AND i.status <> 'void'
               AND i.total_minor > i.paid_minor
             GROUP BY i.customer_id
             ORDER BY SUM(i.total_minor - i.paid_minor) DESC
            """;

    public List<Reports.CustomerBalance> customerBalances(String companyId, int limit) {
        MapSqlParameterSource params =
                new MapSqlParameterSource().addValue("companyId", companyId);
        List<Reports.CustomerBalance> all = jdbc.query(CUSTOMER_BALANCES, params, (rs, i) -> {
            java.sql.Date oldest = rs.getDate("oldest_due_on");
            return new Reports.CustomerBalance(
                    rs.getString("customer_id"),
                    rs.getString("customer_name"),
                    rs.getLong("invoices"),
                    rs.getLong("billed_minor"),
                    rs.getLong("paid_minor"),
                    rs.getLong("outstanding_minor"),
                    oldest == null ? null : oldest.toLocalDate());
        });
        return all.size() > limit ? all.subList(0, limit) : all;
    }
}
