package com.smartshelfkart.reporting.sync;

import com.google.cloud.firestore.Firestore;
import com.google.cloud.firestore.QueryDocumentSnapshot;
import com.smartshelfkart.reporting.domain.Expense;
import com.smartshelfkart.reporting.repository.ExpenseRepository;
import com.smartshelfkart.reporting.repository.InvoiceLineRepository;
import com.smartshelfkart.reporting.repository.InvoiceRepository;
import com.smartshelfkart.reporting.repository.PaymentRepository;
import com.smartshelfkart.reporting.repository.PurchaseBillRepository;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.lang.Nullable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Rebuilds a workspace's projection from the operational store.
 *
 * <p>A full rebuild rather than an incremental merge, and that is a considered
 * choice. Incremental sync of a document store means watching for deletes,
 * which Firestore will not tell you about after the fact — a deleted invoice
 * would linger in the projection forever and quietly inflate every report. A
 * rebuild of one workspace is a few thousand rows and takes under a second; the
 * complexity of getting incremental right is not worth what it saves.
 *
 * <p>The whole rebuild runs in one transaction. A half-applied projection is a
 * financial report that is wrong in a way nobody can see, so it either replaces
 * the workspace's rows completely or it changes nothing and the previous
 * projection stands.
 */
@Service
public class FirestoreSyncService {

    private static final Logger log = LoggerFactory.getLogger(FirestoreSyncService.class);

    /** Guards against a runaway read on a workspace with a pathological catalog. */
    private static final int MAX_DOCUMENTS = 100_000;

    private final Firestore firestore;
    private final InvoiceRepository invoices;
    private final InvoiceLineRepository lines;
    private final PaymentRepository payments;
    private final PurchaseBillRepository bills;
    private final ExpenseRepository expenses;

    public FirestoreSyncService(
            @Nullable Firestore firestore,
            InvoiceRepository invoices,
            InvoiceLineRepository lines,
            PaymentRepository payments,
            PurchaseBillRepository bills,
            ExpenseRepository expenses) {
        this.firestore = firestore;
        this.invoices = invoices;
        this.lines = lines;
        this.payments = payments;
        this.bills = bills;
        this.expenses = expenses;
    }

    public record SyncResult(
            String companyId,
            int invoices,
            int lines,
            int payments,
            int purchaseBills,
            int expenses,
            long millis) {
    }

    @Transactional
    public SyncResult sync(String companyId) {
        if (firestore == null) {
            throw new IllegalStateException(
                    "No Firestore credentials; this service cannot read the operational store.");
        }
        long started = System.currentTimeMillis();
        Instant syncedAt = Instant.now();

        List<Map<String, Object>> invoiceDocs = read(companyId, "invoices");
        InvoiceProjector.Projected projected =
                InvoiceProjector.project(companyId, invoiceDocs, syncedAt);

        List<Expense> expenseRows = new ArrayList<>();
        for (Map<String, Object> doc : read(companyId, "expenses")) {
            String id = String.valueOf(doc.get("id"));
            if (id != null && !id.isBlank() && !"null".equals(id)) {
                expenseRows.add(InvoiceProjector.toExpense(companyId, id, doc, syncedAt));
            }
        }

        // Children first, then parents: the line and payment tables reference
        // invoices, so deleting in the other order trips the foreign key.
        lines.deleteByCompanyId(companyId);
        payments.deleteByCompanyId(companyId);
        invoices.deleteByCompanyId(companyId);
        bills.deleteByCompanyId(companyId);
        expenses.deleteByCompanyId(companyId);

        invoices.saveAll(projected.invoices());
        lines.saveAll(projected.lines());
        payments.saveAll(projected.payments());
        bills.saveAll(projected.bills());
        expenses.saveAll(expenseRows);

        SyncResult result = new SyncResult(
                companyId,
                projected.invoices().size(),
                projected.lines().size(),
                projected.payments().size(),
                projected.bills().size(),
                expenseRows.size(),
                System.currentTimeMillis() - started);

        log.info("projected workspace {}: {} invoices, {} lines, {} bills, {} expenses in {}ms",
                companyId, result.invoices(), result.lines(),
                result.purchaseBills(), result.expenses(), result.millis());
        return result;
    }

    private List<Map<String, Object>> read(String companyId, String collection) {
        List<Map<String, Object>> documents = new ArrayList<>();
        try {
            List<QueryDocumentSnapshot> snapshots = firestore
                    .collection("companies").document(companyId)
                    .collection(collection)
                    .limit(MAX_DOCUMENTS)
                    .get().get().getDocuments();

            for (QueryDocumentSnapshot snapshot : snapshots) {
                Map<String, Object> data = new HashMap<>(snapshot.getData());
                // The document id is not part of its data, and every projected
                // row is keyed by it.
                data.put("id", snapshot.getId());
                documents.add(data);
            }
        } catch (Exception e) {
            throw new IllegalStateException(
                    "Could not read " + collection + " for workspace " + companyId, e);
        }
        return documents;
    }
}
