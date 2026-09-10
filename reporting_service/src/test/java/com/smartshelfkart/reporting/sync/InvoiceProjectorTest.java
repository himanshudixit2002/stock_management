package com.smartshelfkart.reporting.sync;

import static org.assertj.core.api.Assertions.assertThat;

import com.smartshelfkart.reporting.domain.Expense;
import com.smartshelfkart.reporting.domain.Invoice;
import com.smartshelfkart.reporting.domain.InvoiceLine;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.LinkedHashMap;
import java.util.Map;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

/**
 * The mapping from operational documents to projected rows.
 *
 * <p>This is where the quiet errors live. A report built on a correct query over
 * badly mapped rows is wrong in a way that looks entirely plausible, so the
 * mapping is tested on its own, without a database or an application context.
 */
class InvoiceProjectorTest {

    private static final String COMPANY = "acme";
    private static final Instant SYNCED = Instant.parse("2026-09-11T10:00:00Z");

    private static Map<String, Object> doc(Object... pairs) {
        Map<String, Object> map = new LinkedHashMap<>();
        for (int i = 0; i < pairs.length; i += 2) {
            map.put(String.valueOf(pairs[i]), pairs[i + 1]);
        }
        return map;
    }

    private static Map<String, Object> item(double qty, double unitPrice, double taxRate,
            double discountPercent) {
        return doc("productId", "p1", "productName", "Widget",
                "quantity", qty, "unitPrice", unitPrice,
                "taxRate", taxRate, "discountPercent", discountPercent);
    }

    @Nested
    @DisplayName("money")
    class MoneyConversion {

        @Test
        @DisplayName("a price that binary floating point cannot hold converts exactly")
        void awkwardPrices() {
            // new BigDecimal(19.99) is 19.9899999999999984368... and rounds to
            // 1998. The invoice says 1999. This is the whole reason Money exists.
            assertThat(Money.toMinor(19.99)).isEqualTo(1999L);
            assertThat(Money.toMinor(0.1 + 0.2)).isEqualTo(30L);
            assertThat(Money.toMinor(1234.565)).isEqualTo(123457L);
        }

        @Test
        @DisplayName("absent and unparseable amounts are zero, not an exception")
        void missingAmounts() {
            assertThat(Money.toMinor(null)).isZero();
            assertThat(Money.toMinor("not a number")).isZero();
            assertThat(Money.toMinor("")).isZero();
        }

        @Test
        @DisplayName("amounts written as strings still convert")
        void stringAmounts() {
            assertThat(Money.toMinor("1499.50")).isEqualTo(149950L);
        }
    }

    @Nested
    @DisplayName("invoice status")
    class Statuses {

        @Test
        @DisplayName("cancelled becomes void, and is the only thing that does")
        void cancelledIsVoid() {
            assertThat(InvoiceStatuses.normalise("cancelled")).isEqualTo("void");
            assertThat(InvoiceStatuses.normalise("InvoiceStatus.cancelled")).isEqualTo("void");
            assertThat(InvoiceStatuses.normalise("refunded")).isEqualTo("refunded");
        }

        @Test
        @DisplayName("overdue is not a state, because it depends on today")
        void overdueIsDerived() {
            // Storing it would make the projection wrong every night at
            // midnight until something rewrote it. Aging derives it instead.
            assertThat(InvoiceStatuses.normalise("overdue")).isEqualTo("sent");
        }

        @Test
        @DisplayName("an unrecognised status is treated as issued, not as void")
        void unknownIsConservative() {
            // Guessing "void" would silently drop real revenue out of every
            // report; guessing "sent" at worst leaves it visible and owed.
            assertThat(InvoiceStatuses.normalise("something_new")).isEqualTo("sent");
            assertThat(InvoiceStatuses.normalise(null)).isEqualTo("sent");
        }

