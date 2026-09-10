package com.smartshelfkart.reporting.sync;

import com.smartshelfkart.reporting.domain.Expense;
import com.smartshelfkart.reporting.domain.Invoice;
import com.smartshelfkart.reporting.domain.InvoiceLine;
import com.smartshelfkart.reporting.domain.Payment;
import com.smartshelfkart.reporting.domain.PurchaseBill;
import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Map;

/**
 * Turns operational documents into projected rows.
 *
 * <p>Kept free of Firestore and of Spring on purpose. It takes maps and returns
 * entities, so the mapping — which is where the subtle errors live — can be
 * tested exhaustively without a database, a network, or an application context.
 */
public final class InvoiceProjector {

    private InvoiceProjector() {
    }

    public record Projected(
            List<Invoice> invoices,
            List<InvoiceLine> lines,
            List<Payment> payments,
            List<PurchaseBill> bills) {
    }

    public static Projected project(
            String companyId, List<Map<String, Object>> documents, Instant syncedAt) {

        List<Invoice> invoices = new ArrayList<>();
        List<InvoiceLine> lines = new ArrayList<>();
        List<Payment> payments = new ArrayList<>();
        List<PurchaseBill> bills = new ArrayList<>();

        for (Map<String, Object> doc : documents) {
            String id = text(doc.get("id"));
            if (id.isEmpty()) {
                continue;
            }
            if (InvoiceStatuses.isSalesInvoice(doc.get("invoiceType"))) {
                invoices.add(toInvoice(companyId, id, doc, syncedAt));
                lines.addAll(toLines(companyId, id, doc));
                payments.addAll(toPayments(companyId, id, doc, syncedAt));
            } else {
                bills.add(toBill(companyId, id, doc, syncedAt));
            }
        }
        return new Projected(invoices, lines, payments, bills);
    }

    private static Invoice toInvoice(
            String companyId, String id, Map<String, Object> doc, Instant syncedAt) {

        Invoice invoice = new Invoice();
        invoice.setCompanyId(companyId);
        invoice.setId(id);
        invoice.setInvoiceNumber(text(doc.get("invoiceNumber")));
        invoice.setCustomerId(blankToNull(text(doc.get("customerId"))));
        invoice.setCustomerName(text(doc.get("customerName")));
        invoice.setIssuedOn(date(doc.get("invoiceDate"), LocalDate.EPOCH));
        invoice.setDueOn(nullableDate(doc.get("dueDate")));
        invoice.setStatus(InvoiceStatuses.normalise(doc.get("status")));
        invoice.setSubtotalMinor(Money.toMinor(doc.get("subtotal")));
        invoice.setDiscountMinor(Money.toMinor(doc.get("totalDiscount")));
        invoice.setTaxMinor(Money.toMinor(doc.get("totalTax")));

        long total = Money.toMinor(doc.get("grandTotal"));
        long paid = Money.toMinor(doc.get("amountPaid"));
        invoice.setTotalMinor(total);
        // The schema refuses an invoice paid beyond its total, and rounding at
        // the boundary can produce one from a source that is a rupee out.
        // Clamping here keeps a single malformed document from failing a whole
        // batch — it is a projection, and the operational store stays the truth.
        invoice.setPaidMinor(Math.min(paid, total));

        invoice.setCurrency(orDefault(text(doc.get("currency")), "INR"));
        invoice.setSourceUpdatedAt(instant(doc.get("updatedAt")));
        invoice.setSyncedAt(syncedAt);
        return invoice;
    }

