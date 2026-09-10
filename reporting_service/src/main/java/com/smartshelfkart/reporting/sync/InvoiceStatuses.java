package com.smartshelfkart.reporting.sync;

import java.util.Locale;

/**
 * Normalises the operational store's invoice states into the four the reports
 * actually distinguish.
 *
 * <p>{@code overdue} is not one of them. Whether an invoice is overdue is a
 * function of its due date and today, so storing it as a state means the
 * projection is wrong every night at midnight until something rewrites it. The
 * aging report derives it instead.
 *
 * <p>{@code cancelled} maps to {@code void} and is excluded from every
 * financial figure. {@code refunded} does not: a refunded invoice was really
 * issued and really collected, and erasing it from a tax period that has
 * already been filed would be the wrong kind of tidy.
 */
public final class InvoiceStatuses {

    private InvoiceStatuses() {
    }

    public static String normalise(Object raw) {
        String value = raw == null ? "" : String.valueOf(raw).toLowerCase(Locale.ROOT).trim();
        // Documents store either the plain name or the enum's toString.
        int dot = value.lastIndexOf('.');
        if (dot >= 0) {
            value = value.substring(dot + 1);
        }
        return switch (value) {
            case "cancelled", "canceled", "void" -> "void";
            case "paid" -> "paid";
            case "partiallypaid", "partially_paid", "partial" -> "partial";
            case "refunded" -> "refunded";
            case "draft" -> "draft";
            // `overdue` and anything unrecognised land here: issued, not settled.
            default -> "sent";
        };
    }

    public static boolean isSalesInvoice(Object invoiceType) {
        String value = invoiceType == null
                ? "sales"
                : String.valueOf(invoiceType).toLowerCase(Locale.ROOT);
        return !value.contains("purchase");
    }
}
