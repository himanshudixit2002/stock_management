package com.smartshelfkart.reporting.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.IdClass;
import jakarta.persistence.Table;
import java.math.BigDecimal;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * One line of an invoice.
 *
 * <p>The tax rate lives here rather than on the invoice because a single
 * invoice routinely mixes rates, and a tax return has to report each rate
 * separately. Putting it on the header is the modelling mistake that forces
 * every tax report to be rewritten later.
 *
 * <p>{@code costPriceMinor} is the cost at the moment of sale, copied rather
 * than looked up. Cost prices change; the margin on a sale made last March must
 * not move because someone edited a product today.
 */
@Entity
@Table(name = "invoice_lines")
@IdClass(InvoiceKey.class)
@Getter
@Setter
@NoArgsConstructor
public class InvoiceLine {

    @Id
    @Column(name = "company_id", nullable = false, length = 128)
    private String companyId;

    @Id
    @Column(name = "id", nullable = false, length = 128)
    private String id;

    @Column(name = "invoice_id", nullable = false, length = 128)
    private String invoiceId;

    @Column(name = "product_id", length = 128)
    private String productId;

    @Column(name = "product_name", length = 256)
    private String productName;

    @Column(name = "quantity", nullable = false, precision = 14, scale = 3)
    private BigDecimal quantity = BigDecimal.ZERO;

    @Column(name = "unit_price_minor", nullable = false)
    private long unitPriceMinor;

    @Column(name = "discount_minor", nullable = false)
    private long discountMinor;

    @Column(name = "tax_rate", nullable = false, precision = 6, scale = 3)
    private BigDecimal taxRate = BigDecimal.ZERO;

    @Column(name = "tax_minor", nullable = false)
    private long taxMinor;

    @Column(name = "line_total_minor", nullable = false)
    private long lineTotalMinor;

    @Column(name = "cost_price_minor", nullable = false)
    private long costPriceMinor;
}
