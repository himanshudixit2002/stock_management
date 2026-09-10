package com.smartshelfkart.reporting.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.IdClass;
import jakarta.persistence.Table;
import java.time.Instant;
import java.time.LocalDate;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * A projected invoice.
 *
 * <p>Money is a {@code long} of minor units throughout — paise, cents — never a
 * {@code double} or a {@code float}. Binary floating point cannot represent
 * 0.10, so a column of them accumulates error across a quarter and reports a
 * tax total of 4999.9999999997. A report that is nearly right is worse than one
 * that is missing, because nobody notices it is wrong.
 */
@Entity
@Table(name = "invoices")
@IdClass(InvoiceKey.class)
@Getter
@Setter
@NoArgsConstructor
public class Invoice {

    @Id
    @Column(name = "company_id", nullable = false, length = 128)
    private String companyId;

    @Id
    @Column(name = "id", nullable = false, length = 128)
    private String id;

    @Column(name = "invoice_number", length = 64)
    private String invoiceNumber;

    @Column(name = "customer_id", length = 128)
    private String customerId;

    @Column(name = "customer_name", length = 256)
    private String customerName;

    @Column(name = "issued_on", nullable = false)
    private LocalDate issuedOn;

    @Column(name = "due_on")
    private LocalDate dueOn;

    @Column(name = "status", nullable = false, length = 32)
    private String status;

    @Column(name = "subtotal_minor", nullable = false)
    private long subtotalMinor;

    @Column(name = "discount_minor", nullable = false)
    private long discountMinor;

    @Column(name = "tax_minor", nullable = false)
    private long taxMinor;

    @Column(name = "total_minor", nullable = false)
    private long totalMinor;

    @Column(name = "paid_minor", nullable = false)
    private long paidMinor;

    @Column(name = "currency", nullable = false, length = 8)
    private String currency = "INR";

    @Column(name = "source_updated_at")
    private Instant sourceUpdatedAt;

    @Column(name = "synced_at", nullable = false)
    private Instant syncedAt;

    /** What is still owed. Never negative; the schema refuses overpayment. */
    public long outstandingMinor() {
        return totalMinor - paidMinor;
    }
}
