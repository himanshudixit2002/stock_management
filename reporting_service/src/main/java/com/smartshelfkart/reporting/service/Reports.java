package com.smartshelfkart.reporting.service;

import java.time.LocalDate;
import java.util.List;

/** Result shapes for the financial reports. Money is always minor units. */
public final class Reports {

    private Reports() {
    }

    /** One tax rate's contribution, on either the sales or the purchase side. */
    public record TaxBand(String rate, long taxableMinor, long taxMinor, long documents) {
    }

    public record TaxSummary(
            LocalDate from,
            LocalDate to,
            List<TaxBand> output,
            List<TaxBand> input,
            long outputTaxMinor,
            long inputTaxMinor,
            /** Positive means owed to the authority; negative means reclaimable. */
            long netPayableMinor) {
    }

    /** One age bucket of unpaid receivables. */
    public record AgingBucket(String bucket, long invoices, long outstandingMinor) {
    }

    public record AgingReport(
            LocalDate asOf,
            List<AgingBucket> buckets,
            long totalOutstandingMinor,
            /** Everything past its due date, which is the number people act on. */
            long overdueMinor) {
    }

    public record ProfitAndLoss(
            LocalDate from,
            LocalDate to,
            long revenueMinor,
            long costOfGoodsSoldMinor,
            long grossProfitMinor,
            long operatingExpenseMinor,
            long netProfitMinor,
            List<ExpenseHead> expenseBreakdown) {
    }

    public record ExpenseHead(String head, long amountMinor) {
    }

    /** Per-customer exposure, for credit control. */
    public record CustomerBalance(
            String customerId,
            String customerName,
            long invoices,
            long billedMinor,
            long paidMinor,
            long outstandingMinor,
            LocalDate oldestDueOn) {
    }
}