        @Test
        @DisplayName("partiallyPaid collapses onto partial")
        void partial() {
            assertThat(InvoiceStatuses.normalise("partiallyPaid")).isEqualTo("partial");
        }
    }

    @Nested
    @DisplayName("invoice lines")
    class Lines {

        @Test
        @DisplayName("discount is applied before tax, not after")
        void discountBeforeTax() {
            // 2 x 1000.00 = 2000.00, less 10% = 1800.00, plus 18% = 2124.00.
            // Taxing before the discount would give 2124.00 -> 2360.00 gross
            // and overstate the tax by 36.00. This is the classic invoicing bug.
            InvoiceProjector.Projected projected = InvoiceProjector.project(
                    COMPANY,
                    List.of(doc("id", "inv1", "invoiceDate", "2026-03-01",
                            "items", List.of(item(2, 1000.00, 18, 10)))),
                    SYNCED);

            InvoiceLine line = projected.lines().get(0);
            assertThat(line.getDiscountMinor()).isEqualTo(20_000L);
            assertThat(line.getTaxMinor()).isEqualTo(32_400L);
            assertThat(line.getLineTotalMinor()).isEqualTo(212_400L);
        }

        @Test
        @DisplayName("line ids are stable across re-syncs so an upsert is idempotent")
        void stableLineIds() {
            List<Map<String, Object>> documents = List.of(
                    doc("id", "inv1", "invoiceDate", "2026-03-01",
                            "items", List.of(item(1, 10, 0, 0), item(1, 20, 0, 0))));

            List<String> first = InvoiceProjector.project(COMPANY, documents, SYNCED)
                    .lines().stream().map(InvoiceLine::getId).toList();
            List<String> second = InvoiceProjector.project(COMPANY, documents, SYNCED)
                    .lines().stream().map(InvoiceLine::getId).toList();

            assertThat(first).containsExactly("inv1:0", "inv1:1").isEqualTo(second);
        }

        @Test
        @DisplayName("the tax rate is kept per line, because one invoice mixes rates")
        void ratesArePerLine() {
            InvoiceProjector.Projected projected = InvoiceProjector.project(
                    COMPANY,
                    List.of(doc("id", "inv1", "invoiceDate", "2026-03-01",
                            "items", List.of(item(1, 100, 5, 0), item(1, 100, 18, 0)))),
                    SYNCED);

            assertThat(projected.lines())
                    .extracting(line -> line.getTaxRate().intValue())
                    .containsExactly(5, 18);
        }
    }

    @Nested
    @DisplayName("invoices")
    class Invoices {

        @Test
        @DisplayName("paid is clamped to the total so the schema check cannot trip")
        void paidNeverExceedsTotal() {
            // A source document a rupee out would otherwise fail the whole batch
            // on a CHECK constraint. It is a projection; the operational store
            // stays the truth and one odd document should not stop the rebuild.
            Invoice invoice = InvoiceProjector.project(
                    COMPANY,
                    List.of(doc("id", "inv1", "invoiceDate", "2026-03-01",
                            "grandTotal", 100.00, "amountPaid", 100.01)),
                    SYNCED).invoices().get(0);

            assertThat(invoice.getTotalMinor()).isEqualTo(10_000L);
            assertThat(invoice.getPaidMinor()).isEqualTo(10_000L);
            assertThat(invoice.outstandingMinor()).isZero();
        }

        @Test
        @DisplayName("a purchase invoice becomes a bill, not revenue")
        void purchaseInvoicesAreSeparated() {
            InvoiceProjector.Projected projected = InvoiceProjector.project(
                    COMPANY,
                    List.of(
                            doc("id", "s1", "invoiceType", "sales",
                                    "invoiceDate", "2026-03-01", "grandTotal", 100.0),
                            doc("id", "p1", "invoiceType", "InvoiceType.purchase",
                                    "invoiceDate", "2026-03-02", "grandTotal", 50.0,
                                    "totalTax", 5.0)),
                    SYNCED);

            assertThat(projected.invoices()).extracting(Invoice::getId).containsExactly("s1");
            assertThat(projected.bills()).singleElement()
                    .satisfies(bill -> {
                        assertThat(bill.getId()).isEqualTo("p1");
                        assertThat(bill.getTaxMinor()).isEqualTo(500L);
                        assertThat(bill.getTaxableMinor()).isEqualTo(4_500L);
                    });
        }

