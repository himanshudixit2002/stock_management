package com.smartshelfkart.reporting.repository;

import com.smartshelfkart.reporting.domain.PurchaseBill;
import com.smartshelfkart.reporting.domain.InvoiceKey;
import org.springframework.data.jpa.repository.JpaRepository;

public interface PurchaseBillRepository extends JpaRepository<PurchaseBill, InvoiceKey> {

    long countByCompanyId(String companyId);

    void deleteByCompanyId(String companyId);
}