    @SuppressWarnings("unchecked")
    private static List<InvoiceLine> toLines(
            String companyId, String invoiceId, Map<String, Object> doc) {

        List<InvoiceLine> lines = new ArrayList<>();
        Object raw = doc.get("items");
        if (!(raw instanceof List<?> items)) {
            return lines;
        }
        int index = 0;
        for (Object element : items) {
            if (!(element instanceof Map<?, ?> map)) {
                continue;
            }
            Map<String, Object> item = (Map<String, Object>) map;
            InvoiceLine line = new InvoiceLine();
            line.setCompanyId(companyId);
            // Lines have no id of their own in the source, so one is derived
            // from the invoice and the position. Stable across re-syncs, which
            // is what makes the upsert idempotent rather than duplicating.
            line.setId(invoiceId + ":" + index++);
            line.setInvoiceId(invoiceId);
            line.setProductId(blankToNull(text(item.get("productId"))));
            line.setProductName(text(item.get("productName")));

            BigDecimal quantity = Money.decimal(item.get("quantity"), BigDecimal.ZERO);
            line.setQuantity(quantity);

            long unitPrice = Money.toMinor(item.get("unitPrice"));
            line.setUnitPriceMinor(unitPrice);

            BigDecimal taxRate = Money.decimal(item.get("taxRate"), BigDecimal.ZERO);
            line.setTaxRate(taxRate);

            BigDecimal discountPercent =
                    Money.decimal(item.get("discountPercent"), BigDecimal.ZERO);

            // Gross, then the line discount, then tax on what is left. This is
            // the same order the client bills in; computing tax before the
            // discount overstates it, which is the classic invoicing bug.
            BigDecimal gross = quantity.multiply(BigDecimal.valueOf(unitPrice));
            BigDecimal discount = gross
                    .multiply(discountPercent)
                    .divide(BigDecimal.valueOf(100), 0, java.math.RoundingMode.HALF_UP);
            BigDecimal net = gross.subtract(discount);
            BigDecimal tax = net
                    .multiply(taxRate)
                    .divide(BigDecimal.valueOf(100), 0, java.math.RoundingMode.HALF_UP);

            line.setDiscountMinor(discount.longValue());
            line.setTaxMinor(tax.longValue());
            line.setLineTotalMinor(net.add(tax).longValue());

            // Cost at the time of sale is not recorded on the source line, so
            // it cannot be recovered here. Left at zero rather than filled from
            // the product's *current* cost, which would silently rewrite the
            // margin on every historical sale each time a cost price changed.
            // The profit-and-loss report reports COGS as unavailable while this
            // is zero; see the open item in the service README.
            line.setCostPriceMinor(Money.toMinor(item.get("costPrice")));

            lines.add(line);
        }
        return lines;
    }

    @SuppressWarnings("unchecked")
    private static List<Payment> toPayments(
            String companyId, String invoiceId, Map<String, Object> doc, Instant syncedAt) {

        List<Payment> payments = new ArrayList<>();
        Object raw = doc.get("payments");
        if (!(raw instanceof List<?> entries)) {
            return payments;
        }
        int index = 0;
        for (Object element : entries) {
            if (!(element instanceof Map<?, ?> map)) {
                continue;
            }
            Map<String, Object> entry = (Map<String, Object>) map;
            Payment payment = new Payment();
            payment.setCompanyId(companyId);
            String id = text(entry.get("id"));
            payment.setId(id.isEmpty() ? invoiceId + ":pay:" + index : id);
            index++;
            payment.setInvoiceId(invoiceId);
            payment.setCustomerId(blankToNull(text(doc.get("customerId"))));
            payment.setReceivedOn(date(entry.get("date"), LocalDate.EPOCH));
            payment.setAmountMinor(Money.toMinor(entry.get("amount")));
            payment.setMethod(text(entry.get("method")));
            payment.setSyncedAt(syncedAt);
            payments.add(payment);
        }
        return payments;
    }

    private static PurchaseBill toBill(
            String companyId, String id, Map<String, Object> doc, Instant syncedAt) {

        PurchaseBill bill = new PurchaseBill();
        bill.setCompanyId(companyId);
        bill.setId(id);
        bill.setVendorId(blankToNull(text(doc.get("vendorId"))));
        bill.setVendorName(text(doc.get("vendorName")));
        bill.setBilledOn(date(doc.get("invoiceDate"), LocalDate.EPOCH));

        long tax = Money.toMinor(doc.get("totalTax"));
        long total = Money.toMinor(doc.get("grandTotal"));
        bill.setTaxMinor(tax);
        bill.setTotalMinor(total);
        bill.setTaxableMinor(total - tax);
        bill.setTaxRate(dominantRate(doc));
        bill.setSyncedAt(syncedAt);
        return bill;
    }

