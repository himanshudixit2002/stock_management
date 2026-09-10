package com.smartshelfkart.reporting.repository;

import com.smartshelfkart.reporting.domain.Payment;
import com.smartshelfkart.reporting.domain.InvoiceKey;
import org.springframework.data.jpa.repository.JpaRepository;

public interface PaymentRepository extends JpaRepository<Payment, InvoiceKey> {

    long countByCompanyId(String companyId);

    void deleteByCompanyId(String companyId);
}
