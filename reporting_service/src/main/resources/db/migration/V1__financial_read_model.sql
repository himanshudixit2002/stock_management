-- The financial read model.
--
-- This is not the system of record. Firestore is. These tables are a projection
-- of it, maintained by the sync job, and they exist because the questions asked
-- of financial data are the questions a document store is worst at: group by
-- tax rate across a quarter, bucket receivables by age, join lines to invoices
-- to payments and subtract. Those were being answered by loading collections
-- into memory and aggregating there, which stops working long before a
-- business outgrows the product.
--
-- Two conventions hold everywhere below.
--
-- Money is stored in minor units as BIGINT, never as a floating-point type. A
-- REAL or DOUBLE column will eventually report a tax total of 4999.999999997,
-- and a financial report that is nearly right is worse than one that is
-- missing, because nobody notices.
--
-- Every table carries company_id and it is the first column of every primary
-- key and every index. Tenancy is not a filter applied by the application
-- layer and hoped for; it is the leading edge of the physical layout, so a
-- query that forgets it cannot use an index and will be found in review long
-- before it is found in production.

CREATE TABLE invoices (
    company_id      VARCHAR(128) NOT NULL,
    id              VARCHAR(128) NOT NULL,
    invoice_number  VARCHAR(64),
    customer_id     VARCHAR(128),
    customer_name   VARCHAR(256),
    issued_on       DATE         NOT NULL,
    due_on          DATE,
    -- draft | sent | partial | paid | void
    status          VARCHAR(32)  NOT NULL,
    subtotal_minor  BIGINT       NOT NULL DEFAULT 0,
    discount_minor  BIGINT       NOT NULL DEFAULT 0,
    tax_minor       BIGINT       NOT NULL DEFAULT 0,
    total_minor     BIGINT       NOT NULL DEFAULT 0,
    paid_minor      BIGINT       NOT NULL DEFAULT 0,
    currency        VARCHAR(8)   NOT NULL DEFAULT 'INR',
    source_updated_at TIMESTAMP,
    synced_at       TIMESTAMP    NOT NULL,
    CONSTRAINT pk_invoices PRIMARY KEY (company_id, id),
    -- An invoice cannot be paid more than it is worth. If the projection ever
    -- produces one, the sync is wrong and it should fail loudly here rather
    -- than quietly skew every collections report downstream.
    CONSTRAINT ck_invoices_paid_within_total CHECK (paid_minor <= total_minor),
    CONSTRAINT ck_invoices_total_non_negative CHECK (total_minor >= 0)
);

-- Period reports scan by issue date within one company; this is the index they
-- use. Status is included because every financial query excludes voided rows,
-- so it belongs in the index rather than being a filter applied after the read.
CREATE INDEX idx_invoices_period ON invoices (company_id, issued_on, status);

-- Aging walks unpaid invoices by due date. Partial-index syntax is not portable,
-- so the predicate stays in the query and the index stays plain.
CREATE INDEX idx_invoices_due ON invoices (company_id, due_on);
CREATE INDEX idx_invoices_customer ON invoices (company_id, customer_id);

CREATE TABLE invoice_lines (
    company_id        VARCHAR(128) NOT NULL,
    id                VARCHAR(128) NOT NULL,
    invoice_id        VARCHAR(128) NOT NULL,
    product_id        VARCHAR(128),
    product_name      VARCHAR(256),
    quantity          NUMERIC(14,3) NOT NULL DEFAULT 0,
    unit_price_minor  BIGINT        NOT NULL DEFAULT 0,
    discount_minor    BIGINT        NOT NULL DEFAULT 0,
    -- The rate as a percentage, e.g. 18.00. Kept per line rather than per
    -- invoice because a single invoice routinely mixes rates, and a tax return
    -- has to report each one separately.
    tax_rate          NUMERIC(6,3)  NOT NULL DEFAULT 0,
    tax_minor         BIGINT        NOT NULL DEFAULT 0,
    line_total_minor  BIGINT        NOT NULL DEFAULT 0,
    -- Cost at the moment of sale, copied rather than referenced. Cost prices
    -- change; margin on a sale made last March must not move when someone
    -- edits a product today.
    cost_price_minor  BIGINT        NOT NULL DEFAULT 0,
    CONSTRAINT pk_invoice_lines PRIMARY KEY (company_id, id),
    CONSTRAINT fk_invoice_lines_invoice
        FOREIGN KEY (company_id, invoice_id) REFERENCES invoices (company_id, id)
        ON DELETE CASCADE
);

-- The join in every revenue, tax and margin query.
CREATE INDEX idx_invoice_lines_invoice ON invoice_lines (company_id, invoice_id);
CREATE INDEX idx_invoice_lines_rate ON invoice_lines (company_id, tax_rate);

CREATE TABLE payments (
    company_id    VARCHAR(128) NOT NULL,
    id            VARCHAR(128) NOT NULL,
    invoice_id    VARCHAR(128),
    customer_id   VARCHAR(128),
    received_on   DATE         NOT NULL,
    amount_minor  BIGINT       NOT NULL,
    method        VARCHAR(32),
    synced_at     TIMESTAMP    NOT NULL,
    CONSTRAINT pk_payments PRIMARY KEY (company_id, id)
);

CREATE INDEX idx_payments_period ON payments (company_id, received_on);
CREATE INDEX idx_payments_invoice ON payments (company_id, invoice_id);

CREATE TABLE expenses (
    company_id    VARCHAR(128) NOT NULL,
    id            VARCHAR(128) NOT NULL,
    incurred_on   DATE         NOT NULL,
    head          VARCHAR(128) NOT NULL,
    vendor_id     VARCHAR(128),
    amount_minor  BIGINT       NOT NULL,
    tax_minor     BIGINT       NOT NULL DEFAULT 0,
    note          VARCHAR(512),
    synced_at     TIMESTAMP    NOT NULL,
    CONSTRAINT pk_expenses PRIMARY KEY (company_id, id)
);

CREATE INDEX idx_expenses_period ON expenses (company_id, incurred_on, head);

CREATE TABLE purchase_bills (
    company_id      VARCHAR(128) NOT NULL,
    id              VARCHAR(128) NOT NULL,
    vendor_id       VARCHAR(128),
    vendor_name     VARCHAR(256),
    billed_on       DATE         NOT NULL,
    -- Input tax. The other half of a tax return: what was charged on sales,
    -- less what was paid on purchases.
    taxable_minor   BIGINT       NOT NULL DEFAULT 0,
    tax_rate        NUMERIC(6,3) NOT NULL DEFAULT 0,
    tax_minor       BIGINT       NOT NULL DEFAULT 0,
    total_minor     BIGINT       NOT NULL DEFAULT 0,
    synced_at       TIMESTAMP    NOT NULL,
    CONSTRAINT pk_purchase_bills PRIMARY KEY (company_id, id)
);

CREATE INDEX idx_purchase_bills_period ON purchase_bills (company_id, billed_on, tax_rate);

-- What the sync last managed to do, per company and per collection. The sync is
-- incremental and resumable, and without a durable watermark a restart either
-- re-reads everything or silently skips whatever arrived while it was down.
CREATE TABLE sync_state (
    company_id     VARCHAR(128) NOT NULL,
    collection     VARCHAR(64)  NOT NULL,
    last_synced_at TIMESTAMP,
    last_cursor    VARCHAR(256),
    rows_written   BIGINT       NOT NULL DEFAULT 0,
    CONSTRAINT pk_sync_state PRIMARY KEY (company_id, collection)
);