        @Test
        @DisplayName("dates parse from every shape real documents contain")
        void dateShapes() {
            for (Object raw : List.of(
                    "2026-03-01",
                    "2026-03-01T09:30:00Z",
                    1772348400000L)) {
                Invoice invoice = InvoiceProjector.project(
                        COMPANY, List.of(doc("id", "i", "invoiceDate", raw)), SYNCED)
                        .invoices().get(0);
                assertThat(invoice.getIssuedOn()).isNotNull();
            }
        }

        @Test
        @DisplayName("a missing due date leaves it null rather than inventing one")
        void noDueDate() {
            Invoice invoice = InvoiceProjector.project(
                    COMPANY, List.of(doc("id", "i", "invoiceDate", "2026-03-01")), SYNCED)
                    .invoices().get(0);
            assertThat(invoice.getDueOn()).isNull();
        }

        @Test
        @DisplayName("a document with no id is skipped rather than keyed on null")
        void missingId() {
            assertThat(InvoiceProjector.project(
                    COMPANY, List.of(doc("invoiceDate", "2026-03-01")), SYNCED).invoices())
                    .isEmpty();
        }

        @Test
        @DisplayName("embedded payments become rows")
        void payments() {
            InvoiceProjector.Projected projected = InvoiceProjector.project(
                    COMPANY,
                    List.of(doc("id", "inv1", "invoiceDate", "2026-03-01",
                            "customerId", "c1",
                            "payments", List.of(
                                    doc("id", "pay1", "amount", 500.0,
                                            "date", "2026-03-05", "method", "cash")))),
                    SYNCED);

            assertThat(projected.payments()).singleElement().satisfies(payment -> {
                assertThat(payment.getId()).isEqualTo("pay1");
                assertThat(payment.getInvoiceId()).isEqualTo("inv1");
                assertThat(payment.getAmountMinor()).isEqualTo(50_000L);
                assertThat(payment.getReceivedOn()).isEqualTo(LocalDate.of(2026, 3, 5));
            });
        }
    }

    @Nested
    @DisplayName("expenses")
    class Expenses {

        @Test
        @DisplayName("a custom category is preferred over the enum's 'other'")
        void customCategoryWins() {
            // Otherwise a third of a profit-and-loss statement collapses into a
            // single line called "other", which is the least useful report there is.
            Expense expense = InvoiceProjector.toExpense(COMPANY, "e1",
                    doc("expenseDate", "2026-03-01", "category", "ExpenseCategory.other",
                            "customCategory", "Diwali bonus", "amount", 5000.0),
                    SYNCED);
            assertThat(expense.getHead()).isEqualTo("Diwali bonus");
        }

        @Test
        @DisplayName("a named category keeps its name, enum prefix stripped")
        void namedCategory() {
            Expense expense = InvoiceProjector.toExpense(COMPANY, "e1",
                    doc("expenseDate", "2026-03-01", "category", "ExpenseCategory.rent",
                            "amount", 25000.0),
                    SYNCED);
            assertThat(expense.getHead()).isEqualTo("rent");
            assertThat(expense.getAmountMinor()).isEqualTo(2_500_000L);
        }

        @Test
        @DisplayName("no category at all still lands somewhere reportable")
        void uncategorised() {
            Expense expense = InvoiceProjector.toExpense(COMPANY, "e1",
                    doc("expenseDate", "2026-03-01", "amount", 100.0), SYNCED);
            assertThat(expense.getHead()).isEqualTo("Uncategorised");
        }
    }
}
