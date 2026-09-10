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
@Table(name = "payments")
@IdClass(InvoiceKey.class)
@Getter
@Setter
@NoArgsConstructor
public class Payment {

    @Id
    @Column(name = "company_id", nullable = false, length = 128)
    private String companyId;

    @Id
    @Column(name = "id", nullable = false, length = 128)
    private String id;

    @Column(name = "invoice_id", length = 128)
    private String invoiceId;

    @Column(name = "customer_id", length = 128)
    private String customerId;

    @Column(name = "received_on", nullable = false)
    private LocalDate receivedOn;

    @Column(name = "amount_minor", nullable = false)
    private long amountMinor;

    @Column(name = "method", length = 32)
    private String method;

    @Column(name = "synced_at", nullable = false)
    private Instant syncedAt;
}
