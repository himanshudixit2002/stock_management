package com.smartshelfkart.reporting.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.IdClass;
import jakarta.persistence.Table;
import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/** Input tax: the other half of a return, against the output tax on sales. */
@Entity
@Table(name = "purchase_bills")
@IdClass(InvoiceKey.class)
@Getter
@Setter
@NoArgsConstructor
public class PurchaseBill {

    @Id
    @Column(name = "company_id", nullable = false, length = 128)
    private String companyId;

    @Id
    @Column(name = "id", nullable = false, length = 128)
    private String id;

    @Column(name = "vendor_id", length = 128)
    private String vendorId;

    @Column(name = "vendor_name", length = 256)
    private String vendorName;

    @Column(name = "billed_on", nullable = false)
    private LocalDate billedOn;

    @Column(name = "taxable_minor", nullable = false)
    private long taxableMinor;

    @Column(name = "tax_rate", nullable = false, precision = 6, scale = 3)
    private BigDecimal taxRate = BigDecimal.ZERO;

    @Column(name = "tax_minor", nullable = false)
    private long taxMinor;

    @Column(name = "total_minor", nullable = false)
    private long totalMinor;

    @Column(name = "synced_at", nullable = false)
    private Instant syncedAt;
}
