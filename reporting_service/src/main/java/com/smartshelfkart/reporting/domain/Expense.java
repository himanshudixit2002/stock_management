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

@Entity
@Table(name = "expenses")
@IdClass(InvoiceKey.class)
@Getter
@Setter
@NoArgsConstructor
public class Expense {

    @Id
    @Column(name = "company_id", nullable = false, length = 128)
    private String companyId;

    @Id
    @Column(name = "id", nullable = false, length = 128)
    private String id;

    @Column(name = "incurred_on", nullable = false)
    private LocalDate incurredOn;

    @Column(name = "head", nullable = false, length = 128)
    private String head;

    @Column(name = "vendor_id", length = 128)
    private String vendorId;

    @Column(name = "amount_minor", nullable = false)
    private long amountMinor;

    @Column(name = "tax_minor", nullable = false)
    private long taxMinor;

    @Column(name = "note", length = 512)
    private String note;

    @Column(name = "synced_at", nullable = false)
    private Instant syncedAt;
}
