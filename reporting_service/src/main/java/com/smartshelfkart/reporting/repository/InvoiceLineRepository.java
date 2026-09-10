package com.smartshelfkart.reporting.repository;

import com.smartshelfkart.reporting.domain.InvoiceLine;
import com.smartshelfkart.reporting.domain.InvoiceKey;
import org.springframework.data.jpa.repository.JpaRepository;

public interface InvoiceLineRepository extends JpaRepository<InvoiceLine, InvoiceKey> {

    long countByCompanyId(String companyId);

    void deleteByCompanyId(String companyId);
}