    /**
     * A purchase bill is summarised at one rate: the rate on the largest line.
     *
     * <p>An approximation, and a stated one. Splitting a bill across rates
     * properly needs its lines projected the way sales lines are; until a
     * return has to be filed from purchase data, the largest line is the rate
     * that characterises the bill and it is right for the common case of a bill
     * at a single rate.
     */
    @SuppressWarnings("unchecked")
    private static BigDecimal dominantRate(Map<String, Object> doc) {
        Object raw = doc.get("items");
        if (!(raw instanceof List<?> items)) {
            return BigDecimal.ZERO;
        }
        BigDecimal rate = BigDecimal.ZERO;
        long largest = Long.MIN_VALUE;
        for (Object element : items) {
            if (!(element instanceof Map<?, ?> map)) {
                continue;
            }
            Map<String, Object> item = (Map<String, Object>) map;
            long value = Money.toMinor(item.get("unitPrice"))
                    * Money.decimal(item.get("quantity"), BigDecimal.ZERO).longValue();
            if (value > largest) {
                largest = value;
                rate = Money.decimal(item.get("taxRate"), BigDecimal.ZERO);
            }
        }
        return rate;
    }

    public static Expense toExpense(
            String companyId, String id, Map<String, Object> doc, Instant syncedAt) {

        Expense expense = new Expense();
        expense.setCompanyId(companyId);
        expense.setId(id);
        expense.setIncurredOn(date(doc.get("expenseDate"), LocalDate.EPOCH));
        expense.setHead(expenseHead(doc));
        expense.setVendorId(blankToNull(text(doc.get("vendorId"))));
        expense.setAmountMinor(Money.toMinor(doc.get("amount")));
        expense.setTaxMinor(Money.toMinor(doc.get("taxAmount")));
        expense.setNote(text(doc.get("notes")));
        expense.setSyncedAt(syncedAt);
        return expense;
    }

    /**
     * The head an expense is reported under.
     *
     * <p>The source carries an enum plus a free-text {@code customCategory} used
     * when the enum says "other". Preferring the free text in that one case is
     * what keeps a profit-and-loss statement from collapsing a third of the
     * spend into a line called "other".
     */
    private static String expenseHead(Map<String, Object> doc) {
        String category = text(doc.get("category"));
        int dot = category.lastIndexOf('.');
        if (dot >= 0) {
            category = category.substring(dot + 1);
        }
        if (category.isBlank() || category.equalsIgnoreCase("other")) {
            String custom = text(doc.get("customCategory"));
            if (!custom.isBlank()) {
                return custom;
            }
        }
        return category.isBlank() ? "Uncategorised" : category;
    }

    // ------------------------------------------------------------------

    private static String text(Object raw) {
        return raw == null ? "" : String.valueOf(raw).trim();
    }

    private static String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value;
    }

    private static String orDefault(String value, String fallback) {
        return value == null || value.isBlank() ? fallback : value;
    }

    private static LocalDate date(Object raw, LocalDate fallback) {
        LocalDate parsed = nullableDate(raw);
        return parsed == null ? fallback : parsed;
    }

    /**
     * Dates arrive as a Firestore timestamp, a {@link Date}, epoch millis or an
     * ISO string depending on how the document was written. All four appear in
     * real data, so all four are handled rather than assuming the tidy one.
     */
    private static LocalDate nullableDate(Object raw) {
        Instant instant = instant(raw);
        return instant == null ? null : instant.atZone(ZoneOffset.UTC).toLocalDate();
    }

    private static Instant instant(Object raw) {
        if (raw == null) {
            return null;
        }
        if (raw instanceof Instant instant) {
            return instant;
        }
        if (raw instanceof Date date) {
            return date.toInstant();
        }
        if (raw instanceof com.google.cloud.Timestamp timestamp) {
            return Instant.ofEpochSecond(timestamp.getSeconds(), timestamp.getNanos());
        }
        if (raw instanceof Number number) {
            return Instant.ofEpochMilli(number.longValue());
        }
        String value = String.valueOf(raw).trim();
        if (value.isEmpty()) {
            return null;
        }
        try {
            return Instant.parse(value);
        } catch (Exception ignored) {
            // Fall through to a plain date.
        }
        try {
            return LocalDate.parse(value).atStartOfDay(ZoneOffset.UTC).toInstant();
        } catch (Exception ignored) {
            return null;
        }
    }
}
