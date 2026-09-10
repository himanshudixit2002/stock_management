package com.smartshelfkart.reporting.repository;

import com.smartshelfkart.reporting.domain.Expense;
import com.smartshelfkart.reporting.domain.InvoiceKey;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ExpenseRepository extends JpaRepository<Expense, InvoiceKey> {

    long countByCompanyId(String companyId);

    void deleteByCompanyId(String companyId);
}
