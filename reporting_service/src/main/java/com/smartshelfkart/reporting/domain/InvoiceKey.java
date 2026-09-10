package com.smartshelfkart.reporting.domain;

import java.io.Serializable;
import java.util.Objects;

/**
 * Composite key for every projected row: the workspace, then the document id.
 *
 * <p>Company first is not cosmetic. It is the leading column of the primary key
 * and therefore of the physical layout, so a query that forgets to scope by
 * workspace cannot use the index — which turns a tenancy bug into a performance
 * cliff that shows up in review rather than a silent cross-tenant read.
 */
public class InvoiceKey implements Serializable {

    private String companyId;
    private String id;

    public InvoiceKey() {
    }

    public InvoiceKey(String companyId, String id) {
        this.companyId = companyId;
        this.id = id;
    }

    public String getCompanyId() {
        return companyId;
    }

    public String getId() {
        return id;
    }

    @Override
    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof InvoiceKey key)) {
            return false;
        }
        return Objects.equals(companyId, key.companyId) && Objects.equals(id, key.id);
    }

    @Override
    public int hashCode() {
        return Objects.hash(companyId, id);
    }
}
