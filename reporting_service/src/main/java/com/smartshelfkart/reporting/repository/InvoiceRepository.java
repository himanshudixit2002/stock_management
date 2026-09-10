package com.smartshelfkart.reporting.repository;

import com.smartshelfkart.reporting.domain.Invoice;
import com.smartshelfkart.reporting.domain.InvoiceKey;
import org.springframework.data.jpa.repository.JpaRepository;

/**
 * The write side of the projection.
 *
 * <p>Deliberately thin. JPA earns its place for upserting synced documents,
 * where an entity graph and dirty checking are exactly what is wanted. It is
 * the wrong tool for the reports, which are set-based aggregate queries over
 * millions of rows and are written as SQL in {@code FinancialQueries}.
 */
public interface InvoiceRepository extends JpaRepository<Invoice, InvoiceKey> {

    long countByCompanyId(String companyId);

    void deleteByCompanyId(String companyId);
}
