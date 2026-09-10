package com.smartshelfkart.reporting.sync;

import java.math.BigDecimal;
import java.math.RoundingMode;

/**
 * The boundary between the operational store's doubles and this model's longs.
 *
 * <p>The source documents hold money as JSON numbers, which arrive as
 * {@code double}. That is the wrong type for money and it is not fixable from
 * here, so the conversion happens once, at the edge, and everything downstream
 * is integer minor units.
 *
 * <p>{@code BigDecimal.valueOf} is used rather than {@code new BigDecimal(d)}
 * deliberately: the constructor takes the exact binary value, so 19.99 becomes
 * 19.989999999999998436805981327779591083526611328125 and rounds to 1998.
 * {@code valueOf} goes through the shortest decimal representation and gives
 * 1999, which is the number on the invoice.
 */
public final class Money {

    private Money() {
    }

    public static long toMinor(Object raw) {
        if (raw == null) {
            return 0L;
        }
        BigDecimal value;
        if (raw instanceof BigDecimal decimal) {
            value = decimal;
        } else if (raw instanceof Number number) {
            value = BigDecimal.valueOf(number.doubleValue());
        } else {
            try {
                value = new BigDecimal(String.valueOf(raw).trim());
            } catch (NumberFormatException e) {
                return 0L;
            }
        }
        return value.movePointRight(2).setScale(0, RoundingMode.HALF_UP).longValueExact();
    }

    public static BigDecimal decimal(Object raw, BigDecimal fallback) {
        if (raw == null) {
            return fallback;
        }
        if (raw instanceof BigDecimal decimal) {
            return decimal;
        }
        if (raw instanceof Number number) {
            return BigDecimal.valueOf(number.doubleValue());
        }
        try {
            return new BigDecimal(String.valueOf(raw).trim());
        } catch (NumberFormatException e) {
            return fallback;
        }
    }
}
